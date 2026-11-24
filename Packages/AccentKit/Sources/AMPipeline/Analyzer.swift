// The analysis pipeline (spec 12, plan §8–§10): your take, a phrase and a native reference in, one
// `AnalysisResponse` out. Stages, each behind its module's API:
//
//   decode → take quality (spec 05) → ASR words ∥ pitch (specs 03, 04), voicing from the quality pass →
//   boundary source (spec 23) and word alignment (spec 06) → syllables (spec 07) → prominence and observed stress
//   (spec 08) → time map and band (spec 09) → measures and verdict (spec 10).
//
// L0 and L1 are cached per take, L2 per take and reference, so a voice switch recomputes L2 only. The reference side
// is read from the `ReferenceSet`, never recomputed during a take. A stage that throws becomes
// `failed(.inferenceFailed(stage:))`; a cancelled request returns `.cancelled`.

import AMAlignment
import AMCapture
import AMCore
import AMLibrary
import AMPitch
import AMProsody
import AMScoring
import AMWarp
import Foundation
import os

/// Thrown by a stage (or a seam it calls) to report an operational error as itself rather than as
/// `inferenceFailed(stage:)`.
public struct OperationalFailure: Error, Sendable, Hashable {
    public let error: OperationalError
    public init(_ error: OperationalError) { self.error = error }
}

public actor Analyzer {
    public struct Configuration: Sendable {
        public var pitchTracker: any PitchTracker
        public var voicing: any VoicingSource
        /// The word-boundary source after ASR (spec 23); its `id` is `ConfigIdentity.aligner` and part of the L1 key.
        public var boundaryRefiner: any WordBoundaryRefiner
        public var aligner: WordAligner
        public var thresholds: Thresholds
        /// Takes (L0, L1) and comparisons (L2) kept in memory.
        public var cacheCapacity: Int
        /// Runs before every stage, inside its signpost interval: a stage that it throws from fails as that stage
        /// would. Diagnostics and tests only (the shipped configuration has none).
        public var beforeStage: (@Sendable (Stage) async throws -> Void)?

        public init(
            pitchTracker: any PitchTracker, voicing: any VoicingSource, boundaryRefiner: any WordBoundaryRefiner,
            aligner: WordAligner, thresholds: Thresholds = .current, cacheCapacity: Int = 8,
            beforeStage: (@Sendable (Stage) async throws -> Void)? = nil
        ) {
            self.pitchTracker = pitchTracker
            self.voicing = voicing
            self.boundaryRefiner = boundaryRefiner
            self.aligner = aligner
            self.thresholds = thresholds
            self.cacheCapacity = cacheCapacity
            self.beforeStage = beforeStage
        }

        /// What the app runs: spec 04's pYIN, spec 05's voicing, `ShippedConfig`'s boundary source, spec 06's aligner.
        public static func shipped(thresholds: Thresholds = .current) throws -> Configuration {
            Configuration(
                pitchTracker: PYINTracker(thresholds: thresholds.pitch), voicing: ACFVoicing(thresholds: thresholds),
                boundaryRefiner: ShippedConfig.wordBoundaryRefiner, aligner: try WordAligner.bundled(thresholds: thresholds),
                thresholds: thresholds)
        }
    }

    /// How often each level was computed or served from the cache.
    public struct Statistics: Sendable, Hashable {
        public var l0Computed = 0, l1Computed = 0, l2Computed = 0
        public var l0Hits = 0, l1Hits = 0, l2Hits = 0
    }

    /// One request's full run: the response, each stage's wall time, and what can be saved or evaluated.
    public struct Run: Sendable {
        public let response: AnalysisResponse
        /// Seconds per stage that ran (ASR and pitch overlap). A cached level's stages don't appear.
        public let timings: [Stage: Double]
        /// L0, L1 and L2 as records, for the take store; empty unless the take reached L2.
        public let derived: [DerivedRecord]
        /// The comparison, when the take reached it.
        public let l2: L2Analysis?
    }

    public let speech: SpeechModelHost
    public let configuration: Configuration
    public private(set) var statistics = Statistics()
    private let detector: StressPlacementDetector
    private var l0Cache: LevelCache<L0Key, L0Analysis>
    private var l1Cache: LevelCache<L1Key, L1Analysis>
    private var l2Cache: LevelCache<L2Key, L2Analysis>

    static let signposter = OSSignposter(subsystem: "AccentMirror", category: "Analysis")

    public init(speech: SpeechModelHost, configuration: Configuration) {
        self.speech = speech
        self.configuration = configuration
        detector = StressPlacementDetector(
            voicing: configuration.voicing, pitchTracker: configuration.pitchTracker, aligner: configuration.aligner,
            thresholds: configuration.thresholds)
        l0Cache = LevelCache(capacity: configuration.cacheCapacity)
        l1Cache = LevelCache(capacity: configuration.cacheCapacity)
        l2Cache = LevelCache(capacity: configuration.cacheCapacity * 4)
    }

    /// The configuration identity of every analysis this analyzer produces.
    public nonisolated var config: ConfigIdentity {
        ConfigIdentity(
            asrModelID: speech.asrModelID, pitchTrackerID: configuration.pitchTracker.id,
            voicingID: configuration.voicing.id, aligner: configuration.boundaryRefiner.id, alignerModelSHA256: "none")
    }

    /// Analyses `take` of `phrase` against `voice`'s recording in `reference`.
    public func analyse(
        take: TakeAudio, phrase: PhraseInput, reference: any ReferenceSet, voice: RecordingID,
        requestID: RequestID = RequestID()
    ) async -> AnalysisResponse {
        await run(take: take, phrase: phrase, reference: reference, voice: voice, requestID: requestID).response
    }

    /// `analyse`, with the stage timings and the derived records.
    public func run(
        take: TakeAudio, phrase: PhraseInput, reference: any ReferenceSet, voice: RecordingID,
        requestID: RequestID = RequestID()
    ) async -> Run {
        let identity = AnalysisIdentity(
            takeAudioSHA256: take.sha256, reference: reference.identity(phrase: phrase.id, voice: voice), config: config)
        var clock = StageClock()
        func respond(_ outcome: AnalysisOutcome, derived: [DerivedRecord] = [], l2: L2Analysis? = nil) -> Run {
            Run(
                response: AnalysisResponse(requestID: requestID, identity: identity, outcome: outcome),
                timings: clock.seconds, derived: derived, l2: l2)
        }
        do {
            let l0 = try await takeL0(take, clock: &clock)
            if let problem = TakeProblem.first(of: l0.takeProblems) { return respond(.takeProblem(problem)) }
            let l1 = try await takeL1(take, phrase: phrase, l0: l0, clock: &clock)
            let l2 = try await compare(
                take: take, phrase: phrase, l1: l1, reference: reference, voice: voice, identity: identity,
                clock: &clock)
            try Task.checkCancellation()
            let derived = try [DerivedCoding.record(l0), DerivedCoding.record(l1), DerivedCoding.record(l2)]
            return respond(l2.outcome, derived: derived, l2: l2)
        } catch {
            return respond(Self.outcome(of: error))
        }
    }

    /// A native recording's L0 and L1, as the reference set stores them (spec 15 builds its records with this; the
    /// agreement harness builds the positive set's references with it). Throws what a stage throws.
    public func analyseNative(take: TakeAudio, phrase: PhraseInput) async throws -> DerivedRecord {
        var clock = StageClock()
        let l0 = try await takeL0(take, clock: &clock, checkQuality: false)
        let l1 = try await takeL1(take, phrase: phrase, l0: l0, clock: &clock)
        return try DerivedCoding.record(NativeAnalysis(l0: l0, l1: l1))
    }

    // MARK: - Levels

    func l0Key(_ take: TakeAudio) -> L0Key {
        L0Key(
            takeAudioSHA256: take.sha256, asrModelID: speech.asrModelID, pitchTrackerID: configuration.pitchTracker.id,
            voicingID: configuration.voicing.id)
    }

    /// Decode, take quality, then ASR alongside pitch. Voicing comes from the quality pass (spec 05 decides both in
    /// one pass over the take). A take with a problem stops here and is not cached.
    private func takeL0(_ take: TakeAudio, clock: inout StageClock, checkQuality: Bool = true) async throws
        -> L0Analysis
    {
        let key = l0Key(take)
        if let cached = l0Cache[key] {
            statistics.l0Hits += 1
            return cached
        }
        let quality = try await stage(.decodeAudio, &clock) { () throws -> TakeAnalysis in
            guard !take.samples.isEmpty, take.samples.allSatisfy(\.isFinite) else {
                throw OperationalFailure(.audioUnreadable)
            }
            return TakeAnalysis(samples: take.samples, sampleRate: TakeAudio.sampleRate, thresholds: configuration.thresholds)
        }
        if checkQuality, !quality.problems.isEmpty {
            return L0Analysis(key: key, takeProblems: quality.problems, voiced: [], pitch: PitchTrack(frameF0Hz: []), words: [])
        }
        let voiced = try await stage(.detectVoicing, &clock) { () throws -> [Bool] in
            configuration.voicing.id == ACFVoicing.voicingID
                ? quality.voiced
                : configuration.voicing.voicedFrames(samples: take.samples, sampleRate: TakeAudio.sampleRate)
        }
        async let words = recognise(take)
        async let pitch = trackPitch(take)
        let (heard, track) = try await (words, pitch)
        clock.record(.recogniseWords, heard.seconds)
        clock.record(.trackPitch, track.seconds)
        let l0 = L0Analysis(key: key, takeProblems: [], voiced: voiced, pitch: track.value, words: heard.value)
        l0Cache.insert(l0, for: key)
        statistics.l0Computed += 1
        return l0
    }

    /// The recogniser, through the model host: ASR runs inside `withTaskCancellationHandler` (WhisperKit's early-stop
    /// callback returns `false` on cancel); the model stays loaded.
    private func recognise(_ take: TakeAudio) async throws -> Timed<[WordTimestamp]> {
        try await timed(.recogniseWords) {
            let timestamper: any WordTimestamper
            do throws(ModelUnavailable) {
                timestamper = try await speech.timestamper()
            } catch {
                throw OperationalFailure(.modelUnavailable(error.failure))
            }
            return try await timestamper.wordTimestamps(
                for: TimestampRequest(clipID: take.clipID, samples: take.samples))
        }
    }

    /// pYIN checks for cancellation every 50 frames (spec 04).
    private func trackPitch(_ take: TakeAudio) async throws -> Timed<PitchTrack> {
        let tracker = configuration.pitchTracker
        return try await timed(.trackPitch) { try await tracker.track(take.samples, sampleRate: TakeAudio.sampleRate) }
    }

    private func takeL1(_ take: TakeAudio, phrase: PhraseInput, l0: L0Analysis, clock: inout StageClock) async throws
        -> L1Analysis
    {
        let key = L1Key(
            l0: l0.key, transcriptRevision: phrase.transcriptRevision, pronunciationHash: phrase.pronunciationHash,
            aligner: configuration.boundaryRefiner.id)
        if let cached = l1Cache[key] {
            statistics.l1Hits += 1
            return cached
        }
        let refiner = configuration.boundaryRefiner
        let (refined, aligned) = try await stage(.alignWords, &clock) { () async throws -> ([WordTimestamp], WordAlignmentResult) in
            let words = try await refiner.refine(l0.words, samples: take.samples, sampleRate: TakeAudio.sampleRate)
            try Task.checkCancellation()
            return (words, try detector.align(placementTake(take, phrase: phrase, heard: words, key: l0.key)))
        }
        let input = placementTake(take, phrase: phrase, heard: refined, key: l0.key)
        let voicing = StoredVoicing(id: configuration.voicing.id, frames: l0.voiced)
        let segmentation = try await stage(.segmentSyllables, &clock) {
            try detector.segment(
                input, alignment: aligned.alignment, voicing: voicing,
                transcriptRevision: phrase.transcriptRevision)
        }
        let analysis = try await stage(.measureStress, &clock) {
            detector.place(input, alignment: aligned.alignment, segmentation: segmentation, pitch: l0.pitch)
        }
        let l1 = L1Analysis(key: key, words: refined, summary: aligned.summary, analysis: analysis)
        l1Cache.insert(l1, for: key)
        statistics.l1Computed += 1
        return l1
    }

    private func placementTake(_ take: TakeAudio, phrase: PhraseInput, heard: [WordTimestamp], key: L0Key)
        -> PlacementTake
    {
        PlacementTake(
            samples: take.samples, sampleRate: TakeAudio.sampleRate, words: phrase.words, heard: heard, l0Key: key.text)
    }

    /// L2: the reference read from the set (one silent rebuild on a corrupt record), the time map and band, then
    /// measures and the verdict.
    private func compare(
        take: TakeAudio, phrase: PhraseInput, l1: L1Analysis, reference: any ReferenceSet, voice: RecordingID,
        identity: AnalysisIdentity, clock: inout StageClock
    ) async throws -> L2Analysis {
        let key = L2Key(l1: l1.key, reference: identity.reference, thresholdsVersion: Versions.thresholdsVersion)
        if let cached = l2Cache[key] {
            statistics.l2Hits += 1
            return cached
        }
        let thresholds = configuration.thresholds
        let natives = try await stage(.mapTime, &clock) { try await self.natives(reference, phrase: phrase) }
        guard let selected = natives.first(where: { $0.recording.id == voice }) else {
            throw OperationalFailure(.inferenceFailed(stage: .mapTime))
        }
        let (input, band) = try await stage(.mapTime, &clock) { () throws -> (ScoringInput, NativeBand) in
            var readings: [WordIndex: [NativeReading]] = [:]
            for native in natives {
                for result in native.analysis.l1.analysis.words {
                    guard let observed = result.observed else { continue }
                    readings[result.word, default: []].append(NativeReading(voice: native.recording.voice, observed: observed))
                }
            }
            let model = selected.analysis.l1.analysis
            let input = try PairScoring.input(
                words: phrase.words, you: l1.analysis, model: model, modelVoice: selected.recording.voice,
                natives: readings, thresholds: thresholds)
            let others = natives.filter { $0.recording.id != voice }.compactMap { native -> WarpedVoice? in
                guard let warp = try? PairScoring.warp(
                    you: native.analysis.l1.analysis, model: model, words: phrase.words, thresholds: thresholds)
                else { return nil }
                return WarpedVoice(
                    voice: NativeVoice(sha256: native.recording.audioSHA256, track: native.analysis.l1.analysis.pitch),
                    ontoSelected: warp)
            }
            let band = try NativeBand(
                selected: NativeVoice(sha256: selected.recording.audioSHA256, track: model.pitch), others: others,
                testTake: take.sha256, hopSeconds: model.pitch.hopSeconds, thresholds: thresholds.band)
            return (input, band)
        }
        let l2 = try await stage(.compare, &clock) { () throws -> L2Analysis in
            let scoring = try Scorer.score(input, thresholds: thresholds)
            let outcome: AnalysisOutcome = switch scoring.decision {
            case .takeProblem(let problem): .takeProblem(problem)
            case .verdict(let verdict):
                .analysed(try ResultAssembly.result(
                    take: take, phrase: phrase, you: l1.analysis, model: selected.analysis.l1.analysis,
                    scoring: scoring, warp: input.warp, band: band, verdict: verdict, identity: identity,
                    thresholds: thresholds))
            }
            return L2Analysis(
                key: key, outcome: outcome, applicability: scoring.applicability, measures: scoring.measures.states,
                modelValues: scoring.modelValues, referenceAnomaly: scoring.stress.contains(where: \.referenceAnomaly),
                bandCoverage: band.coverage(of: scoring.youPitchOnModel, warp: input.warp))
        }
        l2Cache.insert(l2, for: key)
        statistics.l2Computed += 1
        return l2
    }

    /// A native recording and its decoded analysis.
    struct LoadedNative: Sendable {
        let recording: NativeRecording
        let analysis: NativeAnalysis
    }

    /// The phrase's natives, decoded. A corrupt record (or one built for another phrase pronunciation or algorithm)
    /// triggers one silent rebuild of that recording; only a second failure is reported.
    private func natives(_ reference: any ReferenceSet, phrase: PhraseInput) async throws -> [LoadedNative] {
        var rebuilt: Set<RecordingID> = []
        while true {
            try Task.checkCancellation()
            var corrupt: RecordingID?
            var loaded: [LoadedNative] = []
            do {
                for recording in try await reference.natives(phrase: phrase.id) {
                    guard let native = DerivedCoding.native(in: recording.analysis),
                        native.l1.key.l0.takeAudioSHA256 == recording.audioSHA256,
                        native.l1.key.pronunciationHash == phrase.pronunciationHash,
                        native.l1.key.algorithmVersion == Versions.algorithmVersion
                    else {
                        corrupt = recording.id
                        break
                    }
                    loaded.append(LoadedNative(recording: recording, analysis: native))
                }
            } catch .cacheCorrupt(let recording) {
                corrupt = recording
            } catch .notFound {
                throw OperationalFailure(.inferenceFailed(stage: .mapTime))
            }
            guard let corrupt else { return loaded }
            guard rebuilt.insert(corrupt).inserted else { throw OperationalFailure(.referenceCacheCorrupt(corrupt)) }
            do {
                try await reference.rebuild(corrupt, phrase: phrase.id)
            } catch {
                throw OperationalFailure(.referenceCacheCorrupt(corrupt))
            }
        }
    }

    // MARK: - Stages

    /// Runs one stage inside its signpost interval, records its wall time, and names it in any failure.
    private func stage<T: Sendable>(_ stage: Stage, _ clock: inout StageClock, _ body: () async throws -> T) async throws -> T {
        let result = try await timed(stage, body)
        clock.record(stage, result.seconds)
        return result.value
    }

    private func timed<T: Sendable>(_ stage: Stage, _ body: () async throws -> T) async throws -> Timed<T> {
        try Task.checkCancellation()
        let signposter = Self.signposter
        let interval = signposter.beginInterval("stage", id: signposter.makeSignpostID(), "\(stage.rawValue)")
        defer { signposter.endInterval("stage", interval) }
        let start = ContinuousClock.now
        do {
            try await configuration.beforeStage?(stage)
            let value = try await body()
            try Task.checkCancellation()
            return Timed(value: value, seconds: (ContinuousClock.now - start).seconds)
        } catch let failure as OperationalFailure {
            throw failure
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw OperationalFailure(.inferenceFailed(stage: stage))
        }
    }

    static func outcome(of error: any Error) -> AnalysisOutcome {
        if Task.isCancelled || error is CancellationError { return .cancelled }
        if let failure = error as? OperationalFailure { return .failed(failure.error) }
        return .failed(.inferenceFailed(stage: .compare))
    }
}

/// A value and the seconds it took.
struct Timed<T: Sendable>: Sendable {
    let value: T
    let seconds: Double
}

/// Per-stage wall time for one request (a stage run twice adds up).
struct StageClock: Sendable {
    private(set) var seconds: [Stage: Double] = [:]
    mutating func record(_ stage: Stage, _ value: Double) { seconds[stage, default: 0] += value }
}

/// L0's voicing, replayed for the syllable segmenter so it isn't decided twice.
struct StoredVoicing: VoicingSource {
    let id: String
    let frames: [Bool]
    func voicedFrames(samples: [Float], sampleRate: Double) -> [Bool] { frames }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
