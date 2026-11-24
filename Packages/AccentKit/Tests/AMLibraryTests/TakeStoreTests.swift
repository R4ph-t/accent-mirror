// Spec 16: the take store on disk. Every test works in its own temporary folder, with a fake recomputer standing in
// for `AMPipeline`; no real `Application Support`, no audio committed (the samples are synthesised).

import AMCore
import AMLibrary
import Foundation
import Synchronization
import Testing

/// A temporary root, deleted when the fixture goes.
final class TakeStoreFixture: Sendable {
    let parent: URL
    let root: URL
    let recomputer = FakeRecomputer()

    init() throws {
        parent = FileManager.default.temporaryDirectory.appending(path: "TakeStoreTests-\(UUID().uuidString)")
        root = parent.appending(path: "Accent Mirror")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        chmod(root.path, 0o755)
        try? FileManager.default.removeItem(at: parent)
    }

    /// A store over the root, as one launch of the app sees it.
    func store(_ faults: TakeStore.Faults = TakeStore.Faults()) -> TakeStore {
        TakeStore(root: root, recomputer: recomputer.recomputer, faults: faults)
    }

    static let phrase = PhraseID("vctk-018")
    static let voice = RecordingID("p288_018")

    /// Take `n`: a short synthetic tone, distinct per `n`, with its L0, L1 and L2 records for `voice`.
    func record(_ n: Int, voice: RecordingID = voice, phrase: PhraseID = phrase) -> TakeRecord {
        let samples = (0..<1_600).map { Float(sin(Double($0) * 0.01 * Double(n + 1))) * 0.5 }
        let sha = FakeRecomputer.sha(samples)
        let keys = recomputer.keys(phrase: phrase, sha: sha, voice: voice)
        return TakeRecord(
            takeID: TakeID("take-\(n)"), phraseID: phrase, recording: voice,
            recordedAt: Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(n) * 60), audioSHA256: sha,
            samples: samples,
            derived: [
                DerivedRecord(level: .l0, key: "l0-\(sha)", bytes: Data("l0".utf8)),
                DerivedRecord(level: .l1, key: keys.features, bytes: Data("l1".utf8)),
                DerivedRecord(level: .l2, key: keys.comparison, bytes: Data("l2 saved".utf8)),
            ])
    }

    func ref(_ n: Int, phrase: PhraseID = phrase) -> TakeRef { TakeRef(phrase: phrase, id: TakeID("take-\(n)")) }

    var takes: URL { root.appending(path: "phrases/vctk-018/takes") }

    func entries(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }
}

/// `AMPipeline`'s side, faked: keys that move with a thresholds version, and a recompute that records what it read.
final class FakeRecomputer: Sendable {
    struct State {
        var thresholdsVersion = 1
        var recomputes: [(audio: StoredTakeAudio, voice: RecordingID)] = []
        var fails = false
    }

    let state = Mutex(State())

    static func sha(_ samples: [Float]) -> String {
        var bytes: [UInt8] = []
        for sample in samples { withUnsafeBytes(of: sample.bitPattern.littleEndian) { bytes.append(contentsOf: $0) } }
        return SHA256Digest.hex(of: bytes)
    }

    func keys(phrase: PhraseID, sha: String, voice: RecordingID) -> TakeRecomputer.Keys {
        let version = state.withLock { $0.thresholdsVersion }
        return TakeRecomputer.Keys(features: "l1-\(phrase)-\(sha)", comparison: "l2-\(voice)-t\(version)-\(sha)")
    }

    var recomputer: TakeRecomputer {
        TakeRecomputer(
            expectedKeys: { [self] phrase, sha, voice in keys(phrase: phrase, sha: sha, voice: voice) },
            recompute: { [self] audio, voice in
                let fails = state.withLock { state in
                    state.recomputes.append((audio, voice))
                    return state.fails
                }
                if fails { throw CancellationError() }
                let keys = keys(phrase: audio.ref.phrase, sha: audio.audioSHA256, voice: voice)
                return [
                    DerivedRecord(level: .l0, key: "l0-\(audio.audioSHA256)", bytes: Data("l0".utf8)),
                    DerivedRecord(level: .l1, key: keys.features, bytes: Data("l1".utf8)),
                    DerivedRecord(level: .l2, key: keys.comparison, bytes: Data("l2 recomputed".utf8)),
                ]
            })
    }

    var recomputes: Int { state.withLock { $0.recomputes.count } }
}

@Suite("Take store: save, list, prune") struct TakeStoreSaveTests {
    @Test("A saved take is listed after a relaunch, with its number, time, status and voice")
    func saveThenRelaunch() async throws {
        let fixture = try TakeStoreFixture()
        let record = fixture.record(1)
        let saved = try await fixture.store().save(record)
        #expect(saved == SavedTake(id: record.takeID))

        let relaunched = fixture.store()
        let report = await relaunched.recover()
        #expect(report.quarantined.isEmpty)
        let takes = await relaunched.takes(for: TakeStoreFixture.phrase)
        #expect(takes.count == 1)
        let take = try #require(takes.first)
        #expect(take.ref == fixture.ref(1))
        #expect(take.number == 1 && take.title == "Take 1")
        #expect(take.recordedAt == record.recordedAt)
        #expect(take.status == .comparable)
        #expect(take.voices == [TakeStoreFixture.voice])
        #expect(fixture.entries(fixture.takes.appending(path: "take-1"))
            == ["audio.caf", "comparison-p288_018.json", "features.json", "manifest.json"])

        // The stored comparison is served as is: no recompute.
        let l2 = try await relaunched.result(take: take.ref, voice: TakeStoreFixture.voice)
        #expect(l2.bytes == Data("l2 saved".utf8))
        #expect(fixture.recomputer.recomputes == 0)
    }

    @Test("The 11th take prunes the oldest; numbers keep counting and are never reused")
    func eleventhTakePrunesOldest() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        for n in 1...10 { _ = try await store.save(fixture.record(n)) }
        #expect(await store.takes(for: TakeStoreFixture.phrase).count == 10)

        let saved = try await store.save(fixture.record(11))
        #expect(saved.pruneFailure == nil)
        let takes = await store.takes(for: TakeStoreFixture.phrase)
        #expect(takes.map(\.number) == Array((2...11).reversed()))
        #expect(!takes.contains { $0.ref == fixture.ref(1) })
        #expect(fixture.entries(fixture.takes.appending(path: ".trash")).isEmpty)

        // Deleting the newest doesn't free its number.
        try await store.delete(take: fixture.ref(11))
        _ = try await store.save(fixture.record(12))
        #expect(await store.takes(for: TakeStoreFixture.phrase).first?.number == 12)
        let relaunched = fixture.store()
        await relaunched.recover()
        _ = try await relaunched.save(fixture.record(13))
        #expect(await relaunched.takes(for: TakeStoreFixture.phrase).first?.number == 13)
    }

    @Test("Unalignable takes count toward the 10")
    func unalignableTakesCount() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        for n in 1...10 { _ = try await store.save(fixture.record(n)) }
        for n in 1...3 { try await store.markUnalignable(take: fixture.ref(n), reason: "transcript changed") }
        _ = try await store.save(fixture.record(11))
        let takes = await store.takes(for: TakeStoreFixture.phrase)
        #expect(takes.count == 10)
        #expect(takes.last?.ref == fixture.ref(2))
        #expect(takes.last?.status == .unalignable(reason: "transcript changed"))
    }

    @Test("The same take saved again (a voice switch) keeps its folder and number")
    func resaveKeepsTake() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        _ = try await store.save(fixture.record(1))
        _ = try await store.save(fixture.record(2))
        let other = RecordingID("p360_018")
        let saved = try await store.save(fixture.record(1, voice: other))
        #expect(saved.id == TakeID("take-1"))
        let takes = await store.takes(for: TakeStoreFixture.phrase)
        #expect(takes.map(\.number) == [2, 1])
        #expect(takes.last?.voices == [other, TakeStoreFixture.voice])
    }

    @Test("Takes of different phrases are numbered and pruned separately")
    func phrasesAreSeparate() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        let other = PhraseID("vctk-002")
        for n in 1...11 { _ = try await store.save(fixture.record(n)) }
        _ = try await store.save(fixture.record(1, phrase: other))
        #expect(await store.takes(for: other).map(\.number) == [1])
        #expect(await store.takes(for: TakeStoreFixture.phrase).count == 10)
    }

    @Test("A prune failure gives savedPruneFailed; the next launch prunes")
    func pruneFailureRetriedAtLaunch() async throws {
        let fixture = try TakeStoreFixture()
        let failing = fixture.store(TakeStore.Faults(pruneFails: true))
        for n in 1...10 { #expect(try await failing.save(fixture.record(n)).pruneFailure == nil) }
        let saved = try await failing.save(fixture.record(11))
        #expect(saved == SavedTake(id: TakeID("take-11"), pruneFailure: .ioFailure))
        #expect(await failing.takes(for: TakeStoreFixture.phrase).count == 11)

        let relaunched = fixture.store()
        let report = await relaunched.recover()
        #expect(report.pruneFailures.isEmpty)
        let takes = await relaunched.takes(for: TakeStoreFixture.phrase)
        #expect(takes.map(\.number) == Array((2...11).reversed()))
    }

    @Test("A failed save is saveFailed and lists nothing; nothing is pruned")
    func saveFailure() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        for n in 1...10 { _ = try await store.save(fixture.record(n)) }
        // The takes folder is read-only: the commit can't happen.
        #expect(chmod(fixture.takes.path, 0o555) == 0)
        defer { chmod(fixture.takes.path, 0o755) }
        await #expect(throws: StorageError.permissionDenied) { _ = try await store.save(fixture.record(11)) }
        chmod(fixture.takes.path, 0o755)
        let takes = await store.takes(for: TakeStoreFixture.phrase)
        #expect(takes.count == 10)
        #expect(takes.last?.ref == fixture.ref(1))
    }

    @Test("The store writes only under its root")
    func writesOnlyUnderRoot() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        for n in 1...11 { _ = try await store.save(fixture.record(n)) }
        _ = try await store.result(take: fixture.ref(5), voice: RecordingID("p360_018"))
        try await store.delete(take: fixture.ref(5))
        await fixture.store().recover()
        #expect(fixture.entries(fixture.parent) == ["Accent Mirror"])
        #expect(fixture.entries(fixture.root) == ["phrases"])
    }
}

@Suite("Take store: crash safety and recovery") struct TakeStoreRecoveryTests {
    @Test("A crash after each save step leaves no partial take listed, and recovery cleans .staging",
          arguments: TakeStore.SaveStep.allCases)
    func crashAfterStep(_ step: TakeStore.SaveStep) async throws {
        let fixture = try TakeStoreFixture()
        _ = try await fixture.store().save(fixture.record(1))
        let crashing = fixture.store(TakeStore.Faults(crashAfter: step))
        await #expect(throws: StorageError.self) { _ = try await crashing.save(fixture.record(2)) }

        let committed = step == .commit
        let staged = fixture.entries(fixture.takes.appending(path: ".staging"))
        #expect(staged == (committed ? [] : ["take-2"]))
        // Listed before recovery: only complete takes.
        let before = await crashing.takes(for: TakeStoreFixture.phrase).map(\.number)
        #expect(before == (committed ? [2, 1] : [1]))

        let relaunched = fixture.store()
        let report = await relaunched.recover()
        #expect(report.quarantined.isEmpty)
        #expect(fixture.entries(fixture.takes.appending(path: ".staging")).isEmpty)
        let after = await relaunched.takes(for: TakeStoreFixture.phrase)
        #expect(after.map(\.ref) == (committed ? [fixture.ref(2), fixture.ref(1)] : [fixture.ref(1)]))
        // The next take never reuses a number a crash may have taken.
        _ = try await relaunched.save(fixture.record(3))
        #expect(await relaunched.takes(for: TakeStoreFixture.phrase).first?.number == 3)
    }

    @Test("An audio hash mismatch or a missing manifest quarantines the take and leaves it out of the list")
    func quarantine() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        for n in 1...3 { _ = try await store.save(fixture.record(n)) }
        let audio = fixture.takes.appending(path: "take-1/audio.caf")
        var bytes = try Data(contentsOf: audio)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: audio)
        try FileManager.default.removeItem(at: fixture.takes.appending(path: "take-2/manifest.json"))

        let relaunched = fixture.store()
        let report = await relaunched.recover()
        #expect(Set(report.quarantined) == [fixture.ref(1), fixture.ref(2)])
        #expect(await relaunched.takes(for: TakeStoreFixture.phrase).map(\.ref) == [fixture.ref(3)])
        let quarantined = fixture.entries(fixture.takes.appending(path: ".quarantine"))
        #expect(quarantined.count == 2)
        #expect(quarantined.allSatisfy { $0.hasPrefix("take-1-") || $0.hasPrefix("take-2-") })
        #expect(fixture.entries(fixture.takes).filter { !$0.hasPrefix(".") } == ["take-3"])
    }

    @Test("Recovery empties a leftover .trash")
    func recoveryEmptiesTrash() async throws {
        let fixture = try TakeStoreFixture()
        _ = try await fixture.store().save(fixture.record(1))
        let leftover = fixture.takes.appending(path: ".trash/take-0-crashed")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: leftover.appending(path: "audio.caf"))
        let report = await fixture.store().recover()
        #expect(report.cleaned >= 1)
        #expect(fixture.entries(fixture.takes.appending(path: ".trash")).isEmpty)
    }
}

@Suite("Take store: derived records") struct TakeStoreDerivedTests {
    @Test("A thresholdsVersion change keeps the take and recomputes its L2 lazily, from the stored audio, once")
    func identityChangeRecomputesLazily() async throws {
        let fixture = try TakeStoreFixture()
        let record = fixture.record(1)
        _ = try await fixture.store().save(record)
        fixture.recomputer.state.withLock { $0.thresholdsVersion = 2 }

        let relaunched = fixture.store()
        let report = await relaunched.recover()
        #expect(report.quarantined.isEmpty)
        #expect(await relaunched.takes(for: TakeStoreFixture.phrase).map(\.ref) == [fixture.ref(1)])
        #expect(fixture.recomputer.recomputes == 0, "nothing is recomputed until it's needed")

        let l2 = try await relaunched.result(take: fixture.ref(1), voice: TakeStoreFixture.voice)
        #expect(l2.key == "l2-\(TakeStoreFixture.voice)-t2-\(record.audioSHA256)")
        #expect(l2.bytes == Data("l2 recomputed".utf8))
        let recomputed = try #require(fixture.recomputer.state.withLock { $0.recomputes.first })
        #expect(recomputed.audio.samples == record.samples, "the stored audio is bit-exact")
        #expect(recomputed.audio.audioSHA256 == record.audioSHA256)
        #expect(recomputed.audio.recordedAt == record.recordedAt)

        // Stored: the next read (and the next launch) is served from disk.
        _ = try await relaunched.result(take: fixture.ref(1), voice: TakeStoreFixture.voice)
        _ = try await fixture.store().result(take: fixture.ref(1), voice: TakeStoreFixture.voice)
        #expect(fixture.recomputer.recomputes == 1)
    }

    @Test("Missing or tampered derived JSON keeps the take and recomputes")
    func missingDerivedRecomputes() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        _ = try await store.save(fixture.record(1))
        _ = try await store.save(fixture.record(2))
        try FileManager.default.removeItem(at: fixture.takes.appending(path: "take-1/features.json"))
        try Data("{}".utf8).write(to: fixture.takes.appending(path: "take-2/comparison-p288_018.json"))
        await fixture.store().recover()
        #expect(await store.takes(for: TakeStoreFixture.phrase).count == 2)
        _ = try await store.result(take: fixture.ref(1), voice: TakeStoreFixture.voice)
        _ = try await store.result(take: fixture.ref(2), voice: TakeStoreFixture.voice)
        #expect(fixture.recomputer.recomputes == 2)
        #expect(fixture.entries(fixture.takes.appending(path: "take-1")).contains("features.json"))
    }

    @Test("L2 is kept for at most 3 voices, the least recently used dropped first")
    func threeVoicesKept() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        _ = try await store.save(fixture.record(1))
        let (a, b, c, d) = (TakeStoreFixture.voice, RecordingID("b"), RecordingID("c"), RecordingID("d"))
        for voice in [b, c] { _ = try await store.result(take: fixture.ref(1), voice: voice) }
        // Reading a refreshes it: b is now the least recently used.
        _ = try await store.result(take: fixture.ref(1), voice: a)
        _ = try await store.result(take: fixture.ref(1), voice: c)
        #expect(await store.takes(for: TakeStoreFixture.phrase).first?.voices == [c, a, b])
        _ = try await store.result(take: fixture.ref(1), voice: d)
        #expect(await store.takes(for: TakeStoreFixture.phrase).first?.voices == [d, c, a])
        #expect(fixture.entries(fixture.takes.appending(path: "take-1")).filter { $0.hasPrefix("comparison-") }
            == ["comparison-c.json", "comparison-d.json", "comparison-p288_018.json"])
        #expect(fixture.recomputer.recomputes == 3)
        _ = try await store.result(take: fixture.ref(1), voice: b)
        #expect(fixture.recomputer.recomputes == 4, "b was evicted")
        #expect(await store.takes(for: TakeStoreFixture.phrase).first?.voices == [b, d, c])
    }

    @Test("A recompute that fails is recomputeFailed; an unknown take is notFound")
    func resultErrors() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        _ = try await store.save(fixture.record(1))
        fixture.recomputer.state.withLock { $0.fails = true }
        await #expect(throws: TakeStoreError.recomputeFailed(fixture.ref(1))) {
            _ = try await store.result(take: fixture.ref(1), voice: RecordingID("other"))
        }
        await #expect(throws: TakeStoreError.notFound(fixture.ref(9))) {
            _ = try await store.result(take: fixture.ref(9), voice: TakeStoreFixture.voice)
        }
    }

    @Test("ghosts(before:) gives up to 3 earlier takes, newest first, never unalignable ones")
    func ghostsSkipUnalignable() async throws {
        let fixture = try TakeStoreFixture()
        let store = fixture.store()
        for n in 1...6 { _ = try await store.save(fixture.record(n)) }
        try await store.markUnalignable(take: fixture.ref(4), reason: "words don't match")

        let ghosts = await store.ghosts(before: fixture.ref(6), voice: TakeStoreFixture.voice)
        #expect(ghosts.map(\.take.number) == [5, 3, 2])
        #expect(ghosts.allSatisfy { $0.comparison.level == .l2 && $0.take.status == .comparable })
        #expect(await store.ghosts(before: fixture.ref(2), voice: TakeStoreFixture.voice).map(\.take.number) == [1])
        #expect(await store.ghosts(before: fixture.ref(1), voice: TakeStoreFixture.voice).isEmpty)
        // For another voice the ghosts' comparisons are computed on demand.
        let other = await store.ghosts(before: fixture.ref(6), voice: RecordingID("p360_018"))
        #expect(other.map(\.take.number) == [5, 3, 2])
        #expect(fixture.recomputer.recomputes == 3)
    }

    @Test("markUnalignable survives a relaunch")
    func unalignablePersists() async throws {
        let fixture = try TakeStoreFixture()
        _ = try await fixture.store().save(fixture.record(1))
        try await fixture.store().markUnalignable(take: fixture.ref(1), reason: "transcript edited")
        let relaunched = fixture.store()
        await relaunched.recover()
        #expect(await relaunched.takes(for: TakeStoreFixture.phrase).first?.status
            == .unalignable(reason: "transcript edited"))
    }
}
