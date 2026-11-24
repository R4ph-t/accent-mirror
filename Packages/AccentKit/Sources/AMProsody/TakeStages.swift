// The shipped take stages (spec 06 alignment and spec 07 syllables) and what L1 stores (spec 28): alignment,
// segmentation and pitch, with no observed stress and no placement decision. `AMPlacement`'s
// `StressPlacementDetector` runs these same stages, then its placement rule; the shipped analyzer runs only these.

import AMAlignment
import AMCore
import AMPitch
import Foundation

/// One take to analyse: its audio, the phrase words with their pronunciations, and the recogniser's words.
public struct PlacementTake: Sendable {
    public struct Word: Sendable, Hashable {
        public let index: WordIndex
        public let text: String
        /// The pronunciation to segment with; its syllable count is the reference count.
        public let pronunciation: Pronunciation
        /// A(w); nil when the word gets no placement decision (not in the set, or `expectedAmbiguous`).
        public let accepted: Set<Int>?
        /// The context-resolved expected stress (spec 28 §4), one entry per syllable: spec 06's selected
        /// pronunciation (override, or the POS-selected variant). Nil for an `expectedAmbiguous` word or one with no
        /// dictionary pronunciation; the lexical pattern, not what any speaker did.
        public let expectedStress: [SyllableStress]?

        /// `expectedStress` defaults to the pronunciation's own pattern.
        public init(index: WordIndex, text: String, pronunciation: Pronunciation, accepted: Set<Int>?) {
            self.init(
                index: index, text: text, pronunciation: pronunciation, accepted: accepted,
                expectedStress: pronunciation.stressPattern)
        }

        public init(
            index: WordIndex, text: String, pronunciation: Pronunciation, accepted: Set<Int>?,
            expectedStress: [SyllableStress]?
        ) {
            self.index = index
            self.text = text
            self.pronunciation = pronunciation
            self.accepted = accepted
            self.expectedStress = expectedStress
        }
    }

    /// Mono samples.
    public var samples: [Float]
    public var sampleRate: Double
    /// Every transcript word, in order.
    public var words: [Word]
    /// The recogniser's words (replayed in evaluation and CI; ASR never runs here).
    public var heard: [WordTimestamp]
    /// Identifies the L0 inputs (audio, ASR, pitch, voicing) for the L1 key.
    public var l0Key: String

    public init(
        samples: [Float], sampleRate: Double = 16_000, words: [Word], heard: [WordTimestamp], l0Key: String
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.words = words
        self.heard = heard
        self.l0Key = l0Key
    }
}

/// One take's L1 prosody (spec 28): what the shipped path stores and reads. Old L1 records that also carry `words`
/// (observed stress and placement decisions) still decode; the extra keys are ignored.
public struct TakeProsody: Sendable, Hashable, Codable {
    public let segmentation: SyllableSegmentation
    /// The word alignment the segmentation was built from.
    public let alignment: WordAlignment
    /// The take's pitch track (spec 04).
    public let pitch: PitchTrack

    public init(segmentation: SyllableSegmentation, alignment: WordAlignment, pitch: PitchTrack) {
        self.segmentation = segmentation
        self.alignment = alignment
        self.pitch = pitch
    }
}

/// Alignment and syllable segmentation of one take, as stages (spec 12's analyzer runs them separately so each
/// failure names its stage and pitch can run alongside ASR).
public struct TakeStages: Sendable {
    public let voicing: any VoicingSource
    public let aligner: WordAligner
    public let thresholds: Thresholds

    public init(voicing: any VoicingSource, aligner: WordAligner, thresholds: Thresholds = .current) {
        self.voicing = voicing
        self.aligner = aligner
        self.thresholds = thresholds
    }

    /// Spec 06: the recogniser's words aligned to the transcript, with the summary the decision procedure reads.
    public func align(_ take: PlacementTake) throws -> WordAlignmentResult {
        let phrase = ExpectedPhrase(words: take.words.map { word in
            ExpectedWord(
                index: word.index, text: word.text, pronunciation: word.pronunciation, source: .override,
                expectedAmbiguous: word.accepted == nil, isContent: true, isTarget: word.accepted != nil)
        })
        let heard = take.heard.sorted { ($0.start, $0.end) < ($1.start, $1.end) }.compactMap { word in
            (try? TimeRange(start: word.start, end: max(word.start, word.end))).map { HeardWord(text: word.word, range: $0) }
        }
        return try aligner.align(phrase, heard: heard)
    }

    /// Spec 07: syllables of the aligned words. `voicing` defaults to the detector's own; the analyzer passes the
    /// take's voicing decided once in L0.
    public func segment(
        _ take: PlacementTake, alignment: WordAlignment, voicing: (any VoicingSource)? = nil, transcriptRevision: Int = 0
    ) throws -> SyllableSegmentation {
        var spans: [WordIndex: SyllableSegmenter.WordSpan] = [:]
        for pair in alignment.pairs {
            guard let word = pair.phraseWord, let range = pair.yourRange else { continue }
            if case .inserted = pair { continue }
            spans[word] = try SyllableSegmenter.WordSpan(
                start: range.start, end: range.end, probability: Self.probability(of: range, in: take.heard))
        }
        let pronunciations = Dictionary(uniqueKeysWithValues: take.words.map { ($0.index, $0.pronunciation) })
        return try SyllableSegmenter(voicing: voicing ?? self.voicing, thresholds: thresholds).segment(.init(
            samples: take.samples, sampleRate: take.sampleRate, alignment: alignment, pronunciations: pronunciations,
            spans: spans, l0Key: take.l0Key, transcriptRevision: transcriptRevision))
    }

    /// The lowest probability among the recognised words overlapping `range` (a recognised word the aligner split
    /// over several phrase words lends its probability to each); 1 when none overlaps.
    static func probability(of range: TimeRange, in heard: [WordTimestamp]) -> Double {
        let overlapping = heard.filter { $0.start < range.end && $0.end > range.start }
            + heard.filter { $0.start == range.start && $0.end == range.end }
        return min(1, max(0, overlapping.map(\.probability).min() ?? 1))
    }
}
