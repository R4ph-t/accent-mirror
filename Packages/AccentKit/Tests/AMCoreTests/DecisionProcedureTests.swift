import Foundation
import Testing
import AMCore

/// Phrases and measure states shared by the applicability, decision and golden tests.
enum Scenario {
    /// "record": one target word, two syllables (re-CORD or REC-ord), so |S| = 1 and |U| = 1. Model falls at the end.
    static let record = ApplicabilityInput(
        words: [PhraseWordFacts(syllableCount: 2, isTarget: true, isContentWord: true)],
        expectedStressedSyllables: 1, expectedUnstressedSyllables: 1,
        modelVoicedFrames: 45, modelFinalWindowVoicedFrames: 16, modelFinalSlopeSemitonesPerSecond: -8)

    /// "I love photography.": photography is the target; |S| = 2 (love, TOG), |U| = 4.
    static let photography = ApplicabilityInput(
        words: [
            PhraseWordFacts(syllableCount: 1, isTarget: false, isContentWord: false),
            PhraseWordFacts(syllableCount: 1, isTarget: false, isContentWord: true),
            PhraseWordFacts(syllableCount: 4, isTarget: true, isContentWord: true),
        ],
        expectedStressedSyllables: 2, expectedUnstressedSyllables: 4,
        modelVoicedFrames: 90, modelFinalWindowVoicedFrames: 18, modelFinalSlopeSemitonesPerSecond: -6)

    /// "Call me.": two monosyllables, so neither stress measure applies.
    static let callMe = ApplicabilityInput(
        words: [
            PhraseWordFacts(syllableCount: 1, isTarget: false, isContentWord: true),
            PhraseWordFacts(syllableCount: 1, isTarget: false, isContentWord: false),
        ],
        expectedStressedSyllables: 1, expectedUnstressedSyllables: 1,
        modelVoicedFrames: 30, modelFinalWindowVoicedFrames: 12, modelFinalSlopeSemitonesPerSecond: 7)

    /// "record" with every applicable measure good enough for `close`, shape match `shape`.
    static func recordMeasures(
        placement: MeasureState<Double> = .evaluated(1.72, .high), shape: Double = 0.82
    ) throws -> MeasureAssessments {
        try MeasureAssessments(
            applicability: applicability(record),
            states: [
                .stressPlacement: placement,
                .pitchRange: .evaluated(9.5, .high),
                .shapeMatch: .evaluated(shape, .high),
                .finalDirection: .evaluated(-8, .high),
            ])
    }

    /// "photography" with every measure applicable; each state can be set on its own.
    static func photographyMeasures(
        contrast: MeasureState<Double> = .evaluated(4.19, .high),
        tooMuchContrast: MeasureState<Double> = .evaluated(4.19, .high),
        placement: MeasureState<Double> = .evaluated(1.72, .high),
        pitchRange: MeasureState<Double> = .evaluated(11, .high)
    ) throws -> MeasureAssessments {
        try MeasureAssessments(
            applicability: applicability(photography),
            states: [
                .stressPlacement: placement,
                .contrast: contrast,
                .tooMuchContrast: tooMuchContrast,
                .weakLength: .evaluated(50, .high),
                .rhythm: .evaluated(48, .high),
                .pitchRange: pitchRange,
                .shapeMatch: .evaluated(0.85, .high),
                .finalDirection: .evaluated(-6, .high),
            ])
    }

    static let placementRow = DiffRow(
        kind: .placement, word: WordIndex(0), syllables: [0], acceptedSyllable: 0, heardSyllable: 1,
        values: DiffValues(you: 1.14, model: 1.72))

    static func input(
        problems: [TakeProblem] = [], alignment: AlignmentSummary = AlignmentSummary(matchShare: 1),
        timing: TimingLevel = .good, coverage: Double = 1, measures: MeasureAssessments, diffs: [DiffRow] = []
    ) -> DecisionInput {
        DecisionInput(
            takeProblems: problems, alignment: alignment, timing: timing, comparableCoverage: coverage,
            measures: measures, triggeredDiffs: diffs)
    }
}

@Suite("Applicability (§1.1)") struct ApplicabilityTests {
    @Test("one word, two syllables: placement only") func record() {
        let table = applicability(Scenario.record)
        #expect(table[.stressPlacement] == .applicable(.required))
        #expect(table[.contrast] == .notApplicable(.tooFewExpectedUnstressed))
        #expect(table[.tooMuchContrast] == .notApplicable(.tooFewExpectedUnstressed))
        #expect(table[.weakLength] == .notApplicable(.tooFewExpectedUnstressed))
        #expect(table[.rhythm] == .notApplicable(.tooFewSyllablesInPhrase))
        #expect(table[.pitchRange] == .applicable(.optional))
        #expect(table[.shapeMatch] == .applicable(.optional))
        #expect(table[.finalDirection] == .applicable(.optional))
    }

    @Test("a longer phrase: contrast group required, nPVI inspector only") func photography() {
        let table = applicability(Scenario.photography)
        #expect(table[.stressPlacement] == .applicable(.required))
        for kind: MeasureKind in [.contrast, .tooMuchContrast, .weakLength] {
            #expect(table[kind] == .applicable(.required))
        }
        #expect(table[.rhythm] == .applicable(.inspectorOnly))
    }

    @Test("monosyllables only: no placement") func monosyllables() {
        #expect(applicability(Scenario.callMe)[.stressPlacement] == .notApplicable(.noEligibleWord))
    }

    @Test("an expectedAmbiguous word is never eligible for placement") func ambiguous() {
        let input = ApplicabilityInput(
            words: [PhraseWordFacts(syllableCount: 2, isTarget: true, isContentWord: true, isExpectedAmbiguous: true)],
            expectedStressedSyllables: 0, expectedUnstressedSyllables: 0, modelVoicedFrames: 40,
            modelFinalWindowVoicedFrames: 12, modelFinalSlopeSemitonesPerSecond: -8)
        #expect(applicability(input)[.stressPlacement] == .notApplicable(.noEligibleWord))
    }

    @Test("a two-syllable function word isn't eligible either") func functionWord() {
        let input = ApplicabilityInput(
            words: [PhraseWordFacts(syllableCount: 2, isTarget: false, isContentWord: false)],
            expectedStressedSyllables: 1, expectedUnstressedSyllables: 1, modelVoicedFrames: 40,
            modelFinalWindowVoicedFrames: 12, modelFinalSlopeSemitonesPerSecond: -8)
        #expect(applicability(input)[.stressPlacement] == .notApplicable(.noEligibleWord))
    }

    @Test("pitch measures need 20 model voiced frames", arguments: [(19, false), (20, true)])
    func pitchFrames(frames: Int, applicable: Bool) {
        let input = ApplicabilityInput(
            words: Scenario.record.words, expectedStressedSyllables: 1, expectedUnstressedSyllables: 1,
            modelVoicedFrames: frames, modelFinalWindowVoicedFrames: 12, modelFinalSlopeSemitonesPerSecond: -8)
        let table = applicability(input)
        #expect(table[.pitchRange].isApplicable == applicable)
        #expect(table[.shapeMatch].isApplicable == applicable)
        if !applicable { #expect(table[.pitchRange] == .notApplicable(.modelTooFewVoicedFrames)) }
    }

    @Test(
        "final direction needs 10 voiced frames and a non-level model slope",
        arguments: [(9, -8.0, false), (10, -8.0, true), (10, -5.0, true), (10, 5.0, true), (12, 4.9, false),
                    (12, -4.9, false)] as [(Int, Double, Bool)])
    func finalDirection(frames: Int, slope: Double, applicable: Bool) {
        let input = ApplicabilityInput(
            words: Scenario.record.words, expectedStressedSyllables: 1, expectedUnstressedSyllables: 1,
            modelVoicedFrames: 40, modelFinalWindowVoicedFrames: frames, modelFinalSlopeSemitonesPerSecond: slope)
        let expected: MeasureApplicability = applicable ? .applicable(.optional) : .notApplicable(.modelHasNoFinalVoicing)
        #expect(applicability(input)[.finalDirection] == expected)
    }

    @Test("contrast needs |S| ≥ 1 as well as |U| ≥ 2") func contrastNeedsStressed() {
        let input = ApplicabilityInput(
            words: Scenario.photography.words, expectedStressedSyllables: 0, expectedUnstressedSyllables: 4,
            modelVoicedFrames: 40, modelFinalWindowVoicedFrames: 12, modelFinalSlopeSemitonesPerSecond: -8)
        #expect(applicability(input)[.contrast] == .notApplicable(.noEligibleWord))
    }
}

@Suite("Measure assessments") struct MeasureAssessmentsTests {
    @Test("an applicable measure needs a state") func missingState() {
        #expect(throws: MeasureAssessments.Invalid.missingState(.stressPlacement)) {
            try MeasureAssessments(applicability: applicability(Scenario.record), states: [:])
        }
    }

    @Test("a state can't contradict applicability") func contradiction() {
        #expect(throws: MeasureAssessments.Invalid.contradictsApplicability(.contrast)) {
            try MeasureAssessments(
                applicability: applicability(Scenario.record),
                states: [
                    .stressPlacement: .evaluated(1, .high), .contrast: .evaluated(2, .high),
                    .pitchRange: .evaluated(9, .high), .shapeMatch: .evaluated(0.8, .high),
                    .finalDirection: .evaluated(-8, .high),
                ])
        }
    }
}

@Suite("Decision procedure (§1.2)") struct DecisionProcedureTests {
    // MARK: §1.3 examples

    @Test("§1.3 example 1: \"record\", good timing, shape 0.82 → close") func example1() throws {
        #expect(decide(Scenario.input(measures: try Scenario.recordMeasures())) == .verdict(.close))
    }

    @Test("§1.3 example 2: shape 0.5 → noClearDifference(pitchShapeBelowClose(0.5))") func example2() throws {
        let decision = decide(Scenario.input(measures: try Scenario.recordMeasures(shape: 0.5)))
        #expect(decision == .verdict(.noClearDifference([.pitchShapeBelowClose(0.5)])))
    }

    @Test("§1.3 example 3: \"record\" substituted → inconclusive(targetWordsMissing)") func example3() throws {
        let alignment = AlignmentSummary(matchShare: 1, incompleteTargetWords: [WordIndex(0)])
        let decision = decide(Scenario.input(
            alignment: alignment, measures: try Scenario.recordMeasures(placement: .unavailable(.wordSubstituted))))
        #expect(decision == .verdict(.inconclusive([.targetWordsMissing([WordIndex(0)])])))
    }

    @Test("§1.3 example 4: contrast unavailable and placement fires → feedback([placement], partial: [contrast])")
    func example4() throws {
        let measures = try Scenario.photographyMeasures(contrast: .unavailable(.lowConfidence))
        let decision = decide(Scenario.input(measures: measures, diffs: [Scenario.placementRow]))
        #expect(decision == .verdict(.feedback(rows: BoundedRows([Scenario.placementRow])!, partial: [.contrast])))
    }

    @Test("§1.3 example 5: same, nothing firing → inconclusive(requiredMeasureUnavailable([contrast]))")
    func example5() throws {
        let measures = try Scenario.photographyMeasures(contrast: .unavailable(.lowConfidence))
        let decision = decide(Scenario.input(measures: measures))
        #expect(decision == .verdict(.inconclusive([.requiredMeasureUnavailable([.contrast])])))
    }

    // MARK: Steps in order

    @Test("step 1: any take problem wins, and only the first is reported") func step1() throws {
        let decision = decide(Scenario.input(
            problems: [.wordsDontMatch, .clipped, .tooQuiet], alignment: AlignmentSummary(matchShare: 0),
            timing: .poor, measures: try Scenario.recordMeasures()))
        #expect(decision == .takeProblem(.tooQuiet))
    }

    @Test("step 2: match below 80% → wordsDontMatch", arguments: [(0.79, true), (0.8, false)])
    func step2Match(share: Double, refused: Bool) throws {
        let decision = decide(Scenario.input(
            alignment: AlignmentSummary(matchShare: share), measures: try Scenario.recordMeasures()))
        #expect((decision == .takeProblem(.wordsDontMatch)) == refused)
    }

    @Test("step 2: more than 2 non-filler insertions → wordsDontMatch", arguments: [(2, false), (3, true)])
    func step2Insertions(count: Int, refused: Bool) throws {
        let words = Array(["so", "really", "very"].prefix(count))
        let decision = decide(Scenario.input(
            alignment: AlignmentSummary(matchShare: 1, nonFillerInsertions: words),
            measures: try Scenario.recordMeasures()))
        #expect((decision == .takeProblem(.wordsDontMatch)) == refused)
    }

    @Test("step 3 comes before Poor timing and low coverage") func step3First() throws {
        let decision = decide(Scenario.input(
            alignment: AlignmentSummary(matchShare: 0.9, incompleteTargetWords: [WordIndex(2)]), timing: .poor,
            coverage: 0.1, measures: try Scenario.photographyMeasures()))
        #expect(decision == .verdict(.inconclusive([.targetWordsMissing([WordIndex(2)])])))
    }

    @Test("step 4: Poor timing → timingUnreliable, before coverage") func step4() throws {
        let decision = decide(Scenario.input(
            timing: .poor, coverage: 0.1, measures: try Scenario.recordMeasures(), diffs: [Scenario.placementRow]))
        #expect(decision == .verdict(.inconclusive([.timingUnreliable])))
    }

    @Test("step 5: coverage below 70% → comparableCoverageLow", arguments: [(0.69, true), (0.7, false)])
    func step5(coverage: Double, low: Bool) throws {
        let decision = decide(Scenario.input(coverage: coverage, measures: try Scenario.recordMeasures()))
        #expect((decision == .verdict(.inconclusive([.comparableCoverageLow(coverage)]))) == low)
    }

    @Test("step 6: no stress measure applicable → noApplicableStressMeasure, even with a diff") func step6() throws {
        let measures = try MeasureAssessments(
            applicability: applicability(Scenario.callMe),
            states: [
                .pitchRange: .evaluated(4, .high), .shapeMatch: .evaluated(0.9, .high),
                .finalDirection: .evaluated(7, .high),
            ])
        let rangeRow = DiffRow(kind: .pitchRange, values: DiffValues(you: 2, model: 6))
        let decision = decide(Scenario.input(measures: measures, diffs: [rangeRow]))
        #expect(decision == .verdict(.inconclusive([.noApplicableStressMeasure])))
    }

    @Test("step 7: rows are ranked, capped at 3, and too much contrast drops first") func step7Ranking() throws {
        let rows: [DiffRow] = [
            DiffRow(kind: .tooMuchContrast), DiffRow(kind: .weakLength), Scenario.placementRow,
            DiffRow(kind: .contrast),
        ]
        let decision = decide(Scenario.input(measures: try Scenario.photographyMeasures(), diffs: rows))
        let expected = BoundedRows([Scenario.placementRow, DiffRow(kind: .contrast), DiffRow(kind: .weakLength)])!
        #expect(decision == .verdict(.feedback(rows: expected, partial: [])))
    }

    @Test("step 7: too much contrast shows when fewer than 3 rows rank above it") func step7TooMuchContrast() throws {
        let rows = [DiffRow(kind: .tooMuchContrast), Scenario.placementRow]
        let decision = decide(Scenario.input(measures: try Scenario.photographyMeasures(), diffs: rows))
        let expected = BoundedRows([Scenario.placementRow, DiffRow(kind: .tooMuchContrast)])!
        #expect(decision == .verdict(.feedback(rows: expected, partial: [])))
    }

    @Test("step 7: equal kinds keep spec 10's order (ties by relative gap)") func step7Ties() throws {
        let first = DiffRow(kind: .placement, word: WordIndex(2), values: DiffValues(you: 0.9, model: 1.8))
        let second = DiffRow(kind: .placement, word: WordIndex(1), values: DiffValues(you: 1.0, model: 1.2))
        let decision = decide(Scenario.input(measures: try Scenario.photographyMeasures(), diffs: [first, second]))
        #expect(decision == .verdict(.feedback(rows: BoundedRows([first, second])!, partial: [])))
    }

    @Test("step 7: with Rough timing the rough-timing row is first and counts toward 3") func step7Rough() throws {
        let rows: [DiffRow] = [DiffRow(kind: .weakLength), DiffRow(kind: .contrast), Scenario.placementRow]
        let decision = decide(Scenario.input(timing: .rough, measures: try Scenario.photographyMeasures(), diffs: rows))
        let expected = BoundedRows([DiffRow(kind: .roughTiming), Scenario.placementRow, DiffRow(kind: .contrast)])!
        #expect(decision == .verdict(.feedback(rows: expected, partial: [])))
    }

    @Test("step 7: a rough-timing row passed in is ignored with Good timing") func step7RoughIgnored() throws {
        let decision = decide(Scenario.input(
            measures: try Scenario.photographyMeasures(), diffs: [DiffRow(kind: .roughTiming), Scenario.placementRow]))
        #expect(decision == .verdict(.feedback(rows: BoundedRows([Scenario.placementRow])!, partial: [])))
    }

    @Test("step 7: an optional measure unavailable never makes feedback partial") func step7Partial() throws {
        let measures = try Scenario.photographyMeasures(pitchRange: .unavailable(.noVoicedFrames))
        let decision = decide(Scenario.input(measures: measures, diffs: [Scenario.placementRow]))
        #expect(decision == .verdict(.feedback(rows: BoundedRows([Scenario.placementRow])!, partial: [])))
    }

    @Test("step 8: required placement unavailable, nothing triggered → requiredMeasureUnavailable") func step8() throws {
        let measures = try Scenario.recordMeasures(placement: .unavailable(.lowConfidence))
        #expect(decide(Scenario.input(measures: measures))
            == .verdict(.inconclusive([.requiredMeasureUnavailable([.stressPlacement])])))
    }

    @Test("step 9: close on a longer phrase") func step9() throws {
        #expect(decide(Scenario.input(measures: try Scenario.photographyMeasures())) == .verdict(.close))
    }

    @Test("step 10: missing non-target words and insertions are always named") func step10Words() throws {
        let alignment = AlignmentSummary(
            matchShare: 0.9, nonFillerInsertions: ["so"], incompleteNonTargetWords: [WordIndex(0)])
        let decision = decide(Scenario.input(alignment: alignment, measures: try Scenario.photographyMeasures()))
        #expect(decision == .verdict(.noClearDifference([
            .nonTargetWordsIncomplete([WordIndex(0)]), .insertionsPresent(["so"]),
        ])))
    }

    @Test("step 10: Rough timing blocks close") func step10Rough() throws {
        let decision = decide(Scenario.input(timing: .rough, measures: try Scenario.recordMeasures()))
        #expect(decision == .verdict(.noClearDifference([.timingRough])))
    }

    @Test("step 10: an optional measure unavailable blocks close") func step10Optional() throws {
        let measures = try Scenario.photographyMeasures(pitchRange: .unavailable(.noVoicedFrames))
        #expect(decide(Scenario.input(measures: measures))
            == .verdict(.noClearDifference([.optionalMeasuresUnavailable([.pitchRange])])))
    }

    @Test("step 10: a required measure at medium blocks close") func step10Medium() throws {
        let measures = try Scenario.recordMeasures(placement: .evaluated(0.4, .medium))
        #expect(decide(Scenario.input(measures: measures))
            == .verdict(.noClearDifference([.mediumConfidenceOnly([.stressPlacement])])))
    }

    @Test("step 10: an optional measure at medium still allows close") func step10OptionalMedium() throws {
        let measures = try Scenario.photographyMeasures(pitchRange: .evaluated(11, .medium))
        #expect(decide(Scenario.input(measures: measures)) == .verdict(.close))
    }

    @Test("step 10: reasons come in declaration order when several apply") func step10Order() throws {
        let alignment = AlignmentSummary(matchShare: 1, nonFillerInsertions: ["so"])
        let decision = decide(Scenario.input(
            alignment: alignment, timing: .rough, measures: try Scenario.recordMeasures(shape: 0.6)))
        #expect(decision == .verdict(.noClearDifference([
            .pitchShapeBelowClose(0.6), .timingRough, .insertionsPresent(["so"]),
        ])))
    }
}
