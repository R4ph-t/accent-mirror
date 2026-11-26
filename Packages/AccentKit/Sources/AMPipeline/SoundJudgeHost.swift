// The sound judge host (sound-judging plan, 2026-11-25), modelled on `SpeechModelHost`: loads `SoundJudge` from the
// folder it is given, once, in the background, and remembers a failure. Unlike the recogniser it never makes a take
// wait for the load (the first Neural Engine load takes about 40 s): until the judge is ready a take gets
// `.unavailable(.modelNotInstalled)` at once, and the rest of the analysis carries on.

import AMAlignment
import AMCore
import AMJudging
import AMProsody
import Foundation
import os

public actor SoundJudgeHost {
    /// Judges one 16 kHz mono take: `SoundJudge.judge(samples:words:)` in the app, a stub in tests.
    public typealias Judge = @Sendable (_ samples: [Float], _ words: [AMJudging.ExpectedWord]) async throws -> SoundJudgement
    /// Loads the judge. Throws a `SoundJudgeError` or anything else (mapped by `unavailable(for:)`).
    public typealias Loader = @Sendable () async throws -> Judge

    private let loader: Loader
    private var state: State = .idle
    /// Loads started (tests check that a failure is remembered and never reloaded).
    public private(set) var loadAttempts = 0

    private enum State {
        case idle
        case loading(Task<Void, Never>)
        case ready(Judge)
        case failed(SoundJudgementUnavailable)
    }

    public init(load: @escaping Loader) {
        loader = load
    }

    /// A host whose judge is already loaded (tests: a stub judge, no Core ML).
    public init(ready judge: @escaping Judge) {
        loader = { judge }
        state = .ready(judge)
    }

    /// The model's folder name under `Contents/Resources/Models/` (`SoundJudge.modelFolderName`).
    public static let modelFolderName = SoundJudge.modelFolderName

    /// The bundled model in `folder` (`Contents/Resources/Models/wav2vec2-lv-60-espeak-cv-ft`). Nothing is ever
    /// downloaded: a missing folder is `modelNotInstalled`.
    public static func bundled(folder: URL) -> SoundJudgeHost {
        SoundJudgeHost {
            guard FileManager.default.fileExists(atPath: folder.path) else { throw SoundJudgeError.modelNotInstalled }
            let judge = try await SoundJudge.load(folder: folder)
            return { samples, words in try await judge.judge(samples: samples, words: words) }
        }
    }

    /// Starts loading now (after launch, in the background); a no-op once loading, loaded or failed.
    public func prepare() {
        if case .idle = state { startLoad() }
    }

    /// True while a judge is loaded.
    public var isLoaded: Bool {
        if case .ready = state { return true }
        return false
    }

    /// The loaded judge, or why there is none, without waiting.
    public enum Readiness: Sendable {
        case ready(Judge)
        case unavailable(SoundJudgementUnavailable)
    }

    /// The loaded judge, or why there is none, without waiting: a judge still loading is `modelNotInstalled`. A host
    /// never prepared starts loading now.
    public func readyJudge() -> Readiness {
        switch state {
        case .ready(let judge): return .ready(judge)
        case .failed(let reason): return .unavailable(reason)
        case .loading: return .unavailable(.modelNotInstalled)
        case .idle:
            startLoad()
            return .unavailable(.modelNotInstalled)
        }
    }

    /// Judges `samples` (16 kHz mono) against `words`. Never throws for a model problem: that is an `.unavailable`
    /// outcome. Throws `CancellationError` only when the calling task is cancelled. Each settled outcome is logged
    /// (`Self.log`, numbers only).
    public func outcome(samples: [Float], words: [AMJudging.ExpectedWord]) async throws -> SoundJudgementOutcome {
        let outcome = try await judgedOutcome(samples: samples, words: words)
        Self.log.notice("\(Self.logLine(outcome), privacy: .public)")
        return outcome
    }

    /// Judging results in the unified log:
    /// `log show --predicate 'subsystem == "AccentMirror" AND category == "Judge"'`.
    static let log = Logger(subsystem: "AccentMirror", category: "Judge")

    /// One take's outcome as the log line: no words or transcript, only the outcome, the worst P(error), the flagged
    /// word count and the threshold.
    static func logLine(_ outcome: SoundJudgementOutcome) -> String {
        switch outcome {
        case .judged(let judgement):
            let phones = judgement.words.flatMap(\.phones)
            let worst = phones.map { 1 - $0.confidence }.max() ?? 0
            let judged = judgement.words.filter { if case .judged = $0.state { true } else { false } }.count
            return "judged worstPError=\(String(format: "%.3f", worst))"
                + " flaggedWords=\(judgement.words.filter(\.flagged).count) judgedWords=\(judged)"
                + " words=\(judgement.words.count) threshold=\(judgement.errorThreshold) judge=\(judgement.judgeID)"
        case .unavailable(let reason):
            return "unavailable(\(reason.rawValue))"
        }
    }

    private func judgedOutcome(
        samples: [Float], words: [AMJudging.ExpectedWord]
    ) async throws -> SoundJudgementOutcome {
        guard words.contains(where: { !$0.variants.isEmpty }) else { return .unavailable(.nothingJudgeable) }
        let judge: Judge
        switch readyJudge() {
        case .ready(let ready): judge = ready
        case .unavailable(let reason): return .unavailable(reason)
        }
        do {
            let judgement = try await judge(samples, words)
            try Task.checkCancellation()
            guard judgement.words.contains(where: { if case .judged = $0.state { true } else { false } }) else {
                return .unavailable(.nothingJudgeable)
            }
            return .judged(judgement)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            return .unavailable(Self.unavailable(for: error))
        }
    }

    private func startLoad() {
        loadAttempts += 1
        let loader = self.loader
        // Unstructured on purpose: a cancelled analysis must not cancel the load.
        state = .loading(Task.detached(priority: .utility) { [weak self] in
            let loaded: Readiness
            do {
                loaded = .ready(try await loader())
            } catch {
                loaded = .unavailable(Self.unavailable(for: error))
            }
            await self?.finishLoad(loaded)
        })
    }

    private func finishLoad(_ loaded: Readiness) {
        switch loaded {
        case .ready(let judge): state = .ready(judge)
        case .unavailable(let reason): state = .failed(reason)
        }
    }

    /// How a load or judging error reads in the result. `notImplemented` (the interface before the engine landed)
    /// and a missing file read as not installed; anything Core ML or the engine refuses otherwise is `modelFailed`.
    public static func unavailable(for error: any Error) -> SoundJudgementUnavailable {
        switch error {
        case SoundJudgeError.notImplemented, SoundJudgeError.modelNotInstalled: .modelNotInstalled
        case SoundJudgeError.takeOutOfRange: .takeOutOfRange
        case SoundJudgeError.modelFailed: .modelFailed
        case let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile:
            .modelNotInstalled
        default: .modelFailed
        }
    }
}

/// The phrase's words as the judge expects them (sound-judging plan, 2026-11-25).
public enum SoundJudgeWords {
    /// Each phrase word with every CMUdict variant, in dictionary order; an out-of-vocabulary word gets no variants
    /// and is left unjudged. The word is folded as everywhere else in the app (`WordText.fold`: lowercased, curly
    /// apostrophes straightened, leading and trailing apostrophes trimmed, as the spike's gop.py strips them).
    /// `modelRanges` places each word on the selected native recording's timeline.
    public static func expected(
        _ words: [PlacementTake.Word], dictionary: PronouncingDictionary, modelRanges: [WordIndex: TimeRange] = [:]
    ) -> [AMJudging.ExpectedWord] {
        words.map { word in
            AMJudging.ExpectedWord(
                index: word.index, text: word.text,
                variants: dictionary.pronunciations(of: word.text).map(\.phones),
                modelRange: modelRanges[word.index])
        }
    }

    /// The present words of a native recording's segmentation, by phrase word.
    static func modelRanges(_ model: TakeProsody) -> [WordIndex: TimeRange] {
        Dictionary(
            model.segmentation.words.filter { $0.kind == .present }.map { ($0.phraseWord, $0.range) },
            uniquingKeysWith: { first, _ in first })
    }

    /// `outcome` with each judged word placed on the native timeline (judging runs before the native is read). A
    /// word the word alignment says you didn't say (`missing` in `alignment`) loses its own and its sounds' ranges on
    /// your timeline (Designer's ruling, 2026-11-25: there is nothing of yours to play); every other word keeps the
    /// judge's CTC alignment.
    static func placing(
        _ outcome: SoundJudgementOutcome, modelRanges: [WordIndex: TimeRange], alignment: WordAlignment
    ) -> SoundJudgementOutcome {
        guard case .judged(let judgement) = outcome else { return outcome }
        let missing = Set(alignment.pairs.compactMap { pair -> WordIndex? in
            if case .missing(let phrase) = pair { phrase } else { nil }
        })
        return .judged(SoundJudgement(
            modelID: judgement.modelID, judgeID: judgement.judgeID, errorThreshold: judgement.errorThreshold,
            words: judgement.words.map { word in
                guard missing.contains(word.index) else {
                    return JudgedWord(
                        index: word.index, text: word.text, youRange: word.youRange,
                        modelRange: modelRanges[word.index], state: word.state)
                }
                let state: JudgedWord.State = switch word.state {
                case .judged(let phones):
                    .judged(phones.map {
                        JudgedPhone(
                            phone: $0.phone, gop: $0.gop, confidence: $0.confidence, flagged: $0.flagged,
                            heardInstead: $0.heardInstead, youRange: nil)
                    })
                case .unjudged: word.state
                }
                return JudgedWord(
                    index: word.index, text: word.text, youRange: nil, modelRange: modelRanges[word.index],
                    state: state)
            }))
    }
}

extension AnalysisResult {
    /// The same result with `sounds` replaced; every other field kept.
    func with(sounds: SoundJudgementOutcome?) -> AnalysisResult {
        AnalysisResult(
            phraseID: phraseID, takeID: takeID, recordedAt: recordedAt, model: model, you: you, modelAxis: modelAxis,
            alignment: alignment, timeMap: timeMap, youPitchOnModel: youPitchOnModel, nativeBand: nativeBand,
            pitchAxis: pitchAxis, timing: timing, stress: stress, measures: measures, applicability: applicability,
            verdict: verdict, identity: identity, comparableCoverage: comparableCoverage, describe: describe,
            sounds: sounds)
    }
}

extension L2Analysis {
    /// The same comparison with its analysed result's `sounds` replaced.
    func with(sounds: SoundJudgementOutcome?) -> L2Analysis {
        guard case .analysed(let result) = outcome else { return self }
        return L2Analysis(
            key: key, outcome: .analysed(result.with(sounds: sounds)), applicability: applicability,
            measures: measures, modelValues: modelValues, referenceAnomaly: referenceAnomaly,
            bandCoverage: bandCoverage)
    }
}
