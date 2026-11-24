// Spec 10 wiring for evaluation and the smoke goldens: two analyses (yours and a native model's) of the same phrase →
// the time map (spec 09, `PairScoring.warp` in AMPipeline) → `AMScoring`. Verdict-only since spec 28: the shipped
// analyzer reaches this through `VerdictScorer` only when evaluation passes one.

import AMAlignment
import AMCore
import AMPipeline
import AMPlacement
import AMProsody
import AMScoring
import AMWarp
import Foundation

/// Raised when an evaluation path that must be scored gets a `.notScored` result (spec 28): the harness would
/// otherwise quietly report zero flags.
public struct NotScoredInEvaluation: Error, Sendable, Hashable, CustomStringConvertible {
    public let context: String
    public init(_ context: String) { self.context = context }
    public var description: String { "evaluation got a .notScored result (\(context)): pass VerdictScorer()" }
}

extension PairScoring {
    /// Scores `you` against `model`, both analysed from `words` (the phrase, in order). `natives` adds native
    /// readers' observed stress to each word's A(w) (spec 08); empty by default. Spec 22's end-to-end check passes the
    /// synthetic reference's own observed primaries here.
    public static func score(
        words: [PlacementTake.Word], you: PlacementAnalysis, model: PlacementAnalysis, modelVoice: String,
        natives: [WordIndex: [NativeReading]] = [:], thresholds: Thresholds = .current
    ) throws -> Scoring {
        try Scorer.score(
            input(words: words, you: you, model: model, modelVoice: modelVoice, natives: natives, thresholds: thresholds),
            thresholds: thresholds)
    }

    /// What `score` scores: the words with A(w), both takes' L1 data and your take warped onto the model (spec 09).
    public static func input(
        words: [PlacementTake.Word], you: PlacementAnalysis, model: PlacementAnalysis, modelVoice: String,
        natives: [WordIndex: [NativeReading]] = [:], thresholds: Thresholds = .current
    ) throws -> ScoringInput {
        let warp = try warp(you: you.prosody, model: model.prosody, words: words, thresholds: thresholds)
        return input(
            words: words, you: you.prosody, model: model.prosody, modelVoice: modelVoice, natives: natives, warp: warp,
            thresholds: thresholds)
    }

    /// `input` on stored prosody with the warp already computed (the analyzer's path through `VerdictScorer`).
    public static func input(
        words: [PlacementTake.Word], you: TakeProsody, model: TakeProsody, modelVoice: String,
        natives: [WordIndex: [NativeReading]], warp: TimeWarp, thresholds: Thresholds = .current
    ) -> ScoringInput {
        let scoringWords = words.map { word -> ScoringWord in
            // A polysyllable with no A(w) is `expectedAmbiguous`; a monosyllable has nothing to decide but still
            // counts in S and U.
            let ambiguous = word.accepted == nil && word.pronunciation.syllables.count >= 2
            let expected = ExpectedWord(
                index: word.index, text: word.text, pronunciation: word.pronunciation, source: .override,
                expectedAmbiguous: ambiguous, isContent: true, isTarget: word.accepted != nil)
            return ScoringWord(
                index: word.index, syllableCount: expected.syllableCount, isTarget: expected.isTarget, isContent: true,
                expectedPattern: expected.expectedPattern,
                accepted: WordAcceptedSet(expected: expected, natives: natives[word.index] ?? []))
        }

        func take(_ analysis: TakeProsody) -> ScoringTake {
            ScoringTake(
                syllables: ComparableSyllable.all(in: analysis.segmentation, pitch: analysis.pitch, thresholds: thresholds.prominence),
                pitch: analysis.pitch.segments,
                words: Dictionary(
                    analysis.segmentation.words.filter { $0.kind == .present }.map { ($0.phraseWord, $0.range) },
                    uniquingKeysWith: { a, _ in a }))
        }

        return ScoringInput(
            words: scoringWords, modelVoice: modelVoice, model: take(model), you: take(you),
            alignment: you.alignment, alignmentSummary: alignmentSummary(words: words, you: you), warp: warp,
            hopSeconds: you.pitch.hopSeconds)
    }
}

/// The verdict scorer behind the pipeline's seam (spec 28): spec 10's scoring, `.on`. Evaluation passes it
/// explicitly; the shipped app never links it.
public struct VerdictScorer: PairScorer {
    public init() {}

    public var mode: ScoringMode { .on }

    public func score(_ input: PairScorerInput, thresholds: Thresholds) throws -> PairScore {
        let scoring = try scoring(input, thresholds: thresholds)
        guard case .verdict(let verdict) = scoring.decision else {
            // The shipped gate already ran decision steps 1–2 on the same summary; reaching this is a contract break.
            throw NotScoredInEvaluation("decision steps 1–2 fired after the take-problem gate passed")
        }
        return pairScore(scoring, verdict: verdict, input: input, thresholds: thresholds)
    }

    /// Beside a take problem, the measures spec 10 computes, as L2 logged them before spec 28.
    public func evaluationMeasures(_ input: PairScorerInput, thresholds: Thresholds) throws -> PairScore? {
        let scoring = try scoring(input, thresholds: thresholds)
        return PairScore(
            verdict: .notScored, measures: scoring.measures.states, applicability: scoring.applicability,
            stress: scoring.stress, modelValues: scoring.modelValues)
    }

    private func pairScore(_ scoring: Scoring, verdict: Verdict, input: PairScorerInput, thresholds: Thresholds)
        -> PairScore
    {
        let detector = PlacementRule(thresholds: thresholds)
        return PairScore(
            verdict: verdict, measures: scoring.measures.states, applicability: scoring.applicability,
            stress: scoring.stress, modelValues: scoring.modelValues,
            measuredYou: detector.measured(words: input.words, prosody: input.you),
            measuredModel: detector.measured(words: input.words, prosody: input.model))
    }

    /// Spec 10's scoring of the pair, with the natives' observed stress in A(w).
    public func scoring(_ input: PairScorerInput, thresholds: Thresholds) throws -> Scoring {
        let detector = PlacementRule(thresholds: thresholds)
        // Native readers' observed stress for A(w) (spec 08), from each native's stored prosody.
        var readings: [WordIndex: [NativeReading]] = [:]
        for native in input.natives {
            for result in detector.place(words: input.words, prosody: native.prosody).words {
                guard let observed = result.observed else { continue }
                readings[result.word, default: []].append(NativeReading(voice: native.voice, observed: observed))
            }
        }
        let scoringInput = PairScoring.input(
            words: input.words, you: input.you, model: input.model, modelVoice: input.modelVoice, natives: readings,
            warp: input.warp, thresholds: thresholds)
        return try Scorer.score(scoringInput, thresholds: thresholds)
    }
}

/// Observed stress on stored prosody, through `StressPlacementDetector.place` (AMPlacement).
struct PlacementRule {
    let thresholds: Thresholds

    func place(words: [PlacementTake.Word], prosody: TakeProsody) -> PlacementAnalysis {
        StressPlacementDetector.place(words: words, prosody: prosody, thresholds: thresholds)
    }

    /// Each decided word's observed stress at medium confidence or above (spec 08): a scored result's `.measured`
    /// syllable stress.
    func measured(words: [PlacementTake.Word], prosody: TakeProsody) -> [WordIndex: MeasuredWordStress] {
        Dictionary(
            place(words: words, prosody: prosody).words.compactMap { result in
                result.observed.flatMap {
                    $0.confidence >= .medium
                        ? (result.word, MeasuredWordStress(primary: $0.primary, secondary: $0.secondary)) : nil
                }
            }, uniquingKeysWith: { first, _ in first })
    }
}
