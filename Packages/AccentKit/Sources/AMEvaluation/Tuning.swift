// The tuning runner (plan §2): the fixed grid and the selection rule, generic over an objective callback. Runs on
// cached L1 features, locally, never in PR CI.

import Foundation
import AMCore

/// One point of the grid: prominence weights, the lengthening discount λ, and (τ_med, τ_high) per n-bucket.
public struct TuningPoint: Sendable, Hashable, Codable {
    public struct TauPair: Sendable, Hashable, Codable {
        public let medium: Double
        public let high: Double

        public init(medium: Double, high: Double) {
            self.medium = medium
            self.high = high
        }
    }

    public let durationWeight: Double
    public let energyWeight: Double
    public let pitchWeight: Double
    public let lambda: Double
    /// Buckets 2–4, 5–8 and ≥ 9 syllables, in that order.
    public let tau: [TauPair]

    public init(durationWeight: Double, energyWeight: Double, pitchWeight: Double, lambda: Double, tau: [TauPair]) {
        precondition(tau.count == 3, "one τ pair per n-bucket")
        self.durationWeight = durationWeight
        self.energyWeight = energyWeight
        self.pitchWeight = pitchWeight
        self.lambda = lambda
        self.tau = tau
    }

    /// The point `thresholds` currently holds (the initial values when given `Thresholds.current`).
    public init(_ thresholds: Thresholds) {
        let p = thresholds.prominence
        self.init(
            durationWeight: p.durationWeight, energyWeight: p.energyWeight, pitchWeight: p.pitchWeight,
            lambda: p.lengtheningLambda,
            tau: [
                TauPair(medium: p.tauMedium.syllables2to4, high: p.tauHigh.syllables2to4),
                TauPair(medium: p.tauMedium.syllables5to8, high: p.tauHigh.syllables5to8),
                TauPair(medium: p.tauMedium.syllables9Plus, high: p.tauHigh.syllables9Plus),
            ])
    }

    /// `thresholds` with this point's values.
    public func applied(to thresholds: Thresholds) -> Thresholds {
        var t = thresholds
        t.prominence.durationWeight = durationWeight
        t.prominence.energyWeight = energyWeight
        t.prominence.pitchWeight = pitchWeight
        t.prominence.lengtheningLambda = lambda
        t.prominence.tauMedium = Thresholds.MarginBuckets(
            syllables2to4: tau[0].medium, syllables5to8: tau[1].medium, syllables9Plus: tau[2].medium)
        t.prominence.tauHigh = Thresholds.MarginBuckets(
            syllables2to4: tau[0].high, syllables5to8: tau[1].high, syllables9Plus: tau[2].high)
        return t
    }

    var vector: [Double] {
        [durationWeight, energyWeight, pitchWeight, lambda] + tau.flatMap { [$0.medium, $0.high] }
    }
}

/// The fixed grid: weights on the 0.1 simplex with each ≥ 0.1 (36 points), λ ∈ {1.0, 1.1, …, 2.0}, and per n-bucket
/// τ_med ∈ {0.10, 0.15, …, 0.50} with τ_high ∈ {τ_med + 0.10, …, 1.00} in 0.05 steps (117 pairs). Indexable, so a
/// runner can walk it lazily or in slices.
public struct TuningGrid: Sendable, Hashable, RandomAccessCollection {
    public let weights: [[Double]]
    public let lambdas: [Double]
    public let tauPairs: [TuningPoint.TauPair]

    public init() {
        var weights: [[Double]] = []
        for d in 1...8 {
            for e in 1...8 where d + e <= 9 {
                weights.append([Double(d) / 10, Double(e) / 10, Double(10 - d - e) / 10])
            }
        }
        self.weights = weights
        lambdas = (10...20).map { Double($0) / 10 }
        var pairs: [TuningPoint.TauPair] = []
        for medium in stride(from: 10, through: 50, by: 5) {
            for high in stride(from: medium + 10, through: 100, by: 5) {
                pairs.append(TuningPoint.TauPair(medium: Double(medium) / 100, high: Double(high) / 100))
            }
        }
        tauPairs = pairs
    }

    /// A smaller grid with the same indexing (spec 11's tests; the shipped search always uses `init()`).
    init(weights: [[Double]], lambdas: [Double], tauPairs: [TuningPoint.TauPair]) {
        self.weights = weights
        self.lambdas = lambdas
        self.tauPairs = tauPairs
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { weights.count * lambdas.count * tauPairs.count * tauPairs.count * tauPairs.count }

    public subscript(position: Int) -> TuningPoint {
        var rest = position
        let t2 = rest % tauPairs.count; rest /= tauPairs.count
        let t1 = rest % tauPairs.count; rest /= tauPairs.count
        let t0 = rest % tauPairs.count; rest /= tauPairs.count
        let l = rest % lambdas.count; rest /= lambdas.count
        let w = weights[rest]
        return TuningPoint(
            durationWeight: w[0], energyWeight: w[1], pitchWeight: w[2], lambda: lambdas[l],
            tau: [tauPairs[t0], tauPairs[t1], tauPairs[t2]])
    }
}

/// What the objective reports for one point.
public struct TuningMetrics: Sendable, Hashable, Codable {
    public let recall: Double
    public let vctkPlacementFalsePositive: Double
    public let vctkAnyDiffFalsePositive: Double
    public let sharedDetectorFalsePositive: Double
    /// Synthetic which-syllable accuracy, when present (spec 22).
    public let syntheticWhichSyllableAccuracy: Double?

    public init(
        recall: Double, vctkPlacementFalsePositive: Double, vctkAnyDiffFalsePositive: Double,
        sharedDetectorFalsePositive: Double, syntheticWhichSyllableAccuracy: Double? = nil
    ) {
        self.recall = recall
        self.vctkPlacementFalsePositive = vctkPlacementFalsePositive
        self.vctkAnyDiffFalsePositive = vctkAnyDiffFalsePositive
        self.sharedDetectorFalsePositive = sharedDetectorFalsePositive
        self.syntheticWhichSyllableAccuracy = syntheticWhichSyllableAccuracy
    }
}

/// §2's selection rule: maximise recall subject to placement FP ≤ 1.6% on VCTK pairs, any-diff FP ≤ 4% and
/// shared-detector FP ≤ 1.6% on speechocean762 correct words. Ties: lower FP (shared-detector, then VCTK placement,
/// then any-diff), then higher synthetic which-syllable accuracy when both have it, then closest to the initial
/// values, then grid order.
public struct TuningSelectionRule: Sendable, Hashable {
    /// The §2 tuning constraints. They are tighter than the §6.7 gates on purpose (margin for held-out data).
    public var maxVCTKPlacementFalsePositive = 0.016
    public var maxVCTKAnyDiffFalsePositive = 0.04
    public var maxSharedDetectorFalsePositive = 0.016
    public let initial: TuningPoint

    public init(initial: TuningPoint = TuningPoint(.current)) { self.initial = initial }

    public func isFeasible(_ m: TuningMetrics) -> Bool {
        m.vctkPlacementFalsePositive <= maxVCTKPlacementFalsePositive
            && m.vctkAnyDiffFalsePositive <= maxVCTKAnyDiffFalsePositive
            && m.sharedDetectorFalsePositive <= maxSharedDetectorFalsePositive
    }

    func distance(_ point: TuningPoint) -> Double {
        zip(point.vector, initial.vector).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
    }

    /// Whether `a` beats `b` (both feasible). Grid order breaks the last tie, so the choice is deterministic.
    func prefers(_ a: (index: Int, point: TuningPoint, metrics: TuningMetrics), over b: (index: Int, point: TuningPoint, metrics: TuningMetrics)) -> Bool {
        let (ma, mb) = (a.metrics, b.metrics)
        if ma.recall != mb.recall { return ma.recall > mb.recall }
        if ma.sharedDetectorFalsePositive != mb.sharedDetectorFalsePositive {
            return ma.sharedDetectorFalsePositive < mb.sharedDetectorFalsePositive
        }
        if ma.vctkPlacementFalsePositive != mb.vctkPlacementFalsePositive {
            return ma.vctkPlacementFalsePositive < mb.vctkPlacementFalsePositive
        }
        if ma.vctkAnyDiffFalsePositive != mb.vctkAnyDiffFalsePositive {
            return ma.vctkAnyDiffFalsePositive < mb.vctkAnyDiffFalsePositive
        }
        if let sa = ma.syntheticWhichSyllableAccuracy, let sb = mb.syntheticWhichSyllableAccuracy, sa != sb {
            return sa > sb
        }
        let (da, db) = (distance(a.point), distance(b.point))
        if da != db { return da < db }
        return a.index < b.index
    }
}

public struct TuningResult: Sendable, Hashable {
    public let chosen: TuningPoint?
    public let metrics: TuningMetrics?
    public let evaluated: Int
    public let feasible: Int
}

public struct TuningRunner: Sendable {
    public let rule: TuningSelectionRule

    public init(rule: TuningSelectionRule = TuningSelectionRule()) { self.rule = rule }

    /// Evaluates `objective` on every point of `points` and returns the rule's choice (nil if none is feasible).
    public func run<Points: Sequence<TuningPoint>>(
        _ points: Points, objective: (TuningPoint) async throws -> TuningMetrics
    ) async rethrows -> TuningResult {
        var best: (index: Int, point: TuningPoint, metrics: TuningMetrics)?
        var evaluated = 0
        var feasible = 0
        for (index, point) in points.enumerated() {
            let metrics = try await objective(point)
            evaluated += 1
            guard rule.isFeasible(metrics) else { continue }
            feasible += 1
            let candidate = (index: index, point: point, metrics: metrics)
            if best == nil || rule.prefers(candidate, over: best!) { best = candidate }
        }
        return TuningResult(chosen: best?.point, metrics: best?.metrics, evaluated: evaluated, feasible: feasible)
    }
}
