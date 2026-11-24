// The shared-detector stages (spec 08 wiring for spec 02's §6.3 mode): L0 (voicing, pitch, replayed word timings),
// L1 (alignment to the transcript, syllables with the given pronunciations), prominence over every syllable of the
// present words, the lengthening discount, observed stress, confidence, then `placementDecision`, the same function
// spec 10's scoring calls (AMScoring, through AMVerdicts). Not run here: warp, DTW, band, pitch measures, contrast, weak length, ranking.
//
// Suppression is counted at two points (§6.3): before (observed primary ∉ A(w)) and after Poor timing, low word
// confidence, then the placement rule's own suppressions.

import AMAlignment
import AMCapture
import AMCore
import AMPitch
import AMProsody
import Foundation

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

/// One take's prosody with each decided word's placement: the verdict side (evaluation, `AMVerdicts`). The shipped
/// L1 stores only `TakeProsody` (spec 28).
public struct PlacementAnalysis: Sendable, Hashable, Codable {
    public let segmentation: SyllableSegmentation
    /// One result per transcript word with an A(w), in transcript order.
    public let words: [PlacementWordResult]
    /// The word alignment the segmentation was built from (spec 10 scores pairs from it).
    public let alignment: WordAlignment
    /// The take's pitch track (spec 04).
    public let pitch: PitchTrack

    public init(segmentation: SyllableSegmentation, words: [PlacementWordResult], alignment: WordAlignment, pitch: PitchTrack) {
        self.segmentation = segmentation
        self.words = words
        self.alignment = alignment
        self.pitch = pitch
    }

    /// The prosody alone, as the shipped L1 stores it.
    public var prosody: TakeProsody { TakeProsody(segmentation: segmentation, alignment: alignment, pitch: pitch) }
}

/// Spec 08's detector: the shipped stages (`TakeStages`), pitch, then observed stress and `placementDecision`.
/// Verdict-only since spec 28: it lives in `AMPlacement`, which nothing on the shipped path links.
public struct StressPlacementDetector: Sendable {
    public let voicing: any VoicingSource
    public let pitchTracker: any PitchTracker
    public let aligner: WordAligner
    public let thresholds: Thresholds

    /// The alignment and segmentation stages this detector runs.
    public var stages: TakeStages { TakeStages(voicing: voicing, aligner: aligner, thresholds: thresholds) }

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
        let segmentation = try segment(take, alignment: alignment)
        let pitch = try await pitchTracker.track(take.samples, sampleRate: take.sampleRate)
        return place(take, alignment: alignment, segmentation: segmentation, pitch: pitch)
    }

    // The stages, one by one. `analyse` is exactly these in order.

    /// Spec 06: the recogniser's words aligned to the transcript (`TakeStages.align`).
    public func align(_ take: PlacementTake) throws -> WordAlignmentResult { try stages.align(take) }

    /// Spec 07: syllables of the aligned words (`TakeStages.segment`).
    public func segment(
        _ take: PlacementTake, alignment: WordAlignment, voicing: (any VoicingSource)? = nil, transcriptRevision: Int = 0
    ) throws -> SyllableSegmentation {
        try stages.segment(take, alignment: alignment, voicing: voicing, transcriptRevision: transcriptRevision)
    }

    /// Spec 08: prominence over the present words' syllables, observed stress and each decided word's placement.
    public func place(
        _ take: PlacementTake, alignment: WordAlignment, segmentation: SyllableSegmentation, pitch: PitchTrack
    ) -> PlacementAnalysis {
        Self.place(
            words: take.words, prosody: TakeProsody(segmentation: segmentation, alignment: alignment, pitch: pitch),
            thresholds: thresholds)
    }

    /// `place` on a stored prosody (an L1 record's `TakeProsody`): only the phrase words (with A(w)) are read.
    public static func place(
        words: [PlacementTake.Word], prosody: TakeProsody, thresholds: Thresholds = .current
    ) -> PlacementAnalysis {
        let segmentation = prosody.segmentation, alignment = prosody.alignment, pitch = prosody.pitch
        let prominence = TakeProminence(
            ComparableSyllable.all(in: segmentation, pitch: pitch, thresholds: thresholds.prominence),
            thresholds: thresholds.prominence)
        let segmented = Dictionary(segmentation.words.map { ($0.phraseWord, $0) }, uniquingKeysWith: { first, _ in first })

        let results = words.compactMap { word -> PlacementWordResult? in
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
}
