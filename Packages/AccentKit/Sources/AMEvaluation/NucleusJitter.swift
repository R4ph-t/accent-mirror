// Spec 25 §5 acceptance 1: spec 11 §4b's oracle-boundary jitter test with `.nucleus` measurement, `.span` beside it.
// Read from two `am-timestamps spec11-guard --rows jitter` runs (one per measurement); the limits live here, from
// `Thresholds.wordBoundaries` and `Thresholds.agreement`, through spec 11's `GuardEvaluation`, so no gate value is in
// the tool. `NucleusJitterGateTests` re-evaluates the committed report for the head's configDigest.

import AMCore
import Foundation

public enum NucleusJitter {
    public static let suite = "nucleus-jitter"
    /// The gated radius (spec 11 §4b); ±20 and ±80 ms are reported only.
    public static let gatedID = "jitter-40"
    public static let reportedIDs = ["jitter-20", "jitter-80"]
    /// Both sets must be present and evaluated.
    public static let requiredSets = ["synthetic", "vctk-held-out"]

    /// Acceptance 1's conditions on one set's ±40 ms comparison: flips pooled and per multi-syllable group (n ≥ 30),
    /// the per-group inconclusive rise (2 and 3 gated at n ≥ 30, the rest reported) and the 10% inconclusive budget.
    public static func checks(_ comparison: GuardRun.Comparison?, set: String, thresholds: Thresholds = .current)
        -> [GuardCheck]
    {
        let evaluation = GuardEvaluation(
            run: GuardRun(formatVersion: 1, thresholdsLabel: "", seed: 0, asrModelID: nil, ctcModel: nil, sets: []),
            scope: .heldOut, thresholds: thresholds)
        let name = "jitter ±40 ms"
        return [evaluation.flips(comparison, set: set, name: name)]
            + evaluation.groupFlips(comparison, set: set, name: name)
            + evaluation.groups(comparison, set: set, name: name)
            + [budget(comparison, set: set, name: name, thresholds: thresholds)]
    }

    /// The 10% budget (`agreement.inconclusivePairsMax`) on the jittered run's inconclusive words, so acceptance 1
    /// can't pass by going inconclusive. Spec 25 names the budget without a population; this reads it on the words
    /// the test compares (the strictest reading; spec gap in the PR).
    public static func budget(_ comparison: GuardRun.Comparison?, set: String, name: String,
                              thresholds: Thresholds = .current) -> GuardCheck {
        let limit = thresholds.agreement.inconclusivePairsMax
        guard let c = comparison, c.evaluated else {
            return GuardCheck(name: "\(name), inconclusive budget", set: set, n: comparison?.words ?? 0, value: nil,
                              limit: limit, status: .notEvaluated, interval: nil, detail: comparison?.reason ?? "not run")
        }
        let share = Double(c.candidateInconclusive) / Double(c.words)
        return GuardCheck(
            name: "\(name), inconclusive budget", set: set, n: c.words, value: share, limit: limit,
            status: microunit(share) <= limit ? .met : .notMet,
            interval: Statistics.wilson(successes: c.candidateInconclusive, n: c.words),
            detail: String(format: "jittered %d/%d inconclusive (oracle %d/%d, %.1f%%)", c.candidateInconclusive,
                           c.words, c.oracleInconclusive, c.words, Double(c.oracleInconclusive) / Double(c.words) * 100))
    }

    /// ±20 and ±80 ms flips: reported only.
    public static func reported(_ set: Set, thresholds: Thresholds = .current) -> [GuardCheck] {
        let evaluation = GuardEvaluation(
            run: GuardRun(formatVersion: 1, thresholdsLabel: "", seed: 0, asrModelID: nil, ctcModel: nil, sets: []),
            scope: .heldOut, thresholds: thresholds)
        return reportedIDs.map { id in
            let check = evaluation.flips(set.nucleus.first { $0.id == id }, set: set.set, name: "jitter ±\(id.dropFirst(7)) ms")
            return GuardCheck(name: check.name, set: check.set, n: check.n, value: check.value, limit: nil,
                              status: check.status == .notEvaluated ? .notEvaluated : .reported,
                              interval: check.interval, detail: check.detail)
        }
    }

    /// One set's comparisons under both measurements.
    public struct Set: Sendable, Hashable, Codable {
        public let set: String
        public let oracle: String
        public let clips: Int
        public let span: [GuardRun.Comparison]
        public let nucleus: [GuardRun.Comparison]

        public init(set: String, oracle: String, clips: Int, span: [GuardRun.Comparison], nucleus: [GuardRun.Comparison]) {
            self.set = set
            self.oracle = oracle
            self.clips = clips
            self.span = span
            self.nucleus = nucleus
        }

        public func comparison(_ id: String, measurement: SyllableMeasurement) -> GuardRun.Comparison? {
            (measurement == .span ? span : nucleus).first { $0.id == id }
        }
    }

    /// The sets of both runs, matched by name. Throws when the runs don't hold the same sets or measurements.
    public static func sets(span: GuardRun, nucleus: GuardRun) throws -> [Set] {
        guard span.measurement == "span", nucleus.measurement == "nucleus" else {
            throw NucleusJitterError.wrongMeasurement(span: span.measurement, nucleus: nucleus.measurement)
        }
        guard span.seed == nucleus.seed else { throw NucleusJitterError.seedsDiffer }
        return try nucleus.sets.map { n in
            guard let s = span.set(n.set) else { throw NucleusJitterError.missingSet(n.set) }
            return Set(set: n.set, oracle: n.oracle, clips: n.clips, span: s.comparisons, nucleus: n.comparisons)
        }
    }

    /// Every gated check of both sets on `.nucleus`, plus a NOT EVALUATED line for a missing set.
    public static func gatedChecks(_ sets: [Set], thresholds: Thresholds = .current) -> [GuardCheck] {
        requiredSets.flatMap { name -> [GuardCheck] in
            let set = sets.first { $0.set == name }
            return checks(set?.comparison(gatedID, measurement: .nucleus), set: name, thresholds: thresholds)
        }
    }

    public static func met(_ checks: [GuardCheck]) -> Bool { GuardEvaluation.met(checks) }
}

public enum NucleusJitterError: Error, CustomStringConvertible {
    case wrongMeasurement(span: String?, nucleus: String?)
    case seedsDiffer
    case missingSet(String)

    public var description: String {
        switch self {
        case .wrongMeasurement(let span, let nucleus):
            "nucleus-jitter: --span must be a span run and --nucleus a nucleus run (got \(span ?? "none"), \(nucleus ?? "none"))"
        case .seedsDiffer: "nucleus-jitter: the two runs used different seeds"
        case .missingSet(let name): "nucleus-jitter: the span run has no set \(name)"
        }
    }
}

// MARK: - The report

/// `docs/agreement/reports/nucleus-jitter-<configDigest8>.json`: the identity (§6.6), the nucleus parameters, both
/// runs' ±20/±40/±80 ms comparisons, the gated checks and the outcome. The gate test re-derives the checks from the
/// comparisons, so a stored status alone never passes.
public struct NucleusJitterReport: Sendable, Hashable, Codable {
    public let suite: String
    public let generatedAt: String
    public let identity: ReportIdentity
    /// The measurement the head ships (`prominence.measurement`) when the report was written.
    public let shippedMeasurement: String
    /// The nucleus parameters (spec 25 §1–§3), fixed at their initial values (CTO markup 4).
    public let nucleus: Thresholds.Nucleus
    public let seed: UInt64
    public let asrModelID: String?
    public let sets: [NucleusJitter.Set]
    /// Acceptance 1's conditions on `.nucleus`, both sets.
    public let checks: [GuardCheck]
    /// The same conditions on `.span`, reported (the before column).
    public let spanChecks: [GuardCheck]
    /// ±20 and ±80 ms on `.nucleus`, reported.
    public let reported: [GuardCheck]
    /// `MET` or `NOT MET`.
    public let outcome: String
    /// §6's scope-cut proposal, written only when acceptance 1 is not met.
    public let proposal: NucleusJitterProposal?

    public init(generatedAt: String, identity: ReportIdentity, shippedMeasurement: String, nucleus: Thresholds.Nucleus,
                seed: UInt64, asrModelID: String?, sets: [NucleusJitter.Set], thresholds: Thresholds = .current,
                proposal: NucleusJitterProposal?) {
        suite = NucleusJitter.suite
        self.generatedAt = generatedAt
        self.identity = identity
        self.shippedMeasurement = shippedMeasurement
        self.nucleus = nucleus
        self.seed = seed
        self.asrModelID = asrModelID
        self.sets = sets
        checks = NucleusJitter.gatedChecks(sets, thresholds: thresholds)
        spanChecks = NucleusJitter.requiredSets.flatMap { name in
            NucleusJitter.checks(sets.first { $0.set == name }?.comparison(NucleusJitter.gatedID, measurement: .span),
                                 set: name, thresholds: thresholds)
        }
        reported = sets.flatMap { NucleusJitter.reported($0, thresholds: thresholds) }
        outcome = NucleusJitter.met(checks) ? "MET" : "NOT MET"
        self.proposal = proposal
    }

    public var met: Bool { outcome == "MET" }
    public var baseName: String { "\(suite)-\(identity.configDigest.prefix(8))" }

    /// Finds the committed report for the head's thresholds: the `nucleus-jitter-*.json` whose name matches the
    /// configDigest of its own config under `thresholds`.
    public static func report(in directory: URL, thresholds: Thresholds = .current) throws -> (NucleusJitterReport, String)? {
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(NucleusJitter.suite + "-") && $0.hasSuffix(".json") }.sorted()
        for file in files {
            guard let report = try? JSONDecoder().decode(
                NucleusJitterReport.self, from: Data(contentsOf: directory.appendingPathComponent(file)))
            else { continue }
            let digest = try configDigest(report.identity.config, thresholds: thresholds)
            if file == "\(NucleusJitter.suite)-\(digest.prefix(8)).json" { return (report, digest) }
        }
        return nil
    }

    /// Why the report doesn't show acceptance 1 MET for the head; empty when it does. The checks are re-derived from
    /// the stored comparisons, and every stored gated check must also be MET with its value within its limit.
    public static func failures(_ report: NucleusJitterReport, digest: String, thresholds: Thresholds = .current)
        -> [String]
    {
        var out: [String] = []
        if report.identity.configDigest != digest {
            out.append("configDigest \(report.identity.configDigest.prefix(8)) is not the head's \(digest.prefix(8))")
        }
        if report.identity.config.thresholdsVersion != Versions.thresholdsVersion {
            out.append("thresholdsVersion \(report.identity.config.thresholdsVersion) is not the head's \(Versions.thresholdsVersion)")
        }
        if report.nucleus != thresholds.nucleus { out.append("nucleus parameters differ from the head's") }
        for name in NucleusJitter.requiredSets where !report.sets.contains(where: { $0.set == name }) {
            out.append("set \(name) missing")
        }
        for check in NucleusJitter.gatedChecks(report.sets, thresholds: thresholds)
        where ![.met, .reported, .reportedSmall].contains(check.status) {
            out.append("\(check.status.rawValue): \(check.line)")
        }
        for check in report.checks where check.status == .met || check.status == .notMet {
            if check.status != .met { out.append("stored \(check.status.rawValue): \(check.line)") }
            if let value = check.value, let limit = check.limit, microunit(value) > limit {
                out.append("stored value over its limit: \(check.line)")
            }
        }
        if report.outcome != "MET" { out.append("outcome \(report.outcome)") }
        return out
    }
}

/// §6: the scope-cut proposal's numbers (for CTO to route; nothing is cut in code).
public struct NucleusJitterProposal: Sendable, Hashable, Codable {
    /// Per set and measurement at ±40 ms: each group's own flip rate and its share of the pooled flips, the pooled
    /// rate, and the pooled rate without 2–3-syllable words.
    public struct GroupRow: Sendable, Hashable, Codable {
        public let set: String
        public let measurement: String
        public let group: String
        public let words: Int
        public let flips: Int
        public let rate: Double?
        public let interval: Interval?
        public let shareOfPooledFlips: Double?
    }

    public struct PooledRow: Sendable, Hashable, Codable {
        public let set: String
        public let measurement: String
        public let words: Int
        public let flips: Int
        public let rate: Double?
        public let wordsWithoutCut: Int
        public let flipsWithoutCut: Int
        public let rateWithoutCut: Double?
    }

    public let groups: [GroupRow]
    public let pooled: [PooledRow]
    /// What the cut removes and what it costs, as text lines with their numbers (or NOT EVALUATED with the reason).
    public let removes: [String]
    public let rows: [String]

    public init(sets: [NucleusJitter.Set], removes: [String], rows: [String]) {
        var groups: [GroupRow] = [], pooled: [PooledRow] = []
        for set in sets {
            for measurement in SyllableMeasurement.allCases {
                guard let c = set.comparison(NucleusJitter.gatedID, measurement: measurement), c.evaluated else { continue }
                for b in c.bySyllables {
                    groups.append(GroupRow(
                        set: set.set, measurement: measurement.name, group: b.bucket, words: b.words, flips: b.differing,
                        rate: b.words == 0 ? nil : Double(b.differing) / Double(b.words),
                        interval: b.words == 0 ? nil : Statistics.wilson(successes: b.differing, n: b.words),
                        shareOfPooledFlips: c.differing == 0 ? nil : Double(b.differing) / Double(c.differing)))
                }
                let cut = c.bySyllables.filter { $0.bucket == "2" || $0.bucket == "3" }
                let words = c.words - cut.reduce(0) { $0 + $1.words }
                let flips = c.differing - cut.reduce(0) { $0 + $1.differing }
                pooled.append(PooledRow(
                    set: set.set, measurement: measurement.name, words: c.words, flips: c.differing,
                    rate: Double(c.differing) / Double(c.words), wordsWithoutCut: words, flipsWithoutCut: flips,
                    rateWithoutCut: words == 0 ? nil : Double(flips) / Double(words)))
            }
        }
        self.groups = groups
        self.pooled = pooled
        self.removes = removes
        self.rows = rows
    }
}
