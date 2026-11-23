import AMAlignment
import AMTimestampEval
import Foundation

/// Spec 03 local tooling. Never run by the app, CI or `make check`; the scripts under `scripts/` call it.
/// It reads only local files: model weights, VCTK clips and MFA output are fetched by the scripts beforehand.
@main
struct AMTimestamps {
    static let usage = """
        am-timestamps <command> [options]

          record        --clips F --corpus D --manifest M --model-dir D --out D
                        Run WhisperKit on every clip and write replay JSON plus manifest.json (agreement-record).
          baseline      --clips F --mfa-output D --out F --mfa-version V --acoustic-model F --dictionary F --command S
                        Convert MFA JSON alignments into the committed word baseline.
          eval          --repo D --clips F --corpus D --manifest M --model-dir D --out D
                        [--baseline F] [--archive-pin F] [--release] [--no-comparator]
                        Run WhisperKit, compare with the baseline, write the report. Exit 1 on FAIL; on a --release
                        run, exit 2 on a dirty tree and 3 on NOT EVALUATED.
          cancel-check  --clips F --corpus D --manifest M --model-dir D
                        Cancel a transcription 100 ms in; check it returns within about 300 ms and the model stays loaded.
        """

    static func main() async {
        let arguments = CommandLine.arguments.dropFirst()
        do {
            guard let command = arguments.first else { throw ToolError.usage(usage) }
            let options = try Options(arguments.dropFirst())
            let status: Int32
            switch command {
            case "record": status = try await record(options)
            case "baseline": status = try baseline(options)
            case "eval": status = try await evaluate(options)
            case "cancel-check": status = try await cancelCheck(options)
            default: throw ToolError.usage(usage)
            }
            exit(status)
        } catch {
            log("\(error)")
            exit(64)
        }
    }

    // MARK: - Shared

    static func loadTimestamper(_ options: Options) async throws
        -> (timestamper: WhisperKitTimestamper, manifest: ModelManifest, verifyMs: Double, loadMs: Double) {
        let manifest = try ModelManifest(contentsOf: try options.url("manifest"))
        let folder = try options.url("model-dir")
        let clock = ContinuousClock()
        let verifyMs = milliseconds(try clock.measure { try manifest.verify(folder: folder) })
        let start = clock.now
        let timestamper = try await WhisperKitTimestamper.load(manifest: manifest, folder: folder)
        let loadMs = milliseconds(start.duration(to: clock.now))
        log("loaded \(manifest.asrModelID) (verify \(Int(verifyMs)) ms, load \(Int(loadMs)) ms)")
        return (timestamper, manifest, verifyMs, loadMs)
    }

    static func clips(_ options: Options) throws -> [Clip] {
        let clips = try Clip.load(list: try options.url("clips"), corpus: try options.url("corpus"))
        for clip in clips where !FileManager.default.fileExists(atPath: clip.audio.path) {
            throw ToolError.failed("missing \(clip.audio.path); run scripts/fetch-vctk.sh")
        }
        return clips
    }

    // MARK: - record

    static func record(_ options: Options) async throws -> Int32 {
        let clips = try clips(options)
        let out = try options.url("out")
        let (timestamper, manifest, _, _) = try await loadTimestamper(options)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for stale in try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
        where stale.pathExtension == "json" {
            try FileManager.default.removeItem(at: stale)
        }
        var entries: [ReplayManifest.Entry] = []
        for clip in clips {
            let samples = try WhisperKitTimestamper.samples(fromFileAt: clip.audio)
            let (text, words) = try await timestamper.transcribe(TimestampRequest(clipID: clip.id, samples: samples))
            let recording = RecordedTimestamps(
                clipID: clip.id, audioSHA256: try Digest.sha256(fileAt: clip.audio),
                asrModelID: manifest.asrModelID, text: text, words: words)
            let file = "\(clip.id).json"
            try writeJSON(recording, to: out.appending(path: file))
            entries.append(.init(clipID: clip.id, file: file,
                                 sha256: try Digest.sha256(fileAt: out.appending(path: file))))
        }
        let replay = ReplayManifest(asrModelID: manifest.asrModelID, attribution: vctkAttribution, clips: entries)
        try writeJSON(replay, to: out.appending(path: ReplayManifest.fileName))
        print("record: \(entries.count) clips → \(out.path); recordingsSHA256 \(replay.recordingsSHA256); "
              + "manifest.json SHA-256 \(try Digest.sha256(fileAt: out.appending(path: ReplayManifest.fileName)))")
        return 0
    }

    // MARK: - baseline

    static func baseline(_ options: Options) throws -> Int32 {
        let ids = try Clip.load(list: try options.url("clips"), corpus: URL(filePath: "/")).map(\.id)
        let output = try options.url("mfa-output")
        var clips: [WordBaseline.Clip] = []
        var missing: [String] = []
        for id in ids {
            let speaker = String(id.prefix { $0 != "_" })
            let candidates = [output.appending(path: "\(speaker)/\(id).json"), output.appending(path: "\(id).json")]
            guard let file = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                missing.append(id)
                continue
            }
            clips.append(.init(clipID: id, words: try MFAOutput.words(fromJSON: Data(contentsOf: file))))
        }
        let acoustic = try options.url("acoustic-model"), dictionary = try options.url("dictionary")
        let aligner = WordBaseline.Aligner(
            name: "Montreal Forced Aligner", version: try options.string("mfa-version"),
            acousticModel: acoustic.lastPathComponent, acousticModelSHA256: try Digest.sha256(fileAt: acoustic),
            dictionary: dictionary.lastPathComponent, dictionarySHA256: try Digest.sha256(fileAt: dictionary),
            command: try options.string("command"))
        let baseline = WordBaseline(aligner: aligner, attribution: vctkAttribution, clips: clips)
        let out = try options.url("out")
        try baseline.encoded().write(to: out, options: .atomic)
        print("baseline: \(clips.count) clips aligned, \(missing.count) not aligned\(missing.isEmpty ? "" : " (\(missing.joined(separator: ", ")))"); SHA-256 \(try Digest.sha256(fileAt: out))")
        return 0
    }

    // MARK: - eval

    static func evaluate(_ options: Options) async throws -> Int32 {
        let repo = try options.url("repo")
        let release = options.flag("release")
        let commit = try shell("git", "rev-parse", "HEAD", in: repo)
        let clean = try shell("git", "status", "--porcelain", in: repo).isEmpty
        if release && !clean {
            log("the working tree is dirty: a release report must come from a clean tree (commit first)")
            return 2
        }
        let sourceTreeHash = SourceTree.hash(lsTree: try shell("git", "ls-tree", "-r", "--full-tree", commit, in: repo))
        let toolchain = TimestampReport.Toolchain(
            xcode: try shell("xcodebuild", "-version").replacingOccurrences(of: "\nBuild version ", with: " build "),
            swift: try shell("swift", "--version").split(separator: "\n").first.map(String.init) ?? "",
            macOS: "\(try shell("sw_vers", "-productVersion")) (\(try shell("sw_vers", "-buildVersion")))",
            hardware: "\(try shell("sysctl", "-n", "machdep.cpu.brand_string")), \(try shell("sysctl", "-n", "hw.model"))",
            runnerImage: ProcessInfo.processInfo.environment["ImageVersion"].map {
                "\(ProcessInfo.processInfo.environment["ImageOS"] ?? "") \($0)"
            })

        let clips = try clips(options)
        let transcripts = try clips.map { try $0.text() }
        let corpusHash = CorpusHash.hash(fileSHA256s: try clips.map { try Digest.sha256(fileAt: $0.audio) })
        let archivePin = try options.optional("archive-pin").map {
            try String(contentsOf: URL(filePath: $0), encoding: .utf8).split(separator: " ").first.map(String.init)
        } ?? nil

        var notes: [String] = []
        var baseline: WordBaseline?
        var labelHash: String?
        var labelFile: String?
        if let path = options.optional("baseline"), FileManager.default.fileExists(atPath: path) {
            let url = URL(filePath: path)
            baseline = try JSONDecoder().decode(WordBaseline.self, from: Data(contentsOf: url))
            labelHash = try Digest.sha256(fileAt: url)
            labelFile = url.path.hasPrefix(repo.path + "/") ? String(url.path.dropFirst(repo.path.count + 1)) : url.lastPathComponent
        } else {
            notes.append("No forced-aligner baseline was available, so word-boundary accuracy is NOT EVALUATED.")
        }

        let (timestamper, manifest, verifyMs, loadMs) = try await loadTimestamper(options)
        var asrWords: [[WordTimestamp]] = []
        var asrMs: [Double] = []
        var clipSeconds: [Double] = []
        let clock = ContinuousClock()
        for (index, clip) in clips.enumerated() {
            let samples = try WhisperKitTimestamper.samples(fromFileAt: clip.audio)
            clipSeconds.append(Double(samples.count) / TimestampRequest.sampleRate)
            let start = clock.now
            let words = try await timestamper.wordTimestamps(for: TimestampRequest(clipID: clip.id, samples: samples))
            asrMs.append(milliseconds(start.duration(to: clock.now)))
            asrWords.append(words)
            if index % 20 == 0 { log("ASR \(index + 1)/\(clips.count)") }
        }

        let accuracy: AccuracyResult? = baseline.map { baseline in
            let spans = Dictionary(uniqueKeysWithValues: baseline.clips.map { ($0.clipID, $0.words) })
            let missing = clips.filter { spans[$0.id] == nil }.map(\.id)
            if !missing.isEmpty {
                notes.append("The baseline has no alignment for \(missing.count) clips (\(missing.joined(separator: ", "))); their tokens count as missing from the baseline.")
            }
            return Evaluation.evaluate(
                clips.indices.map {
                    ClipInput(clipID: clips[$0].id, transcript: transcripts[$0], asrWords: asrWords[$0],
                              baselineWords: spans[clips[$0].id] ?? [])
                },
                gate: .plan)
        }

        var comparator = TimestampReport.Comparator(
            name: SpeechComparator.name, status: SpeechComparator.notPresent,
            locale: SpeechComparator.locale.identifier, coverage: nil, raw: nil)
        let assets = options.flag("no-comparator") ? nil : await SpeechComparator.assetStatus()
        if let assets, !assets.installed {
            comparator.status = "\(SpeechComparator.notPresent) (AssetInventory status: \(assets.description))"
        } else if assets == nil {
            comparator.status = "not run (--no-comparator)"
        } else {
            comparator.status = "present"
            if let baseline {
                let spans = Dictionary(uniqueKeysWithValues: baseline.clips.map { ($0.clipID, $0.words) })
                var inputs: [ClipInput] = []
                for (index, clip) in clips.enumerated() {
                    inputs.append(ClipInput(
                        clipID: clip.id, transcript: transcripts[index],
                        asrWords: try await SpeechComparator.words(forFileAt: clip.audio),
                        baselineWords: spans[clip.id] ?? []))
                }
                let (words, coverage) = Evaluation.comparableWords(inputs)
                comparator.coverage = coverage
                comparator.raw = BoundaryStats(errorsMs: words.flatMap { $0.errorsMs(paddingMs: 0) },
                                               toleranceMs: TimestampGate.plan.toleranceMs)
            }
        }

        let config = ConfigIdentity.spec03(asrModelID: manifest.asrModelID)
        let digest = try ConfigDigest(config: config, thresholds: .plan)
        let timing = TimestampReport.Timing(verifyMs: verifyMs, loadMs: loadMs, asrMs: asrMs, clipSeconds: clipSeconds,
                                            budgetMs: TimestampGate.plan.asrWarmBudgetMs)
        if timing.budgetOutcome == .fail {
            notes.append("base.en is over the warm ASR budget: the plan's fallback is tiny.en, which must be pinned and gated in its own run.")
        }
        notes.append("Clips are the official VCTK 0.92 wav48_silence_trimmed mic1 files, untrimmed by this spec: no shared 02/15 trim exists yet.")
        notes.append("Comparable tokens: the longest in-order match of normalised words (lower case, punctuation stripped) against the transcript's phrase tokens, on each side. Padded spans are not clamped to the clip.")
        notes.append("configDigest covers ConfigIdentity plus the spec 03 gate (TimestampGate); spec 01's full Thresholds does not exist yet, so the digest changes when it lands.")
        let report = TimestampReport(
            generatedAt: Date(),
            identity: .init(config: config, configDigest: digest, corpusManifestHash: corpusHash,
                            labelHash: labelHash, labelFile: labelFile, sourceTreeHash: sourceTreeHash,
                            evaluatedCommit: commit, cleanTree: clean, toolchain: toolchain),
            model: .init(manifest: manifest,
                         decoding: "greedy (temperature 0, WhisperKit fallback), English, word timestamps",
                         shippingModel: timing.budgetOutcome == .fail ? "openai_whisper-tiny.en (fallback, not yet gated)" : manifest.model),
            baseline: baseline?.aligner,
            corpus: .init(name: "VCTK 0.92", archiveSHA256: archivePin, clips: clips.count,
                          speakers: Array(Set(clips.map(\.speaker))).sorted(),
                          textIDs: Array(Set(clips.map { String($0.id.split(separator: "_")[1]) })).sorted(),
                          audio: "wav48_silence_trimmed/<speaker>/<speaker>_<text>_mic1.flac, as published",
                          attribution: vctkAttribution),
            gate: .plan, accuracy: accuracy, timing: timing, comparator: comparator, notes: notes)

        let out = try options.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let json = out.appending(path: "\(report.baseName).json"), md = out.appending(path: "\(report.baseName).md")
        try report.json().write(to: json, options: .atomic)
        try Data((report.markdown() + "\n").utf8).write(to: md, options: .atomic)
        print("eval: \(report.verdict.overall.rawValue) → \(json.path), \(md.path)")
        print("eval: configDigest \(digest.sha256), sourceTreeHash \(sourceTreeHash), commit \(commit), clean \(clean)")

        switch report.verdict.overall {
        case .pass: return 0
        case .fail: return 1
        case .notEvaluated: return release ? 3 : 0
        }
    }

    // MARK: - cancel-check

    static func cancelCheck(_ options: Options) async throws -> Int32 {
        let clips = try clips(options)
        let (timestamper, _, _, _) = try await loadTimestamper(options)
        let first = try WhisperKitTimestamper.samples(fromFileAt: clips[0].audio)
        _ = try await timestamper.transcribe(TimestampRequest(clipID: clips[0].id, samples: first))
        // About a minute of speech, so decoding is still running 100 ms in.
        var long: [Float] = []
        for clip in clips.prefix(20) { long += try WhisperKitTimestamper.samples(fromFileAt: clip.audio) }
        let request = TimestampRequest(clipID: "cancel-check", samples: long)
        let clock = ContinuousClock()
        var latencies: [Double] = []
        var allCancelled = true
        for trial in 1...5 {
            let task = Task { try await timestamper.transcribe(request) }
            try await Task.sleep(for: .milliseconds(100))
            let cancelledAt = clock.now
            task.cancel()
            let result = await task.result
            let latency = milliseconds(cancelledAt.duration(to: clock.now))
            latencies.append(latency)
            let cancelled: Bool
            if case .failure(let error) = result, error is CancellationError { cancelled = true } else { cancelled = false }
            allCancelled = allCancelled && cancelled
            print("cancel-check: trial \(trial): \(cancelled ? "cancelled" : "not cancelled (\(result))"), returned \(String(format: "%.1f", latency)) ms after cancel")
        }
        let loaded = await timestamper.isLoaded
        let after = try await timestamper.transcribe(TimestampRequest(clipID: clips[0].id, samples: first))
        let worst = latencies.max() ?? .infinity
        print("cancel-check: input \(String(format: "%.1f", Double(long.count) / TimestampRequest.sampleRate)) s; worst return \(String(format: "%.1f", worst)) ms (about 300 ms allowed); model still loaded: \(loaded); next request: \"\(after.text)\"")
        let pass = allCancelled && worst <= 300 && loaded && !after.words.isEmpty
        print("cancel-check: \(pass ? "PASS" : "FAIL")")
        return pass ? 0 : 1
    }
}
