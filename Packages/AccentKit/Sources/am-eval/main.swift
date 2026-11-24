// am-eval: the agreement harness's command-line runner (spec 02). Called by scripts/agreement.sh, scripts/tune.sh and
// the corpus fetchers; never by the app, never in PR CI beyond `swift build`. No network: it reads caches only.

import AMAlignment
import AMCapture
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
    static let subPhrases = "fixtures/vctk/sub-phrases.json"
    static let subPhraseCuts = "fixtures/vctk/sub-phrase-cuts.json"
    static let smoke = "fixtures/smoke"
    static let so762Pin = "fixtures/corpora/speechocean762.pin.json"
    static let vctkPin = "fixtures/corpora/vctk.pin.json"
    static let tuningLog = "docs/agreement/tuning-log.md"
    static let smokeDetector = "fixtures/smoke/detector"
    static let mfaBaseline = "fixtures/vctk/mfa-word-baseline.json"
    /// Spec 11 §3a: each phrase's ordered native references.
    static let referenceLists = "fixtures/vctk/reference-lists.json"
    static let so762Cache = "eval-cache/speechocean762/current"
    static let so762Timings = "eval-cache/speechocean762-timings"
    static let whisperModel = "openai_whisper-base.en"
    static let vctkCache = "eval-cache/vctk/current"
    static let vctkTimings = "eval-cache/vctk-timings"
    /// Spec 11: the VCTK tuning speakers' replayed word timings (spec 22's synthref reads the same folder).
    static let vctkTuningTimings = "eval-cache/vctk-tuning-timings"
}

/// A path under `eval-cache/`, moved to `$AM_EVAL_CACHE` when that is set (spec 11: corpora, recordings and models
/// stay outside the worktree, which `make test-vm` syncs into the VM).
func cacheURL(_ root: URL, _ path: String) -> URL {
    let prefix = "eval-cache/"
    if path.hasPrefix(prefix), let cache = ProcessInfo.processInfo.environment["AM_EVAL_CACHE"], !cache.isEmpty {
        return URL(fileURLWithPath: cache).appendingPathComponent(String(path.dropFirst(prefix.count)))
    }
    return root.appendingPathComponent(path)
}

/// The identity of the configuration the harness evaluates. ASR is replayed word timings (CI never runs ASR); the
/// detector (spec 08) runs spec 05's voicing and spec 04's pYIN.
func harnessConfig() -> ConfigIdentity {
    ShippedConfig.identity(asrModelID: "replayed-word-timings")
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

/// Trims, resamples to 16 kHz and caches the VCTK clips the eval-speakers manifest names, then cuts every listed clip
/// of a split prompt into its sub-phrases at the committed MFA cuts and trims each by the same rule (spec 24).
func vctkTrim(_ args: Arguments) throws {
    let manifest = try VCTKEvalSpeakersManifest.load(try args.url("eval-speakers"))
    let table = try VCTKSubPhraseTable.load(try args.url("sub-phrases"))
    let cuts = try VCTKSubPhraseCutList.load(try args.url("cuts"))
    let raw = try args.url("raw")
    let out = try args.url("out")
    guard cuts.subPhrasesSHA256 == (try sha256(of: try args.url("sub-phrases"))) else {
        throw CLIError.failed("the cut list was made from another sub-phrase table: run scripts/vctk-sub-phrase-cuts.sh")
    }
    let rule = TrimRule()
    var kept: [VCTKClip] = []
    var rejected: [[String: String]] = []
    func trimAndWrite(_ samples: [Float], rate: Double, speaker: String, phrase: String) throws {
        switch rule.apply(samples: samples, sampleRate: rate) {
        case .keep(let range):
            let resampled = try AudioFiles.resample(Array(samples[range]), from: rate, to: 16_000)
            try AudioFiles.writeFLAC(
                resampled, sampleRate: 16_000,
                to: out.appendingPathComponent("\(speaker)/\(speaker)_\(phrase).flac"))
            kept.append(VCTKClip(speaker: speaker, phrase: phrase))
        case .noSpeech:
            rejected.append(["speaker": speaker, "phrase": phrase, "stage": "trim", "reason": "no speech"])
        case .outOfRange(let seconds):
            rejected.append([
                "speaker": speaker, "phrase": phrase, "stage": "trim",
                "reason": String(format: "%.2f s outside 2–6 s", seconds),
            ])
        }
    }
    for entry in manifest.bundled + manifest.speakers {
        let dir = out.appendingPathComponent(entry.speaker)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for phrase in VCTK.phrases where entry.files[phrase] != nil {
            let source = raw.appendingPathComponent("\(entry.speaker)/\(entry.speaker)_\(phrase)_mic1.flac")
            guard (try? sha256(of: source)) == entry.files[phrase] else {
                throw CLIError.failed("\(source.lastPathComponent): SHA-256 does not match eval-speakers.json")
            }
            let (samples, rate) = try AudioFiles.readMono(source)
            try trimAndWrite(samples, rate: rate, speaker: entry.speaker, phrase: phrase)
        }
    }
    // Sub-phrases: cut at the committed times (MFA word span extended into the neighbouring silence, clamped to the
    // clip), then the same trim (spec 24).
    let subPhrases = Dictionary(uniqueKeysWithValues: table.subPhrases.map { ($0.id, $0) })
    for entry in cuts.entries {
        guard let sub = subPhrases[entry.subPhrase] else {
            throw CLIError.failed("cut list names \(entry.subPhrase), which the sub-phrase table doesn't define")
        }
        let base = ["speaker": entry.speaker, "phrase": sub.id]
        switch entry.outcome {
        case .cut(let start, let end, _, _, _):
            let source = raw.appendingPathComponent("\(entry.speaker)/\(entry.speaker)_\(sub.prompt)_mic1.flac")
            let (samples, rate) = try AudioFiles.readMono(source)
            let range = min(samples.count, Int((start * rate).rounded()))..<min(samples.count, Int((end * rate).rounded()))
            try trimAndWrite(Array(samples[range]), rate: rate, speaker: entry.speaker, phrase: sub.id)
        case .mfaMismatch(let words):
            rejected.append(base.merging(["stage": "mfa", "reason": "MFA words don't contain the sub-phrase once: \(words.joined(separator: " "))"]) { $1 })
        case .noAlignment:
            rejected.append(base.merging(["stage": "mfa", "reason": "no MFA alignment"]) { $1 })
        case .transcriptMismatch:
            rejected.append(base.merging(["stage": "transcript", "reason": "transcript doesn't contain the sub-phrase: not listed"]) { $1 })
        }
    }
    let report: [String: Any] = [
        "kept": kept.map { "\($0.speaker)_\($0.phrase)" }.sorted(), "rejected": rejected,
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: out.appendingPathComponent("trim-report.json"))
    print("vctk-trim: kept \(kept.count), rejected \(rejected.count)")
    for r in rejected { print("  rejected \(r["speaker"]!)_\(r["phrase"]!) (\(r["stage"]!)): \(r["reason"]!)") }
    for line in PositiveSetCounts(manifest: manifest, table: table, kept: kept, rejected: rejected).lines {
        print("vctk-trim: \(line)")
    }
}

/// The positive set's counts as the trim left them (spec 24): phrases and distinct source prompts, headline pairs,
/// held-out speakers, per-phrase rejections and the minimums.
struct PositiveSetCounts {
    let pairs: VCTKPairs
    let lines: [String]

    init(manifest: VCTKEvalSpeakersManifest, table: VCTKSubPhraseTable, kept: [VCTKClip], rejected: [[String: String]]) {
        let phrases = table.evaluationPhrases
        pairs = VCTKPairs(manifest: manifest, available: Set(kept), phrases: phrases)
        func clips(_ stage: String) -> [VCTKClip] {
            rejected.filter { $0["stage"] == stage }.compactMap { r in
                r["speaker"].flatMap { s in r["phrase"].map { VCTKClip(speaker: s, phrase: $0) } }
            }
        }
        var lines = ["\(kept.count) clips kept; \(clips("trim").count) rejected by the 2–6 s trim, "
            + "\(clips("mfa").count) by MFA mismatch, \(clips("transcript").count) not listed (transcript)"]
        lines += VCTKPairs.rejectionsByPhrase(
            trimmed: clips("trim"), misaligned: clips("mfa"), phrases: (phrases + table.splitPrompts).sorted(),
            manifest: manifest
        ).map { "rejections \($0)" }
        lines.append(
            "phrases kept \(pairs.phraseCount) from \(pairs.sourcePromptCount) distinct source prompts "
                + "(\(table.subPhrases.count) sub-phrases of \(table.splitPrompts.sorted().joined(separator: ", ")) replace those prompts); "
                + "headline pairs \(pairs.headline.count); held-out speakers \(pairs.heldOutSpeakerCount); "
                + "secondary pairs \(pairs.secondary.count) (correlated)")
        lines += pairs.minimums().map { "minimum \($0.line)" }
        self.lines = lines
    }
}

/// Builds fixtures/vctk/sub-phrase-cuts.json from the MFA alignments scripts/mfa-align.sh wrote (spec 24). Local
/// only: CI replays the committed cut list and never runs MFA.
func vctkSubPhraseCuts(_ args: Arguments) throws {
    struct Alignments: Decodable {
        struct Clip: Decodable {
            let clipID: String
            let words: [VCTKTimedWord]
        }
        let aligner: [String: String]
        let clips: [Clip]
    }
    let root = try repositoryRoot()
    let tablePath = args.value("sub-phrases").map(URL.init(fileURLWithPath:)) ?? root.appendingPathComponent(Paths.subPhrases)
    let manifestPath = args.value("eval-speakers").map(URL.init(fileURLWithPath:)) ?? root.appendingPathComponent(Paths.evalSpeakers)
    let table = try VCTKSubPhraseTable.load(tablePath)
    let manifest = try VCTKEvalSpeakersManifest.load(manifestPath)
    let problems = table.problems(phraseText: manifest.phraseText ?? [:])
    guard problems.isEmpty else { throw CLIError.failed("sub-phrase table: " + problems.joined(separator: "; ")) }
    let alignmentsPath = try args.url("alignments")
    let alignments = try JSONDecoder().decode(Alignments.self, from: Data(contentsOf: alignmentsPath))
    let transcripts = try args.url("transcripts")
    var texts: [String: String] = [:]
    for entry in manifest.bundled + manifest.speakers {
        for prompt in table.splitPrompts where entry.files[prompt] != nil {
            let clip = "\(entry.speaker)_\(prompt)"
            texts[clip] = try String(
                contentsOf: transcripts.appendingPathComponent("\(entry.speaker)/\(clip).txt"), encoding: .utf8)
        }
    }
    let list = VCTKSubPhraseCutList.make(
        table: table, manifest: manifest, transcripts: texts,
        alignments: Dictionary(uniqueKeysWithValues: alignments.clips.map { ($0.clipID, $0.words) }),
        subPhrasesSHA256: try sha256(of: tablePath), alignmentsSHA256: try sha256(of: alignmentsPath),
        aligner: alignments.aligner)
    let out = args.value("out").map(URL.init(fileURLWithPath:)) ?? root.appendingPathComponent(Paths.subPhraseCuts)
    try ManifestJSON.encode(list).write(to: out, options: .atomic)
    var tally: [String: [String: Int]] = [:]
    for entry in list.entries {
        let kind: String = switch entry.outcome {
        case .cut: "cut"
        case .mfaMismatch, .noAlignment: "MFA mismatch"
        case .transcriptMismatch: "not listed (transcript)"
        }
        tally[entry.subPhrase, default: [:]][kind, default: 0] += 1
    }
    for (sub, kinds) in tally.sorted(by: { $0.key < $1.key }) {
        print("vctk-sub-phrase-cuts: \(sub): " + kinds.sorted(by: { $0.key < $1.key }).map { "\($0.value) \($0.key)" }.joined(separator: ", "))
    }
    print("vctk-sub-phrase-cuts: \(list.entries.count) entries → \(out.path)")
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
    print("smoke: never a rate gate; placement goldens: `am-eval smoke-detector` (spec 08), verdicts with spec 10")
    return problems.isEmpty && manifest.totalBytes <= SmokeManifest.maximumBytes && elapsed < limit ? 0 : 1
}

/// The speechocean762 shared-detector suite (§6.3). Reported, not gated (gating is spec 11): every line reads
/// REPORTED, never PASS. Runs spec 08's detector over replayed word timings (`am-eval record-timings --set l2-shared`).
func l2Shared(_ args: Arguments, root: URL) async throws -> Int32 {
    let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
    let sets = SpeechOceanSets(labels: labels)
    let split = try JSONDecoder().decode(
        SpeechOceanSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent(Paths.soSplit)))
    let corpusDir = args.value("corpus").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.so762Cache)
    let timingsDir = args.value("timings").map(URL.init(fileURLWithPath:))
        ?? cacheURL(root, Paths.so762Timings)
    let suites: [(name: String, words: [SpeechOceanWord], layer: ValidationLayer, key: String)] = [
        ("L2 recall (stress-wrong words), after suppression", sets.recall, .descriptive, "recall"),
        ("L2 false positives, clean 1,400, after suppression", sets.cleanFalsePositive, .shippedConfigCheck, "clean"),
        ("Unintelligible words with a placement diff (count)", sets.unintelligible, .shippedConfigCheck, "unintelligible"),
    ]
    var metrics: [MetricResult] = []
    var notes: [String] = []
    let manifestURL = timingsDir.appendingPathComponent(ReplayManifest.fileName)
    if FileManager.default.fileExists(atPath: corpusDir.appendingPathComponent("resource/text-phone").path),
        FileManager.default.fileExists(atPath: manifestURL.path)
    {
        let corpus = try SpeechOceanCorpusFiles(root: corpusDir)
        let detector = ReplayedPlacementDetector(
            corpus: corpus, timings: try FixtureTimestamper(directory: timingsDir),
            refPhones: Dictionary(labels.words.map { ($0.id, $0.refPhones) }, uniquingKeysWith: { first, _ in first }),
            dictionary: try .bundled())
        let runner = SharedDetectorRunner(
            detector: detector, corpus: corpus, dictionary: SelectorPrimaryLookup(selector: try .bundled()))
        let config = try FoldConfig(identity: harnessConfig(), thresholds: .current)
        print("l2-shared: spec 08 detector, initial thresholds (untuned; the fold-tuned CV estimate is spec 11), config \(config.digest.prefix(12))")
        for suite in suites {
            let results = try await runner.run(suite.words, config: config)
            let before = results.units(afterSuppression: false).count(where: \.hit)
            let after = results.units(afterSuppression: true).count(where: \.hit)
            let present = results.comparable.count
            var reasons: [PlacementSuppression: Int] = [:]
            for row in results.rows {
                if let outcome = row.outcome, outcome.present, outcome.flaggedBeforeSuppression,
                    let reason = outcome.suppression
                {
                    reasons[reason, default: 0] += 1
                }
            }
            let reasonText = PlacementSuppression.allCases.compactMap { r in reasons[r].map { "\(r.rawValue) \($0)" } }
                .joined(separator: ", ")
            print("l2-shared: \(suite.key): n=\(suite.words.count), excluded (no A(w)) \(results.excluded.count), present \(present); flagged before suppression \(before), after \(after)\(reasonText.isEmpty ? "" : " (suppressed: \(reasonText))")")
            notes.append("\(suite.key): n=\(suite.words.count), present \(present), before \(before), after \(after)")
            let n = suite.words.count
            let isCount = suite.key == "unintelligible"
            let value = isCount ? Double(after) : (n == 0 ? nil : Double(after) / Double(n))
            let intervals = isCount || n == 0
                ? [] : [Statistics.wilson(successes: after, n: n)]
            metrics.append(MetricResult(
                name: suite.name, layer: suite.layer, n: n, value: value, gate: nil, status: .reported,
                intervals: intervals))
            if isCount { print("l2-shared: \(n) unintelligible: \(after) placement diffs") }
        }
    } else {
        let reason = "no fetched corpus or recorded word timings (scripts/fetch-speechocean762.sh, then am-eval record-timings --set l2-shared)"
        print("l2-shared: NOT EVALUATED: \(reason)")
        notes.append("l2-shared: \(reason)")
        metrics = suites.map {
            MetricResult(name: $0.name, layer: $0.layer, n: 0, value: nil, gate: nil,
                         status: .notEvaluated(n: 0, minimum: $0.words.count))
        }
    }
    for m in metrics {
        let value = m.value.map { $0 >= 1 || $0 == 0 ? String(format: "%.0f", $0) : String(format: "%.4f", $0) } ?? "–"
        let interval = m.intervals.first.map { " [\(String(format: "%.4f, %.4f", $0.lower, $0.upper))] Wilson 95%, \($0.label)" } ?? ""
        print("\(m.layer.label): \(m.name): n=\(m.n) value \(value)\(interval): \(m.status.text)")
    }
    print("l2-shared: reported, not gated (gating is spec 11)")
    let summary = ReleaseSummary(negativeSet: nil, gated: [])
    for line in summary.lines { print(line) }
    if args.flag("write-report") {
        let identity = try reportIdentity(
            root: root, corpusManifestHash: pinValue(root, Paths.so762Pin, "corpusManifestSHA256"),
            labelHash: labels.sourceSHA256, splitPath: Paths.soSplit, splitSeed: split.foldSeed)
        let report = AgreementReport(
            suite: "l2-shared", generatedAt: Date(), release: args.flag("release"), identity: identity,
            metrics: metrics, summary: summary, notes: notes)
        let written = try ReportWriter.write(report, to: ReportWriter.directory(repositoryRoot: root))
        print("wrote \(written.json.path) and .md")
    }
    return 0
}

/// The positive set's result: its gate lines (with §3a accounting), the reported anomaly line, notes and status.
struct PositiveResult {
    var status: PositiveSetStatus
    var lines: [MetricResult]
    var anomaly: MetricResult
    var notes: [String]
    var run: PositiveRun
    var headlinePairs: Int
}

/// The VCTK positive set (specs 09, 10, 12; spec 11 §3a): every held-out take with a kept clip, scored by the
/// analyzer against the first listed reference usable for every phrase word.
func positiveResult(_ args: Arguments, root: URL, prefix: String = "positive") async throws -> PositiveResult? {
    let manifest = try VCTKEvalSpeakersManifest.load(root.appendingPathComponent(Paths.evalSpeakers))
    let cacheDir = args.value("vctk").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.vctkCache)
    guard let cache = PositiveCache(cacheDir) else {
        print("\(prefix): NOT EVALUATED (no trimmed VCTK cache: run scripts/fetch-vctk-eval.sh)")
        return nil
    }
    let table = try VCTKSubPhraseTable.load(root.appendingPathComponent(Paths.subPhrases))
    let counts = PositiveSetCounts(manifest: manifest, table: table, kept: cache.kept, rejected: cache.rejected)
    for line in counts.lines { print("\(prefix): \(line)") }
    let status = counts.pairs.status()
    print("\(prefix): \(status.text)")

    let lists = try VCTKReferenceLists.load(root.appendingPathComponent(Paths.referenceLists))
    let listProblems = lists.problems(manifest: manifest)
    guard listProblems.isEmpty else { throw CLIError.failed("reference lists: " + listProblems.joined(separator: "; ")) }
    for short in lists.shortLists { print("\(prefix): reference list short: \(short)") }
    let timingsDir = args.value("timings").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.vctkTimings)
    var notes: [String] = []
    var run = PositiveRun()
    let pairs = referencedPairs(
        speakers: manifest.heldOutSpeakers.map(\.id), available: Set(cache.kept), phrases: table.evaluationPhrases)
    if FileManager.default.fileExists(atPath: timingsDir.appendingPathComponent(ReplayManifest.fileName).path) {
        var parts = [try FixtureTimestamper(directory: timingsDir)]
        let tuningTimings = cacheURL(root, Paths.vctkTuningTimings)
        if FileManager.default.fileExists(atPath: tuningTimings.appendingPathComponent(ReplayManifest.fileName).path) {
            parts.append(try FixtureTimestamper(directory: tuningTimings))
        }
        let timings = ReplayUnion(parts: parts)
        print("\(prefix): analysing \(pairs.count) held-out takes through the pipeline (spec 12) against the §3a reference lists, word timings replayed from \(timings.asrModelID)")
        let references = try await ReferencedPhrases.build(
            phrases: Set(pairs.map(\.phrase)), lists: lists, cache: cacheDir, available: Set(cache.kept),
            phrases: try PositivePhrases(root: root, manifest: manifest, table: table), timings: timings)
        run = try await PositiveRun.run(pairs: pairs, references: references)
        notes.append("pipeline: spec 12 Analyzer, word timings replayed from \(timings.asrModelID), pYIN pitch, spec 10 scoring; references: fixtures/vctk/reference-lists.json (§3a), first listed reference usable for every phrase word; natives (A(w), band) = the phrase's analysed references but the take's speaker")
        let served = Dictionary(grouping: run.accounts.compactMap(\.reference), by: { $0 }).mapValues(\.count)
        notes.append("references serving pairs: " + served.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        var skips: [String: Int] = [:]
        for a in run.accounts { for (_, reason) in a.skipped { skips[reason.rawValue, default: 0] += 1 } }
        notes.append("references skipped before the one used (first unusable word's reason): " + skips.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    } else {
        let reason = "no recorded word timings at \(timingsDir.path) (am-eval record-timings --set positive)"
        print("\(prefix): pairs not analysed: \(reason)")
        notes.append(reason)
    }
    notes += lists.shortLists.map { "reference list short (§3a minimum 3): \($0)" }
    var measured = PositiveGates.measured(run.outcomes)
    measured[BandCoverageGate.dependent().name] = BandCoverageGate.measured(run.band)
    let accounting = run.accounting()
    let lines = PositiveSetGates.dependents().map { dependent in
        PositiveSetGates.line(dependent, positiveSet: status, measured: measured[dependent.name], pairs: pairs.count)
            .with(accounting: accounting[dependent.name])
    }
    for m in lines { print("\(prefix): \(describePositive(m))") }
    for row in PositiveGates.coverageByMeasure(run.outcomes) {
        let line = "evaluation coverage, \(row.measure.rawValue): \(String(format: "%.3f", row.coverage)) of \(row.applicable) applicable"
        print("\(prefix): \(line)")
        notes.append(line)
    }
    let anomaly = PositiveGates.referenceAnomaly(run.outcomes, positiveSet: status)
    print("\(prefix): \(describePositive(anomaly.line)) (reported, not a release gate)")
    if !anomaly.reviewPhrases.isEmpty {
        notes.append("override review (referenceAnomaly ≥ 20%): \(anomaly.reviewPhrases.joined(separator: ", "))")
    }
    let decisions = Dictionary(grouping: run.outcomes) { outcome -> String in
        switch outcome.decision {
        case .takeProblem(let problem): "takeProblem(\(problem.rawValue))"
        case .verdict(.feedback): "feedback"
        case .verdict(.close): "close"
        case .verdict(.noClearDifference): "noClearDifference"
        case .verdict(.inconclusive): "inconclusive"
        }
    }.mapValues(\.count).sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    let measuredLine = "pairs measured: scoring \(run.outcomes.count), band coverage \(run.band.count) of \(pairs.count) held-out takes (\(decisions.isEmpty ? "none" : decisions)); thresholds digest \(try configDigest(harnessConfig()).prefix(8))"
    print("\(prefix): \(measuredLine)")
    notes.append(measuredLine)
    for (reason, count) in run.unscored.sorted(by: { $0.key < $1.key }) {
        print("\(prefix): not scored: \(count) \(reason)")
        notes.append("not scored: \(count) \(reason)")
    }
    if run.noBandCoverage > 0 {
        notes.append("scored with no band coverage (no comparable voiced frame): \(run.noBandCoverage)")
    }
    return PositiveResult(
        status: status, lines: lines, anomaly: anomaly.line, notes: notes, run: run, headlinePairs: pairs.count)
}

func describePositive(_ m: MetricResult) -> String {
    let value = m.value.map { String(format: "%.3f", $0) } ?? "–"
    let gate = m.gate.map { " gate \($0.direction == .atLeast ? "≥" : "≤") \($0.bound)" } ?? ""
    func f(_ x: Double) -> String { String(format: "%.3f", x) }
    let interval = m.intervals.map { "\($0.label) [\(f($0.lower)), \(f($0.upper))]" }.joined(separator: "; ")
    let worstSpeaker = m.worstSpeaker.map { "\($0.id) \(f($0.value)) (n \($0.n))" } ?? "–"
    let worstPhrase = m.worstPhrase.map { "\($0.id) \(f($0.value)) (n \($0.n))" } ?? "–"
    let accounting = m.accounting.map { "; \($0.text)" } ?? ""
    return "\(m.name): n \(m.n), value \(value),\(gate), interval \(interval.isEmpty ? "–" : interval), worst speaker \(worstSpeaker), worst phrase \(worstPhrase): \(m.status.text)\(accounting)"
}

/// `suite --suite positive`: the positive set alone (spec 12's report, with spec 11's references).
func positive(_ args: Arguments, root: URL) async throws -> Int32 {
    guard let result = try await positiveResult(args, root: root) else { return 0 }
    let summary = ReleaseSummary(negativeSet: nil, positiveSet: result.status, gated: result.lines)
    for line in summary.lines { print(line) }
    if args.flag("write-report") {
        let manifest = try VCTKEvalSpeakersManifest.load(root.appendingPathComponent(Paths.evalSpeakers))
        let split = try JSONDecoder().decode(
            VCTKSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent(Paths.vctkSplit)))
        let identity = try reportIdentity(
            root: root, corpusManifestHash: manifest.corpusManifestHash,
            labelHash: try sha256(of: root.appendingPathComponent(Paths.evalSpeakers)), splitPath: Paths.vctkSplit,
            splitSeed: split.foldSeed)
        let report = AgreementReport(
            suite: "positive", generatedAt: Date(), release: args.flag("release"), identity: identity,
            metrics: result.lines + [result.anomaly], summary: summary, notes: result.notes)
        let written = try ReportWriter.write(report, to: ReportWriter.directory(repositoryRoot: root))
        print("wrote \(written.json.path) and .md")
    }
    return 0
}

/// Writes fixtures/vctk/reference-lists.json from the trimmed cache's kept clips (§3a; availability only).
func vctkReferenceLists(_ args: Arguments, root: URL) throws -> Int32 {
    let path = root.appendingPathComponent(Paths.evalSpeakers)
    let manifest = try VCTKEvalSpeakersManifest.load(path)
    let cacheDir = args.value("vctk").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.vctkCache)
    guard let cache = PositiveCache(cacheDir) else { throw CLIError.failed("no trimmed VCTK cache at \(cacheDir.path)") }
    let table = try VCTKSubPhraseTable.load(root.appendingPathComponent(Paths.subPhrases))
    let lists = VCTKReferenceLists.make(
        manifest: manifest, available: Set(cache.kept), phrases: table.evaluationPhrases.sorted(),
        evalSpeakersSHA256: try sha256(of: path))
    let problems = lists.problems(manifest: manifest)
    for problem in problems + lists.shortLists { print("vctk-reference-lists: \(problem)") }
    try ManifestJSON.encode(lists).write(to: root.appendingPathComponent(Paths.referenceLists), options: .atomic)
    print("vctk-reference-lists: \(lists.phrases.count) phrases → \(Paths.referenceLists)")
    return problems.isEmpty ? 0 : 1
}

func usage() {
    print("""
        am-eval <command> [options]
          so762-labels --corpus <dir> [--out <tsv>]        build the label-only fixture from the fetched corpus
          sets [--corpus <dir> | --labels <tsv>] [--write-split <json>]   recount the §6.3 sets
          vctk-trim --eval-speakers <json> --sub-phrases <json> --cuts <json> --raw <dir> --out <dir>
                                                           trim and cache the VCTK clips and sub-phrases
          vctk-sub-phrase-cuts --alignments <json> --transcripts <dir> [--sub-phrases <json>] [--eval-speakers <json>] [--out <json>]
                                                           write the sub-phrase cut list from MFA alignments
          vctk-split [--eval-speakers <json>] [--out <json>]               write fixtures/splits/vctk.json
          smoke-build --selection <json> --so762 <dir> --vctk <dir> --out <dir>
          suite --suite smoke|l2-shared|positive|release [--write-report] [--release] [--tuning <json>] [--guard <json>] [--guard-initial <json>]
          tune [--guard <spec11-guard tuning JSON>] [--limit <n>] [--spot-checks <n>]
                                                           spec 11: the fixed-grid fit, the nested CV and the VCTK CV
          vctk-reference-lists [--vctk <dir>]             spec 11 §3a: write fixtures/vctk/reference-lists.json
          guard-inputs --scope tuning|held-out --out <dir> [--vctk <dir>]
                                                           spec 11: the guard's VCTK clips, MFA input corpus and inputs JSON
          record-timings --set smoke|l2-shared|l2-tuning|positive|vctk-tuning [--corpus <so762 dir>] [--vctk <dir>] [--model-dir <dir>] [--out <dir>] [--append]
                                                           run WhisperKit once and save replayable word timings (local only)
          starter-build --phrases <json> --eval-speakers <json> --raw <dir> --timings <dir> --out <dir>
                                                           build Resources/Starter (spec 15; scripts/build-starter.sh)
          bench [--runs <n>] [--model-dir <dir>]           spec 12 latency: L_stop, L_speech, L2 recompute (real WhisperKit, local only)
          smoke-detector [--build-inputs --corpus <so762 dir>] [--record]
                                                           check (or record) the smoke set's L1 digests and placements
          nucleus-jitter --span <run> --nucleus <run> [--write-report] [--summary <file>]
                                                           spec 25 acceptance 1 from two spec11-guard --rows jitter runs
        """)
}

// MARK: - Main

setlinebuf(stdout)  // progress reaches a tee'd log as it happens
let args = Arguments(Array(CommandLine.arguments.dropFirst()))
do {
    switch args.command {
    case "so762-labels": try so762Labels(args)
    case "sets": exit(try sets(args))
    case "vctk-trim": try vctkTrim(args)
    case "vctk-split": try vctkSplit(args)
    case "vctk-sub-phrase-cuts": try vctkSubPhraseCuts(args)
    case "smoke-build": try smokeBuild(args)
    case "suite":
        let root = try repositoryRoot()
        switch try args.required("suite") {
        case "smoke": exit(try smoke(root: root))
        case "l2-shared": exit(try await l2Shared(args, root: root))
        case "positive": exit(try await positive(args, root: root))
        case "release": exit(try await release(args, root: root))
        case let other: throw CLIError.usage("unknown suite \(other)")
        }
    case "tune": exit(try await tune(args, root: try repositoryRoot()))
    case "guard-inputs": exit(try guardInputs(args, root: try repositoryRoot()))
    case "vctk-reference-lists": exit(try vctkReferenceLists(args, root: try repositoryRoot()))
    case "record-timings": exit(try await recordTimingsCommand(args, root: try repositoryRoot()))
    case "smoke-detector": exit(try await smokeDetector(args, root: try repositoryRoot()))
    case "bench": exit(try await bench(args, root: try repositoryRoot()))
    case "starter-build": exit(try await starterBuild(args))
    case "nucleus-jitter": exit(try await nucleusJitter(args, root: try repositoryRoot()))
    default:
        usage()
        exit(args.command == "help" ? 0 : 64)
    }
} catch {
    FileHandle.standardError.write(Data("am-eval: \(error)\n".utf8))
    exit(1)
}
