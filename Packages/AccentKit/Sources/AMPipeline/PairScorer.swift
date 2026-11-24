// The scoring seam (spec 28 §2): the analyzer runs the take-problem gate itself, then hands the pair to a
// `PairScorer`. The shipped scorer is `NoOpScorer` (`.off`: never judges). `AMVerdicts.VerdictScorer` (`.on`) runs
// spec 10's scoring and lives outside the shipped graph; evaluation passes it explicitly.

import AMAlignment
import AMCore
import AMProsody
import AMWarp
import Foundation

/// A native reader of the phrase, by voice, with its stored prosody (for A(w) on the verdict side).
public struct NativeProsody: Sendable {
    public let voice: String
    public let prosody: TakeProsody

    public init(voice: String, prosody: TakeProsody) {
        self.voice = voice
        self.prosody = prosody
    }
}

/// What a scorer reads: the phrase words, both takes' L1 prosody, the phrase's natives and the time map.
public struct PairScorerInput: Sendable {
    /// Every transcript word, in order, with A(w) seeds.
    public let words: [PlacementTake.Word]
    public let you: TakeProsody
    /// The selected native voice.
    public let model: TakeProsody
    public let modelVoice: String
    /// Every native reader of the phrase, the selected one included.
    public let natives: [NativeProsody]
    /// Your take on the model's timeline (spec 09).
    public let warp: TimeWarp
    /// What the take-problem gate read.
    public let alignmentSummary: AlignmentSummary

    public init(
        words: [PlacementTake.Word], you: TakeProsody, model: TakeProsody, modelVoice: String, natives: [NativeProsody],
        warp: TimeWarp, alignmentSummary: AlignmentSummary
    ) {
        self.words = words
        self.you = you
        self.model = model
        self.modelVoice = modelVoice
        self.natives = natives
        self.warp = warp
        self.alignmentSummary = alignmentSummary
    }
}

/// A word's stress as the verdict side measured it (observed primary and secondary at medium confidence or above),
/// for the `.measured` syllable stress of a scored result. Empty when scoring is off.
public struct MeasuredWordStress: Sendable, Hashable {
    public let primary: Int
    public let secondary: Int?

    public init(primary: Int, secondary: Int?) {
        self.primary = primary
        self.secondary = secondary
    }
}

/// What a scorer returns once the gate has passed.
public struct PairScore: Sendable {
    public let verdict: Verdict
    public let measures: [MeasureKind: MeasureState<Double>]
    public let applicability: ApplicabilityTable
    public let stress: [StressLine]
    /// The model's own value of each measure it has (spec 10), for evaluation.
    public let modelValues: [MeasureKind: Double]
    /// Measured stress per phrase word, for each speaker. Empty when scoring is off.
    public let measuredYou: [WordIndex: MeasuredWordStress]
    public let measuredModel: [WordIndex: MeasuredWordStress]

    public init(
        verdict: Verdict, measures: [MeasureKind: MeasureState<Double>], applicability: ApplicabilityTable,
        stress: [StressLine], modelValues: [MeasureKind: Double] = [:],
        measuredYou: [WordIndex: MeasuredWordStress] = [:], measuredModel: [WordIndex: MeasuredWordStress] = [:]
    ) {
        self.verdict = verdict
        self.measures = measures
        self.applicability = applicability
        self.stress = stress
        self.modelValues = modelValues
        self.measuredYou = measuredYou
        self.measuredModel = measuredModel
    }

    /// Scoring off: `.notScored`, no measures, no applicability, no stress lines.
    public static let notScored = PairScore(verdict: .notScored, measures: [:], applicability: .empty, stress: [])
}

/// Scores a pair once the take-problem gate has passed.
public protocol PairScorer: Sendable {
    /// Written into `AnalysisIdentity.scoringMode` (and so the L2 key).
    var mode: ScoringMode { get }
    func score(_ input: PairScorerInput, thresholds: Thresholds) throws -> PairScore
    /// Evaluation only: the measures to log in L2 beside a take problem (the outcome stays `.takeProblem`, the verdict
    /// is never used). The agreement harness's tolerance rows read them as they did before spec 28. Nil by default.
    func evaluationMeasures(_ input: PairScorerInput, thresholds: Thresholds) throws -> PairScore?
}

extension PairScorer {
    public func evaluationMeasures(_ input: PairScorerInput, thresholds: Thresholds) throws -> PairScore? { nil }
}

/// The shipped scorer: never judges. It does not call `decide()`.
public struct NoOpScorer: PairScorer {
    public init() {}
    public var mode: ScoringMode { .off }
    public func score(_ input: PairScorerInput, thresholds: Thresholds) throws -> PairScore { .notScored }
}
