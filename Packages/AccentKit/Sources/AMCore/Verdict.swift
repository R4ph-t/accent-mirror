// Verdicts and diff rows (plan §1). Rows carry structured values only; sentences live in the app (Designer).

import Foundation

public enum Verdict: Sendable, Hashable, Codable {
    /// 1...3 ranked rows; `partial` lists required applicable measures that were unavailable (empty = complete).
    case feedback(rows: BoundedRows, partial: [MeasureKind])
    /// Every §1.3 condition holds.
    case close
    /// Judged, nothing fired, but a `close` condition failed.
    case noClearDifference([NeutralReason])
    /// Abstained: required evidence missing.
    case inconclusive([InconclusiveReason])

    enum NoClearDifferenceCodingKeys: String, CodingKey { case _0 = "reasons" }
    enum InconclusiveCodingKeys: String, CodingKey { case _0 = "reasons" }
}

public enum NeutralReason: Sendable, Hashable, Codable {
    case pitchShapeBelowClose(Double)
    case optionalMeasuresUnavailable([MeasureKind])
    case mediumConfidenceOnly([MeasureKind])
    case timingRough
    case nonTargetWordsIncomplete([WordIndex])
    case insertionsPresent([String])

    enum PitchShapeBelowCloseCodingKeys: String, CodingKey { case _0 = "shapeMatch" }
    enum OptionalMeasuresUnavailableCodingKeys: String, CodingKey { case _0 = "measures" }
    enum MediumConfidenceOnlyCodingKeys: String, CodingKey { case _0 = "measures" }
    enum NonTargetWordsIncompleteCodingKeys: String, CodingKey { case _0 = "words" }
    enum InsertionsPresentCodingKeys: String, CodingKey { case _0 = "words" }
}

public enum InconclusiveReason: Sendable, Hashable, Codable {
    case targetWordsMissing([WordIndex])
    case timingUnreliable
    case comparableCoverageLow(Double)
    case requiredMeasureUnavailable([MeasureKind])
    case noApplicableStressMeasure

    enum TargetWordsMissingCodingKeys: String, CodingKey { case _0 = "words" }
    enum ComparableCoverageLowCodingKeys: String, CodingKey { case _0 = "coverage" }
    enum RequiredMeasureUnavailableCodingKeys: String, CodingKey { case _0 = "measures" }
}

/// Diff kinds in ranking order (v1, Open question 3): the rough-timing row first, too much contrast always last.
/// Ties within a kind go to the larger relative gap (spec 10 computes the gaps).
public enum DiffKind: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case roughTiming, placement, contrast, weakLength, pitchRange, finalDirection, tooMuchContrast

    public static func < (lhs: DiffKind, rhs: DiffKind) -> Bool {
        Self.allCases.firstIndex(of: lhs)! < Self.allCases.firstIndex(of: rhs)!
    }
}

/// One feedback row: structured values only, never a sentence.
public struct DiffRow: Sendable, Hashable, Codable {
    public let kind: DiffKind
    /// The phrase word the row is about; nil for phrase-level rows (rough timing, pitch range, contrast over the phrase).
    public let word: WordIndex?
    /// Syllables the row points at, as indices into the model's `SpeakerAnalysis.syllables`.
    public let syllables: [Int]
    /// Placement: the accepted primary the row names, as a syllable index within `word`.
    public let acceptedSyllable: Int?
    /// Placement: your observed primary, as a syllable index within `word`.
    public let heardSyllable: Int?
    /// Placement: the native voice whose accepted pattern is named ("like p311"), when it isn't the context pronunciation.
    public let likeVoice: String?
    public let values: DiffValues

    public init(
        kind: DiffKind, word: WordIndex? = nil, syllables: [Int] = [], acceptedSyllable: Int? = nil,
        heardSyllable: Int? = nil, likeVoice: String? = nil, values: DiffValues = DiffValues()
    ) {
        self.kind = kind
        self.word = word
        self.syllables = syllables
        self.acceptedSyllable = acceptedSyllable
        self.heardSyllable = heardSyllable
        self.likeVoice = likeVoice
        self.values = values
    }
}

/// The measured numbers behind a row, in the measure's own unit (ratio, points, st, st/s).
public struct DiffValues: Sendable, Hashable, Codable {
    public let you: Double?
    public let model: Double?

    public init(you: Double? = nil, model: Double? = nil) {
        self.you = you
        self.model = model
    }
}

/// One to three diff rows. Any other count can't be built, and decoding one throws.
public struct BoundedRows: Sendable, Hashable, Codable, RandomAccessCollection {
    public static let allowedCount = 1...3

    public let rows: [DiffRow]

    public init?(_ rows: [DiffRow]) {
        guard Self.allowedCount.contains(rows.count) else { return nil }
        self.rows = rows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rows = try container.decode([DiffRow].self)
        guard let bounded = BoundedRows(rows) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "BoundedRows needs 1...3 rows, got \(rows.count)")
        }
        self = bounded
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rows)
    }

    public var startIndex: Int { rows.startIndex }
    public var endIndex: Int { rows.endIndex }
    public subscript(position: Int) -> DiffRow { rows[position] }
}
