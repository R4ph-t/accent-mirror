// My Phrases (spec 17): the phrases you made from a clip, each with its own one-take native reference.
//
//   <root>/my-phrases/<phraseID>/   phrase.json (written last), clip.caf (the trimmed clip, 16 kHz mono Float32),
//                                   reference.json (the clip's L0/L1 analysis, `AMPipeline`'s `DerivedRecord`)
//   <root>/my-phrases/.staging/     a phrase being created; committed by one rename into my-phrases/
//
// The same staging-then-rename rule as spec 16's take store: a phrase folder exists only once it is complete. A
// transcript re-run replaces reference.json, then phrase.json, each atomically. The library depends on AMCore alone:
// pronunciations are stored as plain values, and the analysis as `AMPipeline`'s opaque record.

import AMCore
import Foundation

/// The part of the imported file a phrase was made from, in seconds of the file.
public struct ClipSelection: Sendable, Hashable, Codable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var duration: Double { end - start }
}

/// One word's pronunciation as chosen at import (spec 06's `PersistedPronunciation`, stored without AMAlignment).
public struct StoredPronunciation: Sendable, Hashable, Codable {
    /// The word index after spec 06's tokenisation.
    public let word: Int
    /// The folded word it was chosen for; a value for another word is ignored.
    public let text: String
    /// ARPAbet; nil when the word has no pronunciation (out of vocabulary and not measured).
    public let arpabet: String?
    public let expectedAmbiguous: Bool
    /// Spec 06's `PronunciationSource` raw value.
    public let chosenBy: String

    public init(word: Int, text: String, arpabet: String?, expectedAmbiguous: Bool, chosenBy: String) {
        self.word = word
        self.text = text
        self.arpabet = arpabet
        self.expectedAmbiguous = expectedAmbiguous
        self.chosenBy = chosenBy
    }
}

/// `phrase.json`.
public struct MyPhrase: Sendable, Hashable, Codable {
    public static let currentFormat = 1
    /// The clip is a phrase's only native recording.
    public static let recordingID = RecordingID("clip")
    /// The clip's reader, as a placement row names it.
    public static let voice = "clip"

    public var format: Int
    public let id: PhraseID
    public var text: String
    /// Bumped by every transcript re-run (part of every L1 key).
    public var transcriptRevision: Int
    /// The imported file's name, for the subtitle; the file itself is never kept.
    public let sourceFileName: String
    public let createdAt: Date
    public let selection: ClipSelection
    /// SHA-256 of clip.caf's samples as little-endian Float32.
    public let clipSHA256: String
    /// Every word's pronunciation as chosen at import (or at the last re-run).
    public var pronunciations: [StoredPronunciation]

    public init(
        id: PhraseID, text: String, transcriptRevision: Int = 0, sourceFileName: String, createdAt: Date,
        selection: ClipSelection, clipSHA256: String, pronunciations: [StoredPronunciation]
    ) {
        format = Self.currentFormat
        self.id = id
        self.text = text
        self.transcriptRevision = transcriptRevision
        self.sourceFileName = sourceFileName
        self.createdAt = createdAt
        self.selection = selection
        self.clipSHA256 = clipSHA256
        self.pronunciations = pronunciations
    }

    /// A new phrase ID; the prefix keeps it apart from the starter phrases' IDs.
    public static func newID() -> PhraseID { PhraseID("my-" + UUID().uuidString.lowercased()) }

    /// The sidebar subtitle (Designer v2 §6).
    public var subtitle: String { "My Phrases · From \(sourceFileName)" }

    /// The clip's `ReferenceIdentity`: one native take, so the native set is the clip alone.
    public var identity: ReferenceIdentity {
        ReferenceIdentity(
            phraseID: id, recordingID: Self.recordingID, recordingSHA256: clipSHA256,
            transcriptRevision: transcriptRevision,
            pronunciationOverridesHash: (try? CanonicalJSON.sha256(pronunciations)) ?? "",
            targetsHash: "import-default", nativeSetHash: SHA256Digest.hex(of: Data(clipSHA256.utf8)))
    }
}

/// How the running code analyses a clip, injected by `AMPipeline`.
public struct MyPhraseRebuilder: Sendable {
    /// The key the running code gives the clip's analysis; a stored record with another key is rebuilt.
    public let expectedKey: @Sendable (MyPhrase) -> String
    /// Analyses the stored clip (16 kHz mono) as `phrase`'s reference.
    public let rebuild: @Sendable (MyPhrase, [Float]) async throws -> DerivedRecord

    public init(
        expectedKey: @escaping @Sendable (MyPhrase) -> String,
        rebuild: @escaping @Sendable (MyPhrase, [Float]) async throws -> DerivedRecord
    ) {
        self.expectedKey = expectedKey
        self.rebuild = rebuild
    }
}

enum MyPhraseFiles {
    static let folder = "my-phrases"
    static let phrase = "phrase.json"
    static let clip = "clip.caf"
    static let reference = "reference.json"
}

public actor MyPhraseStore: ReferenceSet {
    /// `Application Support/Accent Mirror/` (tests pass a temporary folder).
    public nonisolated let root: URL
    private let rebuilder: MyPhraseRebuilder
    /// Rebuilds run so far, by phrase (tests).
    public private(set) var rebuilds: [PhraseID: Int] = [:]

    public init(root: URL, rebuilder: MyPhraseRebuilder) {
        self.root = root
        self.rebuilder = rebuilder
    }

    nonisolated var phrasesFolder: URL { root.appending(path: MyPhraseFiles.folder) }
    nonisolated var stagingFolder: URL { phrasesFolder.appending(path: TakeFiles.staging) }

    /// A committed phrase's folder.
    public nonisolated func folder(_ phrase: PhraseID) -> URL {
        phrasesFolder.appending(path: TakeFiles.component(phrase.rawValue))
    }

    // MARK: Reading

    /// Every phrase, newest first. A folder without a readable phrase.json isn't a phrase.
    public nonisolated func phrases() -> [MyPhrase] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: phrasesFolder, includingPropertiesForKeys: nil))
            ?? []
        return entries
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { Self.decode($0.appending(path: MyPhraseFiles.phrase)) }
            .sorted { ($0.createdAt, $0.id.rawValue) > ($1.createdAt, $1.id.rawValue) }
    }

    public nonisolated func phrase(_ id: PhraseID) -> MyPhrase? {
        guard let phrase = Self.decode(folder(id).appending(path: MyPhraseFiles.phrase)), phrase.id == id else {
            return nil
        }
        return phrase
    }

    /// The stored clip, 16 kHz mono Float32.
    public nonisolated func clip(_ id: PhraseID) throws(StorageError) -> [Float] {
        do {
            return try TakeFiles.readAudio(folder(id).appending(path: MyPhraseFiles.clip))
        } catch {
            throw TakeFiles.storageError(error)
        }
    }

    // MARK: Writing

    /// Creates a phrase: clip and reference staged, phrase.json last, committed by one rename.
    public func create(_ phrase: MyPhrase, clip: [Float], reference: DerivedRecord) throws(StorageError) {
        let fileManager = FileManager.default
        let staged = stagingFolder.appending(path: TakeFiles.component(phrase.id.rawValue))
        do {
            try? fileManager.removeItem(at: staged)
            try fileManager.createDirectory(at: staged, withIntermediateDirectories: true)
            let clipURL = staged.appending(path: MyPhraseFiles.clip)
            try TakeFiles.writeAudio(clip, to: clipURL)
            try TakeFiles.sync(clipURL)
            try TakeFiles.write(try TakeFiles.encoder().encode(reference), to: staged.appending(path: MyPhraseFiles.reference))
            try TakeFiles.write(try TakeFiles.encoder().encode(phrase), to: staged.appending(path: MyPhraseFiles.phrase))
            try TakeFiles.sync(staged)
            try TakeFiles.renameExclusive(staged, to: folder(phrase.id))
            try TakeFiles.sync(phrasesFolder)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw TakeFiles.storageError(error)
        }
    }

    /// A transcript re-run: the reference replaced first, then phrase.json, each atomically, in the same folder.
    public func update(_ phrase: MyPhrase, reference: DerivedRecord) throws(StorageError) {
        let folder = folder(phrase.id)
        do {
            guard FileManager.default.fileExists(atPath: folder.appending(path: MyPhraseFiles.phrase).path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            try TakeFiles.replace(folder.appending(path: MyPhraseFiles.reference), with: try TakeFiles.encoder().encode(reference))
            try TakeFiles.replace(folder.appending(path: MyPhraseFiles.phrase), with: try TakeFiles.encoder().encode(phrase))
        } catch {
            throw TakeFiles.storageError(error)
        }
    }

    /// Run once at launch: deletes leftover staging folders and temporary files.
    @discardableResult
    public func recover() -> Int {
        let fileManager = FileManager.default
        var cleaned = 0
        for entry in (try? fileManager.contentsOfDirectory(at: stagingFolder, includingPropertiesForKeys: nil)) ?? [] {
            if (try? fileManager.removeItem(at: entry)) != nil { cleaned += 1 }
        }
        for phrase in (try? fileManager.contentsOfDirectory(at: phrasesFolder, includingPropertiesForKeys: nil)) ?? []
        where !phrase.lastPathComponent.hasPrefix(".") {
            for file in (try? fileManager.contentsOfDirectory(at: phrase, includingPropertiesForKeys: nil)) ?? []
            where file.lastPathComponent.hasSuffix(TakeFiles.temporarySuffix) {
                if (try? fileManager.removeItem(at: file)) != nil { cleaned += 1 }
            }
        }
        return cleaned
    }

    // MARK: ReferenceSet

    public nonisolated func identity(phrase: PhraseID, voice: RecordingID) -> ReferenceIdentity {
        self.phrase(phrase)?.identity
            ?? ReferenceIdentity(
                phraseID: phrase, recordingID: voice, recordingSHA256: "", transcriptRevision: 0,
                pronunciationOverridesHash: "", targetsHash: "", nativeSetHash: "")
    }

    /// The clip with its analysis: the stored record when the running code gives it the same key, else rebuilt from
    /// clip.caf and stored. An unreadable record, or a failed rebuild, is `cacheCorrupt`.
    public func natives(phrase id: PhraseID) async throws(ReferenceSetError) -> [NativeRecording] {
        guard let phrase = phrase(id) else { return [] }
        let url = folder(id).appending(path: MyPhraseFiles.reference)
        let record: DerivedRecord
        if let data = try? Data(contentsOf: url) {
            guard let stored = try? JSONDecoder().decode(DerivedRecord.self, from: data) else {
                throw .cacheCorrupt(MyPhrase.recordingID)
            }
            record = stored.key == rebuilder.expectedKey(phrase) ? stored : try await rebuildRecord(phrase)
        } else {
            throw .cacheCorrupt(MyPhrase.recordingID)
        }
        return [NativeRecording(
            id: MyPhrase.recordingID, voice: MyPhrase.voice, audioSHA256: phrase.clipSHA256, analysis: record)]
    }

    public func rebuild(_ recording: RecordingID, phrase id: PhraseID) async throws(ReferenceSetError) {
        guard recording == MyPhrase.recordingID, let phrase = phrase(id) else { throw .notFound(recording) }
        _ = try await rebuildRecord(phrase)
    }

    private func rebuildRecord(_ phrase: MyPhrase) async throws(ReferenceSetError) -> DerivedRecord {
        rebuilds[phrase.id, default: 0] += 1
        do {
            let record = try await rebuilder.rebuild(phrase, try clip(phrase.id))
            try TakeFiles.replace(
                folder(phrase.id).appending(path: MyPhraseFiles.reference), with: try TakeFiles.encoder().encode(record))
            return record
        } catch {
            throw .cacheCorrupt(MyPhrase.recordingID)
        }
    }

    private static func decode(_ url: URL) -> MyPhrase? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MyPhrase.self, from: data)
    }
}
