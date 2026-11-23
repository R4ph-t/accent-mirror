// Metrics, gates and the report's summary lines (plan §6.6, §6.7). Gate values come only from
// `Thresholds.agreement`, and NOT EVALUATED is never a pass.

import Foundation
import AMCore

/// A gate on one metric. Built only from a `Thresholds.Agreement` key path, so no gate value lives in harness code.
public struct Gate: Sendable, Hashable, Codable {
    public enum Direction: String, Sendable, Codable {
        /// The metric passes at or above the bound (recall, accuracy).
        case atLeast
        /// The metric passes at or below the bound (false positives, diffs).
        case atMost
    }

    /// The `docs/thresholds.md` key, for example `agreement.l2RecallMin`.
    public let key: String
    public let bound: Double
    public let direction: Direction

    /// A gate on `Thresholds.agreement`. `key` is the row's key in `docs/thresholds.md` (checked by the tests).
    public static func agreement(
        _ key: String, _ path: KeyPath<Thresholds.Agreement, Double>, _ direction: Direction,
        thresholds: Thresholds = .current
    ) -> Gate {
        Gate(key: key, bound: thresholds.agreement[keyPath: path], direction: direction)
    }

    public func passes(_ value: Double) -> Bool {
        switch direction {
        case .atLeast: value >= bound
        case .atMost: value <= bound
        }
    }
}

/// PASS, FAIL, NOT EVALUATED, or REPORTED for a number with no gate. Only `.pass` passes.
public enum MetricStatus: Sendable, Hashable, Codable {
    case pass
    case fail
    case notEvaluated(n: Int, minimum: Int)
    case reported

    public var isPass: Bool { self == .pass }

    public var text: String {
        switch self {
        case .pass: "PASS"
        case .fail: "FAIL"
        case .notEvaluated(let n, let minimum): "NOT EVALUATED (n=\(n), min=\(minimum))"
        case .reported: "REPORTED (no gate)"
        }
    }
}

/// Which validation layer a number belongs to; reports print them separately (§6.6).
public enum ValidationLayer: String, Sendable, Hashable, Codable, CaseIterable {
    /// Pooled out-of-fold results of the tuning procedure.
    case cvEstimate
    /// The shipped (fully tuned) config on held-out data.
    case shippedConfigCheck
    /// Counts and descriptive numbers that are not a gate.
    case descriptive

    public var label: String {
        switch self {
        case .cvEstimate: "CV estimate, not shipped"
        case .shippedConfigCheck: "shipped-config check"
        case .descriptive: "descriptive, not a gate"
        }
    }
}

/// The worst cluster of a metric: the speaker (or phrase) with the worst rate.
public struct WorstCluster: Sendable, Hashable, Codable {
    public let id: String
    public let value: Double
    public let n: Int

    public init(id: String, value: Double, n: Int) {
        self.id = id
        self.value = value
        self.n = n
    }
}

/// One scored unit of a rate metric: a word or pair, its speaker and phrase, and whether it counts as a hit.
public struct ScoredUnit: Sendable, Hashable {
    public let speaker: String
    public let phrase: String
    public let hit: Bool

    public init(speaker: String, phrase: String = "", hit: Bool) {
        self.speaker = speaker
        self.phrase = phrase
        self.hit = hit
    }
}

/// One line of a report: n, value, gate, status, interval, and the worst speaker (and phrase on the positive set).
public struct MetricResult: Sendable, Hashable, Codable {
    public let name: String
    public let layer: ValidationLayer
    public let n: Int
    public let value: Double?
    public let gate: Gate?
    public let status: MetricStatus
    public let intervals: [Interval]
    public let worstSpeaker: WorstCluster?
    public let worstPhrase: WorstCluster?

    public init(
        name: String, layer: ValidationLayer, n: Int, value: Double?, gate: Gate?, status: MetricStatus,
        intervals: [Interval] = [], worstSpeaker: WorstCluster? = nil, worstPhrase: WorstCluster? = nil
    ) {
        self.name = name
        self.layer = layer
        self.n = n
        self.value = value
        self.gate = gate
        self.status = status
        self.intervals = intervals
        self.worstSpeaker = worstSpeaker
        self.worstPhrase = worstPhrase
    }

    /// A rate metric (hits ÷ units) against `gate`, NOT EVALUATED below `minimumN`. Prints the Wilson interval
    /// (descriptive) and, when `bootstrap` is given, the clustered bootstrap interval.
    public static func rate(
        name: String, layer: ValidationLayer, units: [ScoredUnit], gate: Gate?, minimumN: Int,
        bootstrap: (clustering: ClusteredBootstrap.Clustering, resamples: Int, seed: UInt64)? = nil,
        reportWorstPhrase: Bool = false
    ) -> MetricResult {
        let n = units.count
        guard n > 0, n >= minimumN else {
            return MetricResult(
                name: name, layer: layer, n: n, value: nil, gate: gate,
                status: .notEvaluated(n: n, minimum: minimumN))
        }
        let hits = units.filter(\.hit).count
        let value = Double(hits) / Double(n)
        var intervals = [Statistics.wilson(successes: hits, n: n)]
        if let bootstrap {
            let bootUnits = units.map { BootstrapUnit(speaker: $0.speaker, phrase: $0.phrase, value: $0.hit ? 1 : 0) }
            intervals.append(
                ClusteredBootstrap.meanInterval(
                    units: bootUnits, clustering: bootstrap.clustering, resamples: bootstrap.resamples,
                    seed: bootstrap.seed))
        }
        let worstIsHigh = gate?.direction != .atLeast
        let status: MetricStatus = gate.map { $0.passes(value) ? .pass : .fail } ?? .reported
        return MetricResult(
            name: name, layer: layer, n: n, value: value, gate: gate, status: status,
            intervals: intervals,
            worstSpeaker: worst(units, by: \.speaker, high: worstIsHigh),
            worstPhrase: reportWorstPhrase ? worst(units, by: \.phrase, high: worstIsHigh) : nil)
    }

    /// The cluster with the highest (FP-like) or lowest (recall-like) hit rate; ties go to the larger, then the id.
    static func worst(_ units: [ScoredUnit], by key: KeyPath<ScoredUnit, String>, high: Bool) -> WorstCluster? {
        let groups = Dictionary(grouping: units, by: { $0[keyPath: key] })
        let clusters = groups.map { id, members in
            WorstCluster(id: id, value: Double(members.filter(\.hit).count) / Double(members.count), n: members.count)
        }
        return clusters.min { a, b in
            if a.value != b.value { return high ? a.value > b.value : a.value < b.value }
            if a.n != b.n { return a.n > b.n }
            return a.id < b.id
        }
    }
}

/// The report's closing lines. Until spec 11 wires the speechocean762 gate, the negative set is NOT EVALUATED and
/// the release gate is NOT MET, whatever the other metrics say.
public struct ReleaseSummary: Sendable, Hashable, Codable {
    /// The speechocean762 (negative set) gate, or nil while it is not wired.
    public let negativeSet: MetricStatus?
    public let gated: [MetricResult]

    public init(negativeSet: MetricStatus?, gated: [MetricResult]) {
        self.negativeSet = negativeSet
        self.gated = gated
    }

    public var releaseGateMet: Bool {
        guard let negativeSet, negativeSet.isPass, !gated.isEmpty else { return false }
        return gated.allSatisfy(\.status.isPass)
    }

    public var lines: [String] {
        [
            "Negative set: " + (negativeSet.map(\.text) ?? "NOT EVALUATED"),
            "Release gate: " + (releaseGateMet ? "MET" : "NOT MET"),
        ]
    }
}
