import Testing
import AMCore
import AMEvaluation

@Suite("Tuning runner") struct TuningTests {
    @Test("The fixed grid: 36 weight points, 11 λ, 117 τ pairs per n-bucket") func grid() {
        let grid = TuningGrid()
        #expect(grid.weights.count == 36)
        for w in grid.weights {
            #expect(w.allSatisfy { $0 >= 0.1 - 1e-12 })
            #expect(abs(w.reduce(0, +) - 1) < 1e-9)
        }
        #expect(grid.lambdas.first == 1.0 && grid.lambdas.last == 2.0 && grid.lambdas.count == 11)
        #expect(grid.tauPairs.count == 117)
        #expect(grid.tauPairs.allSatisfy { $0.medium >= 0.1 - 1e-12 && $0.medium <= 0.5 + 1e-12 && $0.high >= $0.medium + 0.1 - 1e-9 && $0.high <= 1 + 1e-12 })
        #expect(grid.count == 36 * 11 * 117 * 117 * 117)
        #expect(Set((0..<500).map { grid[$0] }).count == 500)
        let last = grid[grid.count - 1]
        #expect(last.lambda == 2.0 && last.tau.allSatisfy { $0 == TuningPoint.TauPair(medium: 0.5, high: 1.0) })
    }

    @Test("A point applies to Thresholds and reads back") func applyPoint() {
        let point = TuningGrid()[12_345]
        #expect(TuningPoint(point.applied(to: .current)) == point)
        #expect(TuningPoint(.current).lambda == 1.6)
    }

    static func metrics(_ recall: Double, shared: Double = 0.01, placement: Double = 0.01, anyDiff: Double = 0.03, synthetic: Double? = nil) -> TuningMetrics {
        TuningMetrics(recall: recall, vctkPlacementFalsePositive: placement, vctkAnyDiffFalsePositive: anyDiff, sharedDetectorFalsePositive: shared, syntheticWhichSyllableAccuracy: synthetic)
    }

    @Test("Selection maximises recall subject to the FP constraints, then breaks ties in order") func selection() async {
        let grid = TuningGrid()
        let points = (0..<8).map { grid[$0 * 1000] }
        let table: [TuningMetrics] = [
            Self.metrics(0.95, shared: 0.017),           // infeasible: shared FP > 1.6%
            Self.metrics(0.95, placement: 0.02),         // infeasible: placement FP > 1.6%
            Self.metrics(0.95, anyDiff: 0.05),           // infeasible: any-diff FP > 4%
            Self.metrics(0.80),
            Self.metrics(0.85, shared: 0.012),
            Self.metrics(0.85, shared: 0.010, synthetic: 0.7),
            Self.metrics(0.85, shared: 0.010, synthetic: 0.9),  // chosen: same recall and FP, better synthetic
            Self.metrics(0.84),
        ]
        let result = await TuningRunner().run(points) { point in table[points.firstIndex(of: point)!] }
        #expect(result.evaluated == 8 && result.feasible == 5)
        #expect(result.chosen == points[6])
    }

    @Test("With everything else equal, the point closest to the initial values wins") func closestToInitial() async {
        let initial = TuningPoint(.current)
        let far = TuningGrid()[0]
        let near = TuningPoint(
            durationWeight: 0.4, energyWeight: 0.3, pitchWeight: 0.3, lambda: 1.5, tau: initial.tau)
        let result = await TuningRunner().run([far, near]) { _ in Self.metrics(0.9) }
        #expect(result.chosen == near)
        let none = await TuningRunner().run([far]) { _ in Self.metrics(0.9, shared: 0.5) }
        #expect(none.chosen == nil && none.feasible == 0)
    }
}
