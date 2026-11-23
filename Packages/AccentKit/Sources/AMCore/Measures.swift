// Measures, their states and confidence (plan §1, §1.1).

import Foundation

public enum MeasureKind: String, Sendable, Hashable, Codable, CaseIterable, CodingKeyRepresentable {
    case stressPlacement, contrast, tooMuchContrast, weakLength, rhythm, pitchRange, shapeMatch, finalDirection
}

public enum Confidence: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case low, medium, high

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        Self.allCases.firstIndex(of: lhs)! < Self.allCases.firstIndex(of: rhs)!
    }
}

public enum MeasureState<Value: Sendable & Codable & Hashable>: Sendable, Hashable, Codable {
    /// Impossible by design for this phrase, whatever the take.
    case notApplicable(NotApplicableReason)
    /// Possible for this phrase, but this take's evidence is too poor.
    case unavailable(UnavailableReason)
    case evaluated(Value, Confidence)

    enum NotApplicableCodingKeys: String, CodingKey { case _0 = "reason" }
    enum UnavailableCodingKeys: String, CodingKey { case _0 = "reason" }
    enum EvaluatedCodingKeys: String, CodingKey {
        case _0 = "value"
        case _1 = "confidence"
    }

    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    /// The confidence when evaluated, else nil.
    public var confidence: Confidence? {
        if case .evaluated(_, let confidence) = self { return confidence }
        return nil
    }

    /// The value when evaluated, else nil.
    public var value: Value? {
        if case .evaluated(let value, _) = self { return value }
        return nil
    }
}

public enum NotApplicableReason: String, Sendable, Hashable, Codable, CaseIterable {
    case noEligibleWord, tooFewSyllablesInPhrase, tooFewExpectedUnstressed, modelHasNoFinalVoicing
    case modelTooFewVoicedFrames
}

public enum UnavailableReason: String, Sendable, Hashable, Codable, CaseIterable {
    case wordMissing, wordSubstituted, lowConfidence, noVoicedFrames, tooFewOverlappingFrames, zeroVariance, coverageLow
}

/// Take-level timing (first v2 §5): share of comparable syllables at medium or above.
public enum TimingLevel: String, Sendable, Hashable, Codable, CaseIterable {
    case good, rough, poor
}
