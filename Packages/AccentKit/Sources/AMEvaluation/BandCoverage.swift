// Band coverage (spec 09, plan §6.7): per held-out pair, the share of T's comparable voiced frames inside the native
// band (computed by `AMWarp`); the gate is the median over pairs. It consumes the positive set, so its line is built
// only by `PositiveSetGates.line`: NOT EVALUATED (blocked on spec 24) while the set is short, never a pass.

import Foundation
import AMCore

/// One held-out pair's band coverage.
public struct PairBandCoverage: Sendable, Hashable, Codable {
    public let speaker: String
    public let phrase: String
    /// 0–1.
    public let coverage: Double

    public init(speaker: String, phrase: String, coverage: Double) {
        self.speaker = speaker
        self.phrase = phrase
        self.coverage = coverage
    }
}

public enum BandCoverageGate {
    /// The positive-set dependent this gate reports as.
    public static func dependent(thresholds: Thresholds = .current) -> PositiveSetGates.Dependent {
        PositiveSetGates.dependents(thresholds: thresholds).first { $0.spec == "spec 09" }!
    }

    /// The measured line: the median over pairs against `agreement.bandCoverageMedianMin`, with the speaker whose
    /// median is lowest. NOT EVALUATED below `agreement.positiveMinPairs` pairs.
    public static func measured(_ pairs: [PairBandCoverage], thresholds: Thresholds = .current) -> MetricResult {
        let dependent = dependent(thresholds: thresholds)
        let minimum = Int(thresholds.agreement.positiveMinPairs)
        guard !pairs.isEmpty, pairs.count >= minimum else {
            return MetricResult(
                name: dependent.name, layer: .shippedConfigCheck, n: pairs.count, value: nil, gate: dependent.gate,
                status: .notEvaluated(n: pairs.count, minimum: minimum))
        }
        let median = Statistics.quantile(pairs.map(\.coverage).sorted(), 0.5)
        let worst = Dictionary(grouping: pairs, by: \.speaker).map { speaker, members in
            WorstCluster(id: speaker, value: Statistics.quantile(members.map(\.coverage).sorted(), 0.5), n: members.count)
        }.min { ($0.value, $0.id) < ($1.value, $1.id) }
        return MetricResult(
            name: dependent.name, layer: .shippedConfigCheck, n: pairs.count, value: median, gate: dependent.gate,
            status: dependent.gate.passes(median) ? .pass : .fail, worstSpeaker: worst)
    }

    /// The report line, through the one consumer of the positive-set result.
    public static func line(
        positiveSet: PositiveSetStatus, pairs: [PairBandCoverage], pairCount: Int, thresholds: Thresholds = .current
    ) -> MetricResult {
        PositiveSetGates.line(
            dependent(thresholds: thresholds), positiveSet: positiveSet,
            measured: measured(pairs, thresholds: thresholds), pairs: pairCount)
    }
}
