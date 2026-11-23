import AMAlignment
import AMCore
import AMTimestampEval
import Foundation
import Testing

let repoRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// Runs a shell pipeline in the repo and returns its trimmed standard output.
func sh(_ script: String) throws -> String {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-c", script]
    process.currentDirectoryURL = repoRoot
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

@Suite("Report identity (plan §6.6)")
struct IdentityTests {
    @Test("sourceTreeHash leaves out docs/agreement/reports/ and ignores line order")
    func sourceTreeIgnoresReports() {
        let tree = "100644 blob aaa\tREADME.md\n100644 blob bbb\tdocs/thresholds.md\n"
        let withReport = tree + "100644 blob ccc\tdocs/agreement/reports/timestamp-feasibility-1234.json\n"
        let reordered = "100644 blob bbb\tdocs/thresholds.md\n100644 blob aaa\tREADME.md\n"
        #expect(SourceTree.hash(lsTree: withReport) == SourceTree.hash(lsTree: tree))
        #expect(SourceTree.hash(lsTree: reordered) == SourceTree.hash(lsTree: tree))
        #expect(SourceTree.hash(lsTree: tree + "100644 blob ddd\tdocs/agreement/other.md\n") != SourceTree.hash(lsTree: tree))
    }

    @Test("sourceTreeHash matches the documented shell recipe on this repo's HEAD")
    func sourceTreeMatchesRecipe() throws {
        let lsTree = try sh("git ls-tree -r --full-tree HEAD")
        let recipe = try sh(SourceTree.recipe.replacingOccurrences(of: "<commit>", with: "HEAD"))
        #expect(recipe == "\(SourceTree.hash(lsTree: lsTree))  -")
    }

    @Test("configDigest is AMCore's, over the identity with placeholder IDs and the full Thresholds")
    func configDigestRecord() throws {
        let config = ConfigIdentity.timestampFeasibility(asrModelID: "openai_whisper-base.en@c#12345678")
        let record = try ConfigDigestRecord(config: config)
        #expect(record.sha256 == (try configDigest(config)))
        #expect(record.sha256 == Digest.sha256(record.canonicalJSON))
        #expect(record.canonicalJSON.hasPrefix(#"{"config":{"algorithmVersion":\#(Versions.algorithmVersion),"aligner":"whisper","asrModelID":"openai_whisper-base.en@c#12345678","contractVersion":\#(Versions.contractVersion),"pitchTrackerID":"none","thresholdsVersion":\#(Versions.thresholdsVersion),"voicingID":"none"},"thresholds":{"#))
        #expect(record.canonicalJSON.contains(#""wordTimestamps":{"medianErrorMaxMs":40,"withinToleranceMs":80,"withinToleranceShareMin":0.85}"#))
        var lowered = Thresholds.current
        lowered.wordTimestamps.medianErrorMaxMs = 45
        #expect(try ConfigDigestRecord(config: config, thresholds: lowered).sha256 != record.sha256)
    }

    @Test("The gate reads the plan's numbers from Thresholds")
    func gateFromThresholds() {
        let gate = TimestampGate.plan
        #expect(gate.medianErrorMaxMs == 40)
        #expect(gate.toleranceMs == 80)
        #expect(gate.minShareWithinTolerance == 0.85)
        #expect(TimestampGate.comparisonPaddingMs == Thresholds.current.alignment.asrPaddingMs)
        #expect(gate.asrWarmBudgetMs == Thresholds.current.performance.asrWarmMs)
    }

    @Test("The corpus manifest hash depends on the files, not their order")
    func corpusHash() {
        #expect(CorpusHash.hash(fileSHA256s: ["b", "a"]) == CorpusHash.hash(fileSHA256s: ["a", "b"]))
        #expect(CorpusHash.hash(fileSHA256s: ["a", "b"]) == Digest.sha256("a\nb\n"))
    }

    @Test("The file listing digest is the shasum listing's SHA-256")
    func listingDigest() {
        #expect(Digest.listing([("b.bin", "22"), ("a.bin", "11")]) == Digest.sha256("11  a.bin\n22  b.bin\n"))
    }
}

@Suite("Evaluation set")
struct EvaluationSetTests {
    @Test("The starter set is 20 shared texts × 8 voices, no p315, and no p225 for 015: 159 clips")
    func starterClips() throws {
        let clips = try String(contentsOf: repoRoot.appending(path: "fixtures/vctk/starter-clips.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
        let speakers = Set(clips.map { String($0.prefix(4)) })
        let texts = Set(clips.map { String($0.suffix(3)) })
        #expect(clips.count == 159)
        #expect(Set(clips).count == 159)
        #expect(speakers == ["p225", "p226", "p227", "p233", "p241", "p252", "p311", "p345"])
        #expect(texts == Set(["002", "003", "004", "005", "006", "007", "008", "009", "010", "011", "012", "013", "014",
                              "015", "016", "017", "018", "019", "020", "024"]))
        #expect(!clips.contains("p225_015"))
        #expect(!speakers.contains("p315"))
    }
}

@Suite("Report")
struct ReportTests {
    static func report(accuracy: AccuracyResult?, asrMs: [Double]) throws -> TimestampReport {
        let manifest = try ModelManifest(contentsOf: repoRoot.appending(path: "Resources/Models/openai_whisper-base.en/manifest.json"))
        let config = ConfigIdentity.timestampFeasibility(asrModelID: manifest.asrModelID)
        let digest = try ConfigDigestRecord(config: config)
        return TimestampReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            identity: .init(config: config, configDigest: digest, corpusManifestHash: "c", labelHash: nil,
                            labelFile: nil, sourceTreeHash: "s", evaluatedCommit: "e", cleanTree: true,
                            toolchain: .init(xcode: "Xcode", swift: "Swift", macOS: "26", hardware: "M", runnerImage: nil)),
            model: .init(manifest: manifest, decoding: "greedy", shippingModel: manifest.model),
            baseline: nil,
            corpus: .init(name: "VCTK 0.92", archiveSHA256: nil, specifiedClips: 159, absentClips: ["p227_007"],
                          clips: 158, speakers: [], textIDs: [], audio: "", attribution: ""),
            gate: .plan, accuracy: accuracy,
            timing: .init(verifyMs: 1, loadMs: 2, asrMs: asrMs, clipSeconds: [3], budgetMs: 900),
            comparator: .init(name: "SpeechAnalyzer", status: "comparator not present", locale: "en_US",
                              coverage: nil, raw: nil),
            notes: [])
    }

    @Test("Without a baseline the report is NOT EVALUATED and says so")
    func noBaseline() throws {
        let report = try Self.report(accuracy: nil, asrMs: [500, 200, 210])
        #expect(report.verdict.overall == .notEvaluated)
        #expect(report.baseName == "timestamp-feasibility-\(report.identity.configDigest.prefix(8))")
        let markdown = report.markdown()
        #expect(markdown.contains("NOT EVALUATED"))
        #expect(markdown.contains(report.identity.sourceTreeHash))
        #expect(markdown.contains(report.identity.configDigest))
        #expect(markdown.contains("comparator not present"))
        #expect(markdown.contains("158 of 159 specified clips"))
        #expect(markdown.contains("p227_007"))
    }

    @Test("The report labels the padded table and the end-bias line as not the gate, and never says ground truth")
    func labels() throws {
        let accuracy = Evaluation.evaluate([
            clip("p225_002", "a b c d", shifts: [(0, -0.1, 0.99), (0, -0.12, 0.95), (0.02, -0.14, 0.4), (0.02, -0.1, 0.3)]),
        ])
        let markdown = try Self.report(accuracy: accuracy, asrMs: [300, 120]).markdown()
        #expect(markdown.contains("Padded (not the gate; padding belongs to spec 07)"))
        #expect(markdown.contains("diagnostic baseline only, not a fix, not the gate"))
        #expect(markdown.contains("| Starts: median error |"))
        #expect(markdown.contains("| Ends: within 80.0 ms |"))
        #expect(markdown.contains("### Per speaker"))
        #expect(!markdown.lowercased().contains("ground truth"))
    }

    @Test("Cold and warm ASR times are split, and a warm median over 900 ms fails the budget")
    func budget() throws {
        let passing = Evaluation.evaluate([
            clip("p225_002", "a b c d", shifts: [(0, 0, 0.99), (0, 0, 0.95), (0.02, -0.02, 0.4), (0.02, -0.02, 0.3)]),
        ])
        #expect(passing.outcome == .pass)
        let fast = try Self.report(accuracy: passing, asrMs: [1500, 300, 320])
        #expect(fast.timing.coldASRMs == 1500)
        #expect(fast.timing.warmASR.medianMs == 310)
        #expect(fast.verdict.overall == .pass)
        let slow = try Self.report(accuracy: passing, asrMs: [1500, 950, 990])
        #expect(slow.verdict.warmBudget == .fail)
        #expect(slow.verdict.overall == .fail)
    }
}
