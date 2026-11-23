// The L1 segmentation output (spec 07, plan §9.2): per present word its dictionary syllables with raw duration,
// energy, lengthening exposure and confidence; per word its edges and span confidence; the take's timing level.
// Peak F0 is added by spec 08 from spec 04's track; prominence and the exposure discount are spec 08's.

import AMCore
import Foundation

/// One take's L1 segmentation. `Codable`, keyed by its identity, with a digest specs 08 and 10 can golden-test.
public struct SyllableSegmentation: Sendable, Hashable, Codable {
    /// The L1 identity key (§9.2): the L0 key, the transcript revision, the pronunciation hash and the algorithm
    /// version.
    public struct Key: Sendable, Hashable, Codable {
        /// The key of the L0 stage (frame features, pitch, voicing, word timings) this segmentation was built on.
        /// Opaque here; the pipeline (spec 12) defines it.
        public let l0Key: String
        public let transcriptRevision: Int
        /// SHA-256 of the canonical JSON of the pronunciations the segmenter used, by phrase word.
        public let pronunciationHash: String
        public let algorithmVersion: Int

        public init(l0Key: String, transcriptRevision: Int, pronunciationHash: String,
                    algorithmVersion: Int = Versions.algorithmVersion) {
            self.l0Key = l0Key
            self.transcriptRevision = transcriptRevision
            self.pronunciationHash = pronunciationHash
            self.algorithmVersion = algorithmVersion
        }
    }

    public let key: Key
    /// The `present` and `substituted` words, in your-time order.
    public let words: [SegmentedWord]
    /// Share of the take's syllables at medium confidence or above.
    public let timingShare: Double
    public let timing: TimingLevel

    public init(key: Key, words: [SegmentedWord], timingShare: Double, timing: TimingLevel) {
        self.key = key
        self.words = words
        self.timingShare = timingShare
        self.timing = timing
    }

    /// Every syllable of the take, in time order.
    public var syllables: [SegmentedSyllable] { words.flatMap(\.syllables) }

    /// SHA-256 of this segmentation's canonical JSON, key included.
    public func digest() throws -> String { try CanonicalJSON.sha256(self) }
}

/// One phrase word with audio: `present` words carry syllables, `substituted` words only their edges (anchors for
/// spec 09) and are never measured.
public struct SegmentedWord: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case present, substituted
    }

    public let phraseWord: WordIndex
    public let kind: Kind
    /// The reported word edges: the union of its syllables for a present word. Never the padded edges.
    public let range: TimeRange
    /// The injected boundary this word was segmented from.
    public let injected: SyllableSegmenter.WordSpan
    /// The padded analysis window searched for nuclei. Search only: nothing reported comes from its edges.
    public let searchWindow: TimeRange
    /// 1.0 when the injected span is 60 ms–1.5 s and doesn't overlap a neighbour, else 0.3.
    public let spanSanity: Double
    /// c_w = min(ASR word probability, span sanity).
    public let confidence: Double
    /// Nil for a substituted word, which is never split.
    public let split: SyllableSplit?
    public let syllables: [SegmentedSyllable]

    public init(
        phraseWord: WordIndex, kind: Kind, range: TimeRange, injected: SyllableSegmenter.WordSpan,
        searchWindow: TimeRange, spanSanity: Double, confidence: Double, split: SyllableSplit?,
        syllables: [SegmentedSyllable]
    ) {
        self.phraseWord = phraseWord
        self.kind = kind
        self.range = range
        self.injected = injected
        self.searchWindow = searchWindow
        self.spanSanity = spanSanity
        self.confidence = confidence
        self.split = split
        self.syllables = syllables
    }
}

/// How a present word was split into its dictionary syllables.
public struct SyllableSplit: Sendable, Hashable, Codable {
    public enum Method: String, Sendable, Hashable, Codable {
        /// Boundaries at intensity-envelope minima between voiced nuclei.
        case valleys
        /// Boundaries proportional to each syllable's phone count, when the valleys can't give the dictionary count.
        case proportional
    }

    public let method: Method
    /// The syllable count the word was split into. The dictionary count always wins.
    public let dictionaryCount: Int
    /// Voiced energy peaks inside the word, separated by valleys of at least `confidence.splitValleyMinDB`.
    public let peakCount: Int
    /// s_w.
    public let confidence: Double

    public init(method: Method, dictionaryCount: Int, peakCount: Int, confidence: Double) {
        self.method = method
        self.dictionaryCount = dictionaryCount
        self.peakCount = peakCount
        self.confidence = confidence
    }
}

/// One dictionary syllable of a present word, with its raw L1 features.
public struct SegmentedSyllable: Sendable, Hashable, Codable {
    public let phraseWord: WordIndex
    public let indexInWord: Int
    public let phones: [String]
    /// The dictionary stress of the pronunciation used.
    public let stress: SyllableStress
    public let range: TimeRange
    /// d, in seconds.
    public let duration: Double
    /// e: RMS over the syllable in dBFS, floored at `prominence.energyMinimumDBFS`.
    public let energyDBFS: Double
    /// The last syllable before the end of the take or before a pause longer than `prominence.exposurePauseMs`.
    /// Spec 08 applies the discount.
    public let lengtheningExposed: Bool
    /// min(c_w, s_w).
    public let confidence: Double
    public let level: Confidence

    public init(
        phraseWord: WordIndex, indexInWord: Int, phones: [String], stress: SyllableStress, range: TimeRange,
        duration: Double, energyDBFS: Double, lengtheningExposed: Bool, confidence: Double, level: Confidence
    ) {
        self.phraseWord = phraseWord
        self.indexInWord = indexInWord
        self.phones = phones
        self.stress = stress
        self.range = range
        self.duration = duration
        self.energyDBFS = energyDBFS
        self.lengtheningExposed = lengtheningExposed
        self.confidence = confidence
        self.level = level
    }
}

extension SyllableSegmenter {
    /// Word and syllable confidence levels: high ≥ `levelHigh`, medium ≥ `levelMedium`, else low.
    public static func level(of confidence: Double, thresholds: Thresholds.ConfidenceLevels) -> Confidence {
        if confidence >= thresholds.levelHigh { return .high }
        if confidence >= thresholds.levelMedium { return .medium }
        return .low
    }

    /// Take timing from the share of syllables at medium or above: Good ≥ `timingGood`, Rough ≥ `timingRough`, else
    /// Poor. No syllables is Poor.
    public static func timing(
        of levels: [Confidence], thresholds: Thresholds.ConfidenceLevels
    ) -> (level: TimingLevel, share: Double) {
        guard !levels.isEmpty else { return (.poor, 0) }
        let share = Double(levels.count { $0 >= .medium }) / Double(levels.count)
        if share >= thresholds.timingGood { return (.good, share) }
        if share >= thresholds.timingRough { return (.rough, share) }
        return (.poor, share)
    }
}
