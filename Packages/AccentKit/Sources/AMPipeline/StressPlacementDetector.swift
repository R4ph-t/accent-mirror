// The shared-detector stages (spec 08 wiring for spec 02's §6.3 mode): L0 (voicing, pitch, replayed word timings),
// L1 (alignment to the transcript, syllables with the given pronunciations), prominence over every syllable of the
// present words, the lengthening discount, observed stress, confidence, then `placementDecision`, the same function
// the app calls. Not run here: warp, DTW, band, pitch measures, contrast, weak length, ranking.
//
// Suppression is counted at two points (§6.3): before (observed primary ∉ A(w)) and after Poor timing, low word
// confidence, then the placement rule's own suppressions.

import AMAlignment
import AMCapture
import AMCore
import AMPitch
import AMProsody
import Foundation

/// One take to decide placement on.
public struct PlacementTake: Sendable {
    public struct Word: Sendable, Hashable {
        public let index: WordIndex
        public let text: String
        /// The pronunciation to segment with; its syllable count is the reference count.
        public let pronunciation: Pronunciation
        /// A(w); nil when the word gets no placement decision (not in the set, or `expectedAmbiguous`).
        public let accepted: Set<Int>?

        public init(index: WordIndex, text: String, pronunciation: Pronunciation, accepted: Set<Int>?) {
            self.index = index
            self.text = text
            self.pronunciation = pronunciation
            self.accepted = accepted
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

/// Why a raw mismatch was not flagged in the shared-detector mode.
public enum DetectorSuppression: Sendable, Hashable, Codable {
    case poorTiming
    case lowWordConfidence
    case placement(PlacementSuppressionReason)
}

/// One decided word.
public struct PlacementWordResult: Sendable, Hashable, Codable {
    public let word: WordIndex
    /// The word is `present` in the take, so its syllables are comparable.
    public let present: Bool
    public let observed: ObservedStress?
    /// Nil when there is no decision: absent, a monosyllable, or no A(w).
    public let decision: PlacementDecision?
    public let suppression: DetectorSuppression?

    /// Before suppression: observed primary ∉ A(w).
    public var flaggedBeforeSuppression: Bool { decision?.outsideAccepted == true }
    /// After suppression: a placement diff.
    public var flaggedAfterSuppression: Bool { flaggedBeforeSuppression && suppression == nil }
}

public struct PlacementAnalysis: Sendable, Hashable, Codable {
    public let segmentation: SyllableSegmentation
    /// One result per transcript word with an A(w), in transcript order.
    public let words: [PlacementWordResult]
    /// The word alignment the segmentation was built from (spec 10 scores pairs from it).
    public let alignment: WordAlignment
    /// The take's pitch track (spec 04).
    public let pitch: PitchTrack
}

public struct StressPlacementDetector: Sendable {
    public let voicing: any VoicingSource
    public let pitchTracker: any PitchTracker
    public let aligner: WordAligner
    public let thresholds: Thresholds

    public init(
        voicing: any VoicingSource, pitchTracker: any PitchTracker, aligner: WordAligner,
        thresholds: Thresholds = .current
    ) {
        self.voicing = voicing
        self.pitchTracker = pitchTracker
        self.aligner = aligner
        self.thresholds = thresholds
    }

    /// The shipped stages: spec 05's voicing, spec 04's pYIN, spec 06's bundled aligner.
    public static func bundled(thresholds: Thresholds = .current) throws -> StressPlacementDetector {
        StressPlacementDetector(
            voicing: ACFVoicing(thresholds: thresholds), pitchTracker: PYINTracker(thresholds: thresholds.pitch),
            aligner: try WordAligner.bundled(thresholds: thresholds), thresholds: thresholds)
    }

    public func analyse(_ take: PlacementTake) async throws -> PlacementAnalysis {
        let alignment = try align(take).alignment
        let pitch = try await pitchTracker.track(take.samples, sampleRate: take.sampleRate)
        let segmentation = try segment(take, alignment: alignment, pitch: pitch)
        return place(take, alignment: alignment, segmentation: segmentation, pitch: pitch)
    }

    // The stages, one by one (spec 12's analyzer runs them separately so each failure names its stage and pitch can
    // run alongside ASR). `analyse` is exactly these in order.

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
    /// take's voicing decided once in L0. `pitch` (spec 04's track) is needed when `prominence.measurement` is
    /// `.nucleus` (spec 25): its voicing finds the nuclei.
    public func segment(
        _ take: PlacementTake, alignment: WordAlignment, voicing: (any VoicingSource)? = nil, transcriptRevision: Int = 0,
        pitch: PitchTrack? = nil
    ) throws -> SyllableSegmentation {
        var spans: [WordIndex: SyllableSegmenter.WordSpan] = [:]
        for pair in alignment.pairs {
            guard let word = pair.phraseWord, let range = pair.yourRange else { continue }
            if case .inserted = pair { continue }
            spans[word] = try SyllableSegmenter.WordSpan(
                start: range.start, end: range.end, probability: Self.probability(of: range, in: take.heard))
        }
        let pronunciations = Dictionary(uniqueKeysWithValues: take.words.map { ($0.index, $0.pronunciation) })
        // Spec 26 §2: N_w as a set, `.nucleus` only (`.span` keeps the context count).
        var allowed: [WordIndex: AllowedSyllableCounts] = [:]
        if thresholds.prominence.measurement == .nucleus {
            let dictionary = try PronouncingDictionary.bundled(), reduced = try ReducedForms.bundled()
            for word in take.words {
                allowed[word.index] = AllowedSyllableCounts.of(
                    word: word.text, context: word.pronunciation, dictionary: dictionary, reducedForms: reduced)
            }
        }
        return try SyllableSegmenter(voicing: voicing ?? self.voicing, thresholds: thresholds).segment(.init(
            samples: take.samples, sampleRate: take.sampleRate, alignment: alignment, pronunciations: pronunciations,
            spans: spans, l0Key: take.l0Key, transcriptRevision: transcriptRevision, pitch: pitch,
            allowedCounts: allowed))
    }

    /// Spec 08: prominence over the present words' syllables, observed stress and each decided word's placement.
    public func place(
        _ take: PlacementTake, alignment: WordAlignment, segmentation: SyllableSegmentation, pitch: PitchTrack
    ) -> PlacementAnalysis {
        place(
            take, alignment: alignment, segmentation: segmentation, pitch: pitch,
            syllables: ComparableSyllable.all(in: segmentation, pitch: pitch, thresholds: thresholds.prominence))
    }

    /// `place` with the comparable syllables already built (`ComparableSyllable.all(in: segmentation, pitch:)`).
    /// They read no tuned key, so spec 11's tuner builds them once per take and re-places them at every grid point.
    public func place(
        _ take: PlacementTake, alignment: WordAlignment, segmentation: SyllableSegmentation, pitch: PitchTrack,
        syllables: [ComparableSyllable]
    ) -> PlacementAnalysis {
        let prominence = TakeProminence(syllables, thresholds: thresholds.prominence)
        let segmented = Dictionary(segmentation.words.map { ($0.phraseWord, $0) }, uniquingKeysWith: { first, _ in first })

        let results = take.words.compactMap { word -> PlacementWordResult? in
            guard let accepted = word.accepted else { return nil }
            guard let segmentedWord = segmented[word.index], segmentedWord.kind == .present else {
                return PlacementWordResult(word: word.index, present: false, observed: nil, decision: nil, suppression: nil)
            }
            guard let observed = prominence?.observedStress(of: word.index),
                let decision = placementDecision(
                    observed: observed, accepted: accepted, confidence: observed.syllableConfidence,
                    exposure: observed.exposed)
            else {
                return PlacementWordResult(word: word.index, present: true, observed: nil, decision: nil, suppression: nil)
            }
            var suppression: DetectorSuppression?
            if decision.outsideAccepted {
                let wordLevel = SyllableSegmenter.level(of: segmentedWord.confidence, thresholds: thresholds.confidence)
                if segmentation.timing == .poor {
                    suppression = .poorTiming
                } else if wordLevel < .medium {
                    suppression = .lowWordConfidence
                } else if let reason = decision.suppression {
                    suppression = .placement(reason)
                }
            }
            return PlacementWordResult(
                word: word.index, present: true, observed: observed, decision: decision, suppression: suppression)
        }
        return PlacementAnalysis(segmentation: segmentation, words: results, alignment: alignment, pitch: pitch)
    }

    /// The lowest probability among the recognised words overlapping `range` (a recognised word the aligner split
    /// over several phrase words lends its probability to each); 1 when none overlaps.
    static func probability(of range: TimeRange, in heard: [WordTimestamp]) -> Double {
        let overlapping = heard.filter { $0.start < range.end && $0.end > range.start }
            + heard.filter { $0.start == range.start && $0.end == range.end }
        return min(1, max(0, overlapping.map(\.probability).min() ?? 1))
    }
}
