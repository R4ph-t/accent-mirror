// The positive-set guard (CTO ruling, 2026-11-23 14:18): NOT EVALUATED never reads as a pass. Every gate, summary
// line or report line that depends on the VCTK positive set goes through `PositiveSetGates.line`, the one consumer of
// the positive-set result. While the set is NOT EVALUATED, that function returns NOT EVALUATED (blocked on spec 24)
// whatever the measured value says. There is no waiver.

import Foundation
import AMCore

/// Whether the VCTK positive set can be evaluated (§6.2 minimums met), as one value every consumer reads.
public enum PositiveSetStatus: Sendable, Hashable, Codable {
    case evaluable
    /// Short of a minimum. `blockedOn` names the spec that closes the gap.
    case notEvaluated(shortfalls: [String], blockedOn: String)

    public var isEvaluable: Bool { self == .evaluable }

    public var text: String {
        switch self {
        case .evaluable: "EVALUABLE"
        case .notEvaluated(let shortfalls, let spec):
            "NOT EVALUATED (blocked on \(spec): \(shortfalls.joined(separator: "; ")))"
        }
    }
}

extension VCTKPairs {
    /// The positive set's status: evaluable only when every §6.2 minimum is met.
    public func status(thresholds: Thresholds = .current) -> PositiveSetStatus {
        let shortfalls = shortfalls(thresholds: thresholds)
        return shortfalls.isEmpty
            ? .evaluable : .notEvaluated(shortfalls: shortfalls, blockedOn: PositiveSetGates.blockingSpec)
    }
}

/// The gates that consume the positive-set result, and the one function that turns a measurement into their line.
public enum PositiveSetGates {
    /// The follow-up that closes the phrase gap (spec 24, VCTK positive-set phrase coverage).
    public static let blockingSpec = "spec 24"

    /// One gate that reads the positive set: its report name, the spec that wires it, and its gate.
    public struct Dependent: Sendable, Hashable {
        public let name: String
        public let spec: String
        public let gate: Gate
    }

    /// Every positive-set gate (§6.7): spec 09's band coverage, spec 10's any-diff, placement-diff, inconclusive and
    /// coverage gates, and spec 22's positive-set placement-FP gate. Gate values come from `Thresholds.agreement`.
    public static func dependents(thresholds: Thresholds = .current) -> [Dependent] {
        func d(_ name: String, _ spec: String, _ key: String, _ path: KeyPath<Thresholds.Agreement, Double>,
               _ direction: Gate.Direction) -> Dependent {
            Dependent(name: name, spec: spec, gate: .agreement(key, path, direction, thresholds: thresholds))
        }
        return [
            d("Band coverage, median over pairs", "spec 09", "agreement.bandCoverageMedianMin", \.bandCoverageMedianMin, .atLeast),
            d("Any-diff pairs", "spec 10", "agreement.anyDiffPairsMax", \.anyDiffPairsMax, .atMost),
            d("Any-diff pairs, worst speaker", "spec 10", "agreement.anyDiffWorstSpeakerMax", \.anyDiffWorstSpeakerMax, .atMost),
            d("Any-diff pairs, worst phrase", "spec 10", "agreement.anyDiffWorstPhraseMax", \.anyDiffWorstPhraseMax, .atMost),
            d("Placement-diff pairs", "spec 10", "agreement.placementDiffPairsMax", \.placementDiffPairsMax, .atMost),
            d("Placement-diff pairs, worst speaker", "spec 10", "agreement.placementDiffWorstSpeakerMax", \.placementDiffWorstSpeakerMax, .atMost),
            d("Inconclusive pairs", "spec 10", "agreement.inconclusivePairsMax", \.inconclusivePairsMax, .atMost),
            d("Evaluation coverage", "spec 10", "agreement.evaluationCoverageMin", \.evaluationCoverageMin, .atLeast),
            d("Positive-set placement false positives (synthetic references)", "spec 22", "agreement.placementDiffPairsMax", \.placementDiffPairsMax, .atMost),
        ]
    }

    /// The one consumer of the positive-set result. A NOT EVALUATED positive set gives NOT EVALUATED (blocked on
    /// spec 24) whatever `measured` says; an evaluable set passes `measured` through, and a gate nobody has wired yet
    /// is NOT EVALUATED. The line is always marked as depending on the positive set.
    public static func line(
        _ dependent: Dependent, positiveSet: PositiveSetStatus, measured: MetricResult? = nil, pairs: Int = 0
    ) -> MetricResult {
        let minimum = Int(Thresholds.current.agreement.positiveMinPairs)
        let status: MetricStatus
        switch positiveSet {
        case .notEvaluated(let shortfalls, let spec):
            status = .blocked(on: spec, reason: shortfalls.joined(separator: "; "))
        case .evaluable:
            status = measured?.status ?? .notEvaluated(n: 0, minimum: minimum)
        }
        let blocked = !positiveSet.isEvaluable
        return MetricResult(
            name: "\(dependent.name) (\(dependent.spec))", layer: .shippedConfigCheck,
            n: blocked ? pairs : (measured?.n ?? 0), value: blocked ? nil : measured?.value, gate: dependent.gate,
            status: status, intervals: blocked ? [] : (measured?.intervals ?? []),
            worstSpeaker: blocked ? nil : measured?.worstSpeaker, worstPhrase: blocked ? nil : measured?.worstPhrase,
            dependsOnPositiveSet: true)
    }

    /// Every dependent gate's line. `measured` is keyed by `Dependent.name`; specs 09, 10 and 22 fill it in.
    public static func lines(
        positiveSet: PositiveSetStatus, measured: [String: MetricResult] = [:], pairs: Int = 0,
        thresholds: Thresholds = .current
    ) -> [MetricResult] {
        dependents(thresholds: thresholds).map {
            line($0, positiveSet: positiveSet, measured: measured[$0.name], pairs: pairs)
        }
    }
}
