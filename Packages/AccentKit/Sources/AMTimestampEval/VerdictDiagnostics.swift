import Foundation

/// The CTO diagnostic round on spec 23's downstream gate (decision on #27, 2026-11-23): counts and bins over the
/// gate's per-word verdict pairs. Measures only: it reads no threshold and decides nothing.
///
/// One `DiagnosticWord` is one comparable word of the gate harness: the oracle's verdict, the candidate's, the
/// candidate's again with the CTC confidence gate bypassed (equal to `candidate` for candidates with no gate), the
/// word's boundary error against the oracle and whether the confidence gate set its probability to 0.
public struct DiagnosticWord: Codable, Sendable, Equatable {
    public var clipID: String
    public var word: String
    public var oracle: WordVerdict
    public var candidate: WordVerdict
    public var candidateUngated: WordVerdict
    /// max(|start error|, |end error|) of the candidate's span against the oracle's, in ms.
    public var boundaryErrorMs: Double
    public var gatedByConfidence: Bool
    /// Spec 25 (CTO markup 3): a nucleus peak lies within 40 ms of either of the word's oracle edges. Nil when the
    /// harness had no pitch track (no nuclei).
    public var nucleusNearEdge: Bool?
    /// Spec 25, `.nucleus` only, on the oracle side: P (the nuclei the word could take) and whether it is
    /// nucleus-short. Diagnostics only.
    public var oracleNucleusAvailable: Int?
    public var oracleNucleusShort: Bool?

    public init(clipID: String, word: String, oracle: WordVerdict, candidate: WordVerdict,
                candidateUngated: WordVerdict? = nil, boundaryErrorMs: Double, gatedByConfidence: Bool = false,
                nucleusNearEdge: Bool? = nil) {
        self.clipID = clipID
        self.word = word
        self.oracle = oracle
        self.candidate = candidate
        self.candidateUngated = candidateUngated ?? candidate
        self.boundaryErrorMs = boundaryErrorMs
        self.gatedByConfidence = gatedByConfidence
        self.nucleusNearEdge = nucleusNearEdge
    }

    public var flipped: Bool { oracle != candidate }

    /// The verdict parts that differ, in the gate's names.
    public var differingParts: [String] {
        VerdictDiagnostics.parts.filter { part in
            switch part {
            case "inconclusive": oracle.inconclusive != candidate.inconclusive
            case "syllableCount": oracle.syllableCount != candidate.syllableCount
            case "longestSyllable": oracle.longestSyllable != candidate.longestSyllable
            default: oracle.loudestSyllable != candidate.loudestSyllable
            }
        }
    }
}

public enum VerdictDiagnostics {
    /// Spec 07's verdict parts, as `DownstreamGate` names them. Spec 07's verdict has no pitch part.
    public static let parts = ["inconclusive", "syllableCount", "longestSyllable", "loudestSyllable"]

    /// n words, n flipped, flip share of a group.
    public struct Bin: Codable, Sendable, Equatable {
        public var label: String
        public var words: Int
        public var flipped: Int
        public var share: Double?

        public init(label: String, words: Int, flipped: Int) {
            self.label = label
            self.words = words
            self.flipped = flipped
            share = words == 0 ? nil : Double(flipped) / Double(words)
        }
    }

    /// The gate's columns for one oracle/candidate pair.
    public struct Diff: Codable, Sendable, Equatable {
        public var words: Int
        public var differing: Int
        public var share: Double?
        public var parts: [String: Int]
        public var oracleInconclusive: Int
        public var candidateInconclusive: Int
        public var oracleInconclusiveRate: Double?
        public var candidateInconclusiveRate: Double?
        public var risePoints: Double?
    }

    public static func diff(_ words: [DiagnosticWord]) -> Diff {
        var parts: [String: Int] = [:]
        for word in words { for part in word.differingParts { parts[part, default: 0] += 1 } }
        let n = Double(words.count)
        let o = words.count { $0.oracle.inconclusive }, c = words.count { $0.candidate.inconclusive }
        let oRate = words.isEmpty ? nil : Double(o) / n, cRate = words.isEmpty ? nil : Double(c) / n
        return Diff(words: words.count, differing: words.count(where: \.flipped),
                    share: words.isEmpty ? nil : Double(words.count(where: \.flipped)) / n, parts: parts,
                    oracleInconclusive: o, candidateInconclusive: c, oracleInconclusiveRate: oRate,
                    candidateInconclusiveRate: cRate,
                    risePoints: oRate.flatMap { o in cRate.map { (($0 - o) * 100 * 1_000_000).rounded() / 1_000_000 } })
    }

    /// Flipped words by cue. `parts`: a word counts once per part that differs. `sole`: words where that part is
    /// the only one that differs.
    public struct Cues: Codable, Sendable, Equatable {
        public var flipped: Int
        public var parts: [String: Int]
        public var sole: [String: Int]
        public var pitch: String
    }

    public static func cues(_ words: [DiagnosticWord]) -> Cues {
        var parts: [String: Int] = [:], sole: [String: Int] = [:]
        for word in words where word.flipped {
            let differing = word.differingParts
            for part in differing { parts[part, default: 0] += 1 }
            if differing.count == 1 { sole[differing[0], default: 0] += 1 }
        }
        return Cues(flipped: words.count(where: \.flipped), parts: parts, sole: sole,
                    pitch: "pitch: not a verdict part in spec 07")
    }

    /// By the oracle side's syllable count: 1, 2, 3, 4+.
    public static func bySyllableCount(_ words: [DiagnosticWord]) -> [Bin] {
        let labels = ["1", "2", "3", "4+"]
        return labels.enumerated().map { index, label in
            let group = words.filter { index == 3 ? $0.oracle.syllableCount >= 4 : $0.oracle.syllableCount == index + 1 }
            return Bin(label: label, words: group.count, flipped: group.count(where: \.flipped))
        } + {
            let other = words.filter { $0.oracle.syllableCount < 1 }
            return other.isEmpty ? [] : [Bin(label: "0", words: other.count, flipped: other.count(where: \.flipped))]
        }()
    }

    /// Flipped words by transition: `decided↔decided` (neither side inconclusive: feedback↔close) and
    /// `↔inconclusive` (either side inconclusive). `words` is all flipped words; `flipped` is that type's count.
    public static func byTransition(_ words: [DiagnosticWord]) -> [Bin] {
        let flipped = words.filter(\.flipped)
        let decided = flipped.count { !$0.oracle.inconclusive && !$0.candidate.inconclusive }
        return [Bin(label: "decided↔decided (feedback↔close)", words: flipped.count, flipped: decided),
                Bin(label: "anything↔inconclusive", words: flipped.count, flipped: flipped.count - decided)]
    }

    /// The boundary-error bins, upper edges inclusive: [0, 20], (20, 40], (40, 80], (80, 160], > 160 ms.
    public static let errorEdgesMs: [Double] = [20, 40, 80, 160]

    public static func byBoundaryError(_ words: [DiagnosticWord]) -> [Bin] {
        let labels = ["0–20 ms", "20–40 ms", "40–80 ms", "80–160 ms", ">160 ms"]
        var groups = Array(repeating: [DiagnosticWord](), count: labels.count)
        for word in words {
            groups[errorEdgesMs.firstIndex { word.boundaryErrorMs <= $0 } ?? errorEdgesMs.count].append(word)
        }
        return zip(labels, groups).map { Bin(label: $0, words: $1.count, flipped: $1.count(where: \.flipped)) }
    }

    /// Splits the candidate's inconclusive rise over the oracle into what the CTC confidence gate adds and the rest
    /// (the verdict margins): full rise − rise with the gate bypassed, and the rise with the gate bypassed.
    public struct InconclusiveSplit: Codable, Sendable, Equatable {
        public var words: Int
        public var oracleInconclusive: Int
        public var candidateInconclusive: Int
        public var candidateUngatedInconclusive: Int
        public var gatedWords: Int
        public var fullRiseWords: Int
        public var fromGateWords: Int
        public var fromMarginsWords: Int
        public var fullRisePoints: Double?
        public var fromGatePoints: Double?
        public var fromMarginsPoints: Double?
    }

    public static func inconclusiveSplit(_ words: [DiagnosticWord]) -> InconclusiveSplit {
        let o = words.count { $0.oracle.inconclusive }
        let c = words.count { $0.candidate.inconclusive }
        let u = words.count { $0.candidateUngated.inconclusive }
        func points(_ count: Int) -> Double? {
            words.isEmpty ? nil : (Double(count) / Double(words.count) * 100 * 1_000_000).rounded() / 1_000_000
        }
        return InconclusiveSplit(
            words: words.count, oracleInconclusive: o, candidateInconclusive: c, candidateUngatedInconclusive: u,
            gatedWords: words.count(where: \.gatedByConfidence), fullRiseWords: c - o, fromGateWords: c - u,
            fromMarginsWords: u - o, fullRisePoints: points(c - o), fromGatePoints: points(c - u),
            fromMarginsPoints: points(u - o))
    }

    /// Phrase words the oracle times (and that have a pronunciation) but the recogniser's words don't match, so the
    /// gate leaves them out of the comparable words. `substituted`: an unmatched recogniser word lies between the
    /// nearest matched words around it (the recogniser heard something else there); `deleted`: none does.
    ///
    /// - Parameters:
    ///   - matches: per phrase token, the index of the recogniser word matched to it (`Tokens.match`), or nil.
    ///   - eligible: per phrase token, whether the oracle times it and it has a pronunciation.
    ///   - recognised: how many recogniser words there are.
    public static func unmatched(matches: [Int?], eligible: [Bool], recognised: Int) -> (substituted: Int, deleted: Int) {
        let used = Set(matches.compactMap { $0 })
        var substituted = 0, deleted = 0
        for (position, match) in matches.enumerated() where match == nil && eligible[position] {
            let before = matches[..<position].last { $0 != nil }.flatMap { $0 } ?? -1
            let after = matches[(position + 1)...].first { $0 != nil }.flatMap { $0 } ?? recognised
            let gap = before + 1 < after ? (before + 1)..<after : 0..<0
            if gap.contains(where: { !used.contains($0) }) { substituted += 1 } else { deleted += 1 }
        }
        return (substituted, deleted)
    }
}
