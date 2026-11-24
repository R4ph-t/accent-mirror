// Descriptive measures (spec 28 §4a): plain values for your take next to the range across the phrase's native voices.
// Measurements, not verdicts: nothing here says whether you are inside the range, and the values are a distinct type
// from `MeasureState` so views that must show no measure state can be checked for it.

import Foundation

/// A final pitch direction (§11): rise at or above +5 st/s, fall at or below −5 st/s, else level. Moved down from
/// `AMScoring` (spec 28) so the shipped description and scoring read the same rule and the same thresholds.
public enum PitchDirection: String, Sendable, Hashable, Codable, CaseIterable {
    case rise, fall, level

    public init(slope: Double, thresholds: Thresholds.FinalDirection = Thresholds.current.finalDirection) {
        self = slope >= thresholds.riseSemitonesPerSecond ? .rise
            : slope <= thresholds.fallSemitonesPerSecond ? .fall : .level
    }
}

/// Why a described value is missing (shown as "—" with a tooltip).
public enum DescribedMissingReason: String, Sendable, Hashable, Codable, CaseIterable {
    /// No voiced frame where the measure reads.
    case noVoicedFrames
    /// Too few syllables (nPVI needs 3).
    case tooFewSyllables
    /// Too few voiced frames in the final window.
    case tooFewFinalFrames
    /// No word of the phrase was heard.
    case noWords
}

/// One measured value, or why it is missing.
public enum DescribedValue: Sendable, Hashable, Codable {
    case value(Double)
    case missing(DescribedMissingReason)

    enum ValueCodingKeys: String, CodingKey { case _0 = "value" }
    enum MissingCodingKeys: String, CodingKey { case _0 = "reason" }

    public var value: Double? {
        if case .value(let value) = self { return value }
        return nil
    }
}

/// One speaker's measures, all from the same function.
public struct SpeakerDescription: Sendable, Hashable, Codable {
    /// Seconds from the first heard phrase word's start to the last one's end.
    public let lengthSeconds: DescribedValue
    public let syllablesPerSecond: DescribedValue
    /// P90 − P10 in st over the voiced frames on the selected model's comparable frames.
    public let pitchRangeSemitones: DescribedValue
    /// nPVI over the syllable durations in time order.
    public let rhythmNPVI: DescribedValue
    /// Least-squares slope of the final window, st/s.
    public let finalSlope: DescribedValue
    /// The direction `finalSlope` gives under `Thresholds.finalDirection`; nil when the slope is missing.
    public let endingDirection: PitchDirection?

    public init(
        lengthSeconds: DescribedValue, syllablesPerSecond: DescribedValue, pitchRangeSemitones: DescribedValue,
        rhythmNPVI: DescribedValue, finalSlope: DescribedValue, endingDirection: PitchDirection?
    ) {
        self.lengthSeconds = lengthSeconds
        self.syllablesPerSecond = syllablesPerSecond
        self.pitchRangeSemitones = pitchRangeSemitones
        self.rhythmNPVI = rhythmNPVI
        self.finalSlope = finalSlope
        self.endingDirection = endingDirection
    }
}

/// The min–max of one measure across the native voices; nil bounds when no voice has the value.
public struct DescribedRange: Sendable, Hashable, Codable {
    public let min: Double?
    public let max: Double?
    /// Voices that had a value.
    public let count: Int

    public init(_ values: [Double]) {
        min = values.min()
        max = values.max()
        count = values.count
    }
}

/// The native side: the range of each measure across the phrase's native voices (one voice for an imported clip).
public struct NativeDescription: Sendable, Hashable, Codable {
    /// Native voices measured.
    public let voices: Int
    public let lengthSeconds: DescribedRange
    public let syllablesPerSecond: DescribedRange
    public let pitchRangeSemitones: DescribedRange
    public let rhythmNPVI: DescribedRange
    public let finalSlope: DescribedRange
    /// How many voices end rising, falling and level ("5 falling, 3 rising").
    public let endingDirections: [PitchDirection: Int]
    /// The raw final slopes the directions were read from, one per voice that had one.
    public let finalSlopes: [Double]

    public init(_ speakers: [SpeakerDescription]) {
        voices = speakers.count
        lengthSeconds = DescribedRange(speakers.compactMap(\.lengthSeconds.value))
        syllablesPerSecond = DescribedRange(speakers.compactMap(\.syllablesPerSecond.value))
        pitchRangeSemitones = DescribedRange(speakers.compactMap(\.pitchRangeSemitones.value))
        rhythmNPVI = DescribedRange(speakers.compactMap(\.rhythmNPVI.value))
        finalSlope = DescribedRange(speakers.compactMap(\.finalSlope.value))
        var counts: [PitchDirection: Int] = [:]
        for direction in speakers.compactMap(\.endingDirection) { counts[direction, default: 0] += 1 }
        endingDirections = counts
        finalSlopes = speakers.compactMap(\.finalSlope.value)
    }
}

extension PitchDirection: CodingKeyRepresentable {}

/// Spec 28 §4a: you, and the native range.
public struct DescribedMeasures: Sendable, Hashable, Codable {
    public let you: SpeakerDescription
    public let native: NativeDescription

    public init(you: SpeakerDescription, native: NativeDescription) {
        self.you = you
        self.native = native
    }
}
