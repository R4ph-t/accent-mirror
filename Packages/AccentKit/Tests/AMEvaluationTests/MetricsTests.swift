import Foundation
import Testing
import AMCore
import AMEvaluation

@Suite("Metrics, gates and summary") struct MetricsTests {
    static let recallGate = Gate.agreement("agreement.l2RecallMin", \.l2RecallMin, .atLeast)
    static let fpGate = Gate.agreement("agreement.l2FalsePositiveMax", \.l2FalsePositiveMax, .atMost)

    @Test("NOT EVALUATED below the minimum n, and it is never a pass") func notEvaluatedNeverPasses() {
        let units = (0..<100).map { ScoredUnit(speaker: "s\($0 % 5)", hit: true) }
        let result = MetricResult.rate(name: "pairs", layer: .shippedConfigCheck, units: units, gate: Self.recallGate, minimumN: 150)
        #expect(result.status == .notEvaluated(n: 100, minimum: 150))
        #expect(!result.status.isPass)
        #expect(result.status.text == "NOT EVALUATED (n=100, min=150)")
        #expect(result.value == nil)
        let empty = MetricResult.rate(name: "none", layer: .cvEstimate, units: [], gate: Self.recallGate, minimumN: 0)
        #expect(!empty.status.isPass)
        #expect(!MetricStatus.reported.isPass)
    }

    @Test("A release summary is NOT MET while the negative set is not evaluated, even if every metric passes")
    func summaryLines() {
        let pass = MetricResult(name: "x", layer: .shippedConfigCheck, n: 10, value: 1, gate: Self.recallGate, status: .pass)
        let pending = ReleaseSummary(negativeSet: nil, gated: [pass])
        #expect(pending.lines == ["Negative set: NOT EVALUATED", "Positive set: NOT EVALUATED", "Release gate: NOT MET"])
        let notEvaluated = ReleaseSummary(negativeSet: .notEvaluated(n: 0, minimum: 1400), gated: [pass])
        #expect(!notEvaluated.releaseGateMet)
        let failing = MetricResult(name: "y", layer: .shippedConfigCheck, n: 10, value: 0, gate: Self.recallGate, status: .notEvaluated(n: 10, minimum: 20))
        #expect(!ReleaseSummary(negativeSet: .pass, positiveSet: .evaluable, gated: [pass, failing]).releaseGateMet)
        // A passing negative set and passing lines still need an evaluable positive set.
        #expect(!ReleaseSummary(negativeSet: .pass, gated: [pass]).releaseGateMet)
        #expect(ReleaseSummary(negativeSet: .pass, positiveSet: .evaluable, gated: [pass]).lines
            == ["Negative set: PASS", "Positive set: EVALUABLE", "Release gate: MET"])
    }

    @Test("A rate prints n, value, gate, status, the Wilson and bootstrap intervals and the worst speaker and phrase")
    func rateMetric() {
        var units: [ScoredUnit] = []
        for s in 0..<10 {
            for p in 0..<20 { units.append(ScoredUnit(speaker: "s\(s)", phrase: "p\(p)", hit: s == 3 && p < 4 || p == 7 && s < 2)) }
        }
        let result = MetricResult.rate(
            name: "placement-diff pairs", layer: .shippedConfigCheck, units: units,
            gate: .agreement("agreement.placementDiffPairsMax", \.placementDiffPairsMax, .atMost), minimumN: 150,
            bootstrap: (.speakersAndPhrases, 200, 1), reportWorstPhrase: true)
        #expect(result.n == 200)
        #expect(result.value == 6.0 / 200)
        #expect(result.status == .fail)
        #expect(result.intervals.count == 2)
        #expect(result.intervals[0].label == "descriptive (ignores clustering)")
        #expect(result.worstSpeaker == WorstCluster(id: "s3", value: 0.2, n: 20))
        #expect(result.worstPhrase?.id == "p7")
    }

    @Test("Gates come from Thresholds.agreement, and every key names a docs/thresholds.md row") func gatesFromThresholds() throws {
        #expect(Self.recallGate.bound == Thresholds.current.agreement.l2RecallMin)
        #expect(Self.recallGate.passes(0.80) && !Self.recallGate.passes(0.79))
        #expect(Self.fpGate.passes(0.02) && !Self.fpGate.passes(0.021))
        let doc = try String(contentsOf: Repo.url("docs/thresholds.md"), encoding: .utf8)
        for key in [Self.recallGate.key, Self.fpGate.key, "agreement.unintelligiblePlacementDiffsMax", "agreement.placementDiffPairsMax"] {
            #expect(doc.contains("`\(key)`"), "\(key)")
        }
    }
}
