// Every tunable number in Accent Mirror, in one value. `docs/thresholds.md` is the human mirror: each row names a
// key below (dotted path) and `ThresholdsMirrorTests` fails if a row and the value here disagree.
//
// Values are plan v2 rev 4.1 initial values. They are tuned only on the tuning split (plan §2), never on held-out
// clips, and never lowered quietly: a change bumps `Versions.thresholdsVersion` and says why in its PR.
// Units are in the property names; shares are fractions (0.8 = 80%).

import Foundation

public struct Thresholds: Sendable, Hashable, Codable {
    public static let current = Thresholds()

    public var pitch = Pitch()
    public var capture = Capture()
    public var voicing = Voicing()
    public var alignment = Alignment()
    public var confidence = ConfidenceLevels()
    public var prominence = Prominence()
    public var applicability = Applicability()
    public var finalDirection = FinalDirection()
    public var diffs = Diffs()
    public var measures = Measures()
    public var band = Band()
    public var decision = Decision()
    public var agreement = Agreement()
    public var performance = Performance()

    public init() {}

    /// Pitch tracking, spec 04 (v1 thresholds, plan §11 "as before").
    public struct Pitch: Sendable, Hashable, Codable {
        public var windowMs = 40.0
        public var hopMs = 10.0
        public var minF0Hz = 60.0
        public var maxF0Hz = 500.0
        public var voicingProbability = 0.5
        public var minVoicedRunMs = 30.0
        public var medianFilterFrames = 5.0
        public var lineBreakMs = 250.0
        public var axisInitialSemitones = 12.0
        public var axisStepSemitones = 6.0
        public var axisMaxSemitones = 24.0
        public init() {}
    }

    /// Onset, endpoint and take quality, spec 05 (plan §10; take-quality rows from v1).
    public struct Capture: Sendable, Hashable, Codable {
        public var onsetMinimumDBFS = -50.0
        public var onsetAboveFloorDB = 10.0
        public var onsetFrames = 3.0
        public var onsetVoicedWithinMs = 100.0
        public var offsetAboveFloorDB = 6.0
        public var provisionalFloorDBFS = -60.0
        public var settleNonSpeechMs = 300.0
        public var settleStationaryAfterS = 2.0
        public var stationarySpreadDB = 6.0
        public var floorPercentile = 10.0
        public var floorWindowS = 2.0
        public var floorClampLowDBFS = -70.0
        public var floorClampHighDBFS = -35.0
        public var retractionAboveFloorDB = 10.0
        public var preRollMs = 200.0
        public var ringBufferMs = 500.0
        public var endOfTakeS = 1.2
        public var recordingCapS = 20.0
        public var noSpeechS = 0.15
        public var tooShortS = 0.5
        public var tooQuietDBFS = -40.0
        public var clippedShare = 0.005
        public var clipRunSamples = 3.0
        public var clipLevel = 0.999
        public var importLimitS = 15.0
        public init() {}
    }

    /// `ACFVoicing`, spec 05 (plan §10).
    public struct Voicing: Sendable, Hashable, Codable {
        public var windowMs = 40.0
        public var hopMs = 10.0
        public var minLagMs = 2.0
        public var maxLagMs = 16.7
        public var minPeak = 0.45
        public var aboveFloorDB = 3.0
        public init() {}
    }

    /// Word alignment, specs 06 and 07 (plan §4.3; CTO decision 4).
    public struct Alignment: Sendable, Hashable, Codable {
        public var asrPaddingMs = 80.0
        public var matchScore = 2.0
        public var mismatchScore = -1.0
        public var gapScore = -1.0
        public init() {}
    }

    /// Confidence levels (first v2 §5, "as before").
    public struct ConfidenceLevels: Sendable, Hashable, Codable {
        /// Word c_w and syllable min(c_w, s_w).
        public var levelHigh = 0.7
        public var levelMedium = 0.45
        /// Share of comparable syllables at medium or above.
        public var timingGood = 0.8
        public var timingRough = 0.5
        /// Contrast and weak length: share of S∪U syllables at medium or above.
        public var contrastHigh = 0.9
        public var contrastMedium = 0.7
        /// Pitch measures: voiced coverage of comparable frames.
        public var pitchHigh = 0.7
        public var pitchMedium = 0.5
        /// Final direction: voiced frames in the window.
        public var finalDirectionHighFrames = 15.0
        public var finalDirectionMediumFrames = 10.0
        public init() {}
    }

    /// Prominence and observed stress, spec 08 (plan §2).
    public struct Prominence: Sendable, Hashable, Codable {
        public var durationWeight = 0.4
        public var energyWeight = 0.3
        public var pitchWeight = 0.3
        public var durationFloorLn = 0.05
        public var energyFloorDB = 1.0
        public var pitchFloorSemitones = 1.0
        public var energyMinimumDBFS = -60.0
        public var pitchMinVoicedFrames = 3.0
        public var lengtheningLambda = 1.6
        public var exposurePauseMs = 150.0
        public var tauMedium = MarginBuckets(syllables2to4: 0.25, syllables5to8: 0.25, syllables9Plus: 0.25)
        public var tauHigh = MarginBuckets(syllables2to4: 0.5, syllables5to8: 0.5, syllables9Plus: 0.5)
        public var secondaryStressShare = 0.75
        public init() {}
    }

    /// A margin per take-length bucket n ∈ {2–4, 5–8, ≥ 9} syllables (plan §2).
    public struct MarginBuckets: Sendable, Hashable, Codable {
        public var syllables2to4: Double
        public var syllables5to8: Double
        public var syllables9Plus: Double
        public init(syllables2to4: Double, syllables5to8: Double, syllables9Plus: Double) {
            self.syllables2to4 = syllables2to4
            self.syllables5to8 = syllables5to8
            self.syllables9Plus = syllables9Plus
        }

        /// The margin for a take of `syllableCount` syllables (fewer than 2 uses the first bucket).
        public func margin(forSyllableCount syllableCount: Int) -> Double {
            switch syllableCount {
            case ...4: syllables2to4
            case 5...8: syllables5to8
            default: syllables9Plus
            }
        }
    }

    /// Applicability, decided from the phrase and the model only (plan §1.1).
    public struct Applicability: Sendable, Hashable, Codable {
        public var placementMinSyllables = 2.0
        public var contrastMinStressed = 1.0
        public var contrastMinUnstressed = 2.0
        public var rhythmMinSyllables = 3.0
        public var pitchMinModelVoicedFrames = 20.0
        public init() {}
    }

    /// Final direction, spec 10 (plan §11).
    public struct FinalDirection: Sendable, Hashable, Codable {
        public var windowMs = 200.0
        public var extendedWindowMs = 300.0
        public var minVoicedFrames = 10.0
        public var riseSemitonesPerSecond = 5.0
        public var fallSemitonesPerSecond = -5.0
        public init() {}
    }

    /// Diff triggers, spec 10 (v1 thresholds, "as before").
    public struct Diffs: Sendable, Hashable, Codable {
        public var contrastBelowModelRatio = 0.7
        public var contrastModelMinimum = 1.3
        public var tooMuchContrastAboveModelRatio = 2.0
        public var weakLengthPointsAboveModel = 15.0
        public var pitchRangeBelowModelRatio = 0.6
        public var pitchRangeNarrowerSemitones = 3.0
        public init() {}
    }

    /// Measures, spec 10.
    public struct Measures: Sendable, Hashable, Codable {
        public var shapeMatchMinOverlappingFrames = 20.0
        public init() {}
    }

    /// Native band, spec 09 (v1 thresholds).
    public struct Band: Sendable, Hashable, Codable {
        public var lowerPercentile = 10.0
        public var upperPercentile = 90.0
        public var singleTakeHalfWidthSemitones = 1.5
        public init() {}
    }

    /// Decision procedure and `close` (plan §1.2, §1.3).
    public struct Decision: Sendable, Hashable, Codable {
        public var minMatchShare = 0.8
        public var maxNonFillerInsertions = 2.0
        public var minComparableCoverage = 0.7
        public var closeMinShapeMatch = 0.7
        public var maxDiffRows = 3.0
        public init() {}
    }

    /// The agreement gate table (plan §6.7), with the §6.5 baseline rule and §6.6 bootstrap. Point values and bounds
    /// are shares; "points" are percentage points as shares (0.03 = 3 pp).
    public struct Agreement: Sendable, Hashable, Codable {
        public var positiveMinPairs = 150.0
        public var positiveHeldOutSpeakers = 12.0
        public var anyDiffPairsMax = 0.05
        public var anyDiffWorstSpeakerMax = 0.15
        public var anyDiffWorstPhraseMax = 0.30
        public var placementDiffPairsMax = 0.02
        public var placementDiffWorstSpeakerMax = 0.07
        public var inconclusivePairsMax = 0.10
        public var evaluationCoverageMin = 0.90
        public var contrastRatioLow = 0.7
        public var contrastRatioHigh = 1.43
        public var contrastRatioWithinShareMin = 0.90
        public var weakLengthMaxDeltaPoints = 15.0
        public var npviMaxDelta = 15.0
        public var pitchRangeRatioMin = 0.6
        public var pitchRangeRatioShareMin = 0.95
        public var bandCoverageMedianMin = 0.80
        public var finalDirectionAgreementMin = 0.90
        public var l2RecallMin = 0.80
        public var l2RecallWilsonLowerMin = 0.70
        public var l2FalsePositiveMax = 0.02
        public var l2FalsePositiveWorstSpeakerMax = 0.10
        public var whichSyllableAccuracyMin = 0.80
        public var syntheticControlDiffsMax = 0.02
        public var unintelligiblePlacementDiffsMax = 0.0
        public var endToEndRecallWithinPoints = 0.10
        public var endToEndFalsePositiveMax = 0.02
        public var smokeSetMaxSeconds = 60.0
        public var referenceAnomalyReviewShare = 0.20
        public var baselineMaxShortfallPoints = 0.03
        public var baselineBootstrapLowerPoints = -0.05
        public var baselineCeiling = 0.85
        public var baselineMinLiftCapPoints = 0.10
        public var baselineFalsePositiveMaxExcessPoints = 0.01
        public var bootstrapResamples = 2000.0
        public init() {}
    }

    /// Latency budgets (v1 performance budget).
    public struct Performance: Sendable, Hashable, Codable {
        public var endToEndBudgetS = 2.0
        public var nonASRStagesMs = 500.0
        public var asrWarmMs = 900.0
        public init() {}
    }
}
