// Shared fixtures for spec 12's tests: three readers of VCTK prompt 018 from the committed smoke set (CC BY 4.0) with
// their replayed word timings, a reference set over two of them, and fakes for the seams (recogniser, pitch, store).
// No ASR, no network, no microphone.

import AMAlignment
import AMCore
import AMLibrary
import AMPipeline
import AMPlacement
import AMProsody
import AMVerdicts
import AMPitch
import Foundation
import Synchronization
import Testing

enum PipelineFixtures {
    static let detector = SmokePlacementGoldenTests.detector
    /// The prompt: 018 ("Aristotle thought that the rainbow was caused by reflection of the sun's rays by the rain",
    /// 4.6 s) by default; 002 (3.1 s) for the 3 s latency figure.
    static let prompt = "018"
    static var phraseID: PhraseID { PhraseID("vctk-" + prompt) }
    /// Your take: p245; the selected voice p288; the other native reader p360.
    static let youItem = "vctk-p245_018"
    static let modelItem = "vctk-p288_018"
    static let otherItem = "vctk-p360_018"
    static let recordedAt = Date(timeIntervalSince1970: 1_795_000_000)

    static func items() throws -> [String: PlacementFixtureItem] {
        let inputs = try JSONDecoder().decode(
            PlacementFixtureFile.self, from: Data(contentsOf: detector.appendingPathComponent("inputs.json")))
        return Dictionary(uniqueKeysWithValues: inputs.items.map { ($0.item, $0) })
    }

    static func timings() throws -> FixtureTimestamper {
        try FixtureTimestamper(directory: detector.appendingPathComponent("timestamps"))
    }

    static func take(_ item: PlacementFixtureItem) throws -> TakeAudio {
        let samples = try SmokePlacementGoldenTests.readMono(SmokePlacementGoldenTests.smoke.appendingPathComponent(item.audio))
        return TakeAudio(samples: samples, sha256: item.audioSHA256, clipID: item.item, recordedAt: recordedAt)
    }

    static func phrase(_ item: PlacementFixtureItem, revision: Int = 0) throws -> PhraseInput {
        PhraseInput(
            id: PhraseID("vctk-" + (item.item.split(separator: "_").last.map(String.init) ?? prompt)),
            words: try item.words.map {
                PlacementTake.Word(
                    index: WordIndex($0.index), text: $0.text, pronunciation: try Pronunciation(arpabet: $0.phones),
                    accepted: $0.accepted.map(Set.init))
            }, transcriptRevision: revision)
    }

    static func voice(_ item: String) -> RecordingID { RecordingID(item) }

    /// Everything a test needs, built once per test.
    struct World {
        let you: TakeAudio
        let phrase: PhraseInput
        let reference: FixtureReferenceSet
        let timings: FixtureTimestamper
    }

    static func world(prompt: String = prompt) async throws -> World {
        func named(_ item: String) -> String { item.replacingOccurrences(of: "_" + Self.prompt, with: "_" + prompt) }
        let items = try items()
        let timings = try timings()
        let you = try take(items[named(youItem)]!)
        let phrase = try phrase(items[named(youItem)]!)
        let builder = Analyzer(speech: SpeechModelHost(ready: timings), configuration: try .shipped())
        var natives: [NativeRecording] = []
        for name in [modelItem, otherItem] {
            let item = items[named(name)]!
            let record = try await builder.analyseNative(take: try take(item), phrase: phrase)
            natives.append(NativeRecording(
                id: voice(name), voice: item.speaker, audioSHA256: item.audioSHA256, analysis: record))
        }
        return World(you: you, phrase: phrase, reference: FixtureReferenceSet(natives: natives), timings: timings)
    }

    static func analyzer(
        _ world: World, timestamper: (any WordTimestamper)? = nil, pitch: (any PitchTracker)? = nil,
        beforeStage: (@Sendable (Stage) async throws -> Void)? = nil, scorer: (any PairScorer)? = nil
    ) throws -> Analyzer {
        var configuration = try Analyzer.Configuration.shipped()
        if let pitch { configuration.pitchTracker = pitch }
        if let scorer { configuration.scorer = scorer }
        configuration.beforeStage = beforeStage
        return Analyzer(speech: SpeechModelHost(ready: timestamper ?? world.timings), configuration: configuration)
    }
}

/// A reference set over precomputed native records. Can serve corrupt bytes a number of times, and can move its
/// identity (a transcript edit landing while a request is in flight).
final class FixtureReferenceSet: ReferenceSet {
    private struct State {
        var natives: [NativeRecording]
        var corruptReads: [RecordingID: Int] = [:]
        var rebuilds: [RecordingID] = []
        var transcriptRevision = 0
    }

    private let state: Mutex<State>

    init(natives: [NativeRecording]) { state = Mutex(State(natives: natives)) }

    /// The next `count` reads of `recording` return bytes that don't decode.
    func corrupt(_ recording: RecordingID, reads count: Int) { state.withLock { $0.corruptReads[recording] = count } }
    func bumpTranscriptRevision() { state.withLock { $0.transcriptRevision += 1 } }
    var rebuilds: [RecordingID] { state.withLock { $0.rebuilds } }

    func identity(phrase: PhraseID, voice: RecordingID) -> ReferenceIdentity {
        state.withLock { state in
            let hashes = state.natives.map(\.audioSHA256).sorted()
            let selected = state.natives.first { $0.id == voice }
            return ReferenceIdentity(
                phraseID: phrase, recordingID: voice, recordingSHA256: selected?.audioSHA256 ?? "",
                transcriptRevision: state.transcriptRevision, pronunciationOverridesHash: "none", targetsHash: "none",
                nativeSetHash: SHA256Digest.hex(of: Data(hashes.joined(separator: "\n").utf8)))
        }
    }

    func natives(phrase: PhraseID) async throws(ReferenceSetError) -> [NativeRecording] {
        state.withLock { state in
            state.natives.map { native in
                guard let left = state.corruptReads[native.id], left > 0 else { return native }
                state.corruptReads[native.id] = left - 1
                return NativeRecording(
                    id: native.id, voice: native.voice, audioSHA256: native.audioSHA256,
                    analysis: DerivedRecord(level: .l1, key: native.analysis.key, bytes: Data("corrupt".utf8)))
            }
        }
    }

    func rebuild(_ recording: RecordingID, phrase: PhraseID) async throws(ReferenceSetError) {
        state.withLock { $0.rebuilds.append(recording) }
    }
}

/// Counts calls into a wrapped recogniser.
final class CountingTimestamper: WordTimestamper {
    let base: any WordTimestamper
    private let count = Atomic<Int>(0)
    init(_ base: any WordTimestamper) { self.base = base }
    var asrModelID: String { base.asrModelID }
    var calls: Int { count.load(ordering: .relaxed) }
    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] {
        count.add(1, ordering: .relaxed)
        return try await base.wordTimestamps(for: request)
    }
}

/// Counts calls into a wrapped pitch tracker.
final class CountingPitchTracker: PitchTracker {
    let base: any PitchTracker
    private let count = Atomic<Int>(0)
    init(_ base: any PitchTracker) { self.base = base }
    var id: String { base.id }
    var calls: Int { count.load(ordering: .relaxed) }
    func track(_ samples: [Float], sampleRate: Double) async throws -> PitchTrack {
        count.add(1, ordering: .relaxed)
        return try await base.track(samples, sampleRate: sampleRate)
    }
}

/// A recogniser that takes `seconds` like a real decode, stopping at once when cancelled (as WhisperKit's early-stop
/// callback does), then answers with the replayed words.
struct SlowTimestamper: WordTimestamper {
    let base: any WordTimestamper
    let seconds: Double
    var asrModelID: String { base.asrModelID }
    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] {
        try await Task.sleep(for: .seconds(seconds))
        return try await base.wordTimestamps(for: request)
    }
}

/// An in-memory take store.
actor FakeTakeStore: TakePersisting {
    private(set) var saved: [TakeRecord] = []
    private let failure: StorageError?

    init(failing failure: StorageError? = nil) { self.failure = failure }

    func save(_ take: TakeRecord) async throws(StorageError) -> SavedTake {
        if let failure { throw failure }
        saved.append(take)
        return SavedTake(id: take.takeID)
    }
}

struct InjectedError: Error {}
