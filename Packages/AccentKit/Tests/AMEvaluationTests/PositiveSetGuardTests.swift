import Foundation
import Testing
import AMCore
import AMEvaluation

/// The positive-set guard (CTO ruling 2026-11-23 14:18): NOT EVALUATED never reads as a pass.
@Suite("Positive-set guard") struct PositiveSetGuardTests {
    /// A NOT EVALUATED positive set built like today's: enough pairs and held-out speakers, too few phrases.
    static func shortSet() throws -> VCTKPairs {
        let manifest = try SyntheticVCTK.manifest()
        var clips = SyntheticVCTK.allClips(manifest)
        for phrase in VCTK.phrases.prefix(9) { clips.remove(VCTKClip(speaker: "p225", phrase: phrase)) }
        return VCTKPairs(manifest: manifest, available: clips)
    }

    /// A measured PASS for every dependent gate, as a downstream spec might hand in.
    static func allPassing() -> [String: MetricResult] {
        Dictionary(uniqueKeysWithValues: PositiveSetGates.dependents().map {
            ($0.name, MetricResult(name: $0.name, layer: .shippedConfigCheck, n: 200, value: 0, gate: $0.gate, status: .pass))
        })
    }

    @Test("Only .pass is a pass: NOT EVALUATED, blocked and REPORTED never are") func onlyPassPasses() {
        let statuses: [MetricStatus] = [
            .pass, .fail, .notEvaluated(n: 0, minimum: 150), .blocked(on: "spec 24", reason: "phrases 15 < 18"), .reported,
        ]
        #expect(statuses.filter(\.isPass) == [.pass])
        #expect(!PositiveSetStatus.notEvaluated(shortfalls: ["phrases 15 < 18"], blockedOn: "spec 24").isEvaluable)
    }

    @Test("A NOT EVALUATED positive set: every dependent gate line is NOT EVALUATED, none PASS, release gate NOT MET")
    func notEvaluatedNeverPasses() throws {
        let pairs = try Self.shortSet()
        #expect(pairs.headline.count >= 150 && pairs.shortfalls() == ["phrases 15 < 18"])
        let status = pairs.status()
        #expect(status == .notEvaluated(shortfalls: ["phrases 15 < 18"], blockedOn: "spec 24"))

        // Even when every dependent gate was measured as passing, the consumer blocks it.
        let lines = PositiveSetGates.lines(positiveSet: status, measured: Self.allPassing(), pairs: pairs.headline.count)
        let names = lines.map(\.name).joined(separator: "\n")
        for needle in ["Band coverage", "(spec 09)", "Any-diff pairs", "Placement-diff pairs", "Inconclusive pairs", "(spec 22)"] {
            #expect(names.contains(needle), "\(needle)")
        }
        #expect(lines.count == PositiveSetGates.dependents().count)
        for line in lines {
            #expect(line.status == .blocked(on: "spec 24", reason: "phrases 15 < 18"), "\(line.name)")
            #expect(line.status.text == "NOT EVALUATED (blocked on spec 24: phrases 15 < 18)")
            #expect(!line.status.isPass && line.value == nil && line.dependsOnPositiveSet == true)
        }

        // The summary: even a passing negative set can't meet the release gate.
        let summary = ReleaseSummary(negativeSet: .pass, positiveSet: status, gated: lines)
        #expect(!summary.releaseGateMet)
        #expect(summary.lines == [
            "Negative set: PASS", "Positive set: NOT EVALUATED (blocked on spec 24: phrases 15 < 18)",
            "Release gate: NOT MET",
        ])
        let report = AgreementReport(
            suite: "positive", generatedAt: Date(), release: false, identity: try ReportTests.identity(),
            metrics: lines, summary: summary)
        let text = report.markdown + report.summaryLines.joined(separator: "\n")
        #expect(!text.contains("PASS |") && !text.contains("Release gate: MET"))
        #expect(!text.lowercased().contains("waive"))
    }

    @Test("An evaluable positive set passes measurements through; an unmeasured gate is NOT EVALUATED")
    func evaluablePassesThrough() throws {
        let dependent = try #require(PositiveSetGates.dependents().first)
        let measured = try #require(Self.allPassing()[dependent.name])
        #expect(PositiveSetGates.line(dependent, positiveSet: .evaluable, measured: measured).status == .pass)
        #expect(PositiveSetGates.line(dependent, positiveSet: .evaluable).status == .notEvaluated(n: 0, minimum: 150))
    }

    @Test("check-positive-set-guard.sh passes the written report and fails doctored copies")
    func reportJSONGuard() throws {
        let pairs = try Self.shortSet()
        let status = pairs.status()
        let lines = PositiveSetGates.lines(positiveSet: status, pairs: pairs.headline.count)
        let report = AgreementReport(
            suite: "positive", generatedAt: Date(), release: false, identity: try ReportTests.identity(),
            metrics: lines, summary: ReleaseSummary(negativeSet: nil, positiveSet: status, gated: lines))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = try ReportWriter.write(report, to: dir).json
        #expect(try Self.guardExit(json) == 0)

        func doctored(_ name: String, _ edit: (inout [String: Any]) -> Void) throws -> URL {
            var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: json)) as? [String: Any])
            edit(&object)
            let url = dir.appendingPathComponent(name)
            try JSONSerialization.data(withJSONObject: object).write(to: url)
            return url
        }
        let dependentPass = try doctored("pass.json") { object in
            var metrics = object["metrics"] as! [[String: Any]]
            metrics[0]["status"] = ["pass": [String: Any]()]
            object["metrics"] = metrics
        }
        #expect(try Self.guardExit(dependentPass) == 1)
        let met = try doctored("met.json") { object in
            object["summaryLines"] = ["Negative set: PASS", "Positive set: NOT EVALUATED", "Release gate: MET"]
        }
        #expect(try Self.guardExit(met) == 1)
        let waiver = try doctored("waiver.json") { object in object["notes"] = ["positive set waived"] }
        #expect(try Self.guardExit(waiver) == 1)
    }

    static func guardExit(_ report: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = Repo.url("scripts/check-positive-set-guard.sh")
        process.arguments = [report.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
