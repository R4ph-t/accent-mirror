import Foundation
import Testing
import AMCore
import AMEvaluation

@Suite("Reports") struct ReportTests {
    static func identity(clean: Bool = true) throws -> ReportIdentity {
        let config = ConfigIdentity(asrModelID: "replayed-word-timings", pitchTrackerID: "pyin-1", voicingID: "none", aligner: "whisper", alignerModelSHA256: "none")
        return ReportIdentity(
            config: config, configDigest: try configDigest(config), corpusManifestHash: "c", labelHash: "l",
            splitManifestHash: "s", splitSeed: 20_261_123, sourceTreeHash: "t", evaluatedCommit: "abc", cleanTree: clean,
            xcodeVersion: "Xcode 26.2", swiftVersion: "Swift 6.2.3", macOSVersion: "26", runnerImage: "local")
    }

    @Test("sourceTreeHash ignores docs/agreement/reports/ and line order") func sourceTreeHash() {
        let a = "100644 blob 1111\tREADME.md\n100644 blob 2222\tdocs/thresholds.md\n"
        let b = "100644 blob 2222\tdocs/thresholds.md\n100644 blob 9999\tdocs/agreement/reports/x-12345678.json\n100644 blob 1111\tREADME.md\n"
        let c = "100644 blob 1112\tREADME.md\n100644 blob 2222\tdocs/thresholds.md\n"
        #expect(ReportHashes.sourceTreeHash(lsTree: a) == ReportHashes.sourceTreeHash(lsTree: b))
        #expect(ReportHashes.sourceTreeHash(lsTree: a) != ReportHashes.sourceTreeHash(lsTree: c))
        // The bash check computes the same bytes: sorted lines, each with a newline.
        let expected = SHA256Digest.hex(of: Data("100644 blob 1111\tREADME.md\n100644 blob 2222\tdocs/thresholds.md\n".utf8))
        #expect(ReportHashes.sourceTreeHash(lsTree: b) == expected)
    }

    @Test("Corpus manifest hash is SHA-256 of the sorted file hashes") func corpusHash() {
        #expect(ReportHashes.corpusManifestHash(fileHashes: ["bb", "AA"]) == SHA256Digest.hex(of: Data("aa\nbb\n".utf8)))
    }

    @Test("A report carries the §6.6 header, the limitation and the summary lines") func reportContents() throws {
        let metric = MetricResult.rate(
            name: "L2 recall", layer: .cvEstimate, units: [ScoredUnit(speaker: "a", hit: true)],
            gate: .agreement("agreement.l2RecallMin", \.l2RecallMin, .atLeast), minimumN: 134)
        let report = AgreementReport(
            suite: "l2-shared", generatedAt: Date(timeIntervalSince1970: 0), release: false, identity: try Self.identity(),
            metrics: [metric], summary: ReleaseSummary(negativeSet: nil, gated: [metric]))
        #expect(report.baseName == "l2-shared-" + report.identity.configDigest.prefix(8))
        let md = report.markdown
        for needle in ["configDigest", "sourceTreeHash", "Split seed", "syntheticReference", "`none`", "CV estimate, not shipped",
                       "NOT EVALUATED (n=1, min=134)", AgreementReport.limitation, "Negative set: NOT EVALUATED", "Positive set: NOT EVALUATED", "Release gate: NOT MET"] {
            #expect(md.contains(needle), "\(needle)")
        }
        let json = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(AgreementReport.self, from: json)
        #expect(decoded == report)
        #expect(String(decoding: json, as: UTF8.self).contains("\"syntheticReference\":\"none\""))
        #expect(report.generatedAt == "1970-01-01T00:00:00Z")
    }

    @Test("A dirty tree cannot write a release report") func dirtyRelease() throws {
        let report = AgreementReport(
            suite: "l2-shared", generatedAt: Date(), release: true, identity: try Self.identity(clean: false), metrics: [],
            summary: ReleaseSummary(negativeSet: nil, gated: []))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: ReportWriter.Failure.dirtyTreeRelease) { try ReportWriter.write(report, to: dir) }
        let draft = AgreementReport(
            suite: "l2-shared", generatedAt: Date(), release: false, identity: try Self.identity(clean: false), metrics: [],
            summary: ReleaseSummary(negativeSet: nil, gated: []))
        let written = try ReportWriter.write(draft, to: dir)
        #expect(written.json.lastPathComponent == draft.baseName + ".json")
        #expect(FileManager.default.fileExists(atPath: written.markdown.path))
    }

    @Test("syntheticReference round-trips its three forms") func syntheticReference() throws {
        for value in [SyntheticReference.none, .elevenlabs, .macPremiumFallback(reason: "no key")] {
            let data = try JSONEncoder().encode([value])
            #expect(try JSONDecoder().decode([SyntheticReference].self, from: data) == [value])
        }
        #expect(SyntheticReference.macPremiumFallback(reason: "no key").description == "mac-premium-fallback (no key)")
    }
}
