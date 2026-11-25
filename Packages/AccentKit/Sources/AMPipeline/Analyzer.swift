// The analysis pipeline (spec 12, plan §8–§10): your take, a phrase and a native reference in, one
// `AnalysisResponse` out. Stages, each behind its module's API:
//
//   decode → take quality (spec 05) → ASR words ∥ pitch (specs 03, 04), voicing from the quality pass →
//   boundary source (spec 23) and word alignment (spec 06) → syllables (spec 07) → time map and band (spec 09) →
//   the take-problem gate (spec 28 §1a) → the configured `PairScorer` (spec 28: `NoOpScorer` in the app, so the
//   verdict is `.notScored`; evaluation passes `VerdictScorer`) and the description (§4a).
//
// L0 and L1 are cached per take, L2 per take and reference, so a voice switch recomputes L2 only. The reference side
// is read from the `ReferenceSet`, never recomputed during a take. A stage that throws becomes
// `failed(.inferenceFailed(stage:))`; a cancelled request returns `.cancelled`.
//
// Sound judging (sound-judging plan, 2026-11-25) runs alongside all of it, from the start of the request, off this
// actor, through the `SoundJudgeHost`; its outcome goes into `AnalysisResult.sounds`. It never fails the analysis,
// and a judge still loading answers `.unavailable(.modelNotInstalled)` at once.

import AMAlignment
import AMCapture
import AMCore
import AMJudging
import AMLibrary
import AMPitch
import AMProsody
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
        /// What runs after the take-problem gate (spec 28); its `mode` is `AnalysisIdentity.scoringMode` and part of
        /// the L2 key. The app runs `ShippedConfig.scorer` (`NoOpScorer`).
        public var scorer: any PairScorer
        /// Takes (L0, L1) and comparisons (L2) kept in memory.
        public var cacheCapacity: Int
        /// Runs before every stage, inside its signpost interval: a stage that it throws from fails as that stage
        /// would. Diagnostics and tests only (the shipped configuration has none).
        public var beforeStage: (@Sendable (Stage) async throws -> Void)?

        public init(
            pitchTracker: any PitchTracker, voicing: any VoicingSource, boundaryRefiner: any WordBoundaryRefiner,
            aligner: WordAligner, thresholds: Thresholds = .current, scorer: any PairScorer = ShippedConfig.scorer,
            cacheCapacity: Int = 8, beforeStage: (@Sendable (Stage) async throws -> Void)? = nil
        ) {
            self.pitchTracker = pitchTracker
            self.voicing = voicing
            self.boundaryRefiner = boundaryRefiner
            self.aligner = aligner
            self.thresholds = thresholds
            self.scorer = scorer
            self.cacheCapacity = cacheCapacity
            self.beforeStage = beforeStage
        }

        /// What the app runs: spec 04's pYIN, spec 05's voicing, `ShippedConfig`'s boundary source, spec 06's aligner
        /// and `ShippedConfig.scorer`.
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
    /// Judges your take's sounds; nil leaves `AnalysisResult.sounds` nil (evaluation tools).
    public let sounds: SoundJudgeHost?
    public let configuration: Configuration
    public private(set) var statistics = Statistics()
    private let stages: TakeStages
    private var l0Cache: LevelCache<L0Key, L0Analysis>
    private var l1Cache: LevelCache<L1Key, L1Analysis>
    private var l2Cache: LevelCache<L2Key, Compared>
    /// Settled judgements per take and phrase words (a voice switch doesn't judge again). A judge that wasn't ready
    /// isn't cached, so the next request tries again.
    private var soundsCache: LevelCache<SoundsKey, SoundJudgementOutcome>
    /// Where judged words' pronunciations come from (empty if the bundled CMUdict can't be read: nothing judgeable).
    private let dictionary: PronouncingDictionary

    static let signposter = OSSignposter(subsystem: "AccentMirror", category: "Analysis")

    public init(speech: SpeechModelHost, sounds: SoundJudgeHost? = nil, configuration: Configuration) {
        self.speech = speech
        self.sounds = sounds
        self.configuration = configuration
        dictionary = (try? PronouncingDictionary.bundled()) ?? PronouncingDictionary(contents: "")
        soundsCache = LevelCache(capacity: configuration.cacheCapacity)
        stages = TakeStages(
            voicing: configuration.voicing, aligner: configuration.aligner, thresholds: configuration.thresholds)
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

    /// The scoring mode of every analysis this analyzer produces (`configuration.scorer.mode`).
    public nonisolated var scoringMode: ScoringMode { configuration.scorer.mode }

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
            takeAudioSHA256: take.sha256, reference: reference.identity(phrase: phrase.id, voice: voice), config: config,
            scoringMode: scoringMode)
        var clock = StageClock()
        func respond(_ outcome: AnalysisOutcome, derived: [DerivedRecord] = [], l2: L2Analysis? = nil) -> Run {
            Run(
                response: AnalysisResponse(requestID: requestID, identity: identity, outcome: outcome),
                timings: clock.seconds, derived: derived, l2: l2)
        }
        // Judging starts first and runs beside every stage; it is cancelled with the request and on any early exit.
        let judging = startJudging(take: take, phrase: phrase)
        defer { judging?.task.cancel() }
        return await withTaskCancellationHandler {
            do {
                let l0 = try await takeL0(take, clock: &clock)
                if let problem = TakeProblem.first(of: l0.takeProblems) { return respond(.takeProblem(problem)) }
                let l1 = try await takeL1(take, phrase: phrase, l0: l0, clock: &clock)
                let compared = try await compare(
                    take: take, phrase: phrase, l1: l1, reference: reference, voice: voice, identity: identity,
                    clock: &clock)
                var l2 = compared.l2
                if let judging, case .analysed = l2.outcome {
                    let sounds = try await settle(judging)
                    l2 = l2.with(sounds: SoundJudgeWords.placing(
                        sounds, modelRanges: compared.modelRanges, alignment: l1.analysis.alignment))
                }
                try Task.checkCancellation()
                let derived = try [DerivedCoding.record(l0), DerivedCoding.record(l1), DerivedCoding.record(l2)]
                return respond(l2.outcome, derived: derived, l2: l2)
            } catch {
                return respond(Self.outcome(of: error))
            }
        } onCancel: {
            judging?.task.cancel()
        }
    }

    // MARK: - Sounds

    struct SoundsKey: Hashable, Sendable {
        let takeAudioSHA256: String
        let words: [AMJudging.ExpectedWord]
    }

    /// A judging run in flight, or one served from the cache.
    struct Judging: Sendable {
        let key: SoundsKey
        let task: Task<SoundJudgementOutcome?, Never>
    }

    /// Starts judging `take` off this actor; nil when the analyzer has no judge. The task's value is nil only when
    /// it was cancelled.
    private func startJudging(take: TakeAudio, phrase: PhraseInput) -> Judging? {
        guard let host = sounds else { return nil }
        let words = SoundJudgeWords.expected(phrase.words, dictionary: dictionary)
        let key = SoundsKey(takeAudioSHA256: take.sha256, words: words)
        if let cached = soundsCache[key] {
            return Judging(key: key, task: Task { cached })
        }
        let samples = take.samples
        return Judging(key: key, task: Task.detached(priority: .userInitiated) {
            try? await host.outcome(samples: samples, words: words)
        })
    }

    /// The judging run's outcome, cached when it is settled (judged, or unavailable for a reason a later request
    /// wouldn't change).
    private func settle(_ judging: Judging) async throws -> SoundJudgementOutcome {
        guard let outcome = await judging.task.value else { throw CancellationError() }
        switch outcome {
        case .judged, .unavailable(.nothingJudgeable), .unavailable(.takeOutOfRange):
            soundsCache.insert(outcome, for: judging.key)
        case .unavailable(.modelNotInstalled), .unavailable(.modelFailed):
            break
        }
        return outcome
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

    func l0Key(_ take: TakeAudio) -> L0Key { l0Key(takeAudioSHA256: take.sha256) }

    /// The L0 key this analyzer gives a take with this audio.
    public nonisolated func l0Key(takeAudioSHA256: String) -> L0Key {
        L0Key(
            takeAudioSHA256: takeAudioSHA256, asrModelID: speech.asrModelID,
            pitchTrackerID: configuration.pitchTracker.id, voicingID: configuration.voicing.id)
    }

    /// The L1 key this analyzer gives a take with this L0 key, read against `phrase`.
    public nonisolated func l1Key(l0: L0Key, phrase: PhraseInput) -> L1Key {
        L1Key(
            l0: l0, transcriptRevision: phrase.transcriptRevision, pronunciationHash: phrase.pronunciationHash,
            aligner: configuration.boundaryRefiner.id)
    }

    /// The L2 key this analyzer gives a comparison with `reference` (the take store checks stored records with it).
    public nonisolated func l2Key(l1: L1Key, reference: ReferenceIdentity) -> L2Key {
        L2Key(l1: l1, reference: reference, thresholdsVersion: Versions.thresholdsVersion, scoringMode: scoringMode)
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
        let key = l1Key(l0: l0.key, phrase: phrase)
        if let cached = l1Cache[key] {
            statistics.l1Hits += 1
            return cached
        }
        let refiner = configuration.boundaryRefiner
        let (refined, aligned) = try await stage(.alignWords, &clock) { () async throws -> ([WordTimestamp], WordAlignmentResult) in
            let words = try await refiner.refine(l0.words, samples: take.samples, sampleRate: TakeAudio.sampleRate)
            try Task.checkCancellation()
            return (words, try stages.align(placementTake(take, phrase: phrase, heard: words, key: l0.key)))
        }
        let input = placementTake(take, phrase: phrase, heard: refined, key: l0.key)
        let voicing = StoredVoicing(id: configuration.voicing.id, frames: l0.voiced)
        let segmentation = try await stage(.segmentSyllables, &clock) {
            try stages.segment(
                input, alignment: aligned.alignment, voicing: voicing,
                transcriptRevision: phrase.transcriptRevision)
        }
        // L1 stores the prosody only: no observed stress, no placement decision (spec 28).
        let analysis = try await stage(.measureStress, &clock) {
            TakeProsody(segmentation: segmentation, alignment: aligned.alignment, pitch: l0.pitch)
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
    ) async throws -> Compared {
        let key = l2Key(l1: l1.key, reference: identity.reference)
        if let cached = l2Cache[key] {
            statistics.l2Hits += 1
            return cached
        }
        let thresholds = configuration.thresholds
        let scorer = configuration.scorer
        let natives = try await stage(.mapTime, &clock) { try await self.natives(reference, phrase: phrase) }
        guard let selected = natives.first(where: { $0.recording.id == voice }) else {
            throw OperationalFailure(.inferenceFailed(stage: .mapTime))
        }
        let model = selected.analysis.l1.analysis
        let summary = PairScoring.alignmentSummary(words: phrase.words, you: l1.analysis)
        let (warp, band, describe) = try await stage(.mapTime, &clock) {
            () throws -> (TimeWarp, NativeBand, DescribedMeasures) in
            let warp = try PairScoring.warp(you: l1.analysis, model: model, words: phrase.words, thresholds: thresholds)
            let others = natives.filter { $0.recording.id != voice }.compactMap { native -> (LoadedNative, TimeWarp)? in
                guard let warp = try? PairScoring.warp(
                    you: native.analysis.l1.analysis, model: model, words: phrase.words, thresholds: thresholds)
                else { return nil }
                return (native, warp)
            }
            let band = try NativeBand(
                selected: NativeVoice(sha256: selected.recording.audioSHA256, track: model.pitch),
                others: others.map {
                    WarpedVoice(
                        voice: NativeVoice(sha256: $0.0.recording.audioSHA256, track: $0.0.analysis.l1.analysis.pitch),
                        ontoSelected: $0.1)
                },
                testTake: take.sha256, hopSeconds: model.pitch.hopSeconds, thresholds: thresholds.band)
            // Spec 28 §4a: every native on the selected model's frames, the selected voice through its own warp.
            let selfWarp = try PairScoring.warp(you: model, model: model, words: phrase.words, thresholds: thresholds)
            let describe = ProsodyDescription.describe(
                you: l1.analysis, yourWarp: warp,
                natives: [(model, selfWarp)] + others.map { ($0.0.analysis.l1.analysis, $0.1) }, thresholds: thresholds)
            return (warp, band, describe)
        }
        let l2 = try await stage(.compare, &clock) { () throws -> L2Analysis in
            // Spec 28 §1a: decision steps 1–2 run here, whatever the scorer. The scorer is not called on a take problem.
            let input = PairScorerInput(
                words: phrase.words, you: l1.analysis, model: model, modelVoice: selected.recording.voice,
                natives: natives.map { NativeProsody(voice: $0.recording.voice, prosody: $0.analysis.l1.analysis) },
                warp: warp, alignmentSummary: summary)
            let youOnModel = warp.pitchOnModel(l1.analysis.pitch.segments, hopSeconds: l1.analysis.pitch.hopSeconds)
            if let problem = decideTakeProblem(takeProblems: [], alignment: summary, thresholds: thresholds) {
                // Evaluation's `VerdictScorer` still logs its measures beside the problem; `NoOpScorer` logs none.
                let logged = try scorer.evaluationMeasures(input, thresholds: thresholds)
                return L2Analysis(
                    key: key, outcome: .takeProblem(problem), applicability: logged?.applicability ?? .empty,
                    measures: logged?.measures ?? [:], modelValues: logged?.modelValues ?? [:],
                    referenceAnomaly: logged?.stress.contains(where: \.referenceAnomaly) ?? false,
                    bandCoverage: band.coverage(of: youOnModel, warp: warp))
            }
            let score = try scorer.score(input, thresholds: thresholds)
            let result = try ResultAssembly.result(
                take: take, phrase: phrase, you: l1.analysis, model: model, score: score, mode: scorer.mode,
                warp: warp, band: band, describe: describe, identity: identity, thresholds: thresholds)
            return L2Analysis(
                key: key, outcome: .analysed(result), applicability: score.applicability, measures: score.measures,
                modelValues: score.modelValues, referenceAnomaly: score.stress.contains(where: \.referenceAnomaly),
                bandCoverage: band.coverage(of: youOnModel, warp: warp))
        }
        let compared = Compared(l2: l2, modelRanges: SoundJudgeWords.modelRanges(model))
        l2Cache.insert(compared, for: key)
        statistics.l2Computed += 1
        return compared
    }

    /// L2 and the phrase words on the selected native's timeline (where judged words are placed).
    struct Compared: Sendable {
        let l2: L2Analysis
        let modelRanges: [WordIndex: TimeRange]
    }

    /// A native recording and its decoded analysis.
    struct LoadedNative: Sendable {
        let recording: NativeRecording
        let analysis: NativeAnalysis
    }

    /// The phrase's natives, decoded. A corrupt record (or one built for another phrase pronunciation or algorithm)
    /// triggers one silent rebuild of that recording; only a second failure is reported (`loadNatives`).
    private func natives(_ reference: any ReferenceSet, phrase: PhraseInput) async throws -> [LoadedNative] {
        do {
            return try await reference.loadNatives(phrase: phrase.id) { recording -> LoadedNative? in
                guard let native = DerivedCoding.native(in: recording.analysis),
                    native.l1.key.l0.takeAudioSHA256 == recording.audioSHA256,
                    native.l1.key.pronunciationHash == phrase.pronunciationHash,
                    native.l1.key.algorithmVersion == Versions.algorithmVersion
                else { return nil }
                return LoadedNative(recording: recording, analysis: native)
            }
        } catch let error as ReferenceLoadError {
            throw OperationalFailure(error.operational)
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
