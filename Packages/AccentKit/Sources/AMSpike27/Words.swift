// Spec 27 §1: the words of a take, their lexical targets, and the two front-end arms that pick a word's nuclei.

import AMAlignment
import AMCore
import AMProsody
import Foundation

/// Where a take's word boundaries come from (CTO markup 2).
public enum BoundarySource: String, Sendable, Hashable, Codable, CaseIterable {
    /// MFA word boundaries (spec 07's pinned MFA).
    case oracle
    /// Whisper base.en word times under the known prompt text (the shipped source).
    case runtime
    /// Whisper's own transcript (L2 only, CTO markup 3's ASR-transcript variant).
    case asr
}

/// One phrase word with a span on the take's timeline and, when placement applies, its lexical target.
public struct TimedWord: Sendable, Hashable, Codable {
    /// Position in the phrase (the prompt's word index for known text; Whisper's for `asr`).
    public let index: Int
    public let text: String
    public let start: Double
    public let end: Double
    /// The context pronunciation's syllable count.
    public let syllables: Int
    /// N_w (spec 26 §2).
    public let allowed: [Int]
    /// CMUdict primary stress (0-based syllable), nil when placement doesn't apply (monosyllable, excluded
    /// heteronym, entries disagree, no primary).
    public let target: Int?
    /// Why there's no target, when there isn't.
    public let exclusion: String?
    /// An evaluation label tag (L2 sets: "misplaced" or "correct"; nil for natives).
    public let label: String?

    public init(index: Int, text: String, start: Double, end: Double, syllables: Int, allowed: [Int], target: Int?,
                exclusion: String?, label: String? = nil) {
        self.index = index
        self.text = text
        self.start = start
        self.end = end
        self.syllables = syllables
        self.allowed = allowed
        self.target = target
        self.exclusion = exclusion
        self.label = label
    }

    public func moved(start: Double, end: Double) -> TimedWord {
        TimedWord(index: index, text: text, start: start, end: end, syllables: syllables, allowed: allowed,
                  target: target, exclusion: exclusion, label: label)
    }
}

/// Spec 27 §1's target rule: CMUdict primary stress for words of ≥ 2 syllables; a committed heteronym entry wins;
/// a word whose CMUdict entries disagree on primary stress is otherwise excluded.
public struct TargetRule: Sendable {
    public struct Heteronym: Sendable, Hashable, Codable {
        public let phrase: String
        public let word: String
        public let wordIndex: Int
        public let stressIndex: Int?
        public let reason: String
    }

    public let dictionary: PronouncingDictionary
    public let heteronyms: [Heteronym]

    public init(dictionary: PronouncingDictionary, heteronyms: [Heteronym]) {
        self.dictionary = dictionary
        self.heteronyms = heteronyms
    }

    public static func loadHeteronyms(_ url: URL) throws -> [Heteronym] {
        struct File: Decodable { let entries: [Heteronym] }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).entries
    }

    /// (target, exclusion) for `word` at `index` of `phrase` (nil phrase outside the starter set).
    public func target(word: String, index: Int, phrase: String?, context: Pronunciation?) -> (Int?, String?) {
        guard let context else { return (nil, "out of vocabulary") }
        guard context.syllables.count >= 2 else { return (nil, "monosyllable") }
        if let phrase, let entry = heteronyms.first(where: {
            $0.phrase == phrase && $0.wordIndex == index && WordText.fold($0.word) == WordText.fold(word)
        }) {
            guard let stress = entry.stressIndex, stress < context.syllables.count else {
                return (nil, "heteronym excluded: \(entry.reason)")
            }
            return (stress, nil)
        }
        let primaries = Set(dictionary.pronunciations(of: word).map(\.primarySyllable))
        if primaries.count > 1 { return (nil, "CMUdict entries disagree on primary stress") }
        guard let primary = context.primarySyllable else { return (nil, "no primary stress") }
        return (primary, nil)
    }
}

/// Spec 27 §1's two front-end arms (CTO markup 1).
public enum Arm: String, Sendable, Hashable, Codable, CaseIterable {
    /// Count-matched (P ∈ N_w, assigned count = the context count) and not `assignmentAmbiguous`.
    case a = "A"
    /// Top-k: the N most prominent nuclei inside the word's span, in time order; abstain only below N.
    case b = "B"
}

/// Why a word didn't go through the front end.
public enum Abstention: String, Sendable, Hashable, Codable, CaseIterable {
    case nucleusShort = "nucleus-short"
    case countNotContext = "count-not-context"
    case ambiguous = "assignment-ambiguous"
    case tooFewNuclei = "too-few-nuclei"
    case noSpan = "no-span"
}

public enum ArmSelection {
    /// Arm B: indices (into `nuclei`) of the N most prominent nuclei whose peak lies in [start − pad, end + pad],
    /// in time order; nil with fewer than N. Ties go to the higher peak, then the earlier.
    public static func topK(_ nuclei: [MeasuredNucleus], start: Double, end: Double, count: Int,
                            paddingSeconds: Double) -> [Int]? {
        let inside = nuclei.indices.filter {
            nuclei[$0].peakTime >= start - paddingSeconds - 1e-9 && nuclei[$0].peakTime <= end + paddingSeconds + 1e-9
        }
        guard count > 0, inside.count >= count else { return nil }
        let ranked = inside.sorted {
            (nuclei[$0].prominenceDB, nuclei[$0].peakDB, -$0) > (nuclei[$1].prominenceDB, nuclei[$1].peakDB, -$1)
        }
        return Array(ranked.prefix(count)).sorted()
    }

    /// Arm B's span padding: the runtime (Whisper) spans get `alignment.asrPaddingMs` (CTO decision 4), MFA none.
    public static func padding(_ source: BoundarySource, thresholds: Thresholds = .current) -> Double {
        source == .oracle ? 0 : thresholds.alignment.asrPaddingMs / 1000
    }

    /// Arm A's assignment input for a take's words (time order).
    public static func assignerWords(_ words: [TimedWord]) -> [NucleusAssigner.Word] {
        words.map { NucleusAssigner.Word(start: $0.start, end: $0.end, syllables: $0.syllables, allowed: $0.allowed) }
    }
}
