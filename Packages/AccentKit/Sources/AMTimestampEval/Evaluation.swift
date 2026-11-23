import AMAlignment
import Foundation

/// The spec 03 word-boundary bars and the warm-ASR budget, verbatim from the plan (`docs/thresholds.md`).
/// Never lowered quietly: a result under a bar goes back to CTO.
public struct TimestampGate: Codable, Sendable, Equatable {
    /// Median absolute boundary error must be at most this.
    public var medianErrorMaxMs: Double
    /// "Within" tolerance for the share bar.
    public var toleranceMs: Double
    /// At least this share of boundaries must be within `toleranceMs`.
    public var minShareWithinTolerance: Double
    /// Planned expansion of each Whisper word span on both sides (CTO decision 4). The gate uses padded spans.
    public var spanPaddingMs: Double
    /// Warm ASR budget; over it, `tiny.en` is the fallback.
    public var asrWarmBudgetMs: Double

    public static let plan = TimestampGate(
        medianErrorMaxMs: 40, toleranceMs: 80, minShareWithinTolerance: 0.85, spanPaddingMs: 80, asrWarmBudgetMs: 900)
}

public enum Outcome: String, Codable, Sendable {
    case pass = "PASS"
    case fail = "FAIL"
    case notEvaluated = "NOT EVALUATED"

    /// FAIL if any part fails; otherwise NOT EVALUATED if any part was not evaluated; otherwise PASS.
    /// NOT EVALUATED is never a pass.
    public static func combine(_ parts: [Outcome]) -> Outcome {
        if parts.contains(.fail) { return .fail }
        if parts.contains(.notEvaluated) || parts.isEmpty { return .notEvaluated }
        return .pass
    }
}

/// A baseline (forced-aligner) word span, seconds from the start of the audio.
public struct BaselineWord: Codable, Sendable, Equatable {
    public var word: String
    public var start: Double
    public var end: Double

    public init(word: String, start: Double, end: Double) {
        self.word = word
        self.start = start
        self.end = end
    }
}

/// One evaluated clip: its transcript, the ASR words and the baseline words.
public struct ClipInput: Sendable {
    public var clipID: String
    public var speaker: String
    public var textID: String
    public var transcript: String
    public var asrWords: [WordTimestamp]
    public var baselineWords: [BaselineWord]

    public init(clipID: String, transcript: String, asrWords: [WordTimestamp], baselineWords: [BaselineWord]) {
        self.clipID = clipID
        let parts = clipID.split(separator: "_", maxSplits: 1).map(String.init)
        self.speaker = parts.first ?? clipID
        self.textID = parts.count > 1 ? parts[1] : ""
        self.transcript = transcript
        self.asrWords = asrWords
        self.baselineWords = baselineWords
    }
}

/// Median, share within tolerance and mean of absolute boundary errors.
public struct BoundaryStats: Codable, Sendable, Equatable {
    public var boundaries: Int
    public var medianErrorMs: Double?
    public var shareWithinTolerance: Double?
    public var meanErrorMs: Double?

    public init(errorsMs: [Double], toleranceMs: Double) {
        boundaries = errorsMs.count
        medianErrorMs = Statistics.median(errorsMs)
        shareWithinTolerance = errorsMs.isEmpty
            ? nil : Double(errorsMs.filter { $0 <= toleranceMs }.count) / Double(errorsMs.count)
        meanErrorMs = errorsMs.isEmpty ? nil : errorsMs.reduce(0, +) / Double(errorsMs.count)
    }
}

/// Phrase-token coverage: a token is comparable when both sides produce a span for it.
public struct Coverage: Codable, Sendable, Equatable {
    public var phraseTokens = 0
    public var comparable = 0
    public var missingFromASROnly = 0
    public var missingFromBaselineOnly = 0
    public var missingFromBoth = 0

    public var comparableShare: Double? { phraseTokens == 0 ? nil : Double(comparable) / Double(phraseTokens) }
}

public struct CalibrationBin: Codable, Sendable, Equatable {
    public var words: Int
    public var boundaries: Int
    public var probabilityMin: Double?
    public var probabilityMax: Double?
    public var meanAbsErrorMs: Double?
}

/// Spec 03, Open question 4 default: two bins split at the median word probability over comparable tokens
/// (low: below the median; high: at or above it). PASS when the low bin's mean absolute error is greater than the
/// high bin's; NOT EVALUATED when a bin is empty.
public struct Calibration: Codable, Sendable, Equatable {
    public var medianProbability: Double?
    public var low: CalibrationBin
    public var high: CalibrationBin
    public var outcome: Outcome
}

public struct Breakdown: Codable, Sendable, Equatable {
    public var key: String
    public var padded: BoundaryStats
    public var raw: BoundaryStats
}

/// A comparable token with both spans.
public struct ComparableWord: Sendable, Equatable {
    public var clipID: String
    public var speaker: String
    public var textID: String
    public var token: String
    public var asr: WordTimestamp
    public var baseline: BaselineWord

    /// |start error| and |end error| in ms, after expanding the ASR span by `paddingMs` on both sides.
    /// Rounded to the microsecond, far below both tools' resolution (Whisper 20 ms, MFA 10 ms), so an error of exactly
    /// 80 ms is not pushed to 80.00000000000001 by floating point and counted outside the tolerance.
    public func errorsMs(paddingMs: Double) -> [Double] {
        let pad = paddingMs / 1000
        return [abs(asr.start - pad - baseline.start), abs(asr.end + pad - baseline.end)]
            .map { ($0 * 1_000_000).rounded() / 1000 }
    }
}

/// The word-boundary accuracy of one ASR against the baseline, and its gate lines.
public struct AccuracyResult: Codable, Sendable, Equatable {
    public var coverage: Coverage
    /// The gate figures: ASR spans padded by `spanPaddingMs` on both sides (Open question 3 default).
    public var padded: BoundaryStats
    /// The same boundaries on raw ASR times, for information.
    public var raw: BoundaryStats
    /// Mean signed raw error (ASR minus baseline) of starts and of ends, in ms, for information: negative is early.
    public var rawMeanSignedStartMs: Double?
    public var rawMeanSignedEndMs: Double?
    public var calibration: Calibration
    public var rawCalibration: Calibration
    public var perVoice: [Breakdown]
    public var perPhrase: [Breakdown]
    public var medianOutcome: Outcome
    public var shareOutcome: Outcome
    /// Median, share and calibration combined.
    public var outcome: Outcome
}

public enum Evaluation {
    /// Pairs each clip's ASR words and baseline words with its phrase tokens and counts coverage.
    public static func comparableWords(_ clips: [ClipInput]) -> (words: [ComparableWord], coverage: Coverage) {
        var coverage = Coverage()
        var words: [ComparableWord] = []
        for clip in clips {
            let tokens = Tokens.phraseTokens(of: clip.transcript)
            let asr = Tokens.match(tokens: tokens, words: clip.asrWords.map(\.word))
            let base = Tokens.match(tokens: tokens, words: clip.baselineWords.map(\.word))
            coverage.phraseTokens += tokens.count
            for (index, token) in tokens.enumerated() {
                switch (asr[index], base[index]) {
                case let (a?, b?):
                    coverage.comparable += 1
                    words.append(ComparableWord(
                        clipID: clip.clipID, speaker: clip.speaker, textID: clip.textID, token: token,
                        asr: clip.asrWords[a], baseline: clip.baselineWords[b]))
                case (nil, .some): coverage.missingFromASROnly += 1
                case (.some, nil): coverage.missingFromBaselineOnly += 1
                case (nil, nil): coverage.missingFromBoth += 1
                }
            }
        }
        return (words, coverage)
    }

    public static func evaluate(_ clips: [ClipInput], gate: TimestampGate = .plan) -> AccuracyResult {
        let (words, coverage) = comparableWords(clips)
        let padded = BoundaryStats(errorsMs: words.flatMap { $0.errorsMs(paddingMs: gate.spanPaddingMs) },
                                   toleranceMs: gate.toleranceMs)
        let raw = BoundaryStats(errorsMs: words.flatMap { $0.errorsMs(paddingMs: 0) }, toleranceMs: gate.toleranceMs)

        func breakdown(_ key: (ComparableWord) -> String) -> [Breakdown] {
            Dictionary(grouping: words, by: key).sorted { $0.key < $1.key }.map { key, group in
                Breakdown(
                    key: key,
                    padded: BoundaryStats(errorsMs: group.flatMap { $0.errorsMs(paddingMs: gate.spanPaddingMs) },
                                          toleranceMs: gate.toleranceMs),
                    raw: BoundaryStats(errorsMs: group.flatMap { $0.errorsMs(paddingMs: 0) },
                                       toleranceMs: gate.toleranceMs))
            }
        }

        let medianOutcome: Outcome = padded.medianErrorMs.map { $0 <= gate.medianErrorMaxMs ? .pass : .fail }
            ?? .notEvaluated
        let shareOutcome: Outcome = padded.shareWithinTolerance.map {
            $0 >= gate.minShareWithinTolerance ? .pass : .fail
        } ?? .notEvaluated
        let calibration = calibrate(words, paddingMs: gate.spanPaddingMs)
        func meanMs(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) * 1000
        }
        return AccuracyResult(
            coverage: coverage, padded: padded, raw: raw,
            rawMeanSignedStartMs: meanMs(words.map { $0.asr.start - $0.baseline.start }),
            rawMeanSignedEndMs: meanMs(words.map { $0.asr.end - $0.baseline.end }),
            calibration: calibration, rawCalibration: calibrate(words, paddingMs: 0),
            perVoice: breakdown(\.speaker), perPhrase: breakdown(\.textID),
            medianOutcome: medianOutcome, shareOutcome: shareOutcome,
            outcome: Outcome.combine([medianOutcome, shareOutcome, calibration.outcome]))
    }

    static func calibrate(_ words: [ComparableWord], paddingMs: Double) -> Calibration {
        guard let split = Statistics.median(words.map(\.asr.probability)) else {
            let empty = CalibrationBin(words: 0, boundaries: 0)
            return Calibration(medianProbability: nil, low: empty, high: empty, outcome: .notEvaluated)
        }
        func bin(_ group: [ComparableWord]) -> CalibrationBin {
            let errors = group.flatMap { $0.errorsMs(paddingMs: paddingMs) }
            return CalibrationBin(
                words: group.count, boundaries: errors.count,
                probabilityMin: group.map(\.asr.probability).min(), probabilityMax: group.map(\.asr.probability).max(),
                meanAbsErrorMs: errors.isEmpty ? nil : errors.reduce(0, +) / Double(errors.count))
        }
        let low = bin(words.filter { $0.asr.probability < split })
        let high = bin(words.filter { $0.asr.probability >= split })
        let outcome: Outcome
        if let lowError = low.meanAbsErrorMs, let highError = high.meanAbsErrorMs {
            outcome = lowError > highError ? .pass : .fail
        } else {
            outcome = .notEvaluated
        }
        return Calibration(medianProbability: split, low: low, high: high, outcome: outcome)
    }
}

extension CalibrationBin {
    init(words: Int, boundaries: Int) {
        self.init(words: words, boundaries: boundaries, probabilityMin: nil, probabilityMax: nil, meanAbsErrorMs: nil)
    }
}

public enum Statistics {
    /// The median; the mean of the two middle values for an even count; `nil` when empty.
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Nearest-rank percentile (`p` in 0–100); `nil` when empty.
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
