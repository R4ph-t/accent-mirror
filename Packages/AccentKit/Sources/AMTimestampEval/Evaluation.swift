import AMAlignment
import AMCore
import Foundation

/// The numbers the spec 03 gate reads, all from `Thresholds` (mirrored in `docs/thresholds.md`): the word-boundary
/// bars and the warm-ASR budget. Never lowered quietly: a result under a bar goes back to CTO.
///
/// CTO ruling 2026-11-23 13:00: the bar is the absolute error per boundary on unpadded Whisper word starts and ends,
/// judged separately for starts and for ends; both sides must meet it. Padding is an analysis-window choice that
/// belongs to spec 07, so it is not part of the gate.
public struct TimestampGate: Codable, Sendable, Equatable {
    /// Median absolute boundary error must be at most this, on each side.
    public var medianErrorMaxMs: Double
    /// "Within" tolerance for the share bar.
    public var toleranceMs: Double
    /// At least this share of each side's boundaries must be within `toleranceMs`.
    public var minShareWithinTolerance: Double
    /// Warm ASR budget; over it, `tiny.en` is the fallback.
    public var asrWarmBudgetMs: Double

    public init(_ thresholds: Thresholds) {
        medianErrorMaxMs = thresholds.wordTimestamps.medianErrorMaxMs
        toleranceMs = thresholds.wordTimestamps.withinToleranceMs
        minShareWithinTolerance = thresholds.wordTimestamps.withinToleranceShareMin
        asrWarmBudgetMs = thresholds.performance.asrWarmMs
    }

    public static let plan = TimestampGate(.current)

    /// Spec 07's planned Whisper span padding (CTO decision 4). Used only for the comparison table, never the gate.
    public static let comparisonPaddingMs = Thresholds.current.alignment.asrPaddingMs
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

/// One side of the gate (starts or ends): its figures and its two bar lines.
public struct SideResult: Codable, Sendable, Equatable {
    public var stats: BoundaryStats
    public var medianOutcome: Outcome
    public var shareOutcome: Outcome
    public var outcome: Outcome

    public init(errorsMs: [Double], gate: TimestampGate) {
        stats = BoundaryStats(errorsMs: errorsMs, toleranceMs: gate.toleranceMs)
        medianOutcome = stats.medianErrorMs.map { $0 <= gate.medianErrorMaxMs ? .pass : .fail } ?? .notEvaluated
        shareOutcome = stats.shareWithinTolerance.map { $0 >= gate.minShareWithinTolerance ? .pass : .fail }
            ?? .notEvaluated
        outcome = Outcome.combine([medianOutcome, shareOutcome])
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
/// (low: below the median; high: at or above it), on unpadded errors. PASS when the low bin's mean absolute error is
/// greater than the high bin's; NOT EVALUATED when a bin is empty.
public struct Calibration: Codable, Sendable, Equatable {
    public var medianProbability: Double?
    public var low: CalibrationBin
    public var high: CalibrationBin
    public var outcome: Outcome
}

/// Unpadded starts and ends for one speaker or one phrase.
public struct SideBreakdown: Codable, Sendable, Equatable {
    public var key: String
    public var starts: SideResult
    public var ends: SideResult
}

/// The old padded figures, kept for comparison only: padding belongs to spec 07 and is not the gate.
public struct PaddedComparison: Codable, Sendable, Equatable {
    public var paddingMs: Double
    public var pooled: BoundaryStats
    public var starts: BoundaryStats
    public var ends: BoundaryStats
}

/// A diagnostic on the same clips, never applied anywhere in the code path: the constant end bias (median signed end
/// error, ASR minus baseline) and the unpadded end figures after subtracting it. Not a fix, not the gate.
public struct EndBiasDiagnostic: Codable, Sendable, Equatable {
    public var medianSignedEndErrorMs: Double?
    public var correctedEnds: BoundaryStats
}

/// A comparable token with both spans.
public struct ComparableWord: Sendable, Equatable {
    public var clipID: String
    public var speaker: String
    public var textID: String
    public var token: String
    public var asr: WordTimestamp
    public var baseline: BaselineWord

    /// |start error| in ms, after moving the ASR start `paddingMs` earlier (0 for the gate).
    public func startErrorMs(paddingMs: Double = 0) -> Double {
        microsecond(abs(asr.start - paddingMs / 1000 - baseline.start) * 1000)
    }

    /// |end error| in ms, after moving the ASR end `paddingMs` later (0 for the gate).
    public func endErrorMs(paddingMs: Double = 0) -> Double {
        microsecond(abs(asr.end + paddingMs / 1000 - baseline.end) * 1000)
    }

    /// Signed end error in ms, ASR minus baseline: negative is early.
    public var signedEndErrorMs: Double { microsecond((asr.end - baseline.end) * 1000) }

    /// |start error| and |end error| in ms.
    public func errorsMs(paddingMs: Double = 0) -> [Double] {
        [startErrorMs(paddingMs: paddingMs), endErrorMs(paddingMs: paddingMs)]
    }
}

/// Rounded to the microsecond, far below both tools' resolution (Whisper 20 ms, MFA 10 ms), so an error of exactly
/// 80 ms is not pushed to 80.00000000000001 by floating point and counted outside the tolerance.
func microsecond(_ ms: Double) -> Double {
    (ms * 1000).rounded() / 1000
}

/// The word-boundary accuracy of one ASR against the baseline, and its gate lines.
public struct AccuracyResult: Codable, Sendable, Equatable {
    public var coverage: Coverage
    /// The gate: unpadded word starts.
    public var starts: SideResult
    /// The gate: unpadded word ends.
    public var ends: SideResult
    /// Unpadded starts and ends per speaker, each judged against the same bars, for information.
    public var perSpeaker: [SideBreakdown]
    /// Unpadded starts and ends per phrase, for information.
    public var perPhrase: [SideBreakdown]
    /// Calibration on unpadded errors (the plan's "low-confidence bin has more error than the high bin").
    public var calibration: Calibration
    /// Mean signed unpadded error (ASR minus baseline) of starts and of ends, in ms: negative is early.
    public var meanSignedStartMs: Double?
    public var meanSignedEndMs: Double?
    public var padded: PaddedComparison
    public var endBias: EndBiasDiagnostic
    /// Starts, ends and calibration combined.
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

    public static func evaluate(_ clips: [ClipInput], gate: TimestampGate = .plan,
                                comparisonPaddingMs: Double = TimestampGate.comparisonPaddingMs) -> AccuracyResult {
        let (words, coverage) = comparableWords(clips)
        let tolerance = gate.toleranceMs

        func sides(_ group: [ComparableWord]) -> (SideResult, SideResult) {
            (SideResult(errorsMs: group.map { $0.startErrorMs() }, gate: gate),
             SideResult(errorsMs: group.map { $0.endErrorMs() }, gate: gate))
        }
        func breakdown(_ key: (ComparableWord) -> String) -> [SideBreakdown] {
            Dictionary(grouping: words, by: key).sorted { $0.key < $1.key }.map { key, group in
                let (starts, ends) = sides(group)
                return SideBreakdown(key: key, starts: starts, ends: ends)
            }
        }
        func meanMs(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) * 1000
        }

        let (starts, ends) = sides(words)
        let calibration = calibrate(words)
        let bias = Statistics.median(words.map(\.signedEndErrorMs))
        let corrected = bias.map { bias in words.map { microsecond(abs($0.signedEndErrorMs - bias)) } } ?? []
        return AccuracyResult(
            coverage: coverage, starts: starts, ends: ends,
            perSpeaker: breakdown(\.speaker), perPhrase: breakdown(\.textID),
            calibration: calibration,
            meanSignedStartMs: meanMs(words.map { $0.asr.start - $0.baseline.start }),
            meanSignedEndMs: meanMs(words.map { $0.asr.end - $0.baseline.end }),
            padded: PaddedComparison(
                paddingMs: comparisonPaddingMs,
                pooled: BoundaryStats(errorsMs: words.flatMap { $0.errorsMs(paddingMs: comparisonPaddingMs) },
                                      toleranceMs: tolerance),
                starts: BoundaryStats(errorsMs: words.map { $0.startErrorMs(paddingMs: comparisonPaddingMs) },
                                      toleranceMs: tolerance),
                ends: BoundaryStats(errorsMs: words.map { $0.endErrorMs(paddingMs: comparisonPaddingMs) },
                                    toleranceMs: tolerance)),
            endBias: EndBiasDiagnostic(medianSignedEndErrorMs: bias,
                                       correctedEnds: BoundaryStats(errorsMs: corrected, toleranceMs: tolerance)),
            outcome: Outcome.combine([starts.outcome, ends.outcome, calibration.outcome]))
    }

    static func calibrate(_ words: [ComparableWord]) -> Calibration {
        guard let split = Statistics.median(words.map(\.asr.probability)) else {
            let empty = CalibrationBin(words: 0, boundaries: 0)
            return Calibration(medianProbability: nil, low: empty, high: empty, outcome: .notEvaluated)
        }
        func bin(_ group: [ComparableWord]) -> CalibrationBin {
            let errors = group.flatMap { $0.errorsMs() }
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
