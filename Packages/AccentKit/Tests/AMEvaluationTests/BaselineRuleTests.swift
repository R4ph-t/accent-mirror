import Testing
import AMCore
import AMEvaluation

@Suite("§6.5 baseline rule") struct BaselineRuleTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let d: Double
        let b: Double
        let lower: Double?
        let kind: BaselineRule.Kind
        let passes: Bool
        let why: String
        var testDescription: String { "\(why): D \(d), B* \(b)" }
    }

    static let table: [Case] = [
        Case(d: 0.80, b: 0.70, lower: -0.02, kind: .accuracy, passes: true, why: "below ceiling, lift exactly min(10, 15) pp"),
        Case(d: 0.79, b: 0.70, lower: -0.02, kind: .accuracy, passes: false, why: "below ceiling, lift 9 pp < 10 pp"),
        Case(d: 0.92, b: 0.84, lower: 0.00, kind: .accuracy, passes: true, why: "B* 84%: lift needed (100 − 84)/2 = 8 pp"),
        Case(d: 0.91, b: 0.84, lower: 0.00, kind: .accuracy, passes: false, why: "B* 84%: lift 7 pp < 8 pp"),
        Case(d: 0.87, b: 0.90, lower: -0.04, kind: .accuracy, passes: true, why: "at the ceiling: 3 pp shortfall allowed"),
        Case(d: 0.86, b: 0.90, lower: -0.04, kind: .accuracy, passes: false, why: "shortfall 4 pp > 3 pp"),
        Case(d: 0.90, b: 0.90, lower: -0.06, kind: .accuracy, passes: false, why: "bootstrap lower bound −6 pp < −5 pp"),
        Case(d: 0.90, b: 0.90, lower: -0.05, kind: .accuracy, passes: true, why: "bootstrap lower bound exactly −5 pp"),
        Case(d: 0.95, b: 0.85, lower: 0.01, kind: .accuracy, passes: true, why: "B* exactly 85%: no lift clause"),
        Case(d: 0.95, b: 0.90, lower: nil, kind: .accuracy, passes: false, why: "missing bootstrap bound never passes"),
        Case(d: 0.025, b: 0.015, lower: nil, kind: .falsePositive, passes: true, why: "FP mirror: D ≤ B* + 1 pp"),
        Case(d: 0.03, b: 0.015, lower: nil, kind: .falsePositive, passes: false, why: "FP mirror: 1.5 pp over"),
        Case(d: 0.00, b: 0.20, lower: nil, kind: .falsePositive, passes: true, why: "FP well below the baseline"),
    ]

    @Test("The rule table", arguments: table) func ruleTable(row: Case) {
        let verdict = BaselineRule().evaluate(detector: row.d, bestBaseline: row.b, pairedLowerBound: row.lower, kind: row.kind)
        #expect(verdict.passes == row.passes, "\(verdict.failures)")
        #expect(verdict.passes == verdict.failures.isEmpty)
    }

    @Test("The rule reads its numbers from Thresholds.agreement") func ruleUsesThresholds() {
        var thresholds = Thresholds.current
        thresholds.agreement.baselineMaxShortfallPoints = 0.05
        let rule = BaselineRule(thresholds: thresholds)
        #expect(rule.evaluate(detector: 0.86, bestBaseline: 0.90, pairedLowerBound: 0, kind: .accuracy).passes)
        #expect(!BaselineRule().evaluate(detector: 0.86, bestBaseline: 0.90, pairedLowerBound: 0, kind: .accuracy).passes)
    }

    @Test("B* is the best baseline: highest for accuracy, lowest for false positives") func bestBaseline() {
        #expect(BaselineRule.best(of: [0.6, 0.8, 0.7], kind: .accuracy) == 0.8)
        #expect(BaselineRule.best(of: [0.06, 0.02, 0.04], kind: .falsePositive) == 0.02)
    }

    static let photography = BaselineWord(
        syllables: [
            SyllableFeatures(durationS: 0.12, energyDB: -20),
            SyllableFeatures(durationS: 0.20, energyDB: -24),
            SyllableFeatures(durationS: 0.09, energyDB: -18),
            SyllableFeatures(durationS: 0.20, energyDB: -30),
        ],
        dictionaryPrimary: 1)

    @Test("B1 picks the longest syllable, B2 the loudest, B0 the dictionary primary; ties go to the earliest")
    func baselinePrimaries() {
        #expect(DetectorBaseline.longestSyllable.primary(of: Self.photography) == 1)
        #expect(DetectorBaseline.loudestSyllable.primary(of: Self.photography) == 2)
        #expect(DetectorBaseline.dictionary.primary(of: Self.photography) == 1)
        #expect(DetectorBaseline.loudestSyllable.flags(Self.photography, accepted: [1]) == true)
        #expect(DetectorBaseline.longestSyllable.flags(Self.photography, accepted: [1]) == false)
        #expect(DetectorBaseline.longestSyllable.primary(of: BaselineWord(syllables: [], dictionaryPrimary: nil)) == nil)
    }

    @Test("Paired comparison counts b, c and per-speaker wins and losses") func pairedComparison() {
        let outcomes: [(speaker: String, detectorRight: Bool, baselineRight: Bool)] =
            Array(repeating: ("a", true, false), count: 7) + Array(repeating: ("b", true, false), count: 3)
            + Array(repeating: ("b", false, true), count: 2) + [("c", true, true), ("c", false, false)]
        let comparison = PairedComparison(outcomes: outcomes)
        #expect(comparison.b == 10 && comparison.c == 2)
        #expect((comparison.pValue * 10_000).rounded() / 10_000 == 0.0386)
        #expect(comparison.perSpeaker["a"] == [7, 0] && comparison.perSpeaker["b"] == [3, 2] && comparison.perSpeaker["c"] == [0, 0])
    }
}
