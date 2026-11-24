// Spec 11 §2: the fixed grid walked exactly, fast enough to run once on the whole tuning pool and once per CV fold.
//
// Every grid point is (weights, λ) × one τ pair per n-bucket. A unit (an L2 word, or a VCTK pair) reads τ only through
// the margin buckets of the takes it is built from, so its outcome is a function of the (weights, λ) index and the τ
// pairs of those buckets alone. The caller evaluates each unit once per (weights, λ) and per value of its own τ axes
// with the real detector and scorer (`TuningUnitTable`); this file sums those tables over a pool and scans all
// 36 × 11 × 117³ points with spec 02's `TuningSelectionRule`, unchanged: the same feasibility test and the same
// preference order (recall, then lower FP, then distance to the initial values, then grid order). The §4c guard is a
// separate filter on top (`TuningGuard`), never a change to the rule.

import AMCore
import Foundation

/// How a unit depends on one bucket's τ pair.
public enum TauAxisKind: String, Sendable, Hashable, Codable {
    /// Every one of the grid's 117 (τ_med, τ_high) pairs can matter.
    case pair
    /// Only τ_high matters (a native reader's reading counts only at high confidence): 17 values.
    case highOnly
}

/// One τ axis of a unit: an n-bucket (0: 2–4, 1: 5–8, 2: ≥ 9 syllables) and what it reads.
public struct TauAxis: Sendable, Hashable, Codable, Comparable {
    public let bucket: Int
    public let kind: TauAxisKind

    public init(bucket: Int, kind: TauAxisKind) {
        precondition((0..<3).contains(bucket))
        self.bucket = bucket
        self.kind = kind
    }

    public static func < (a: TauAxis, b: TauAxis) -> Bool { a.bucket < b.bucket }

    /// The bucket index of a take of `syllableCount` comparable syllables (`MarginBuckets.margin(forSyllableCount:)`).
    public static func bucket(forSyllableCount n: Int) -> Int {
        switch n {
        case ...4: 0
        case 5...8: 1
        default: 2
        }
    }

    /// Merges per-take axes: one per bucket, `pair` winning over `highOnly`, sorted by bucket.
    public static func merged(_ axes: [TauAxis]) -> [TauAxis] {
        var byBucket: [Int: TauAxisKind] = [:]
        for axis in axes where byBucket[axis.bucket] != .pair { byBucket[axis.bucket] = axis.kind }
        return byBucket.keys.sorted().map { TauAxis(bucket: $0, kind: byBucket[$0]!) }
    }
}

extension TuningGrid {
    /// Number of (weights, λ) combinations: 36 × 11.
    public var weightLambdaCount: Int { weights.count * lambdas.count }
    /// The distinct τ_high values over the τ pairs, ascending (0.20 … 1.00: 17).
    public var tauHighValues: [Double] { Array(Set(tauPairs.map(\.high))).sorted() }

    /// The grid index of (weights-λ index, τ pair per bucket).
    public func index(weightLambda k: Int, tau j: [Int]) -> Int {
        ((k * tauPairs.count + j[0]) * tauPairs.count + j[1]) * tauPairs.count + j[2]
    }

    /// The point at (weights-λ index, τ pair per bucket).
    public func point(weightLambda k: Int, tau j: [Int]) -> TuningPoint { self[index(weightLambda: k, tau: j)] }

    /// The weights and λ of combination `k` with the initial τ (for evaluating a unit at one (weights, λ)).
    public func weightsAndLambda(_ k: Int) -> (weights: [Double], lambda: Double) {
        (weights[k / lambdas.count], lambdas[k % lambdas.count])
    }

    /// Values of one axis: τ pair indices (`pair`) or τ_high value indices (`highOnly`).
    public func size(of axis: TauAxis) -> Int { axis.kind == .pair ? tauPairs.count : tauHighValues.count }
}

/// What one unit's outcome bits mean. L2 words: `flagged` after suppression, `flaggedBeforeSuppression`. VCTK pairs:
/// `placementDiff`, `anyDiff`, `inconclusive`.
public struct UnitBits: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let flagged = UnitBits(rawValue: 1 << 0)
    public static let flaggedBeforeSuppression = UnitBits(rawValue: 1 << 1)
    public static let placementDiff = UnitBits(rawValue: 1 << 2)
    public static let anyDiff = UnitBits(rawValue: 1 << 3)
    public static let inconclusive = UnitBits(rawValue: 1 << 4)
}

/// One unit's outcomes over the grid: for each (weights, λ) index, one `UnitBits` per combination of its τ axes.
public struct TuningUnitTable: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        /// An L2 stress-wrong word (recall).
        case recallWord
        /// An L2 unanimous-correct word (shared-detector FP).
        case correctWord
        /// A VCTK pair (placement FP, any-diff FP, inconclusive).
        case vctkPair
    }

    public let id: String
    public let speaker: String
    public let kind: Kind
    public let axes: [TauAxis]
    /// `weightLambdaCount × Π size(axis)` entries, (weights, λ) outermost, then the axes in order.
    public var bits: [UInt8]

    public init(id: String, speaker: String, kind: Kind, axes: [TauAxis], bits: [UInt8]) {
        self.id = id
        self.speaker = speaker
        self.kind = kind
        self.axes = axes
        self.bits = bits
    }

    /// Entries per (weights, λ) index.
    public static func stride(axes: [TauAxis], grid: TuningGrid) -> Int {
        axes.reduce(1) { $0 * grid.size(of: $1) }
    }

    /// The axis coordinates of `combination` (0 ..< stride), in axis order.
    public static func coordinates(_ combination: Int, axes: [TauAxis], grid: TuningGrid) -> [Int] {
        var rest = combination
        var out = [Int](repeating: 0, count: axes.count)
        for (i, axis) in axes.enumerated().reversed() {
            let size = grid.size(of: axis)
            out[i] = rest % size
            rest /= size
        }
        return out
    }

    /// The τ (medium, high) per bucket a combination stands for: each axis's own value, the initial values elsewhere.
    /// A `highOnly` axis takes the smallest τ_med that is valid with its τ_high; the unit doesn't read τ_med there.
    public static func tau(
        combination: Int, axes: [TauAxis], grid: TuningGrid, initial: TuningPoint
    ) -> [TuningPoint.TauPair] {
        var tau = initial.tau
        for (axis, value) in zip(axes, coordinates(combination, axes: axes, grid: grid)) {
            switch axis.kind {
            case .pair: tau[axis.bucket] = grid.tauPairs[value]
            case .highOnly:
                let high = grid.tauHighValues[value]
                let medium = grid.tauPairs.filter { $0.high == high }.map(\.medium).min()!
                tau[axis.bucket] = .init(medium: medium, high: high)
            }
        }
        return tau
    }

    /// This unit's bits at a grid point.
    public func bits(at k: Int, tau j: [Int], grid: TuningGrid, highIndex: [Int]) -> UnitBits {
        var offset = 0
        for axis in axes {
            let value = axis.kind == .pair ? j[axis.bucket] : highIndex[j[axis.bucket]]
            offset = offset * grid.size(of: axis) + value
        }
        return UnitBits(rawValue: bits[k * Self.stride(axes: axes, grid: grid) + offset])
    }
}

/// The pool one fit runs on: which units count for each constraint.
public struct TuningSearchPool: Sendable {
    public let recall: [TuningUnitTable]
    public let correct: [TuningUnitTable]
    public let vctkPairs: [TuningUnitTable]

    public init(recall: [TuningUnitTable], correct: [TuningUnitTable], vctkPairs: [TuningUnitTable]) {
        self.recall = recall
        self.correct = correct
        self.vctkPairs = vctkPairs
    }
}

/// §4c during tuning: a point is feasible only if it also meets the guard on tuning data. The b2-vs-MFA and ±40 ms
/// jitter conditions read spec 07's verdicts, which no tuned key reaches, so they are one fact for the whole grid
/// (`invariantConditionsMet`); the inconclusive budget is per point.
public struct TuningGuard: Sendable, Hashable, Codable {
    public let invariantConditionsMet: Bool
    /// `agreement.inconclusivePairsMax` on the VCTK tuning pairs.
    public let inconclusivePairsMax: Double

    public init(invariantConditionsMet: Bool, inconclusivePairsMax: Double = Thresholds.current.agreement.inconclusivePairsMax) {
        self.invariantConditionsMet = invariantConditionsMet
        self.inconclusivePairsMax = inconclusivePairsMax
    }
}

/// A point's metrics on the pool, with the counts behind them.
public struct PoolMetrics: Sendable, Hashable, Codable {
    public let recallHits: Int
    public let recallN: Int
    public let sharedFalsePositives: Int
    public let correctN: Int
    public let vctkPlacementDiffs: Int
    public let vctkAnyDiffs: Int
    public let vctkInconclusive: Int
    public let vctkPairs: Int

    static func share(_ a: Int, _ n: Int) -> Double { n == 0 ? 0 : Double(a) / Double(n) }

    public var tuning: TuningMetrics {
        TuningMetrics(
            recall: Self.share(recallHits, recallN),
            vctkPlacementFalsePositive: Self.share(vctkPlacementDiffs, vctkPairs),
            vctkAnyDiffFalsePositive: Self.share(vctkAnyDiffs, vctkPairs),
            sharedDetectorFalsePositive: Self.share(sharedFalsePositives, correctN))
    }

    public var inconclusiveShare: Double { Self.share(vctkInconclusive, vctkPairs) }
}

/// One scored point in a search result.
public struct ScoredPoint: Sendable, Hashable, Codable {
    public let index: Int
    public let point: TuningPoint
    public let metrics: PoolMetrics
    /// Σ max(0, value − limit) over the rule's three constraints and the inconclusive budget, in shares.
    public let violation: Double
}

/// The outcome of one search.
public struct TuningSearchResult: Sendable, Hashable, Codable {
    public let evaluated: Int
    /// Points meeting the selection rule's constraints (no guard).
    public let ruleFeasible: Int
    /// Points meeting the rule and the inconclusive budget (the guard's per-point part).
    public let ruleAndBudgetFeasible: Int
    /// Points feasible under the rule and the whole guard (what tuning may choose from).
    public let feasible: Int
    /// The rule's choice among the feasible points; nil when none is feasible.
    public let chosen: ScoredPoint?
    /// The rule's choice ignoring the guard (reported for CTO; never shipped).
    public let chosenWithoutGuard: ScoredPoint?
    /// The closest points by `violation` (ties: grid order), at most `closestCount`.
    public let closest: [ScoredPoint]
    /// The initial point's metrics on the same pool.
    public let initial: ScoredPoint
}

public struct TuningSearch: Sendable {
    public let grid: TuningGrid
    public let rule: TuningSelectionRule
    public let closestCount: Int

    public init(grid: TuningGrid = TuningGrid(), rule: TuningSelectionRule = TuningSelectionRule(), closestCount: Int = 5) {
        self.grid = grid
        self.rule = rule
        self.closestCount = closestCount
    }

    /// The pool's metrics at grid point (k, j).
    public func metrics(_ pool: TuningSearchPool, k: Int, tau j: [Int]) -> PoolMetrics {
        let highIndex = self.highIndex
        func count(_ units: [TuningUnitTable], _ bit: UnitBits) -> Int {
            units.count { $0.bits(at: k, tau: j, grid: grid, highIndex: highIndex).contains(bit) }
        }
        return PoolMetrics(
            recallHits: count(pool.recall, .flagged), recallN: pool.recall.count,
            sharedFalsePositives: count(pool.correct, .flagged), correctN: pool.correct.count,
            vctkPlacementDiffs: count(pool.vctkPairs, .placementDiff), vctkAnyDiffs: count(pool.vctkPairs, .anyDiff),
            vctkInconclusive: count(pool.vctkPairs, .inconclusive), vctkPairs: pool.vctkPairs.count)
    }

    /// The (weights-λ, τ) coordinates of a grid point that lies on the grid; nil otherwise.
    public func coordinates(of point: TuningPoint) -> (k: Int, tau: [Int])? {
        guard let w = grid.weights.firstIndex(where: { zip($0, [point.durationWeight, point.energyWeight, point.pitchWeight]).allSatisfy { abs($0 - $1) < 1e-9 } }),
            let l = grid.lambdas.firstIndex(where: { abs($0 - point.lambda) < 1e-9 })
        else { return nil }
        var tau: [Int] = []
        for pair in point.tau {
            guard let j = grid.tauPairs.firstIndex(where: { abs($0.medium - pair.medium) < 1e-9 && abs($0.high - pair.high) < 1e-9 })
            else { return nil }
            tau.append(j)
        }
        return (w * grid.lambdas.count + l, tau)
    }

    /// τ pair index → index of its τ_high among `tauHighValues`.
    var highIndex: [Int] {
        let highs = grid.tauHighValues
        return grid.tauPairs.map { pair in highs.firstIndex(of: pair.high)! }
    }

    func violation(_ m: PoolMetrics, budget: Double) -> Double {
        let t = m.tuning
        return max(0, t.vctkPlacementFalsePositive - rule.maxVCTKPlacementFalsePositive)
            + max(0, t.vctkAnyDiffFalsePositive - rule.maxVCTKAnyDiffFalsePositive)
            + max(0, t.sharedDetectorFalsePositive - rule.maxSharedDetectorFalsePositive)
            + max(0, m.inconclusiveShare - budget)
    }

    /// Walks every grid point. Each (weights, λ) slice runs as its own task; slices merge with the rule's preference
    /// and global grid order, so the result is the one a single in-order walk gives.
    public func run(_ pool: TuningSearchPool, guard guardRule: TuningGuard) async -> TuningSearchResult {
        let slices = await withTaskGroup(of: Slice.self) { group in
            for k in 0..<grid.weightLambdaCount {
                group.addTask { self.slice(pool, k: k, guard: guardRule) }
            }
            var out: [Slice] = []
            for await slice in group { out.append(slice) }
            return out.sorted { $0.k < $1.k }
        }
        var chosen: ScoredPoint?
        var unguarded: ScoredPoint?
        var closest: [ScoredPoint] = []
        var counts = (rule: 0, budget: 0, feasible: 0)
        for slice in slices {
            counts.rule += slice.ruleFeasible
            counts.budget += slice.ruleAndBudgetFeasible
            counts.feasible += slice.feasible
            if let c = slice.chosen, chosen.map({ prefers(c, over: $0) }) ?? true { chosen = c }
            if let c = slice.chosenWithoutGuard, unguarded.map({ prefers(c, over: $0) }) ?? true { unguarded = c }
            closest = Self.keepClosest(closest + slice.closest, count: closestCount)
        }
        let initialCoordinates = coordinates(of: rule.initial)!
        let initialMetrics = metrics(pool, k: initialCoordinates.k, tau: initialCoordinates.tau)
        let initial = ScoredPoint(
            index: grid.index(weightLambda: initialCoordinates.k, tau: initialCoordinates.tau), point: rule.initial,
            metrics: initialMetrics, violation: violation(initialMetrics, budget: guardRule.inconclusivePairsMax))
        return TuningSearchResult(
            evaluated: grid.count, ruleFeasible: counts.rule, ruleAndBudgetFeasible: counts.budget,
            feasible: counts.feasible, chosen: chosen, chosenWithoutGuard: unguarded, closest: closest,
            initial: initial)
    }

    struct Slice: Sendable {
        let k: Int
        var ruleFeasible = 0
        var ruleAndBudgetFeasible = 0
        var feasible = 0
        var chosen: ScoredPoint?
        var chosenWithoutGuard: ScoredPoint?
        var closest: [ScoredPoint] = []
    }

    static func keepClosest(_ points: [ScoredPoint], count: Int) -> [ScoredPoint] {
        Array(points.sorted { ($0.violation, $0.index) < ($1.violation, $1.index) }.prefix(count))
    }

    func prefers(_ a: ScoredPoint, over b: ScoredPoint) -> Bool {
        rule.prefers((a.index, a.point, a.metrics.tuning), over: (b.index, b.point, b.metrics.tuning))
    }

    /// Per-bucket sums of the single-axis units and dense tables for the multi-axis ones, at one (weights, λ).
    struct Sums {
        /// [metric][bucket][value]; metrics: recall hits, shared FP, placement, any-diff, inconclusive.
        var single = [[[Int32]]](repeating: [[Int32]](repeating: [], count: 3), count: 5)
        /// Multi-axis groups: their axes and [metric][combination].
        var multi: [(axes: [TauAxis], counts: [[Int32]])] = []
    }

    static let metricBits: [(TuningUnitTable.Kind, UnitBits)] = [
        (.recallWord, .flagged), (.correctWord, .flagged), (.vctkPair, .placementDiff), (.vctkPair, .anyDiff),
        (.vctkPair, .inconclusive),
    ]

    func sums(_ pool: TuningSearchPool, k: Int) -> Sums {
        var sums = Sums()
        for m in 0..<5 {
            for b in 0..<3 { sums.single[m][b] = [Int32](repeating: 0, count: grid.tauPairs.count) }
        }
        let highIndex = self.highIndex
        var groups: [[TauAxis]: [[Int32]]] = [:]
        for (m, (kind, bit)) in Self.metricBits.enumerated() {
            let units = kind == .recallWord ? pool.recall : kind == .correctWord ? pool.correct : pool.vctkPairs
            for unit in units {
                let stride = TuningUnitTable.stride(axes: unit.axes, grid: grid)
                let base = k * stride
                if unit.axes.count == 1 {
                    let axis = unit.axes[0]
                    for j in 0..<grid.tauPairs.count {
                        let value = axis.kind == .pair ? j : highIndex[j]
                        if UnitBits(rawValue: unit.bits[base + value]).contains(bit) { sums.single[m][axis.bucket][j] += 1 }
                    }
                } else {
                    var table = groups[unit.axes] ?? [[Int32]](repeating: [Int32](repeating: 0, count: stride), count: 5)
                    for c in 0..<stride where UnitBits(rawValue: unit.bits[base + c]).contains(bit) { table[m][c] += 1 }
                    groups[unit.axes] = table
                }
            }
        }
        sums.multi = groups.keys.sorted { $0.map(\.bucket).lexicographicallyPrecedes($1.map(\.bucket)) }
            .map { ($0, groups[$0]!) }
        return sums
    }

    func slice(_ pool: TuningSearchPool, k: Int, guard guardRule: TuningGuard) -> Slice {
        var slice = Slice(k: k)
        let sums = sums(pool, k: k)
        let highIndex = self.highIndex
        let n = grid.tauPairs.count
        let sizes = sums.multi.map { group in group.axes.map { grid.size(of: $0) } }
        var bestKey: (recall: Int, shared: Int, placement: Int, any: Int)?
        var bestUnguardedKey: (recall: Int, shared: Int, placement: Int, any: Int)?
        var closestCut = Double.infinity
        var j = [0, 0, 0]
        var counts = [Int32](repeating: 0, count: 5)
        for j0 in 0..<n {
            j[0] = j0
            for j1 in 0..<n {
                j[1] = j1
                for j2 in 0..<n {
                    j[2] = j2
                    for m in 0..<5 { counts[m] = sums.single[m][0][j0] + sums.single[m][1][j1] + sums.single[m][2][j2] }
                    for (g, group) in sums.multi.enumerated() {
                        var offset = 0
                        for (a, axis) in group.axes.enumerated() {
                            let value = axis.kind == .pair ? j[axis.bucket] : highIndex[j[axis.bucket]]
                            offset = offset * sizes[g][a] + value
                        }
                        for m in 0..<5 { counts[m] += group.counts[m][offset] }
                    }
                    let metrics = PoolMetrics(
                        recallHits: Int(counts[0]), recallN: pool.recall.count, sharedFalsePositives: Int(counts[1]),
                        correctN: pool.correct.count, vctkPlacementDiffs: Int(counts[2]), vctkAnyDiffs: Int(counts[3]),
                        vctkInconclusive: Int(counts[4]), vctkPairs: pool.vctkPairs.count)
                    let tuning = metrics.tuning
                    let ruleOK = rule.isFeasible(tuning)
                    let budgetOK = metrics.inconclusiveShare <= guardRule.inconclusivePairsMax
                    let v = violation(metrics, budget: guardRule.inconclusivePairsMax)
                    let index = grid.index(weightLambda: k, tau: j)
                    if v < closestCut || slice.closest.count < closestCount {
                        slice.closest = Self.keepClosest(
                            slice.closest + [ScoredPoint(index: index, point: grid[index], metrics: metrics, violation: v)],
                            count: closestCount)
                        if slice.closest.count == closestCount { closestCut = slice.closest.last!.violation }
                    }
                    guard ruleOK else { continue }
                    slice.ruleFeasible += 1
                    let key = (Int(counts[0]), Int(counts[1]), Int(counts[2]), Int(counts[3]))
                    func mayWin(_ best: (recall: Int, shared: Int, placement: Int, any: Int)?) -> Bool {
                        // Same denominators within a pool, so counts order exactly as the rule's shares do.
                        guard let best else { return true }
                        if key.0 != best.recall { return key.0 > best.recall }
                        if key.1 != best.shared { return key.1 < best.shared }
                        if key.2 != best.placement { return key.2 < best.placement }
                        if key.3 != best.any { return key.3 < best.any }
                        return true
                    }
                    if mayWin(bestUnguardedKey) {
                        let candidate = ScoredPoint(index: index, point: grid[index], metrics: metrics, violation: v)
                        if slice.chosenWithoutGuard.map({ prefers(candidate, over: $0) }) ?? true {
                            slice.chosenWithoutGuard = candidate
                            bestUnguardedKey = (key.0, key.1, key.2, key.3)
                        }
                    }
                    guard budgetOK else { continue }
                    slice.ruleAndBudgetFeasible += 1
                    guard guardRule.invariantConditionsMet else { continue }
                    slice.feasible += 1
                    if mayWin(bestKey) {
                        let candidate = ScoredPoint(index: index, point: grid[index], metrics: metrics, violation: v)
                        if slice.chosen.map({ prefers(candidate, over: $0) }) ?? true {
                            slice.chosen = candidate
                            bestKey = (key.0, key.1, key.2, key.3)
                        }
                    }
                }
            }
        }
        return slice
    }
}
