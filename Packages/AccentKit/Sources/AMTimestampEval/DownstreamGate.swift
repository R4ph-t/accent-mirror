import AMCore
import Foundation

/// Spec 07's output for one word, as the spec 23 ship gate reads it (CTO ruling 2026-11-23 14:05).
public struct WordVerdict: Sendable, Hashable, Codable {
    /// Any of the word's syllables at low confidence.
    public var inconclusive: Bool
    public var syllableCount: Int
    /// Index of the longest syllable (the first on a tie); nil with no syllables.
    public var longestSyllable: Int?
    /// Index of the syllable with the highest mean intensity (the first on a tie); nil with no syllables.
    public var loudestSyllable: Int?

    public init(inconclusive: Bool, syllableCount: Int, longestSyllable: Int?, loudestSyllable: Int?) {
        self.inconclusive = inconclusive
        self.syllableCount = syllableCount
        self.longestSyllable = longestSyllable
        self.loudestSyllable = loudestSyllable
    }

    /// From a word's syllables in order: duration (s), mean intensity (dBFS) and whether its confidence is low.
    public init(syllables: [(duration: Double, intensityDB: Double, low: Bool)]) {
        func firstMax(_ values: [Double]) -> Int? {
            guard let best = values.max() else { return nil }
            return values.firstIndex(of: best)
        }
        self.init(inconclusive: syllables.contains { $0.low }, syllableCount: syllables.count,
                  longestSyllable: firstMax(syllables.map(\.duration)),
                  loudestSyllable: firstMax(syllables.map(\.intensityDB)))
    }
}

/// The downstream ship gate on one set (synthetic or VCTK): spec 07's verdicts under oracle boundaries against
/// under b2's, everything else identical. PASS when verdicts differ on at most `verdictDiffMax` of comparable words
/// and b2's inconclusive rate is at most `inconclusiveRiseMaxPoints` above the oracle's.
public struct DownstreamGate: Codable, Sendable, Equatable {
    public var set: String
    public var oracle: String
    public var words: Int
    public var differing: Int
    public var diffShare: Double?
    /// Words whose verdicts differ, by the part that differs (a word can count in several).
    public var differingParts: [String: Int]
    public var oracleInconclusiveRate: Double?
    public var candidateInconclusiveRate: Double?
    /// Of the candidate's inconclusive words, those set inconclusive by the CTC confidence gate.
    public var inconclusiveByConfidence: Int
    public var riseInconclusivePoints: Double?
    public var verdictDiffMax: Double
    public var inconclusiveRiseMaxPoints: Double
    public var diffOutcome: Outcome
    public var riseOutcome: Outcome
    public var outcome: Outcome
    /// Why the set was not evaluated, when it was not.
    public var reason: String?

    public static func compare(_ pairs: [(oracle: WordVerdict, candidate: WordVerdict)], set: String, oracle: String,
                               inconclusiveByConfidence: Int = 0,
                               thresholds: Thresholds.WordBoundaries = Thresholds.current.wordBoundaries) -> DownstreamGate {
        var parts: [String: Int] = [:]
        var differing = 0
        for (o, c) in pairs where o != c {
            differing += 1
            if o.inconclusive != c.inconclusive { parts["inconclusive", default: 0] += 1 }
            if o.syllableCount != c.syllableCount { parts["syllableCount", default: 0] += 1 }
            if o.longestSyllable != c.longestSyllable { parts["longestSyllable", default: 0] += 1 }
            if o.loudestSyllable != c.loudestSyllable { parts["loudestSyllable", default: 0] += 1 }
        }
        let n = Double(pairs.count)
        let share = pairs.isEmpty ? nil : Double(differing) / n
        let oracleRate = pairs.isEmpty ? nil : Double(pairs.count { $0.oracle.inconclusive }) / n
        let candidateRate = pairs.isEmpty ? nil : Double(pairs.count { $0.candidate.inconclusive }) / n
        let rise = oracleRate.flatMap { o in candidateRate.map { microunit($0 - o) } }
        let diffOutcome = share.map { microunit($0) <= thresholds.verdictDiffMax ? Outcome.pass : .fail } ?? .notEvaluated
        let riseOutcome = rise.map { $0 <= thresholds.inconclusiveRiseMaxPoints ? Outcome.pass : .fail } ?? .notEvaluated
        return DownstreamGate(
            set: set, oracle: oracle, words: pairs.count, differing: differing, diffShare: share,
            differingParts: parts, oracleInconclusiveRate: oracleRate, candidateInconclusiveRate: candidateRate,
            inconclusiveByConfidence: inconclusiveByConfidence, riseInconclusivePoints: rise,
            verdictDiffMax: thresholds.verdictDiffMax, inconclusiveRiseMaxPoints: thresholds.inconclusiveRiseMaxPoints,
            diffOutcome: diffOutcome, riseOutcome: riseOutcome, outcome: Outcome.combine([diffOutcome, riseOutcome]),
            reason: pairs.isEmpty ? "no comparable words" : nil)
    }

    public static func notEvaluated(set: String, oracle: String, reason: String,
                                    thresholds: Thresholds.WordBoundaries = Thresholds.current.wordBoundaries) -> DownstreamGate {
        DownstreamGate(
            set: set, oracle: oracle, words: 0, differing: 0, diffShare: nil, differingParts: [:],
            oracleInconclusiveRate: nil, candidateInconclusiveRate: nil, inconclusiveByConfidence: 0,
            riseInconclusivePoints: nil, verdictDiffMax: thresholds.verdictDiffMax,
            inconclusiveRiseMaxPoints: thresholds.inconclusiveRiseMaxPoints, diffOutcome: .notEvaluated,
            riseOutcome: .notEvaluated, outcome: .notEvaluated, reason: reason)
    }
}

/// Rounded to a millionth, so a share of exactly 0.02 isn't pushed over the bar by floating point.
func microunit(_ value: Double) -> Double {
    (value * 1_000_000).rounded() / 1_000_000
}
