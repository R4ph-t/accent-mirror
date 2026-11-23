import AMAlignment
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

    @Test("configDigest is the SHA-256 of sorted, whitespace-free JSON with placeholder IDs")
    func configDigest() throws {
        let config = ConfigIdentity.spec03(asrModelID: "openai_whisper-base.en@c#12345678")
        let digest = try ConfigDigest(config: config, thresholds: .plan)
        #expect(digest.canonicalJSON.hasPrefix(#"{"config":{"algorithmVersion":1,"asrModelID":"openai_whisper-base.en@c#12345678","contractVersion":1,"pitchTrackerID":"none","thresholdsVersion":1,"voicingID":"none"},"thresholds":{"#))
        #expect(!digest.canonicalJSON.contains(" "))
        #expect(digest.canonicalJSON.contains(#""medianErrorMaxMs":40"#))
        #expect(digest.canonicalJSON.contains(#""minShareWithinTolerance":0.85"#))
        #expect(digest.sha256 == Digest.sha256(digest.canonicalJSON))
        var lowered = TimestampGate.plan
        lowered.medianErrorMaxMs = 45
        #expect(try ConfigDigest(config: config, thresholds: lowered).sha256 != digest.sha256)
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
        let config = ConfigIdentity.spec03(asrModelID: manifest.asrModelID)
        let digest = try ConfigDigest(config: config, thresholds: .plan)
        return TimestampReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            identity: .init(config: config, configDigest: digest, corpusManifestHash: "c", labelHash: nil,
                            labelFile: nil, sourceTreeHash: "s", evaluatedCommit: "e", cleanTree: true,
                            toolchain: .init(xcode: "Xcode", swift: "Swift", macOS: "26", hardware: "M", runnerImage: nil)),
            model: .init(manifest: manifest, decoding: "greedy", shippingModel: manifest.model),
            baseline: nil,
            corpus: .init(name: "VCTK 0.92", archiveSHA256: nil, clips: 159, speakers: [], textIDs: [], audio: "",
                          attribution: ""),
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
    }

    @Test("Cold and warm ASR times are split, and a warm median over 900 ms fails the budget")
    func budget() throws {
        let passing = Evaluation.evaluate([
            clip("p225_002", "a b c d", shifts: [(0.08, -0.08, 0.99), (0.08, -0.08, 0.95), (0.1, -0.1, 0.4), (0.1, -0.1, 0.3)]),
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
