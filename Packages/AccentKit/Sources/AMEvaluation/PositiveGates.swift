// Spec 10's positive-set gates (plan §6.7): any-diff, placement-diff and inconclusive pairs, evaluation coverage,
// and the tolerance rows, over held-out VCTK pairs. Each is measured here and reported only through
// `PositiveSetGates.line`, the one consumer of the positive-set result: NOT EVALUATED (blocked) while the set is
// short, NOT EVALUATED below `agreement.positiveMinPairs` measured pairs, never a pass otherwise.
// Initial, untuned thresholds; nothing here is tuned on held-out speakers.

import Foundation
import AMCore

/// One held-out pair's scoring, as the gates read it (built from `AMScoring.Scoring` by the runner).
public struct PairOutcome: Sendable, Hashable, Codable {
    public let speaker: String
    public let phrase: String
    /// The phrase cluster the bootstrap resamples (a sub-phrase's source prompt); the phrase by default.
    public let phraseCluster: String
    public let decision: Decision
    public let applicability: ApplicabilityTable
    /// Your measures.
    public let measures: [MeasureKind: MeasureState<Double>]
    /// The model's own values (C, W points, P90−P10 st, final slope st/s, nPVI).
    public let modelValues: [MeasureKind: Double]
    /// Any word of the pair logged `referenceAnomaly`.
    public let referenceAnomaly: Bool

    public init(
        speaker: String, phrase: String, phraseCluster: String? = nil, decision: Decision,
        applicability: ApplicabilityTable, measures: [MeasureKind: MeasureState<Double>],
        modelValues: [MeasureKind: Double], referenceAnomaly: Bool
    ) {
        self.speaker = speaker
        self.phrase = phrase
        self.phraseCluster = phraseCluster ?? phrase
        self.decision = decision
        self.applicability = applicability
        self.measures = measures
        self.modelValues = modelValues
        self.referenceAnomaly = referenceAnomaly
    }

    var rows: [DiffKind] {
        if case .verdict(.feedback(let rows, _)) = decision { return rows.map(\.kind) }
        return []
    }

    /// A feedback verdict: at least one diff showed (a rough-timing row only shows with one).
    var anyDiff: Bool { !rows.isEmpty }
    var placementDiff: Bool { rows.contains(.placement) }
    var inconclusive: Bool {
        if case .verdict(.inconclusive) = decision { return true }
        return false
    }
}

public enum PositiveGates {
    /// Every spec 10 gate's measured line, keyed by `PositiveSetGates.Dependent.name`; pass it to
    /// `PositiveSetGates.lines(measured:)`. Each is NOT EVALUATED below `agreement.positiveMinPairs` units.
    public static func measured(
        _ pairs: [PairOutcome], seed: UInt64 = 0, thresholds: Thresholds = .current
    ) -> [String: MetricResult] {
        let agreement = thresholds.agreement
        let minimum = Int(agreement.positiveMinPairs)
        let gates = Dictionary(
            PositiveSetGates.dependents(thresholds: thresholds).filter { $0.spec == "spec 10" }.map { ($0.name, $0.gate) },
            uniquingKeysWith: { a, _ in a })
        let bootstrap = (clustering: ClusteredBootstrap.Clustering.speakersAndPhrases,
                         resamples: Int(agreement.bootstrapResamples), seed: seed)
        func units(_ hit: (PairOutcome) -> Bool, _ subset: [PairOutcome] = pairs) -> [ScoredUnit] {
            subset.map { ScoredUnit(speaker: $0.speaker, phrase: $0.phrase, phraseCluster: $0.phraseCluster, hit: hit($0)) }
        }
        func rate(_ name: String, _ units: [ScoredUnit]) -> MetricResult {
            MetricResult.rate(
                name: name, layer: .shippedConfigCheck, units: units, gate: gates[name], minimumN: minimum,
                bootstrap: bootstrap, reportWorstPhrase: true)
        }
        /// A worst-cluster line: the point line's worst speaker (or phrase) against its own gate.
        func worst(_ name: String, from point: MetricResult, _ cluster: WorstCluster?) -> MetricResult {
            guard point.value != nil, let cluster else {
                return MetricResult(
                    name: name, layer: .shippedConfigCheck, n: point.n, value: nil, gate: gates[name],
                    status: .notEvaluated(n: point.n, minimum: minimum))
            }
            return MetricResult(
                name: name, layer: .shippedConfigCheck, n: point.n, value: cluster.value, gate: gates[name],
                status: gates[name]!.passes(cluster.value) ? .pass : .fail, worstSpeaker: point.worstSpeaker,
                worstPhrase: point.worstPhrase)
        }

        var out: [String: MetricResult] = [:]
        let anyDiff = rate("Any-diff pairs", units(\.anyDiff))
        out[anyDiff.name] = anyDiff
        out["Any-diff pairs, worst speaker"] = worst("Any-diff pairs, worst speaker", from: anyDiff, anyDiff.worstSpeaker)
        out["Any-diff pairs, worst phrase"] = worst("Any-diff pairs, worst phrase", from: anyDiff, anyDiff.worstPhrase)
        let placement = rate("Placement-diff pairs", units(\.placementDiff))
        out[placement.name] = placement
        out["Placement-diff pairs, worst speaker"] = worst(
            "Placement-diff pairs, worst speaker", from: placement, placement.worstSpeaker)
        out["Inconclusive pairs"] = rate("Inconclusive pairs", units(\.inconclusive))
        out["Evaluation coverage"] = evaluationCoverage(pairs, gate: gates["Evaluation coverage"]!, minimum: minimum)

        // Tolerance rows: pairs where both sides have the value.
        let contrast = pairs.filter { $0.measures[.contrast]?.value != nil && ($0.modelValues[.contrast] ?? 0) > 0 }
        out["Contrast ratio within tolerance"] = rate("Contrast ratio within tolerance", units({ pair in
            let ratio = pair.measures[.contrast]!.value! / pair.modelValues[.contrast]!
            return agreement.contrastRatioLow <= ratio && ratio <= agreement.contrastRatioHigh
        }, contrast))
        out["Weak length, largest |Δ|"] = largestDelta(
            "Weak length, largest |Δ|", pairs, .weakLength, gate: gates["Weak length, largest |Δ|"]!, minimum: minimum)
        out["nPVI, largest |Δ|"] = largestDelta(
            "nPVI, largest |Δ|", pairs, .rhythm, gate: gates["nPVI, largest |Δ|"]!, minimum: minimum)
        let range = pairs.filter { $0.measures[.pitchRange]?.value != nil && ($0.modelValues[.pitchRange] ?? 0) > 0 }
        out["Pitch range ratio at or above minimum"] = rate("Pitch range ratio at or above minimum", units({ pair in
            pair.measures[.pitchRange]!.value! / pair.modelValues[.pitchRange]! >= agreement.pitchRangeRatioMin
        }, range))
        let final = pairs.filter {
            $0.applicability[.finalDirection].isApplicable && $0.measures[.finalDirection]?.value != nil
                && $0.modelValues[.finalDirection] != nil
        }
        out["Final direction agreement"] = rate("Final direction agreement", units({ pair in
            direction(pair.measures[.finalDirection]!.value!, thresholds) == direction(pair.modelValues[.finalDirection]!, thresholds)
        }, final))
        return out
    }

    /// Evaluated ÷ applicable for each required measure; the line's value is the lowest measure's coverage.
    static func evaluationCoverage(_ pairs: [PairOutcome], gate: Gate, minimum: Int) -> MetricResult {
        let byMeasure = coverageByMeasure(pairs)
        let n = byMeasure.map(\.applicable).max() ?? 0
        guard n > 0, n >= minimum, let lowest = byMeasure.min(by: { $0.coverage < $1.coverage }) else {
            return MetricResult(
                name: "Evaluation coverage", layer: .shippedConfigCheck, n: n, value: nil, gate: gate,
                status: .notEvaluated(n: n, minimum: minimum))
        }
        return MetricResult(
            name: "Evaluation coverage", layer: .shippedConfigCheck, n: n, value: lowest.coverage, gate: gate,
            status: gate.passes(lowest.coverage) ? .pass : .fail)
    }

    /// Per required measure: pairs where it is applicable and required, and the share of those evaluated.
    public static func coverageByMeasure(_ pairs: [PairOutcome]) -> [(measure: MeasureKind, applicable: Int, coverage: Double)] {
        MeasureKind.allCases.compactMap { kind in
            let applicable = pairs.filter { $0.applicability[kind].isRequired }
            guard !applicable.isEmpty else { return nil }
            let evaluated = applicable.count { $0.measures[kind]?.value != nil }
            return (kind, applicable.count, Double(evaluated) / Double(applicable.count))
        }
    }

    /// The largest |yours − model's| over pairs with both values (the tolerance holds for every pair).
    static func largestDelta(
        _ name: String, _ pairs: [PairOutcome], _ kind: MeasureKind, gate: Gate, minimum: Int
    ) -> MetricResult {
        let deltas = pairs.compactMap { pair -> (PairOutcome, Double)? in
            guard let yours = pair.measures[kind]?.value, let model = pair.modelValues[kind] else { return nil }
            return (pair, abs(yours - model))
        }
        guard deltas.count >= minimum, let largest = deltas.max(by: { $0.1 < $1.1 }) else {
            return MetricResult(
                name: name, layer: .shippedConfigCheck, n: deltas.count, value: nil, gate: gate,
                status: .notEvaluated(n: deltas.count, minimum: minimum))
        }
        return MetricResult(
            name: name, layer: .shippedConfigCheck, n: deltas.count, value: largest.1, gate: gate,
            status: gate.passes(largest.1) ? .pass : .fail,
            worstSpeaker: WorstCluster(id: largest.0.speaker, value: largest.1, n: 1),
            worstPhrase: WorstCluster(id: largest.0.phrase, value: largest.1, n: 1))
    }

    static func direction(_ slope: Double, _ thresholds: Thresholds) -> Int {
        slope >= thresholds.finalDirection.riseSemitonesPerSecond ? 1
            : slope <= thresholds.finalDirection.fallSemitonesPerSecond ? -1 : 0
    }

    /// The `referenceAnomaly` rate, reported (never a release gate): the worst phrase's share of pairs. Phrases at
    /// or above `agreement.referenceAnomalyReviewShare` get an override review.
    public static func referenceAnomaly(
        _ pairs: [PairOutcome], positiveSet: PositiveSetStatus, thresholds: Thresholds = .current
    ) -> (line: MetricResult, reviewPhrases: [String]) {
        let dependent = PositiveSetGates.Dependent(
            name: "Reference anomaly rate, worst phrase (reported)", spec: "spec 10",
            gate: .agreement(
                "agreement.referenceAnomalyReviewShare", \.referenceAnomalyReviewShare, .atMost, thresholds: thresholds))
        let byPhrase = Dictionary(grouping: pairs, by: \.phrase).mapValues {
            Double($0.count(where: \.referenceAnomaly)) / Double($0.count)
        }
        let minimum = Int(thresholds.agreement.positiveMinPairs)
        let worst = byPhrase.max { ($0.value, $1.key) < ($1.value, $0.key) }
        let measured = MetricResult(
            name: dependent.name, layer: .descriptive, n: pairs.count,
            value: pairs.count >= minimum ? worst?.value : nil, gate: dependent.gate,
            status: pairs.count >= minimum && !pairs.isEmpty ? .reported : .notEvaluated(n: pairs.count, minimum: minimum),
            worstPhrase: worst.map { w in WorstCluster(id: w.key, value: w.value, n: pairs.count { $0.phrase == w.key }) })
        let review = byPhrase.filter { $0.value >= thresholds.agreement.referenceAnomalyReviewShare }.keys.sorted()
        return (PositiveSetGates.line(dependent, positiveSet: positiveSet, measured: measured, pairs: pairs.count),
                pairs.count >= minimum ? review : [])
    }
}
