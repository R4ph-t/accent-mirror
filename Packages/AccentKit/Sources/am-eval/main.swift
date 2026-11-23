// am-eval: the agreement harness's command-line runner (spec 02). Called by scripts/agreement.sh, scripts/tune.sh and
// the corpus fetchers; never by the app, never in PR CI beyond `swift build`. No network: it reads caches only.

import AMCore
import AMEvaluation
import AMPipeline
import AMPitch
import Foundation

// MARK: - Arguments

struct Arguments {
    let command: String
    private var options: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ raw: [String]) {
        command = raw.first ?? "help"
        var i = 1
        while i < raw.count {
            let arg = raw[i]
            if arg.hasPrefix("--"), i + 1 < raw.count, !raw[i + 1].hasPrefix("--") {
                options[String(arg.dropFirst(2))] = raw[i + 1]
                i += 2
            } else {
                flags.insert(String(arg.dropFirst(2)))
                i += 1
            }
        }
    }

    func value(_ name: String) -> String? { options[name] }
    func flag(_ name: String) -> Bool { flags.contains(name) }

    func required(_ name: String) throws -> String {
        guard let value = options[name] else { throw CLIError.usage("missing --\(name)") }
        return value
    }

    func url(_ name: String) throws -> URL { URL(fileURLWithPath: try required(name)) }
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case failed(String)

    var description: String {
        switch self {
        case .usage(let text): "usage: \(text)"
        case .failed(let text): text
        }
    }
}

// MARK: - Helpers

func shell(_ arguments: [String], in directory: URL? = nil) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    if let directory { process.currentDirectoryURL = directory }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self)
}

func repositoryRoot() throws -> URL {
    guard let path = shell(["git", "rev-parse", "--show-toplevel"])?.trimmingCharacters(in: .whitespacesAndNewlines)
    else { throw CLIError.failed("not inside the repository") }
    return URL(fileURLWithPath: path)
}

func sha256(of url: URL) throws -> String { SHA256Digest.hex(of: try Data(contentsOf: url)) }

func loadLabels(_ args: Arguments, root: URL) throws -> SpeechOceanLabels {
    if let corpus = args.value("corpus") {
        let dir = URL(fileURLWithPath: corpus)
        func text(_ path: String) throws -> String {
            try String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8)
        }
        return try SpeechOceanLabels.fromCorpus(
            scoresDetail: Data(contentsOf: dir.appendingPathComponent("resource/scores-detail.json")),
            utt2spk: [.train: try text("train/utt2spk"), .test: try text("test/utt2spk")],
            spk2age: [.train: try text("train/spk2age"), .test: try text("test/spk2age")])
    }
    let fixture = args.value("labels").map(URL.init(fileURLWithPath:)) ?? root.appendingPathComponent(Paths.labels)
    return try SpeechOceanLabels.parseFixture(String(contentsOf: fixture, encoding: .utf8))
}

enum Paths {
    static let labels = "fixtures/speechocean762/labels.tsv"
    static let soSplit = "fixtures/splits/speechocean762.json"
    static let vctkSplit = "fixtures/splits/vctk.json"
    static let evalSpeakers = "fixtures/vctk/eval-speakers.json"
    static let smoke = "fixtures/smoke"
    static let so762Pin = "fixtures/corpora/speechocean762.pin.json"
    static let vctkPin = "fixtures/corpora/vctk.pin.json"
    static let tuningLog = "docs/agreement/tuning-log.md"
}

/// The identity of the configuration the harness evaluates. ASR is replayed word timings (CI never runs ASR);
/// voicing has no implementation on main yet (spec 05).
func harnessConfig() -> ConfigIdentity {
    ConfigIdentity(asrModelID: "replayed-word-timings", pitchTrackerID: PYINTracker.trackerID, voicingID: "none")
}

func pinValue(_ root: URL, _ pin: String, _ key: String) -> String {
    guard let data = try? Data(contentsOf: root.appendingPathComponent(pin)),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return "" }
    return object[key] as? String ?? ""
}

func reportIdentity(root: URL, corpusManifestHash: String, labelHash: String, splitPath: String, splitSeed: UInt64)
    throws -> ReportIdentity
{
    let config = harnessConfig()
    let commit = shell(["git", "rev-parse", "HEAD"], in: root)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let tree = shell(["git", "ls-tree", "-r", "--full-tree", commit], in: root) ?? ""
    let clean = (shell(["git", "status", "--porcelain"], in: root) ?? "x").isEmpty
    let firstLine = { (text: String?) in
        text?.split(separator: "\n").first.map(String.init) ?? "unknown"
    }
    return ReportIdentity(
        config: config, configDigest: try configDigest(config), corpusManifestHash: corpusManifestHash,
        labelHash: labelHash, splitManifestHash: try sha256(of: root.appendingPathComponent(splitPath)),
        splitSeed: splitSeed, sourceTreeHash: ReportHashes.sourceTreeHash(lsTree: tree), evaluatedCommit: commit,
        cleanTree: clean,
        xcodeVersion: firstLine(shell(["xcodebuild", "-version"])),
        swiftVersion: firstLine(shell(["swift", "--version"])),
        macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        runnerImage: ProcessInfo.processInfo.environment["AM_RUNNER_IMAGE"] ?? "local")
}

// MARK: - Commands

/// Builds the label-only fixture from the fetched corpus.
func so762Labels(_ args: Arguments) throws {
    let root = try repositoryRoot()
    guard args.value("corpus") != nil else { throw CLIError.usage("am-eval so762-labels --corpus <dir> [--out <tsv>]") }
    let labels = try loadLabels(args, root: root)
    let out = args.value("out").map(URL.init(fileURLWithPath:)) ?? root.appendingPathComponent(Paths.labels)
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    let commit = pinValue(root, Paths.so762Pin, "repoCommit")
    try labels.fixtureText(sourceDescription: "resource/scores-detail.json (speechocean762 at \(commit))")
        .write(to: out, atomically: true, encoding: .utf8)
    print("so762-labels: wrote \(labels.relevantWords.count) of \(labels.words.count) words to \(out.path)")
}

/// Recounts the §6.3 sets and (with --write-split) writes the split manifest.
func sets(_ args: Arguments) throws -> Int32 {
    let root = try repositoryRoot()
    let labels = try loadLabels(args, root: root)
    let sets = SpeechOceanSets(labels: labels)
    print("speechocean762 sets (\(args.value("corpus") != nil ? "from the fetched corpus" : "from the label-only fixture")); label hash \(labels.sourceSHA256)")
    let checks = sets.countChecks
    for check in checks { print("  " + check.line) }
    let headline = checks.filter { !$0.isCategorySplit }
    let headlineDiffers = headline.filter { !$0.matches }
    let categoryDiffers = checks.filter { $0.isCategorySplit && !$0.matches }
    print(
        "§6.3 counts: \(headline.count - headlineDiffers.count) of \(headline.count) match the plan"
            + (categoryDiffers.isEmpty ? "" : "; the monosyllable category split differs from the plan (to CTO)"))
    if args.value("corpus") != nil {
        let fixture = try String(contentsOf: root.appendingPathComponent(Paths.labels), encoding: .utf8)
        let commit = pinValue(root, Paths.so762Pin, "repoCommit")
        let regenerated = labels.fixtureText(
            sourceDescription: "resource/scores-detail.json (speechocean762 at \(commit))")
        print("label-only fixture: " + (fixture == regenerated ? "matches the fetched corpus" : "DIFFERS from the fetched corpus"))
    }
    if let out = args.value("write-split") {
        let fixtureHash = try sha256(of: root.appendingPathComponent(Paths.labels))
        let folds = SpeechOceanFolds(sets: sets, seed: SpeechOceanSplitManifest.defaultFoldSeed)
        let manifest = SpeechOceanSplitManifest(
            sets: sets, folds: folds, labelFixtureSHA256: fixtureHash,
            foldSeed: SpeechOceanSplitManifest.defaultFoldSeed,
            bootstrapSeed: SpeechOceanSplitManifest.defaultBootstrapSeed)
        try ManifestJSON.encode(manifest).write(to: URL(fileURLWithPath: out), options: .atomic)
        print("wrote \(out)")
    }
    return headlineDiffers.isEmpty ? 0 : 1
}

/// Trims, resamples to 16 kHz and caches the VCTK clips the eval-speakers manifest names.
func vctkTrim(_ args: Arguments) throws {
    let manifest = try VCTKEvalSpeakersManifest.load(try args.url("eval-speakers"))
    let raw = try args.url("raw")
    let out = try args.url("out")
    let rule = TrimRule()
    var kept: [VCTKClip] = []
    var rejected: [[String: String]] = []
    for entry in manifest.bundled + manifest.speakers {
        let dir = out.appendingPathComponent(entry.speaker)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for phrase in VCTK.phrases where entry.files[phrase] != nil {
            let source = raw.appendingPathComponent("\(entry.speaker)/\(entry.speaker)_\(phrase)_mic1.flac")
            guard (try? sha256(of: source)) == entry.files[phrase] else {
                throw CLIError.failed("\(source.lastPathComponent): SHA-256 does not match eval-speakers.json")
            }
            let (samples, rate) = try AudioFiles.readMono(source)
            switch rule.apply(samples: samples, sampleRate: rate) {
            case .keep(let range):
                let resampled = try AudioFiles.resample(Array(samples[range]), from: rate, to: 16_000)
                try AudioFiles.writeFLAC(resampled, sampleRate: 16_000, to: dir.appendingPathComponent("\(entry.speaker)_\(phrase).flac"))
                kept.append(VCTKClip(speaker: entry.speaker, phrase: phrase))
            case .noSpeech:
                rejected.append(["speaker": entry.speaker, "phrase": phrase, "reason": "no speech"])
            case .outOfRange(let seconds):
                rejected.append(["speaker": entry.speaker, "phrase": phrase, "reason": String(format: "%.2f s outside 2–6 s", seconds)])
            }
        }
    }
    let report: [String: Any] = [
        "kept": kept.map { "\($0.speaker)_\($0.phrase)" }.sorted(), "rejected": rejected,
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: out.appendingPathComponent("trim-report.json"))
    let pairs = VCTKPairs(manifest: manifest, available: Set(kept))
    print("vctk-trim: kept \(kept.count), rejected \(rejected.count)")
    for r in rejected { print("  rejected \(r["speaker"]!)_\(r["phrase"]!): \(r["reason"]!)") }
    print("headline pairs \(pairs.headline.count) (\(Set(pairs.headline.map(\.phrase)).count) phrases, \(Set(pairs.headline.map(\.speaker)).count) held-out speakers); secondary pairs \(pairs.secondary.count)")
    let shortfalls = pairs.shortfalls()
    print(shortfalls.isEmpty ? "positive set: evaluable" : "positive set: NOT EVALUATED (\(shortfalls.joined(separator: "; ")))")
}

func vctkSplit(_ args: Arguments) throws {
    let root = try repositoryRoot()
    let path = args.value("eval-speakers").map(URL.init(fileURLWithPath:)) ?? root.appendingPathComponent(Paths.evalSpeakers)
    let manifest = try VCTKEvalSpeakersManifest.load(path)
    let split = VCTKSplitManifest(
        evalSpeakers: manifest, evalSpeakersSHA256: try sha256(of: path),
        foldSeed: VCTKSplitManifest.defaultFoldSeed, bootstrapSeed: VCTKSplitManifest.defaultBootstrapSeed)
    let out = args.value("out").map(URL.init(fileURLWithPath:)) ?? root.appendingPathComponent(Paths.vctkSplit)
    try ManifestJSON.encode(split).write(to: out, options: .atomic)
    print("vctk-split: \(split.tuning.count) tuning, \(split.heldOut.count) held-out, \(split.cvFolds.count) CV folds → \(out.path)")
}

/// Encodes the smoke selection (from tools/pick_smoke_set.py) as 16 kHz FLAC and writes the manifest.
func smokeBuild(_ args: Arguments) throws {
    struct Selection: Decodable {
        struct Utterance: Decodable {
            let utterance: String
            let speaker: String
            let wav: String
            let words: [SmokeManifest.Word]
        }
        struct Phrase: Decodable {
            let speaker: String
            let phrase: String
        }
        let seed: UInt64
        let speechocean762: [Utterance]
        let vctk: [Phrase]
    }
    let selection = try JSONDecoder().decode(Selection.self, from: Data(contentsOf: try args.url("selection")))
    let so762 = try args.url("so762")
    let vctk = try args.url("vctk")
    let out = try args.url("out")
    let audio = out.appendingPathComponent("audio")
    try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
    var files: [[String: Any]] = []
    func add(_ name: String, corpus: String, speaker: String, item: String, words: [SmokeManifest.Word]) throws {
        let url = audio.appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        files.append([
            "path": "audio/\(name)", "sha256": SHA256Digest.hex(of: data), "bytes": data.count, "corpus": corpus,
            "speaker": speaker, "item": item,
            "words": words.map { ["id": $0.id, "text": $0.text, "label": $0.label] },
        ])
    }
    for u in selection.speechocean762 {
        let (samples, rate) = try AudioFiles.readMono(so762.appendingPathComponent(u.wav))
        let name = "speechocean762-\(u.utterance).flac"
        try AudioFiles.writeFLAC(try AudioFiles.resample(samples, from: rate, to: 16_000), sampleRate: 16_000, to: audio.appendingPathComponent(name))
        try add(name, corpus: "speechocean762", speaker: u.speaker, item: u.utterance, words: u.words)
    }
    for p in selection.vctk {
        let source = vctk.appendingPathComponent("\(p.speaker)/\(p.speaker)_\(p.phrase).flac")
        let (samples, rate) = try AudioFiles.readMono(source)
        let name = "vctk-\(p.speaker)_\(p.phrase).flac"
        try AudioFiles.writeFLAC(try AudioFiles.resample(samples, from: rate, to: 16_000), sampleRate: 16_000, to: audio.appendingPathComponent(name))
        try add(name, corpus: "vctk", speaker: p.speaker, item: p.phrase, words: [])
    }
    let manifest: [String: Any] = ["version": 1, "seed": selection.seed, "files": files]
    var data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    data.append(Data("\n".utf8))
    try data.write(to: out.appendingPathComponent("manifest.json"))
    let total = files.reduce(0) { $0 + ($1["bytes"] as! Int) }
    print("smoke-build: \(files.count) files, \(total) bytes (cap \(SmokeManifest.maximumBytes))")
}

/// The smoke check: manifest, size cap and load time.
func smoke(root: URL) throws -> Int32 {
    let dir = root.appendingPathComponent(Paths.smoke)
    let manifest = try SmokeManifest.load(dir.appendingPathComponent("manifest.json"))
    let start = Date()
    var seconds = 0.0
    for file in manifest.files {
        let (samples, rate) = try AudioFiles.readMono(dir.appendingPathComponent(file.path))
        seconds += Double(samples.count) / rate
    }
    let elapsed = Date().timeIntervalSince(start)
    let problems = manifest.problems(in: dir)
    let limit = Thresholds.current.agreement.smokeSetMaxSeconds
    print("smoke: \(manifest.files.count) files, \(manifest.totalBytes) bytes (cap \(SmokeManifest.maximumBytes)), \(String(format: "%.1f", seconds)) s of audio loaded in \(String(format: "%.2f", elapsed)) s (limit \(Int(limit)) s)")
    for problem in problems { print("  " + problem) }
    print("smoke: never a rate gate; goldens arrive with specs 08 and 10")
    return problems.isEmpty && manifest.totalBytes <= SmokeManifest.maximumBytes && elapsed < limit ? 0 : 1
}

/// The speechocean762 shared-detector suite. Reported, not gated, and NOT EVALUATED until spec 08 wires a detector.
func l2Shared(_ args: Arguments, root: URL) throws -> Int32 {
    let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
    let sets = SpeechOceanSets(labels: labels)
    let split = try JSONDecoder().decode(
        SpeechOceanSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent(Paths.soSplit)))
    let reason = "no PlacementDetector is wired (spec 08)"
    func notEvaluated(_ name: String, _ layer: ValidationLayer, _ gate: Gate, n: Int) -> MetricResult {
        MetricResult(name: name, layer: layer, n: 0, value: nil, gate: gate, status: .notEvaluated(n: 0, minimum: n))
    }
    let metrics = [
        notEvaluated("L2 recall, pooled out-of-fold, after suppression", .cvEstimate,
                     .agreement("agreement.l2RecallMin", \.l2RecallMin, .atLeast), n: sets.recall.count),
        notEvaluated("L2 false positives, clean 1,400, after suppression", .shippedConfigCheck,
                     .agreement("agreement.l2FalsePositiveMax", \.l2FalsePositiveMax, .atMost), n: sets.cleanFalsePositive.count),
        notEvaluated("Unintelligible words with a placement diff (count)", .shippedConfigCheck,
                     .agreement("agreement.unintelligiblePlacementDiffsMax", \.unintelligiblePlacementDiffsMax, .atMost), n: sets.unintelligible.count),
    ]
    for m in metrics {
        print("\(m.layer.label): \(m.name): n=\(m.n) gate \(m.gate!.direction == .atLeast ? "≥" : "≤") \(m.gate!.bound): \(m.status.text)")
    }
    print("l2-shared: \(reason)")
    let summary = ReleaseSummary(negativeSet: nil, gated: metrics)
    for line in summary.lines { print(line) }
    if args.flag("write-report") {
        let identity = try reportIdentity(
            root: root, corpusManifestHash: pinValue(root, Paths.so762Pin, "corpusManifestSHA256"),
            labelHash: labels.sourceSHA256, splitPath: Paths.soSplit, splitSeed: split.foldSeed)
        let report = AgreementReport(
            suite: "l2-shared", generatedAt: Date(), release: args.flag("release"), identity: identity,
            metrics: metrics, summary: summary, notes: ["l2-shared: \(reason)"])
        let written = try ReportWriter.write(report, to: ReportWriter.directory(repositoryRoot: root))
        print("wrote \(written.json.path) and .md")
    }
    return 0
}

/// The VCTK positive set: pair counts from the trimmed cache. Metrics are NOT EVALUATED until spec 10.
func positive(_ args: Arguments, root: URL) throws -> Int32 {
    let manifest = try VCTKEvalSpeakersManifest.load(root.appendingPathComponent(Paths.evalSpeakers))
    let cache = args.value("vctk").map(URL.init(fileURLWithPath:))
        ?? root.appendingPathComponent("eval-cache/vctk/current")
    guard let data = try? Data(contentsOf: cache.appendingPathComponent("trim-report.json")),
        let report = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let kept = report["kept"] as? [String]
    else {
        print("positive: NOT EVALUATED (no trimmed VCTK cache: run scripts/fetch-vctk.sh)")
        return 0
    }
    let clips = Set(kept.compactMap { name -> VCTKClip? in
        let parts = name.split(separator: "_")
        return parts.count == 2 ? VCTKClip(speaker: String(parts[0]), phrase: String(parts[1])) : nil
    })
    let pairs = VCTKPairs(manifest: manifest, available: clips)
    let rejected = (report["rejected"] as? [Any])?.count ?? 0
    print("positive: \(kept.count) clips kept, \(rejected) rejected by the 2–6 s trim")
    print("positive: headline pairs \(pairs.headline.count) (\(Set(pairs.headline.map(\.phrase)).count) phrases, \(Set(pairs.headline.map(\.speaker)).count) held-out speakers), secondary pairs \(pairs.secondary.count) (correlated)")
    let shortfalls = pairs.shortfalls()
    print(shortfalls.isEmpty
        ? "positive: pair set evaluable; metrics NOT EVALUATED until spec 10 wires measures and verdicts"
        : "positive: NOT EVALUATED (\(shortfalls.joined(separator: "; ")))")
    print("VCTK CV estimate (6 folds over the 18 tuning speakers): NOT EVALUATED until spec 08")
    return 0
}

func tune(_ args: Arguments, root: URL) -> Int32 {
    let grid = TuningGrid()
    print("tune: grid of \(grid.weights.count) weight points × \(grid.lambdas.count) λ × \(grid.tauPairs.count)³ τ pairs per n-bucket = \(grid.count) points")
    print("tune: NOT RUN: the objective needs spec 08's detector and cached L1 features. Re-tunes are logged in \(Paths.tuningLog).")
    return 2
}

func usage() {
    print("""
        am-eval <command> [options]
          so762-labels --corpus <dir> [--out <tsv>]        build the label-only fixture from the fetched corpus
          sets [--corpus <dir> | --labels <tsv>] [--write-split <json>]   recount the §6.3 sets
          vctk-trim --eval-speakers <json> --raw <dir> --out <dir>         trim and cache the VCTK clips
          vctk-split [--eval-speakers <json>] [--out <json>]               write fixtures/splits/vctk.json
          smoke-build --selection <json> --so762 <dir> --vctk <dir> --out <dir>
          suite --suite smoke|l2-shared|positive [--write-report] [--release]
          tune
        """)
}

// MARK: - Main

let args = Arguments(Array(CommandLine.arguments.dropFirst()))
do {
    switch args.command {
    case "so762-labels": try so762Labels(args)
    case "sets": exit(try sets(args))
    case "vctk-trim": try vctkTrim(args)
    case "vctk-split": try vctkSplit(args)
    case "smoke-build": try smokeBuild(args)
    case "suite":
        let root = try repositoryRoot()
        switch try args.required("suite") {
        case "smoke": exit(try smoke(root: root))
        case "l2-shared": exit(try l2Shared(args, root: root))
        case "positive": exit(try positive(args, root: root))
        case let other: throw CLIError.usage("unknown suite \(other)")
        }
    case "tune": exit(tune(args, root: try repositoryRoot()))
    default:
        usage()
        exit(args.command == "help" ? 0 : 64)
    }
} catch {
    FileHandle.standardError.write(Data("am-eval: \(error)\n".utf8))
    exit(1)
}
