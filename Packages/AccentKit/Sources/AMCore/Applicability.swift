// Applicability (plan §1.1): decided from the phrase and the model take only, never from your take.

import Foundation

/// Whether a measure counts towards the verdict when it is applicable.
public enum MeasureRequirement: String, Sendable, Hashable, Codable, CaseIterable {
    /// Unavailable → `partial` in feedback, or `inconclusive(.requiredMeasureUnavailable)`; must be high for `close`.
    case required
    /// Can produce a diff; must be medium or high for `close`.
    case optional
    /// Shown in the inspector only (nPVI); never a diff.
    case inspectorOnly
}

public enum MeasureApplicability: Sendable, Hashable, Codable {
    case applicable(MeasureRequirement)
    case notApplicable(NotApplicableReason)

    enum ApplicableCodingKeys: String, CodingKey { case _0 = "requirement" }
    enum NotApplicableCodingKeys: String, CodingKey { case _0 = "reason" }

    public var isApplicable: Bool {
        if case .applicable = self { return true }
        return false
    }

    public var isRequired: Bool { self == .applicable(.required) }
}

/// Applicability of every `MeasureKind`. Always total: decoding a table with a kind missing throws.
public struct ApplicabilityTable: Sendable, Hashable, Codable {
    public let entries: [MeasureKind: MeasureApplicability]

    public enum Invalid: Error, Equatable { case missing(MeasureKind) }

    public init(_ entries: [MeasureKind: MeasureApplicability]) throws {
        for kind in MeasureKind.allCases where entries[kind] == nil { throw Invalid.missing(kind) }
        self.entries = entries
    }

    public subscript(kind: MeasureKind) -> MeasureApplicability { entries[kind]! }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let entries = try container.decode([MeasureKind: MeasureApplicability].self)
        do {
            try self.init(entries)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "ApplicabilityTable: \(error)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }
}

/// What applicability needs to know about one phrase word.
public struct PhraseWordFacts: Sendable, Hashable, Codable {
    public let syllableCount: Int
    public let isTarget: Bool
    public let isContentWord: Bool
    /// Stress variants with no context, or out of vocabulary (§3.1): never a placement diff.
    public let isExpectedAmbiguous: Bool

    public init(syllableCount: Int, isTarget: Bool, isContentWord: Bool, isExpectedAmbiguous: Bool = false) {
        self.syllableCount = syllableCount
        self.isTarget = isTarget
        self.isContentWord = isContentWord
        self.isExpectedAmbiguous = isExpectedAmbiguous
    }
}

/// The phrase and the model take, as applicability sees them. Nothing here comes from your take.
public struct ApplicabilityInput: Sendable, Hashable, Codable {
    public let words: [PhraseWordFacts]
    /// |S| and |U|: expected stressed and unstressed syllables over the phrase (spec 08 builds the sets).
    public let expectedStressedSyllables: Int
    public let expectedUnstressedSyllables: Int
    /// Voiced frames in the model take.
    public let modelVoicedFrames: Int
    /// Voiced frames in the model's final window (200 ms, extended to 300 ms, §11).
    public let modelFinalWindowVoicedFrames: Int
    /// Least-squares slope over that window in st/s; nil when it can't be fitted.
    public let modelFinalSlopeSemitonesPerSecond: Double?

    public init(
        words: [PhraseWordFacts], expectedStressedSyllables: Int, expectedUnstressedSyllables: Int,
        modelVoicedFrames: Int, modelFinalWindowVoicedFrames: Int, modelFinalSlopeSemitonesPerSecond: Double?
    ) {
        self.words = words
        self.expectedStressedSyllables = expectedStressedSyllables
        self.expectedUnstressedSyllables = expectedUnstressedSyllables
        self.modelVoicedFrames = modelVoicedFrames
        self.modelFinalWindowVoicedFrames = modelFinalWindowVoicedFrames
        self.modelFinalSlopeSemitonesPerSecond = modelFinalSlopeSemitonesPerSecond
    }
}

/// Which measures are applicable for this phrase and model, and which of them are required (plan §1.1).
public func applicability(_ input: ApplicabilityInput, thresholds: Thresholds = .current) -> ApplicabilityTable {
    let limits = thresholds.applicability
    var table: [MeasureKind: MeasureApplicability] = [:]

    let placementEligible = input.words.contains { word in
        (word.isTarget || word.isContentWord) && !word.isExpectedAmbiguous
            && Double(word.syllableCount) >= limits.placementMinSyllables
    }
    table[.stressPlacement] = placementEligible ? .applicable(.required) : .notApplicable(.noEligibleWord)

    let contrastGroup: MeasureApplicability =
        if Double(input.expectedUnstressedSyllables) < limits.contrastMinUnstressed {
            .notApplicable(.tooFewExpectedUnstressed)
        } else if Double(input.expectedStressedSyllables) < limits.contrastMinStressed {
            .notApplicable(.noEligibleWord)
        } else {
            .applicable(.required)
        }
    table[.contrast] = contrastGroup
    table[.tooMuchContrast] = contrastGroup
    table[.weakLength] = contrastGroup

    let phraseSyllables = input.words.reduce(0) { $0 + $1.syllableCount }
    table[.rhythm] =
        Double(phraseSyllables) >= limits.rhythmMinSyllables
        ? .applicable(.inspectorOnly) : .notApplicable(.tooFewSyllablesInPhrase)

    let pitch: MeasureApplicability =
        Double(input.modelVoicedFrames) >= limits.pitchMinModelVoicedFrames
        ? .applicable(.optional) : .notApplicable(.modelTooFewVoicedFrames)
    table[.pitchRange] = pitch
    table[.shapeMatch] = pitch

    let final = thresholds.finalDirection
    let finalIsDirected = input.modelFinalSlopeSemitonesPerSecond.map { slope in
        slope >= final.riseSemitonesPerSecond || slope <= final.fallSemitonesPerSecond
    } ?? false
    table[.finalDirection] =
        Double(input.modelFinalWindowVoicedFrames) >= final.minVoicedFrames && finalIsDirected
        ? .applicable(.optional) : .notApplicable(.modelHasNoFinalVoicing)

    // Every kind is set above, so the table is total.
    return try! ApplicabilityTable(table)
}
