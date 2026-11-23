// Scoring (spec 10): every measure as a `MeasureState`, suppression (§5), diff triggers (v1, rev 4.1 units), ranking,
// and the verdict through spec 01's decision procedure. Rows carry structured values only; copy is the app's.

import AMCore
import AMProsody
import AMWarp
import Foundation

/// A triggered diff before ranking, with its relative gap (ties within a kind go to the larger gap).
public struct TriggeredDiff: Sendable, Hashable {
    public let row: DiffRow
    /// How far past its trigger the measure is, relative to the model: 0 at the trigger, larger is further.
    public let relativeGap: Double
}

/// One pair's scoring.
public struct Scoring: Sendable {
    public let applicability: ApplicabilityTable
    public let measures: MeasureAssessments
    /// The model's own value of each measure it has (C, W points, P90−P10 st, final slope st/s, nPVI).
    public let modelValues: [MeasureKind: Double]
    /// Every decided placement word, mismatching words flagged.
    public let placements: [WordPlacement]
    /// One inspector line per phrase word of 2 or more syllables.
    public let stress: [StressLine]
    /// Triggered, unsuppressed diffs, ranked; no rough-timing row (the decision procedure adds it).
    public let diffs: [DiffRow]
    /// Your pitch on model time (spec 09).
    public let youPitchOnModel: [PitchSegment]
    public let timing: TimingLevel
    /// Voiced coverage of comparable frames; nil with none.
    public let pitchCoverage: Double?
    public let decision: Decision
}

public enum Scorer {
    /// Scores one pair.
    public static func score(_ input: ScoringInput, thresholds: Thresholds = .current) throws -> Scoring {
        let pitch = PitchMeasures(input, thresholds: thresholds)
        let table = applicability(
            ApplicabilityInput(
                words: input.words.map(\.facts),
                expectedStressedSyllables: input.words.reduce(0) { $0 + ($1.accepted?.contextStressed.count ?? 0) },
                expectedUnstressedSyllables: input.words.reduce(0) {
                    $0 + ($1.accepted.map { $0.syllableCount - $0.contextStressed.count } ?? 0)
                },
                modelVoicedFrames: input.model.voicedFrameCount,
                modelFinalWindowVoicedFrames: pitch.modelFinal.voicedFrames,
                modelFinalSlopeSemitonesPerSecond: pitch.modelFinal.slope),
            thresholds: thresholds)
        let stress = StressMeasures(input, applicability: table, thresholds: thresholds)

        var states: [MeasureKind: MeasureState<Double>] = [:]
        func set(_ kind: MeasureKind, _ state: MeasureState<Double>?) {
            if table[kind].isApplicable { states[kind] = state ?? .unavailable(.lowConfidence) }
        }
        set(.stressPlacement, stress.placement)
        set(.contrast, stress.contrast)
        set(.tooMuchContrast, stress.contrast)
        set(.weakLength, stress.weakLength)
        set(.rhythm, stress.rhythm)
        set(.pitchRange, pitch.pitchRange)
        set(.shapeMatch, pitch.shapeMatch)
        set(.finalDirection, pitch.finalDirection)
        let measures = try MeasureAssessments(applicability: table, states: states)

        var modelValues: [MeasureKind: Double] = [:]
        modelValues[.contrast] = stress.modelContrast
        modelValues[.tooMuchContrast] = stress.modelContrast
        modelValues[.weakLength] = stress.modelWeakLength
        modelValues[.rhythm] = stress.modelRhythm
        modelValues[.pitchRange] = pitch.modelPitchRange
        modelValues[.finalDirection] = pitch.modelFinal.slope

        let diffs = rank(triggers(
            input, measures: measures, modelValues: modelValues, placements: stress.placements, thresholds: thresholds))
        let decision = decide(
            DecisionInput(
                takeProblems: input.takeProblems, alignment: input.alignmentSummary, timing: input.warp.timing,
                comparableCoverage: input.warp.comparableCoverage, measures: measures, triggeredDiffs: diffs),
            thresholds: thresholds)

        return Scoring(
            applicability: table, measures: measures, modelValues: modelValues, placements: stress.placements,
            stress: stress.stress, diffs: diffs,
            youPitchOnModel: input.warp.pitchOnModel(input.you.pitch, hopSeconds: input.hopSeconds),
            timing: input.warp.timing, pitchCoverage: pitch.coverage, decision: reportContrastGroup(decision))
    }

    /// Every triggered, unsuppressed diff, unranked.
    static func triggers(
        _ input: ScoringInput, measures: MeasureAssessments, modelValues: [MeasureKind: Double],
        placements: [WordPlacement], thresholds: Thresholds
    ) -> [TriggeredDiff] {
        let limits = thresholds.diffs
        var out: [TriggeredDiff] = []
        // Poor timing: no stress, contrast or weak-length diffs (§5).
        let stressDiffsAllowed = input.warp.timing != .poor
        // Every evaluated measure here is at medium or above: a low measure is `.unavailable(.lowConfidence)`.
        func evaluated(_ kind: MeasureKind) -> Double? { measures[kind].value }

        if stressDiffsAllowed, let word = StressMeasures.reportedPlacement(placements) {
            let modelSyllable = { (index: Int) in
                input.model.syllables.firstIndex { $0.word == word.word && $0.indexInWord == index }
            }
            let accepted = word.nearest?.primary
            let likeVoice: String? = if case .nativeReader(let voice) = word.nearest?.source { voice } else { nil }
            out.append(TriggeredDiff(
                row: DiffRow(
                    kind: .placement, word: word.word,
                    syllables: [accepted.flatMap(modelSyllable), modelSyllable(word.yours.primary)].compactMap { $0 },
                    acceptedSyllable: accepted, heardSyllable: word.yours.primary, likeVoice: likeVoice,
                    values: DiffValues(you: word.yours.margin, model: word.model?.margin)),
                relativeGap: word.yours.margin))
        }

        if stressDiffsAllowed, let yours = evaluated(.contrast), let model = modelValues[.contrast], model > 0 {
            if yours < limits.contrastBelowModelRatio * model, model >= limits.contrastModelMinimum {
                out.append(TriggeredDiff(
                    row: DiffRow(kind: .contrast, values: DiffValues(you: yours, model: model)),
                    relativeGap: 1 - yours / model))
            }
            if yours > limits.tooMuchContrastAboveModelRatio * model {
                out.append(TriggeredDiff(
                    row: DiffRow(kind: .tooMuchContrast, values: DiffValues(you: yours, model: model)),
                    relativeGap: yours / model - limits.tooMuchContrastAboveModelRatio))
            }
        }

        if stressDiffsAllowed, limits.weakLengthEnabled, let yours = evaluated(.weakLength),
            let model = modelValues[.weakLength], yours - model >= limits.weakLengthPointsAboveModel
        {
            out.append(TriggeredDiff(
                row: DiffRow(kind: .weakLength, values: DiffValues(you: yours, model: model)),
                relativeGap: model > 0 ? (yours - model) / model : yours - model))
        }

        if limits.pitchRangeEnabled, let yours = evaluated(.pitchRange), let model = modelValues[.pitchRange], model > 0,
            yours < limits.pitchRangeBelowModelRatio * model, model - yours >= limits.pitchRangeNarrowerSemitones
        {
            out.append(TriggeredDiff(
                row: DiffRow(kind: .pitchRange, values: DiffValues(you: yours, model: model)),
                relativeGap: 1 - yours / model))
        }

        if limits.finalDirectionEnabled, let yours = evaluated(.finalDirection),
            let model = modelValues[.finalDirection]
        {
            let you = PitchDirection(slope: yours, thresholds: thresholds.finalDirection)
            let them = PitchDirection(slope: model, thresholds: thresholds.finalDirection)
            if you != .level, them != .level, you != them {
                out.append(TriggeredDiff(
                    row: DiffRow(
                        kind: .finalDirection, word: input.words.last?.index,
                        values: DiffValues(you: yours, model: model)),
                    relativeGap: abs(yours - model) / max(abs(model), 1e-9)))
            }
        }
        return out
    }

    /// Ranks diffs: rough timing (added by the decision procedure), placement, contrast, weak length, pitch range,
    /// final direction, too much contrast; ties to the larger relative gap. The procedure caps the list at 3.
    public static func rank(_ diffs: [TriggeredDiff]) -> [DiffRow] {
        diffs.enumerated().sorted { a, b in
            if a.element.row.kind != b.element.row.kind { return a.element.row.kind < b.element.row.kind }
            if a.element.relativeGap != b.element.relativeGap { return a.element.relativeGap > b.element.relativeGap }
            return a.offset < b.offset
        }.map(\.element.row)
    }

    /// Contrast, too much contrast and weak length share one S∪U evidence, so they are unavailable together. The
    /// group reports as `.contrast` in `partial` and `requiredMeasureUnavailable` (spec 10's goldens).
    static func reportContrastGroup(_ decision: Decision) -> Decision {
        func collapse(_ kinds: [MeasureKind]) -> [MeasureKind] {
            kinds.contains(.contrast) ? kinds.filter { $0 != .tooMuchContrast && $0 != .weakLength } : kinds
        }
        switch decision {
        case .verdict(.feedback(let rows, let partial)):
            return .verdict(.feedback(rows: rows, partial: collapse(partial)))
        case .verdict(.inconclusive(let reasons)):
            return .verdict(.inconclusive(reasons.map {
                if case .requiredMeasureUnavailable(let kinds) = $0 { .requiredMeasureUnavailable(collapse(kinds)) } else { $0 }
            }))
        default:
            return decision
        }
    }
}
