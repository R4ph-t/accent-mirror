// Spec 11 §7: the analysis gate. CI runs this on every PR: the head's thresholds must have a committed release report
// that proves the analysis (positive and L2 rows PASS, the guard MET). A FAIL, FALLBACK or NOT EVALUATED keeps CI red.

import Foundation
import Testing
import AMCore
@testable import AMEvaluation

@Suite("Analysis gate (spec 11 §7)") struct AnalysisGateTests {
    /// The repository root from `#filePath` (`Repo.root`), then `docs/agreement/reports/`.
    static let reports = Repo.url(ReportHashes.reportsPrefix)

    @Test("The head's release report exists, matches its configDigest, and every gate passes") func headReport() throws {
        let found = try AnalysisGate.report(in: Self.reports)
        guard let (report, digest) = found else {
            Issue.record("no docs/agreement/reports/release-<configDigest8>.json for the head's thresholds")
            return
        }
        let failures = AnalysisGate.failures(report, digest: digest)
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("A copy of the release report with one positive row NOT EVALUATED fails") func notEvaluatedCopyFails() throws {
        guard let (report, digest) = try AnalysisGate.report(in: Self.reports) else {
            Issue.record("no release report for the head's thresholds")
            return
        }
        let copy = try Self.copy(report, settingPositiveRow: "Placement-diff pairs", to: .notEvaluated(n: 0, minimum: 150))
        #expect(AnalysisGate.failures(copy, digest: digest).contains { $0.contains("NOT EVALUATED") && $0.contains("Placement-diff pairs") })
    }

    @Test("A passing report passes, and the same report with one positive row NOT EVALUATED fails") func syntheticGate() throws {
        let passing = try Self.passingReport()
        let digest = passing.identity.configDigest
        #expect(AnalysisGate.failures(passing, digest: digest) == [])
        let broken = try Self.copy(passing, settingPositiveRow: "Contrast ratio within tolerance", to: .notEvaluated(n: 149, minimum: 150))
        #expect(AnalysisGate.failures(broken, digest: digest) == ["positive row NOT EVALUATED (n=149, min=150): Contrast ratio within tolerance (spec 10)"])
        #expect(!AnalysisGate.failures(passing, digest: String(repeating: "0", count: 64)).isEmpty)
    }

    @Test("A missing jitter group or guard condition fails; a group under 30 words is skipped") func guardRows() throws {
        let passing = try Self.passingReport()
        var spec11 = passing.spec11!
        let conditions = spec11.conditions.map { c -> Spec11Release.Condition in
            guard c.number == 4 else { return c }
            return .init(number: 4, name: c.name, checks: c.checks.filter { !$0.name.hasSuffix("3-syllable flips") || $0.set != "synthetic" })
        }
        spec11 = Spec11Release(conditions: conditions, negativeRows: spec11.negativeRows, lowAsrConfidenceBelow: 0.45,
                               falseFlagSplit: [], reportedLines: [], tuningLines: [])
        let report = try Self.rebuilt(passing, spec11: spec11)
        #expect(AnalysisGate.failures(report, digest: passing.identity.configDigest) == ["±40 ms 3-syllable row missing on synthetic"])
        let threeConditions = Spec11Release(
            conditions: Array(passing.spec11!.conditions.prefix(3)), negativeRows: spec11.negativeRows,
            lowAsrConfidenceBelow: 0.45, falseFlagSplit: [], reportedLines: [], tuningLines: [])
        let failures = AnalysisGate.failures(try Self.rebuilt(passing, spec11: threeConditions), digest: passing.identity.configDigest)
        #expect(failures.contains("guard condition 4 missing"))
    }

    // MARK: - Helpers

    static func copy(_ report: AgreementReport, settingPositiveRow name: String, to status: MetricStatus) throws -> AgreementReport {
        let data = try JSONEncoder().encode(report)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let encodedStatus = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status), options: .fragmentsAllowed)
        var metrics = object["metrics"] as! [[String: Any]]
        let index = metrics.firstIndex { ($0["name"] as! String).hasPrefix(name + " (") }!
        metrics[index]["status"] = encodedStatus
        object["metrics"] = metrics
        return try JSONDecoder().decode(AgreementReport.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func rebuilt(_ report: AgreementReport, spec11: Spec11Release) throws -> AgreementReport {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
        object["spec11"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(spec11))
        return try JSONDecoder().decode(AgreementReport.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// A release report where every row passes and the guard is met.
    static func passingReport() throws -> AgreementReport {
        let config = ConfigIdentity(
            asrModelID: "replayed-word-timings", pitchTrackerID: "pyin-1", voicingID: "acf-1", aligner: "whisper",
            alignerModelSHA256: "none")
        let digest = try configDigest(config)
        let accounting = RowAccounting(pairs: 200, referenceSpeakers: 6, prompts: 21, lostPairs: 0, lostReasons: [:])
        let positive = PositiveSetGates.dependents().map { d in
            MetricResult(name: "\(d.name) (\(d.spec))", layer: .shippedConfigCheck, n: 200, value: 0.5, gate: d.gate,
                         status: .pass, dependsOnPositiveSet: true).with(accounting: accounting)
        }
        let negative = AnalysisGate.requiredNegativeRows.map {
            MetricResult(name: $0 + " (test)", layer: .shippedConfigCheck, n: 100, value: 0, gate: nil, status: .pass)
        }
        func check(_ name: String, _ set: String, n: Int = 300, limit: Double? = 0.02) -> GuardCheck {
            GuardCheck(name: name, set: set, n: n, value: 0.01, limit: limit, status: .met, interval: nil, detail: "")
        }
        var jitter: [GuardCheck] = []
        for set in ["synthetic", "vctk-held-out"] {
            jitter.append(check("jitter ±40 ms", set))
            jitter += ["2", "3"].map { check("jitter ±40 ms, \($0)-syllable flips", set) }
            jitter.append(GuardCheck(name: "jitter ±40 ms, 4+-syllable flips", set: set, n: 7, value: 0.3, limit: 0.02,
                                     status: .reportedSmall, interval: nil, detail: ""))
            jitter.append(check("jitter ±40 ms, 2-syllable inconclusive rise", set))
        }
        let conditions: [Spec11Release.Condition] = [
            .init(number: 1, name: "control", checks: [check("TTS-vs-MFA control", "synthetic")]),
            .init(number: 2, name: "budget", checks: [check("inconclusive pairs, positive set", "vctk-held-out", limit: 0.1)]),
            .init(number: 3, name: "b2", checks: [check("b2 vs oracle", "synthetic"), check("b2 vs oracle", "vctk-held-out")]),
            .init(number: 4, name: "jitter", checks: jitter),
        ]
        let spec11 = Spec11Release(
            conditions: conditions, negativeRows: negative.map(\.name), lowAsrConfidenceBelow: 0.45, falseFlagSplit: [],
            reportedLines: [], tuningLines: [])
        let identity = ReportIdentity(
            config: config, configDigest: digest, corpusManifestHash: "", labelHash: "", splitManifestHash: "",
            splitSeed: 0, sourceTreeHash: "", evaluatedCommit: "", cleanTree: true, xcodeVersion: "", swiftVersion: "",
            macOSVersion: "", runnerImage: "test")
        return AgreementReport(
            suite: "release", generatedAt: Date(timeIntervalSince1970: 0), release: true, identity: identity,
            metrics: positive + negative, summary: ReleaseSummary(negativeSet: .pass, positiveSet: .evaluable, gated: positive),
            spec11: spec11)
    }
}
