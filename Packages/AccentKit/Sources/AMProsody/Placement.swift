// The one placement rule (spec 08, plan §3.3 and §5). The app (spec 10) and the shared-detector validation mode
// (spec 02, §6.3) both call `placementDecision`; there is no second copy.

import AMCore
import Foundation

/// Why a raw placement mismatch was not flagged, in the order the rule checks them.
public enum PlacementSuppressionReason: String, Sendable, Hashable, Codable, CaseIterable {
    /// The word's syllable confidence is below medium.
    case lowSyllableConfidence
    /// The word has a lengthening-exposed syllable and its stress confidence is below high.
    case exposedSyllable
    /// Stress confidence below high (§3.3: a placement flag needs high).
    case stressConfidenceBelowHigh
}

/// The placement decision for one word, with the facts the harness counts before and after suppression.
public struct PlacementDecision: Sendable, Hashable, Codable {
    public let observedPrimary: Int
    /// Before suppression: the observed primary is outside A(w).
    public let outsideAccepted: Bool
    /// The stress confidence the decision read.
    public let stressConfidence: Confidence
    /// Why a mismatch was not flagged; nil when it was flagged or when there was no mismatch.
    public let suppression: PlacementSuppressionReason?

    public init(
        observedPrimary: Int, outsideAccepted: Bool, stressConfidence: Confidence,
        suppression: PlacementSuppressionReason?
    ) {
        self.observedPrimary = observedPrimary
        self.outsideAccepted = outsideAccepted
        self.stressConfidence = stressConfidence
        self.suppression = suppression
    }

    /// After suppression: a placement flag.
    public var flagged: Bool { outsideAccepted && suppression == nil }
}

/// The placement rule. Flags only when the observed primary ∉ A(w), stress confidence is high, and the syllable
/// confidence is ≥ medium. A word with an exposed syllable needs high stress confidence too; the high rule already
/// implies it, and `exposure` keeps it explicit. Nil when A(w) is empty: no placement decision for that word.
///
/// - Parameters:
///   - observed: the word's observed stress in your take.
///   - accepted: A(w), the accepted primaries (indices in word).
///   - confidence: the word's syllable confidence level (spec 07).
///   - exposure: the word has a lengthening-exposed syllable.
public func placementDecision(
    observed: ObservedStress, accepted: Set<Int>, confidence: Confidence, exposure: Bool
) -> PlacementDecision? {
    guard !accepted.isEmpty else { return nil }
    let outside = !accepted.contains(observed.primary)
    let stress = observed.confidence
    var suppression: PlacementSuppressionReason?
    if outside {
        if confidence < .medium {
            suppression = .lowSyllableConfidence
        } else if exposure && stress < .high {
            suppression = .exposedSyllable
        } else if stress < .high {
            suppression = .stressConfidenceBelowHigh
        }
    }
    return PlacementDecision(
        observedPrimary: observed.primary, outsideAccepted: outside, stressConfidence: stress, suppression: suppression)
}
