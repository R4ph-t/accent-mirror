// The take store (spec 16, plan §8.3, §9.2): the last 10 clean takes per phrase on disk, crash-safe, with their
// derived analyses.
//
//   <root>/phrases/<phraseID>/takes/<takeID>/   audio.caf, features.json (L0+L1), comparison-<voice>.json (L2, at
//                                               most 3 voices), manifest.json (written last)
//   <root>/phrases/<phraseID>/takes/.staging/   a save in progress; committed by one rename into takes/
//   <root>/phrases/<phraseID>/takes/.trash/     pruned and deleted takes, on their way out
//   <root>/phrases/<phraseID>/takes/.quarantine/ takes that failed launch recovery
//   <root>/phrases/<phraseID>/take-counter.json  the last take number given, so numbers are never reused
//
// A take folder exists under `takes/` only after its staging folder, manifest last, was renamed there in one step, so
// no partial take is ever listed. Derived records are `AMPipeline`'s opaque `DerivedRecord`s; one that is missing or
// keyed for another identity is recomputed lazily through the injected `TakeRecomputer`, never an error.

import AMCore
import Foundation
import os

/// A stored take's address: its phrase and its ID.
public struct TakeRef: Sendable, Hashable, Codable, CustomStringConvertible {
    public let phrase: PhraseID
    public let id: TakeID

    public init(phrase: PhraseID, id: TakeID) {
        self.phrase = phrase
        self.id = id
    }

    public var description: String { "\(phrase)/\(id)" }
}

/// One take as the take menu lists it.
public struct StoredTake: Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        /// Compared with the model; shown with its result.
        case comparable
        /// Spec 17's transcript re-run couldn't align it. It still counts toward the 10, and is never a ghost.
        case unalignable(reason: String)
    }

    public let ref: TakeRef
    /// "Take n": counts up per phrase, never reused.
    public let number: Int
    public let recordedAt: Date
    public let status: Status
    /// The voices with a stored comparison, most recently used first.
    public let voices: [RecordingID]

    public var id: TakeID { ref.id }
    public var title: String { "Take \(number)" }
}

/// An earlier take drawn behind the current one: the take and its comparison with the current voice, whose
/// `AnalysisResult` carries its pitch on the model timeline (`AMPipeline` decodes it).
public struct Ghost: Sendable, Hashable {
    public let take: StoredTake
    public let comparison: DerivedRecord
}

/// A stored take's audio, for a recompute.
public struct StoredTakeAudio: Sendable, Hashable {
    public let ref: TakeRef
    public let audioSHA256: String
    /// 16 kHz mono Float32.
    public let samples: [Float]
    public let recordedAt: Date
}

/// How the running code analyses a stored take, injected by `AMPipeline` (`AMLibrary` never imports it).
public struct TakeRecomputer: Sendable {
    /// The keys the running code gives a take's derived records.
    public struct Keys: Sendable, Hashable {
        /// The L1 record's key (`features.json` holds L0 and L1; L1's key includes L0's).
        public let features: String
        /// The L2 record's key for the voice.
        public let comparison: String

        public init(features: String, comparison: String) {
            self.features = features
            self.comparison = comparison
        }
    }

    /// The keys for `audioSHA256` of `phrase` against `voice`; nil when the running code can't say (the phrase is
    /// unknown), which reads as stale.
    public let expectedKeys: @Sendable (_ phrase: PhraseID, _ audioSHA256: String, _ voice: RecordingID) -> Keys?
    /// Analyses the stored audio against `voice`: L0, L1 and L2 records. Throws when the take doesn't reach L2.
    public let recompute: @Sendable (StoredTakeAudio, RecordingID) async throws -> [DerivedRecord]

    public init(
        expectedKeys: @escaping @Sendable (PhraseID, String, RecordingID) -> Keys?,
        recompute: @escaping @Sendable (StoredTakeAudio, RecordingID) async throws -> [DerivedRecord]
    ) {
        self.expectedKeys = expectedKeys
        self.recompute = recompute
    }
}

public enum TakeStoreError: Error, Sendable, Hashable {
    case notFound(TakeRef)
    case storage(StorageError)
    /// The stored audio couldn't be analysed again against that voice.
    case recomputeFailed(TakeRef)
}

/// What launch recovery did.
public struct TakeRecoveryReport: Sendable, Hashable {
    /// Leftover staging and trash entries deleted.
    public var cleaned = 0
    /// Take folders moved to `.quarantine/` (no manifest, or the audio doesn't match its hash).
    public var quarantined: [TakeRef] = []
    /// Phrases whose prune failed again; retried at the next launch.
    public var pruneFailures: [PhraseID: StorageError] = [:]
}

public actor TakeStore: TakePersisting {
    /// Clean takes kept per phrase (plan v1, Designer §12: "10 kept").
    public static let takesKept = 10
    /// Voices whose comparison (L2) is kept per take (plan §9.2).
    public static let comparisonsKept = 3
    /// Ghosts drawn behind a take (Designer §12: "3 shown").
    public static let ghostsShown = 3

    /// The steps of a save, in order (plan §8.3).
    public enum SaveStep: String, Sendable, CaseIterable {
        /// Audio and derived files written into `.staging/<takeID>/` and synced.
        case stagedFiles
        /// `manifest.json` written last and synced.
        case manifest
        /// The staging folder renamed into `takes/`.
        case commit
    }

    /// Faults for tests, standing in for a crash or a failing disk. The shipped store has none.
    public struct Faults: Sendable {
        /// The save stops right after this step and leaves everything as it is, as if the process died there.
        public var crashAfter: SaveStep?
        /// Every prune fails (`ioFailure`) before moving anything.
        public var pruneFails: Bool

        public init(crashAfter: SaveStep? = nil, pruneFails: Bool = false) {
            self.crashAfter = crashAfter
            self.pruneFails = pruneFails
        }
    }

    /// The simulated crash: the save gives up without cleaning anything.
    private struct SimulatedCrash: Error {}

    /// `Application Support/Accent Mirror/` (tests pass a temporary folder instead).
    public nonisolated let root: URL
    private let recomputer: TakeRecomputer
    private let faults: Faults
    private let fileManager = FileManager.default
    /// Recomputes in flight, so two readers of the same comparison share one.
    private var recomputing: [String: Task<DerivedRecord, any Error>] = [:]

    static let log = Logger(subsystem: "AccentMirror", category: "TakeStore")

    public init(root: URL, recomputer: TakeRecomputer, faults: Faults = Faults()) {
        self.root = root
        self.recomputer = recomputer
        self.faults = faults
    }

    /// The shipped root, `Application Support/Accent Mirror/` (in the sandbox, the app's container).
    public static func applicationSupportRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Accent Mirror", directoryHint: .isDirectory)
    }

    // MARK: Paths

    nonisolated func phraseFolder(_ phrase: PhraseID) -> URL {
        root.appending(path: "phrases").appending(path: TakeFiles.component(phrase.rawValue), directoryHint: .isDirectory)
    }

    nonisolated func takesFolder(_ phrase: PhraseID) -> URL {
        phraseFolder(phrase).appending(path: "takes", directoryHint: .isDirectory)
    }

    /// A committed take's folder.
    public nonisolated func folder(_ take: TakeRef) -> URL {
        takesFolder(take.phrase).appending(path: TakeFiles.component(take.id.rawValue), directoryHint: .isDirectory)
    }

    // MARK: Save (TakePersisting)

    /// Saves an analysed take: staged, manifest last, committed by one rename, then the phrase pruned to 10. A take
    /// already stored (the same audio analysed again, a voice switch) keeps its folder and number; its derived
    /// records are replaced one file at a time and the manifest last.
    public func save(_ take: TakeRecord) async throws(StorageError) -> SavedTake {
        let ref = TakeRef(phrase: take.phraseID, id: take.takeID)
        do {
            if let manifest = readManifest(ref) {
                try update(ref, manifest: manifest, with: take)
            } else {
                try commit(take, ref: ref)
            }
        } catch is SimulatedCrash {
            throw .ioFailure
        } catch {
            throw TakeFiles.storageError(error)
        }
        return SavedTake(id: take.takeID, pruneFailure: prune(take.phraseID))
    }

    private func commit(_ take: TakeRecord, ref: TakeRef) throws {
        let takes = takesFolder(ref.phrase)
        let staging = takes.appending(path: TakeFiles.staging).appending(path: TakeFiles.component(ref.id.rawValue))
        do {
            try? fileManager.removeItem(at: staging)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            let number = try nextNumber(ref.phrase)

            var files: [String: String] = [:]
            let audio = staging.appending(path: TakeFiles.audio)
            try TakeFiles.writeAudio(take.samples, to: audio)
            try TakeFiles.sync(audio)
            files[TakeFiles.audio] = try TakeFiles.sha256(of: audio)

            let features = take.derived.filter { $0.level != .l2 }
            if !features.isEmpty {
                let data = try TakeFiles.encoder().encode(features)
                try TakeFiles.write(data, to: staging.appending(path: TakeFiles.features))
                files[TakeFiles.features] = Self.sha256(data)
            }
            var comparisons: [TakeManifest.Comparison] = []
            if let l2 = take.derived.last(where: { $0.level == .l2 }) {
                let name = TakeFiles.comparison(take.recording)
                let data = try TakeFiles.encoder().encode(l2)
                try TakeFiles.write(data, to: staging.appending(path: name))
                files[name] = Self.sha256(data)
                comparisons = [.init(voice: take.recording, file: name)]
            }
            try crashPoint(.stagedFiles)

            let manifest = TakeManifest(
                format: TakeManifest.currentFormat, phraseID: ref.phrase, takeID: ref.id, number: number,
                recordedAt: take.recordedAt, audioSHA256: take.audioSHA256, files: files, identity: take.identity,
                comparisons: comparisons, unalignableReason: nil)
            try TakeFiles.write(try TakeFiles.encoder().encode(manifest), to: staging.appending(path: TakeFiles.manifest))
            try TakeFiles.sync(staging)
            try crashPoint(.manifest)

            try TakeFiles.renameExclusive(staging, to: folder(ref))
            try TakeFiles.sync(takes)
            try crashPoint(.commit)
        } catch is SimulatedCrash {
            throw SimulatedCrash()
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// The same take saved again: its features and this voice's comparison replaced, the manifest last.
    private func update(_ ref: TakeRef, manifest old: TakeManifest, with take: TakeRecord) throws {
        var manifest = old
        let folder = folder(ref)
        let features = take.derived.filter { $0.level != .l2 }
        if !features.isEmpty {
            let data = try TakeFiles.encoder().encode(features)
            try TakeFiles.replace(folder.appending(path: TakeFiles.features), with: data)
            manifest.files[TakeFiles.features] = Self.sha256(data)
        }
        var evicted: [String] = []
        if let l2 = take.derived.last(where: { $0.level == .l2 }) {
            evicted = try storeComparison(l2, voice: take.recording, in: folder, manifest: &manifest)
        }
        if let identity = take.identity { manifest.identity = identity }
        try writeManifest(manifest, ref: ref, removing: evicted)
    }

    /// Writes `record` as `voice`'s comparison and makes it the most recently used; returns the files of the voices
    /// it pushed past `comparisonsKept`, to delete once the manifest no longer names them.
    private func storeComparison(
        _ record: DerivedRecord, voice: RecordingID, in folder: URL, manifest: inout TakeManifest
    ) throws -> [String] {
        let name = TakeFiles.comparison(voice)
        let data = try TakeFiles.encoder().encode(record)
        try TakeFiles.replace(folder.appending(path: name), with: data)
        manifest.files[name] = Self.sha256(data)
        manifest.comparisons.removeAll { $0.voice == voice }
        manifest.comparisons.insert(.init(voice: voice, file: name), at: 0)
        let evicted = manifest.comparisons.dropFirst(Self.comparisonsKept).map(\.file)
        manifest.comparisons = Array(manifest.comparisons.prefix(Self.comparisonsKept))
        for file in evicted { manifest.files[file] = nil }
        return evicted
    }

    private func writeManifest(_ manifest: TakeManifest, ref: TakeRef, removing evicted: [String] = []) throws {
        let folder = folder(ref)
        try TakeFiles.replace(folder.appending(path: TakeFiles.manifest), with: TakeFiles.encoder().encode(manifest))
        for file in evicted { try? fileManager.removeItem(at: folder.appending(path: file)) }
    }

    private func crashPoint(_ step: SaveStep) throws {
        if faults.crashAfter == step { throw SimulatedCrash() }
    }

    /// The next take number for `phrase`, recorded before the take is committed: a crash can skip a number, never
    /// reuse one.
    private func nextNumber(_ phrase: PhraseID) throws -> Int {
        let listed = takes(for: phrase).map(\.number).max() ?? 0
        let next = max(readCounter(phrase), listed) + 1
        try writeCounter(next, phrase: phrase)
        return next
    }

    private struct Counter: Codable { var last: Int }

    private func readCounter(_ phrase: PhraseID) -> Int {
        let url = phraseFolder(phrase).appending(path: TakeFiles.counter)
        guard let data = try? Data(contentsOf: url), let counter = try? JSONDecoder().decode(Counter.self, from: data)
        else { return 0 }
        return counter.last
    }

    private func writeCounter(_ last: Int, phrase: PhraseID) throws {
        let url = phraseFolder(phrase).appending(path: TakeFiles.counter)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TakeFiles.replace(url, with: TakeFiles.encoder().encode(Counter(last: last)))
    }

    // MARK: Prune and delete

    /// Moves the takes beyond 10 (oldest first) into `.trash/`, then empties it. Runs only after a commit, and at
    /// launch for a prune that failed.
    private func prune(_ phrase: PhraseID) -> StorageError? {
        let victims = takes(for: phrase).dropFirst(Self.takesKept)
        guard !victims.isEmpty else { return nil }
        do {
            if faults.pruneFails { throw StorageError.ioFailure }
            for victim in victims { try moveToTrash(victim.ref) }
            emptyTrash(phrase)
            return nil
        } catch {
            let failure = TakeFiles.storageError(error)
            Self.log.error("prune of \(phrase.rawValue, privacy: .public) failed: \(failure.rawValue, privacy: .public)")
            return failure
        }
    }

    /// Deletes a take: one rename into `.trash/`, then the trash emptied.
    public func delete(take: TakeRef) throws(TakeStoreError) {
        guard fileManager.fileExists(atPath: folder(take).path) else { throw .notFound(take) }
        do {
            try moveToTrash(take)
        } catch {
            throw .storage(TakeFiles.storageError(error))
        }
        emptyTrash(take.phrase)
    }

    private func moveToTrash(_ take: TakeRef) throws {
        let trash = takesFolder(take.phrase).appending(path: TakeFiles.trash, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        let destination = trash.appending(path: TakeFiles.component(take.id.rawValue) + "-" + UUID().uuidString)
        try TakeFiles.renameExclusive(folder(take), to: destination)
        try TakeFiles.sync(takesFolder(take.phrase))
    }

    /// Best effort: whatever stays is deleted at the next launch.
    @discardableResult
    private func emptyTrash(_ phrase: PhraseID) -> Int {
        let trash = takesFolder(phrase).appending(path: TakeFiles.trash, directoryHint: .isDirectory)
        let entries = (try? fileManager.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for entry in entries where (try? fileManager.removeItem(at: entry)) != nil { removed += 1 }
        return removed
    }

    // MARK: Launch recovery

    /// Run once at launch, before anything is listed: deletes `.staging/` and `.trash/`, quarantines a take with no
    /// manifest or whose audio doesn't match its hash, and retries any prune that failed.
    @discardableResult
    public func recover() -> TakeRecoveryReport {
        var report = TakeRecoveryReport()
        let phrases = root.appending(path: "phrases", directoryHint: .isDirectory)
        let folders = (try? fileManager.contentsOfDirectory(at: phrases, includingPropertiesForKeys: nil)) ?? []
        for phraseFolder in folders {
            let takes = phraseFolder.appending(path: "takes", directoryHint: .isDirectory)
            let staging = takes.appending(path: TakeFiles.staging, directoryHint: .isDirectory)
            let stale = (try? fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
            for entry in stale where (try? fileManager.removeItem(at: entry)) != nil { report.cleaned += 1 }

            var phrase: PhraseID?
            let entries = (try? fileManager.contentsOfDirectory(at: takes, includingPropertiesForKeys: nil)) ?? []
            for folder in entries where !folder.lastPathComponent.hasPrefix(".") {
                if let manifest = verified(folder) {
                    phrase = manifest.phraseID
                    removeTemporaries(in: folder)
                } else {
                    report.quarantined.append(quarantine(folder, takes: takes))
                }
            }
            guard let phrase = phrase ?? phraseID(of: phraseFolder) else { continue }
            report.cleaned += emptyTrash(phrase)
            if let failure = prune(phrase) { report.pruneFailures[phrase] = failure }
            report.cleaned += emptyTrash(phrase)
        }
        return report
    }

    /// The manifest of a take folder whose audio matches its recorded hash, else nil.
    private func verified(_ folder: URL) -> TakeManifest? {
        guard let manifest = decodeManifest(folder.appending(path: TakeFiles.manifest)),
            let expected = manifest.files[TakeFiles.audio],
            let actual = try? TakeFiles.sha256(of: folder.appending(path: TakeFiles.audio)), actual == expected
        else { return nil }
        return manifest
    }

    private func quarantine(_ folder: URL, takes: URL) -> TakeRef {
        let ref = TakeRef(
            phrase: phraseID(of: takes.deletingLastPathComponent()) ?? PhraseID(takes.deletingLastPathComponent().lastPathComponent),
            id: TakeID(folder.lastPathComponent.removingPercentEncoding ?? folder.lastPathComponent))
        let quarantine = takes.appending(path: TakeFiles.quarantine, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: quarantine, withIntermediateDirectories: true)
            try TakeFiles.renameExclusive(
                folder, to: quarantine.appending(path: folder.lastPathComponent + "-" + UUID().uuidString))
            Self.log.error("quarantined take \(ref.description, privacy: .public): no manifest or audio hash mismatch")
        } catch {
            Self.log.error("could not quarantine take \(ref.description, privacy: .public): \(String(describing: error))")
        }
        return ref
    }

    private func removeTemporaries(in folder: URL) {
        let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent.hasSuffix(TakeFiles.temporarySuffix) {
            try? fileManager.removeItem(at: entry)
        }
    }

    /// A phrase folder's ID, decoded from its name.
    private nonisolated func phraseID(of folder: URL) -> PhraseID? {
        folder.lastPathComponent.removingPercentEncoding.map { PhraseID($0) }
    }

    // MARK: Reading

    /// A phrase's takes, newest first. A folder without a readable manifest isn't a take.
    public func takes(for phrase: PhraseID) -> [StoredTake] {
        let takes = takesFolder(phrase)
        let entries = (try? fileManager.contentsOfDirectory(at: takes, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { decodeManifest($0.appending(path: TakeFiles.manifest)) }
            .filter { $0.phraseID == phrase }
            .sorted { $0.number > $1.number }
            .map(Self.stored)
    }

    /// `voice`'s comparison of `take`: the stored record when the running code would give it the same key, else
    /// computed again from the stored audio, stored (evicting the least recently used of 3) and returned.
    public func result(take: TakeRef, voice: RecordingID) async throws(TakeStoreError) -> DerivedRecord {
        guard let manifest = readManifest(take) else { throw .notFound(take) }
        let keys = recomputer.expectedKeys(take.phrase, manifest.audioSHA256, voice)
        if let keys, let stored = storedComparison(take, manifest: manifest, voice: voice, keys: keys) {
            touch(take, voice: voice)
            return stored
        }
        let id = "\(take.description)#\(voice.rawValue)"
        let task: Task<DerivedRecord, any Error>
        if let running = recomputing[id] {
            task = running
        } else {
            task = Task { try await self.recompute(take, voice: voice) }
            recomputing[id] = task
        }
        defer { recomputing[id] = nil }
        do {
            return try await task.value
        } catch let error as TakeStoreError {
            throw error
        } catch {
            throw .recomputeFailed(take)
        }
    }

    /// Up to 3 takes recorded before `take`, newest first, with their comparison with `voice`. Unalignable takes are
    /// never ghosts (Designer §13 item 6); a take whose comparison can't be had is skipped.
    public func ghosts(before take: TakeRef, voice: RecordingID) async -> [Ghost] {
        guard let current = readManifest(take) else { return [] }
        var ghosts: [Ghost] = []
        for earlier in takes(for: take.phrase) where earlier.number < current.number && earlier.status == .comparable {
            guard ghosts.count < Self.ghostsShown else { break }
            if let comparison = try? await result(take: earlier.ref, voice: voice) {
                ghosts.append(Ghost(take: earlier, comparison: comparison))
            }
        }
        return ghosts
    }

    /// Marks a take unalignable (spec 17's transcript re-run). It stays listed and counted, and is never a ghost.
    public func markUnalignable(take: TakeRef, reason: String) throws(TakeStoreError) {
        guard var manifest = readManifest(take) else { throw .notFound(take) }
        manifest.unalignableReason = reason
        do {
            try writeManifest(manifest, ref: take)
        } catch {
            throw .storage(TakeFiles.storageError(error))
        }
    }

    /// Clears the unalignable mark (a later transcript re-run realigned the take).
    public func markComparable(take: TakeRef) throws(TakeStoreError) {
        guard var manifest = readManifest(take) else { throw .notFound(take) }
        guard manifest.unalignableReason != nil else { return }
        manifest.unalignableReason = nil
        do {
            try writeManifest(manifest, ref: take)
        } catch {
            throw .storage(TakeFiles.storageError(error))
        }
    }

    // MARK: Derived records

    private func storedComparison(
        _ take: TakeRef, manifest: TakeManifest, voice: RecordingID, keys: TakeRecomputer.Keys
    ) -> DerivedRecord? {
        let folder = folder(take)
        guard let entry = manifest.comparisons.first(where: { $0.voice == voice }),
            let comparison: DerivedRecord = readDerived(folder, entry.file, manifest: manifest),
            comparison.level == .l2, comparison.key == keys.comparison,
            let features: [DerivedRecord] = readDerived(folder, TakeFiles.features, manifest: manifest),
            features.contains(where: { $0.level == .l1 && $0.key == keys.features })
        else { return nil }
        return comparison
    }

    /// A derived file whose bytes match the manifest's hash, decoded; nil (a miss) otherwise.
    private func readDerived<T: Decodable>(_ folder: URL, _ name: String, manifest: TakeManifest) -> T? {
        guard let expected = manifest.files[name], let data = try? Data(contentsOf: folder.appending(path: name)),
            Self.sha256(data) == expected
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func touch(_ take: TakeRef, voice: RecordingID) {
        guard var manifest = readManifest(take), manifest.comparisons.first?.voice != voice,
            let index = manifest.comparisons.firstIndex(where: { $0.voice == voice })
        else { return }
        manifest.comparisons.insert(manifest.comparisons.remove(at: index), at: 0)
        try? writeManifest(manifest, ref: take)
    }

    private func recompute(_ take: TakeRef, voice: RecordingID) async throws -> DerivedRecord {
        guard let manifest = readManifest(take) else { throw TakeStoreError.notFound(take) }
        let samples: [Float]
        do {
            samples = try TakeFiles.readAudio(folder(take).appending(path: TakeFiles.audio))
        } catch {
            throw TakeStoreError.storage(TakeFiles.storageError(error))
        }
        let audio = StoredTakeAudio(
            ref: take, audioSHA256: manifest.audioSHA256, samples: samples, recordedAt: manifest.recordedAt)
        let derived = try await recomputer.recompute(audio, voice)
        guard let l2 = derived.last(where: { $0.level == .l2 }) else { throw TakeStoreError.recomputeFailed(take) }
        // Store it if the take is still here (a prune or delete may have run meanwhile); return it either way.
        if readManifest(take) != nil {
            do {
                try update(take, manifest: readManifest(take) ?? manifest, with: TakeRecord(
                    takeID: take.id, phraseID: take.phrase, recording: voice, recordedAt: manifest.recordedAt,
                    audioSHA256: manifest.audioSHA256, samples: [], derived: derived))
            } catch {
                Self.log.error("could not store a recomputed comparison of \(take.description, privacy: .public)")
            }
        }
        return l2
    }

    // MARK: Manifests

    private func readManifest(_ take: TakeRef) -> TakeManifest? {
        guard let manifest = decodeManifest(folder(take).appending(path: TakeFiles.manifest)),
            manifest.takeID == take.id, manifest.phraseID == take.phrase
        else { return nil }
        return manifest
    }

    private nonisolated func decodeManifest(_ url: URL) -> TakeManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TakeManifest.self, from: data)
    }

    private static func stored(_ manifest: TakeManifest) -> StoredTake {
        StoredTake(
            ref: TakeRef(phrase: manifest.phraseID, id: manifest.takeID), number: manifest.number,
            recordedAt: manifest.recordedAt,
            status: manifest.unalignableReason.map { .unalignable(reason: $0) } ?? .comparable,
            voices: manifest.comparisons.map(\.voice))
    }

    private static func sha256(_ data: Data) -> String { TakeFiles.sha256(data) }
}
