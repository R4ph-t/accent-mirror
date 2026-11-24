// The §6.5 ceiling-aware baseline rule and the detector baselines it compares against.

import Foundation
import AMCore

/// Per-syllable L1 features a baseline reads: raw duration and energy (spec 07/08 produce them).
public struct SyllableFeatures: Sendable, Hashable, Codable {
    public let durationS: Double
    public let energyDB: Double

    public init(durationS: Double, energyDB: Double) {
        self.durationS = durationS
        self.energyDB = energyDB
    }
}

/// A word as the baselines see it: its syllables' L1 features and, for B0, the dictionary primary.
public struct BaselineWord: Sendable, Hashable, Codable {
    public let syllables: [SyllableFeatures]
    /// The dictionary (CMUdict) primary index, for B0.
    public let dictionaryPrimary: Int?

    public init(syllables: [SyllableFeatures], dictionaryPrimary: Int?) {
        self.syllables = syllables
        self.dictionaryPrimary = dictionaryPrimary
    }
}

/// The baselines of §6.5. B1 and B2 are detector baselines on L1 features; B0 (dictionary) is for which-syllable
/// accuracy only (it never flags a word, since it always says the dictionary primary).
public enum DetectorBaseline: String, Sendable, Hashable, Codable, CaseIterable {
    /// B0: the dictionary primary.
    case dictionary = "B0"
    /// B1: the longest syllable is the primary.
    case longestSyllable = "B1"
    /// B2: the loudest syllable is the primary.
    case loudestSyllable = "B2"

    /// The syllable this baseline calls primary, or nil when it can't say (no syllables, no dictionary entry).
    /// Ties go to the earliest syllable.
    public func primary(of word: BaselineWord) -> Int? {
        switch self {
        case .dictionary:
            return word.dictionaryPrimary
        case .longestSyllable:
            return Self.argmax(word.syllables.map(\.durationS))
        case .loudestSyllable:
            return Self.argmax(word.syllables.map(\.energyDB))
        }
    }

    /// Whether the baseline raises a placement flag: its primary is outside the accepted set A(w).
    public func flags(_ word: BaselineWord, accepted: Set<Int>) -> Bool? {
        primary(of: word).map { !accepted.contains($0) }
    }

    static func argmax(_ values: [Double]) -> Int? {
        guard var best = values.indices.first else { return nil }
        for i in values.indices where values[i] > values[best] { best = i }
        return best
    }
}

/// The §6.5 ceiling-aware rule, as one function. Values are shares; "points" are shares (0.03 = 3 pp).
public struct BaselineRule: Sendable, Hashable {
    public enum Kind: String, Sendable, Codable {
        /// Higher is better (recall, accuracy): D ≥ B* − shortfall, the paired bootstrap lower bound of D − B* at or
        /// above its floor, and below the ceiling D − B* ≥ min(lift cap, (1 − B*)/2).
        case accuracy
        /// Lower is better (false positives): the mirror rule D ≤ B* + excess.
        case falsePositive
    }

    public struct Verdict: Sendable, Hashable, Codable {
        public let passes: Bool
        /// The best baseline value B* the detector was compared with.
        public let bestBaseline: Double
        /// Each failed clause, in words.
        public let failures: [String]
    }

    public let agreement: Thresholds.Agreement

    public init(thresholds: Thresholds = .current) {
        agreement = thresholds.agreement
    }

    /// B*: the best of the baselines (highest for accuracy, lowest for false positives).
    public static func best(of baselines: [Double], kind: Kind) -> Double? {
        kind == .accuracy ? baselines.max() : baselines.min()
    }

    /// Applies the rule. `pairedLowerBound` is the lower bound of the paired clustered bootstrap of D − B*; it is
    /// required for `.accuracy` (a missing bound fails the clause, never passes it).
    public func evaluate(detector d: Double, bestBaseline b: Double, pairedLowerBound: Double?, kind: Kind) -> Verdict {
        var failures: [String] = []
        let epsilon = 1e-12
        switch kind {
        case .accuracy:
            if d < b - agreement.baselineMaxShortfallPoints - epsilon {
                failures.append("D below B* − \(agreement.baselineMaxShortfallPoints)")
            }
            if let lower = pairedLowerBound {
                if lower < agreement.baselineBootstrapLowerPoints - epsilon {
                    failures.append("paired bootstrap lower bound of D − B* below \(agreement.baselineBootstrapLowerPoints)")
                }
            } else {
                failures.append("paired bootstrap lower bound of D − B* missing")
            }
            if b < agreement.baselineCeiling {
                let lift = min(agreement.baselineMinLiftCapPoints, (1 - b) / 2)
                if d - b < lift - epsilon {
                    failures.append("B* below the ceiling and D − B* below min(lift cap, (1 − B*)/2) = \(lift)")
                }
            }
        case .falsePositive:
            if d > b + agreement.baselineFalsePositiveMaxExcessPoints + epsilon {
                failures.append("D above B* + \(agreement.baselineFalsePositiveMaxExcessPoints)")
            }
        }
        return Verdict(passes: failures.isEmpty, bestBaseline: b, failures: failures)
    }
}

/// McNemar comparison of a detector with a baseline on the same words, with per-speaker wins and losses.
public struct PairedComparison: Sendable, Hashable, Codable {
    /// Detector right, baseline wrong.
    public let b: Int
    /// Detector wrong, baseline right.
    public let c: Int
    public let pValue: Double
    /// Per speaker: (wins, losses) = (b, c) restricted to that speaker.
    public let perSpeaker: [String: [Int]]

    /// `outcomes`: per word, its speaker, whether the detector was right, whether the baseline was right.
    public init(outcomes: [(speaker: String, detectorRight: Bool, baselineRight: Bool)]) {
        var b = 0
        var c = 0
        var perSpeaker: [String: [Int]] = [:]
        for outcome in outcomes {
            var entry = perSpeaker[outcome.speaker] ?? [0, 0]
            if outcome.detectorRight && !outcome.baselineRight {
                b += 1
                entry[0] += 1
            } else if !outcome.detectorRight && outcome.baselineRight {
                c += 1
                entry[1] += 1
            }
            perSpeaker[outcome.speaker] = entry
        }
        self.b = b
        self.c = c
        self.pValue = Statistics.mcnemarExact(b: b, c: c)
        self.perSpeaker = perSpeaker
    }
}
