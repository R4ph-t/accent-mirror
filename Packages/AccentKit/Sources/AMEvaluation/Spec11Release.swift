// Spec 11 §6 and §7: what the release report carries beyond spec 02's metric lines (the guard's four conditions,
// the L2 false-flag split, the tuning outcome), and the analysis gate `AnalysisGateTests` enforces on it.

import AMCore
import Foundation

/// The spec 11 section of a release report.
public struct Spec11Release: Sendable, Hashable, Codable {
    /// One §4c condition and the checks behind it.
    public struct Condition: Sendable, Hashable, Codable {
        public let number: Int
        public let name: String
        public let met: Bool
        public let checks: [GuardCheck]

        public init(number: Int, name: String, checks: [GuardCheck]) {
            self.number = number
            self.name = name
            self.checks = checks
            self.met = GuardEvaluation.met(checks)
        }
    }

    /// One group of the L2 false-flag split (§3; reported, never gated).
    public struct SplitRow: Sendable, Hashable, Codable {
        public let thresholds: String
        public let group: String
        public let flagged: Int
        public let words: Int
        public let interval: Interval?

        public init(thresholds: String, group: String, flagged: Int, words: Int, interval: Interval?) {
            self.thresholds = thresholds
            self.group = group
            self.flagged = flagged
            self.words = words
            self.interval = interval
        }
    }

    public let conditions: [Condition]
    public let guardMet: Bool
    /// `MET` or `NOT MET (FALLBACK)`.
    public let guardLine: String
    /// Names of the negative-set (L2) gate lines among the report's metrics.
    public let negativeRows: [String]
    /// The numeric cut of the low-ASR-confidence group (`confidence.levelMedium` when the report was written).
    public let lowAsrConfidenceBelow: Double
    public let falseFlagSplit: [SplitRow]
    /// Lines printed, never asserted: synthetic set, end-to-end check (ii), referenceAnomaly, stability, ±20/±80 ms, …
    public let reportedLines: [String]
    /// The tuning outcome: chosen point or FALLBACK, feasible counts, closest points.
    public let tuningLines: [String]

    public init(
        conditions: [Condition], negativeRows: [String], lowAsrConfidenceBelow: Double, falseFlagSplit: [SplitRow],
        reportedLines: [String], tuningLines: [String]
    ) {
        self.conditions = conditions
        self.guardMet = conditions.count == 4 && conditions.allSatisfy(\.met)
        self.guardLine = guardMet ? "MET" : "NOT MET (FALLBACK)"
        self.negativeRows = negativeRows
        self.lowAsrConfidenceBelow = lowAsrConfidenceBelow
        self.falseFlagSplit = falseFlagSplit
        self.reportedLines = reportedLines
        self.tuningLines = tuningLines
    }
}

/// §7: the analysis gate. `failures` lists every reason a release report doesn't prove the analysis; empty passes.
public enum AnalysisGate {
    /// The positive rows that must be present (stress, rhythm, pitch, plus any-diff, inconclusive, coverage).
    public static let requiredPositiveRows = [
        "Placement-diff pairs", "Contrast ratio within tolerance", "nPVI, largest |Δ|", "Weak length, largest |Δ|",
        "Band coverage, median over pairs", "Pitch range ratio at or above minimum", "Final direction agreement",
        "Any-diff pairs", "Inconclusive pairs", "Evaluation coverage",
    ]

    /// The L2 rows that must be present.
    public static let requiredNegativeRows = [
        "L2 recall, CV estimate, after suppression", "L2 false positives, clean 1,400, after suppression",
        "L2 false positives, clean 1,400, worst speaker", "Unintelligible words with a placement diff",
    ]

    /// The release report for the head's thresholds: the one whose `configDigest` recomputes from its own
    /// `ConfigIdentity` and `thresholds` (`.current` on the head) and matches the file name.
    public static func report(in directory: URL, thresholds: Thresholds = .current) throws -> (AgreementReport, String)? {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("release-") && $0.hasSuffix(".json") }.sorted()
        for file in files {
            guard let report = try? JSONDecoder().decode(
                AgreementReport.self, from: Data(contentsOf: directory.appendingPathComponent(file)))
            else { continue }
            let digest = try configDigest(report.identity.config, thresholds: thresholds)
            if file == "release-\(digest.prefix(8)).json" { return (report, digest) }
        }
        return nil
    }

    public static func failures(_ report: AgreementReport, digest: String) -> [String] {
        var out: [String] = []
        // 1. Identity.
        if report.identity.configDigest != digest {
            out.append("configDigest \(report.identity.configDigest.prefix(8)) is not the head's \(digest.prefix(8))")
        }
        if report.identity.config.thresholdsVersion != Versions.thresholdsVersion {
            out.append("thresholdsVersion \(report.identity.config.thresholdsVersion) is not the head's \(Versions.thresholdsVersion)")
        }
        // 2. Positive rows: present, with §3a accounting, PASS.
        let positive = report.metrics.filter { $0.dependsOnPositiveSet == true }
        for name in requiredPositiveRows {
            guard let row = positive.first(where: { $0.name.hasPrefix(name + " (") }) else {
                out.append("positive row missing: \(name)")
                continue
            }
            if row.accounting == nil { out.append("positive row without reference/prompt/lost-pair accounting: \(name)") }
        }
        for row in positive where row.gate != nil && row.status != .reported && !row.status.isPass {
            out.append("positive row \(row.status.text): \(row.name)")
        }
        guard let spec11 = report.spec11 else {
            out.append("no spec 11 section (negative-set rows and guard)")
            return out
        }
        // 3. Negative rows: present and PASS.
        for name in requiredNegativeRows where !spec11.negativeRows.contains(where: { $0.hasPrefix(name) }) {
            out.append("negative row missing: \(name)")
        }
        for name in spec11.negativeRows {
            guard let row = report.metrics.first(where: { $0.name == name }) else {
                out.append("negative row missing from metrics: \(name)")
                continue
            }
            if !row.status.isPass { out.append("negative row \(row.status.text): \(name)") }
        }
        // 4. Guard: MET, all four conditions present and MET; ±40 ms pooled and every group with n ≥ 30 per set.
        if !spec11.guardMet { out.append("Spec 11 guard: \(spec11.guardLine)") }
        for number in 1...4 {
            guard let condition = spec11.conditions.first(where: { $0.number == number }) else {
                out.append("guard condition \(number) missing")
                continue
            }
            if !condition.met { out.append("guard condition \(number) NOT MET: \(condition.name)") }
        }
        if let jitter = spec11.conditions.first(where: { $0.number == 4 }) {
            for set in ["synthetic", "vctk"] {
                let rows = jitter.checks.filter { $0.set.hasPrefix(set) && $0.name.hasPrefix("jitter ±40 ms") }
                if !rows.contains(where: { $0.name == "jitter ±40 ms" }) { out.append("±40 ms pooled row missing on \(set)") }
                for row in rows where row.status == .notMet || row.status == .notEvaluated {
                    out.append("\(row.name), \(row.set): \(row.status.rawValue)")
                }
                for bucket in GuardEvaluation.flipGatedBuckets
                where !rows.contains(where: { $0.name == "jitter ±40 ms, \(bucket)-syllable flips" }) {
                    out.append("±40 ms \(bucket)-syllable row missing on \(set)")
                }
            }
        }
        // 5. Gaming guard: every gated group (n ≥ 30) meets its rise.
        for check in spec11.conditions.flatMap(\.checks) where check.name.contains("inconclusive rise")
            && check.limit != nil && check.n >= GuardEvaluation.minimumGatedGroupWords && check.status != .met
        {
            out.append("\(check.name), \(check.set): \(check.status.rawValue)")
        }
        return out
    }
}
