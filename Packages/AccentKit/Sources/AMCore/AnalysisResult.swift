// The analysed result (spec 01 Open question 1): v1's `AnalysisResult` with rev 4.1's replacements.
// `WordAlignment` replaces `WordSpan.isMissing`, `PartialTimeMap` replaces `WarpMap`, measures are `MeasureState`s
// plus the applicability table, `verdict` replaces the diff sentences, and per-word stress lines replace
// `stressMismatches`.

import Foundation

public struct AnalysisResult: Sendable, Hashable, Codable {
    public let phraseID: PhraseID
    public let takeID: TakeID
    public let recordedAt: Date
    /// The selected native take, on its own timeline.
    public let model: SpeakerAnalysis
    /// Your take, on your own timeline.
    public let you: SpeakerAnalysis
    /// Model phrase time, pauses trimmed: the one shared x domain for every model-timeline panel.
    public let modelAxis: TimeRange
    public let alignment: WordAlignment
    public let timeMap: PartialTimeMap
    /// Your pitch on model time; breaks at pauses over 250 ms and at time-map gaps.
    public let youPitchOnModel: [PitchSegment]
    public let nativeBand: [BandPoint]
    /// Semitone extent of the pitch chart: ±12…±24, never shrinking within a phrase.
    public let pitchAxis: ClosedRange<Double>
    public let timing: TimingLevel
    public let stress: [StressLine]
    public let measures: [MeasureKind: MeasureState<Double>]
    public let applicability: ApplicabilityTable
    public let verdict: Verdict
    public let identity: AnalysisIdentity
    /// Comparable syllables ÷ the model's syllables (`TimeWarp.comparableCoverage`, spec 28). Nil for takes saved
    /// before spec 28; omitted from JSON when nil.
    public let comparableCoverage: Double?
    /// Plain measures for you and the native range (spec 28 §4a): measurements, never a comparison. Nil for takes
    /// saved before spec 28; omitted from JSON when nil.
    public let describe: DescribedMeasures?

    public init(
        phraseID: PhraseID, takeID: TakeID, recordedAt: Date, model: SpeakerAnalysis, you: SpeakerAnalysis,
        modelAxis: TimeRange, alignment: WordAlignment, timeMap: PartialTimeMap, youPitchOnModel: [PitchSegment],
        nativeBand: [BandPoint], pitchAxis: ClosedRange<Double>, timing: TimingLevel, stress: [StressLine],
        measures: [MeasureKind: MeasureState<Double>], applicability: ApplicabilityTable, verdict: Verdict,
        identity: AnalysisIdentity, comparableCoverage: Double? = nil, describe: DescribedMeasures? = nil
    ) {
        self.phraseID = phraseID
        self.takeID = takeID
        self.recordedAt = recordedAt
        self.model = model
        self.you = you
        self.modelAxis = modelAxis
        self.alignment = alignment
        self.timeMap = timeMap
        self.youPitchOnModel = youPitchOnModel
        self.nativeBand = nativeBand
        self.pitchAxis = pitchAxis
        self.timing = timing
        self.stress = stress
        self.measures = measures
        self.applicability = applicability
        self.verdict = verdict
        self.identity = identity
        self.comparableCoverage = comparableCoverage
        self.describe = describe
    }
}

/// One speaker's take on their own timeline.
public struct SpeakerAnalysis: Sendable, Hashable, Codable {
    /// The words on this timeline: the phrase words for the model; the words heard (present, substituted, inserted)
    /// for you. Tap a word to play it.
    public let words: [WordSpan]
    public let syllables: [SyllableMeasure]
    /// 10 ms frames in semitones re the speaker's median, one segment per stretch between pauses over 250 ms.
    public let pitch: [PitchSegment]
    /// Nil when the take has no voiced frames (spec 04).
    public let medianF0Hz: Double?

    public init(words: [WordSpan], syllables: [SyllableMeasure], pitch: [PitchSegment], medianF0Hz: Double?) {
        self.words = words
        self.syllables = syllables
        self.pitch = pitch
        self.medianF0Hz = medianF0Hz
    }
}

public struct WordSpan: Sendable, Hashable, Codable {
    public let text: String
    public let range: TimeRange
    /// Indices into the same speaker's `syllables`.
    public let syllables: [Int]
    /// The context-resolved lexical pattern (spec 28 §4), one entry per syllable; nil when the word is
    /// `expectedAmbiguous`, has no pattern, or the take was saved before spec 28. It is the dictionary's pattern for
    /// this context, not what the speaker did: native acoustics follow it only 50–70% of the time (spike 27).
    public let expectedStress: [SyllableStress]?

    public init(text: String, range: TimeRange, syllables: [Int], expectedStress: [SyllableStress]? = nil) {
        self.text = text
        self.range = range
        self.syllables = syllables
        self.expectedStress = expectedStress
    }
}

public enum SyllableStress: String, Sendable, Hashable, Codable, CaseIterable {
    case primary, secondary, unstressed
}

public enum StressSource: String, Sendable, Hashable, Codable, CaseIterable {
    case dictionary, measured
}

public struct SyllableMeasure: Sendable, Hashable, Codable {
    public let text: String
    /// The word on this speaker's `words` list.
    public let wordIndex: Int
    public let indexInWord: Int
    public let range: TimeRange
    /// 0–1 share of trimmed phrase time.
    public let share: Double
    /// 0–1 within the take.
    public let prominence: Double
    public let stress: SyllableStress
    public let stressSource: StressSource

    public init(
        text: String, wordIndex: Int, indexInWord: Int, range: TimeRange, share: Double, prominence: Double,
        stress: SyllableStress, stressSource: StressSource
    ) {
        self.text = text
        self.wordIndex = wordIndex
        self.indexInWord = indexInWord
        self.range = range
        self.share = share
        self.prominence = prominence
        self.stress = stress
        self.stressSource = stressSource
    }
}

public struct PitchSegment: Sendable, Hashable, Codable {
    /// Seconds on the segment's timeline.
    public let start: Double
    public let frames: [PitchFrame]

    public init(start: Double, frames: [PitchFrame]) {
        self.start = start
        self.frames = frames
    }
}

public struct PitchFrame: Sendable, Hashable, Codable {
    public let semitones: Double
    /// False: bridged by interpolation.
    public let voiced: Bool

    public init(semitones: Double, voiced: Bool) {
        self.semitones = semitones
        self.voiced = voiced
    }
}

/// The native band at one model frame: P10 and P90 in st (±1.5 st around the model with one native take).
public struct BandPoint: Sendable, Hashable, Codable {
    public let time: Double
    public let lower: Double
    public let upper: Double

    public init(time: Double, lower: Double, upper: Double) {
        self.time = time
        self.lower = lower
        self.upper = upper
    }
}

/// One inspector stress line for a phrase word (§3.3).
public struct StressLine: Sendable, Hashable, Codable {
    public let word: WordIndex
    /// The expected (context-compatible) pattern, one entry per syllable; nil when the word is `expectedAmbiguous`.
    public let expectedPattern: [SyllableStress]?
    /// Your observed primary as a syllable index within the word; nil when not measured.
    public let observedPrimary: Int?
    /// Prominence margin in z units.
    public let margin: Double?
    public let confidence: Confidence?
    /// The accepted pattern you matched, if any.
    public let matchedAccepted: AcceptedPattern?
    /// The model voice's own observed primary is outside A(w) at high confidence: no diff for this word.
    public let referenceAnomaly: Bool

    public init(
        word: WordIndex, expectedPattern: [SyllableStress]?, observedPrimary: Int?, margin: Double?,
        confidence: Confidence?, matchedAccepted: AcceptedPattern?, referenceAnomaly: Bool
    ) {
        self.word = word
        self.expectedPattern = expectedPattern
        self.observedPrimary = observedPrimary
        self.margin = margin
        self.confidence = confidence
        self.matchedAccepted = matchedAccepted
        self.referenceAnomaly = referenceAnomaly
    }
}

/// A member of A(w): its primary syllable and where it came from.
public struct AcceptedPattern: Sendable, Hashable, Codable {
    public enum Source: Sendable, Hashable, Codable {
        case contextPronunciation
        case nativeReader(voice: String)
    }

    public let primary: Int
    public let source: Source

    public init(primary: Int, source: Source) {
        self.primary = primary
        self.source = source
    }
}
