import AMAlignment
import AMCore
import AMPitch
import AMProsody
import AMTimestampEval
import Foundation

/// Spec 23: refine spec 03's Whisper words with each aligner and judge them against the MFA baseline.
extension AMTimestamps {
    /// Seed of the correlation gate's bootstrap (recorded in the report).
    static let correlationSeed: UInt64 = 23

    static func boundaries(_ options: Options) async throws -> Int32 {
        let repo = try options.url("repo")
        let release = options.flag("release")
        let commit = try shell("git", "rev-parse", "HEAD", in: repo)
        let clean = try shell("git", "status", "--porcelain", in: repo).isEmpty
        if release && !clean {
            log("the working tree is dirty: a release report must come from a clean tree (commit first)")
            return 2
        }
        let sourceTreeHash = SourceTree.hash(lsTree: try shell("git", "ls-tree", "-r", "--full-tree", commit, in: repo))
        let (clips, absentClips) = try clips(options)
        let transcripts = try clips.map { try $0.text() }
        let corpusHash = CorpusHash.hash(fileSHA256s: try clips.map { try Digest.sha256(fileAt: $0.audio) })
        let archivePin = try options.optional("archive-pin").map {
            try String(contentsOf: URL(filePath: $0), encoding: .utf8).split(separator: " ").first.map(String.init)
        } ?? nil
        let baselineURL = try options.url("baseline")
        let baseline = try JSONDecoder().decode(WordBaseline.self, from: Data(contentsOf: baselineURL))
        let spans = Dictionary(uniqueKeysWithValues: baseline.clips.map { ($0.clipID, $0.words) })

        let replayURL = try options.url("replay")
        let whisper = try FixtureTimestamper(directory: replayURL)
        let recordRoot = options.optional("record").map { URL(filePath: $0) }

        var samples: [[Float]] = []
        var whisperWords: [[WordTimestamp]] = []
        for clip in clips {
            samples.append(try WhisperKitTimestamper.samples(fromFileAt: clip.audio))
            whisperWords.append(try await whisper.wordTimestamps(for: TimestampRequest(clipID: clip.id, samples: [])))
        }
        log("loaded \(clips.count) clips and their Whisper words from \(replayURL.lastPathComponent)")

        let refiners: [any WordBoundaryRefiner] = [WhisperOnly(), DSPSnapRefiner()]
        var aligners: [WordBoundaryReport.Aligner] = []
        var notes: [String] = []
        let clock = ContinuousClock()
        for refiner in refiners {
            var refined: [[WordTimestamp]] = []
            var times: [Double] = []
            var startRules: [String: Int] = [:], endRules: [String: Int] = [:]
            for index in clips.indices {
                let start = clock.now
                let words: [WordTimestamp]
                if let snap = refiner as? DSPSnapRefiner {
                    let snapped = try await snap.snap(whisperWords[index], samples: samples[index],
                                                      sampleRate: TimestampRequest.sampleRate)
                    for rule in snapped.startRules { startRules[rule.rawValue, default: 0] += 1 }
                    for rule in snapped.endRules { endRules[rule.rawValue, default: 0] += 1 }
                    words = snapped.words
                } else {
                    words = try await refiner.refine(whisperWords[index], samples: samples[index],
                                                     sampleRate: TimestampRequest.sampleRate)
                }
                times.append(milliseconds(start.duration(to: clock.now)))
                refined.append(words)
            }
            let replay = try recordOrCheck(refiner.id, clips: clips, refined: refined, whisperReplay: replayURL,
                                           asrModelID: whisper.asrModelID, recordRoot: recordRoot, repo: repo)
            let accuracy = Evaluation.evaluate(clips.indices.map {
                ClipInput(clipID: clips[$0].id, transcript: transcripts[$0], asrWords: refined[$0],
                          baselineWords: spans[clips[$0].id] ?? [])
            }, gate: .plan)
            let pairs = zip(whisperWords.joined(), refined.joined())
            let moved = pairs.reduce(0) { $0 + ($1.0.start != $1.1.start ? 1 : 0) + ($1.0.end != $1.1.end ? 1 : 0) }
            let boundaryCount = 2 * whisperWords.joined().count
            let config = identity(asrModelID: whisper.asrModelID, aligner: refiner.id)
            aligners.append(WordBoundaryReport.Aligner(
                id: refiner.id, config: config, configDigest: try configDigest(config), accuracy: accuracy,
                latency: .init(Array(times.dropFirst())),
                rules: refiner is DSPSnapRefiner ? .init(starts: startRules, ends: endRules) : nil,
                replay: replay, movedShare: boundaryCount == 0 ? nil : Double(moved) / Double(boundaryCount)))
            log("\(refiner.id): starts \(accuracy.starts.outcome.rawValue) (median \(accuracy.starts.stats.medianErrorMs ?? .nan) ms), ends \(accuracy.ends.outcome.rawValue) (median \(accuracy.ends.stats.medianErrorMs ?? .nan) ms)")
        }

        // Spec 02's unmodified-control and sham-control pairs are not on this machine: spec 02 has not merged.
        let correlation = CorrelationGate.notEvaluated(
            "Spec 02's unmodified-control and sham-control sets are not on this machine (spec 02 is not merged), so Δr cannot be computed. NOT EVALUATED is not a pass.",
            seed: correlationSeed)
        let snapBar = aligners.first { $0.id == DSPSnapRefiner.aligner }?.bar.outcome ?? .notEvaluated
        let decision = BoundaryDecision.decide(
            b1Bar: snapBar, b1Correlation: correlation.outcome, b2Bar: nil,
            b1ID: DSPSnapRefiner.aligner, b2ID: "ctc-w2v2b960-1", fallbackID: WhisperOnly.aligner)

        let config = identity(asrModelID: whisper.asrModelID, aligner: decision.shippedAligner)
        let digest = try ConfigDigestRecord(config: config)
        notes.append("Whisper words are spec 03's committed replay of WhisperKit base.en on these clips (`fixtures/timestamps/\(replayURL.lastPathComponent)`), so no ASR runs here; refiners read the same 16 kHz audio WhisperKit was given.")
        notes.append("The gate is spec 03's: unpadded starts and ends judged separately against `wordTimestamps.*`, pooled and for every speaker. The clips are spec 03's set (the 8 bundled voices); spec 02's 12 held-out speakers are not on main.")
        notes.append("No b1 constant was tuned: `intensityDropDB` is the spec default (10 dB) because spec 02's tuning split is not on main.")
        if !absentClips.isEmpty {
            notes.append("\(absentClips.count) specified clips are not in the VCTK 0.92 archive (\(absentClips.joined(separator: ", "))), as in spec 03.")
        }
        let report = WordBoundaryReport(
            generatedAt: Date(),
            identity: .init(config: config, configDigest: digest, corpusManifestHash: corpusHash,
                            labelHash: try Digest.sha256(fileAt: baselineURL),
                            labelFile: relative(baselineURL, to: repo), sourceTreeHash: sourceTreeHash,
                            evaluatedCommit: commit, cleanTree: clean, toolchain: try toolchain()),
            asrModelID: whisper.asrModelID,
            whisperSource: "spec 03 replay `\(relative(replayURL, to: repo))`",
            baseline: baseline.aligner,
            corpus: .init(name: "VCTK 0.92", archiveSHA256: archivePin, specifiedClips: clips.count + absentClips.count,
                          absentClips: absentClips, clips: clips.count,
                          speakers: Array(Set(clips.map(\.speaker))).sorted(),
                          textIDs: Array(Set(clips.map { String($0.id.split(separator: "_")[1]) })).sorted(),
                          audio: "wav48_silence_trimmed/<speaker>/<speaker>_<text>_mic1.flac, as published",
                          attribution: vctkAttribution),
            aligners: aligners, correlation: correlation, decision: decision, notes: notes)

        let out = try options.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let json = out.appending(path: "\(report.baseName).json"), md = out.appending(path: "\(report.baseName).md")
        try report.json().write(to: json, options: .atomic)
        try Data((report.markdown() + "\n").utf8).write(to: md, options: .atomic)
        print("boundaries: \(report.decision.outcome.rawValue) (ships \(decision.shippedAligner)) → \(json.path), \(md.path)")
        print("boundaries: configDigest \(digest.sha256), sourceTreeHash \(sourceTreeHash), commit \(commit), clean \(clean)")
        if aligners.contains(where: { $0.replay?.matchesRecording == false }) {
            log("a run's boundaries differ from the recorded replay: re-record with --record")
            return 4
        }
        return report.decision.outcome == .pass ? 0 : 1
    }

    /// Spec 23's identity for one aligner: spec 03's, with the pitch tracker dsp-snap-1 reads.
    static func identity(asrModelID: String, aligner: String) -> ConfigIdentity {
        ConfigIdentity(asrModelID: asrModelID, pitchTrackerID: aligner == DSPSnapRefiner.aligner ? PYINTracker.trackerID : "none",
                       voicingID: "none", aligner: aligner)
    }

    /// Writes (with `--record`) or checks the refined words next to spec 03's replay, in the same replay format:
    /// `fixtures/timestamps/<whisper folder>+<aligner>/`. `whisper` itself is spec 03's folder.
    static func recordOrCheck(_ aligner: String, clips: [Clip], refined: [[WordTimestamp]], whisperReplay: URL,
                              asrModelID: String, recordRoot: URL?, repo: URL) throws -> WordBoundaryReport.Replay? {
        guard aligner != WhisperOnly.aligner else { return nil }
        let folderName = "\(whisperReplay.lastPathComponent)+\(aligner)"
        let folder = (recordRoot ?? whisperReplay.deletingLastPathComponent()).appending(path: folderName)
        if recordRoot != nil {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for stale in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where stale.pathExtension == "json" {
                try FileManager.default.removeItem(at: stale)
            }
            var entries: [ReplayManifest.Entry] = []
            for (index, clip) in clips.enumerated() {
                let source = try JSONDecoder().decode(
                    RecordedTimestamps.self, from: Data(contentsOf: whisperReplay.appending(path: "\(clip.id).json")))
                let recording = RecordedTimestamps(clipID: clip.id, audioSHA256: source.audioSHA256,
                                                   asrModelID: asrModelID, text: source.text, words: refined[index])
                let file = "\(clip.id).json"
                try writeJSON(recording, to: folder.appending(path: file))
                entries.append(.init(clipID: clip.id, file: file, sha256: try Digest.sha256(fileAt: folder.appending(path: file))))
            }
            let manifest = ReplayManifest(
                asrModelID: asrModelID,
                attribution: vctkAttribution + ". Word boundaries refined by \(aligner) (spec 23).", clips: entries)
            try writeJSON(manifest, to: folder.appending(path: ReplayManifest.fileName))
            log("recorded \(entries.count) clips → \(folder.path)")
        }
        guard FileManager.default.fileExists(atPath: folder.appending(path: ReplayManifest.fileName).path) else { return nil }
        let replay = try FixtureTimestamper(directory: folder)
        let matches = clips.indices.allSatisfy { replay.recording(for: clips[$0].id)?.words == refined[$0] }
        let manifest = try JSONDecoder().decode(ReplayManifest.self,
                                                from: Data(contentsOf: folder.appending(path: ReplayManifest.fileName)))
        return .init(folder: relative(folder, to: repo), recordingsSHA256: manifest.recordingsSHA256,
                     matchesRecording: matches)
    }

    static func toolchain() throws -> TimestampReport.Toolchain {
        TimestampReport.Toolchain(
            xcode: try shell("xcodebuild", "-version").replacingOccurrences(of: "\nBuild version ", with: " build "),
            swift: try shell("swift", "--version").split(separator: "\n").first.map(String.init) ?? "",
            macOS: "\(try shell("sw_vers", "-productVersion")) (\(try shell("sw_vers", "-buildVersion")))",
            hardware: "\(try shell("sysctl", "-n", "machdep.cpu.brand_string")), \(try shell("sysctl", "-n", "hw.model"))",
            runnerImage: nil)
    }

    static func relative(_ url: URL, to repo: URL) -> String {
        let path = url.standardizedFileURL.path, root = repo.standardizedFileURL.path + "/"
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : url.lastPathComponent
    }
}
