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

        var refiners: [any WordBoundaryRefiner] = [WhisperOnly(), DSPSnapRefiner()]
        var ctcRun: WordBoundaryReport.CTCRun?
        var ctcAligner: CTCAligner?
        var ctcManifest: CTCModelManifest?
        if let path = options.optional("ctc-manifest") {
            let manifestURL = URL(filePath: path)
            let manifest = try CTCModelManifest(contentsOf: manifestURL)
            let folder = try options.url("ctc-dir")
            let clock = ContinuousClock()
            let verifyMs = milliseconds(try clock.measure { try manifest.verify(folder: folder) })
            let start = clock.now
            let ctc = try await CTCAligner.load(manifest: manifest, folder: folder)
            let loadMs = milliseconds(start.duration(to: clock.now))
            log("loaded \(manifest.aligner) (verify \(Int(verifyMs)) ms, compile and load \(Int(loadMs)) ms)")
            let bytes = try manifest.packageFiles.reduce(0) { total, file in
                total + ((try FileManager.default.attributesOfItem(
                    atPath: folder.appending(path: manifest.package).appending(path: file.path).path)[.size] as? Int) ?? 0)
            }
            ctcRun = .init(
                manifest: relative(manifestURL, to: repo), sourceCommit: manifest.source.commit,
                license: manifest.source.license, licenseEvidence: manifest.source.licenseEvidence,
                packageSHA256: manifest.packageSHA256, fp32PackageBytes: bytes, verifyMs: verifyMs, loadMs: loadMs,
                computeUnits: "all",
                cancellation: try await ctcCancelCheck(
                    ctc, cpuOnly: try await CTCAligner.load(manifest: manifest, folder: folder, computeUnits: .cpuOnly),
                    clips: clips, samples: samples, words: whisperWords))
            refiners.append(ctc)
            ctcAligner = ctc
            ctcManifest = manifest
        }
        var ctcConfident: [[ConfidentWord]] = []
        var ctcComparable: [ComparableWord] = []
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
                } else if let ctc = refiner as? CTCAligner {
                    let aligned = try await ctc.align(whisperWords[index], samples: samples[index],
                                                      sampleRate: TimestampRequest.sampleRate)
                    ctcConfident.append(aligned)
                    words = aligned.map(\.word)
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
            if refiner is CTCAligner {
                ctcComparable = Evaluation.comparableWords(clips.indices.map {
                    ClipInput(clipID: clips[$0].id, transcript: transcripts[$0], asrWords: refined[$0],
                              baselineWords: spans[clips[$0].id] ?? [])
                }).words
            }
            let config = identity(asrModelID: whisper.asrModelID, aligner: refiner.id,
                                  modelSHA256: refiner is CTCAligner ? ctcManifest?.packageSHA256 : nil)
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
        // The ship gate on VCTK: MFA is the oracle.
        let harness = try DownstreamHarness()
        var downstream: [DownstreamGate] = []
        if ctcAligner != nil {
            var pairs: [(oracle: WordVerdict, candidate: WordVerdict)] = [], gated = 0
            for index in clips.indices {
                let result = try harness.compare(
                    transcript: transcripts[index], samples: samples[index], sampleRate: TimestampRequest.sampleRate,
                    oracle: spans[clips[index].id] ?? [], candidate: ctcConfident[index], clipID: clips[index].id)
                pairs += result.pairs
                gated += result.gatedByConfidence
            }
            downstream.append(.compare(pairs, set: "VCTK", oracle: "MFA word baseline", inconclusiveByConfidence: gated))
        } else {
            downstream.append(.notEvaluated(set: "VCTK", oracle: "MFA word baseline", reason: "b2 not loaded"))
        }

        // The synthetic set: the TTS phrases from scripts/reference-check.sh, transcribed live by Whisper, then b2.
        var referenceNotes: [String] = []
        var mfaOnTTS: ReferenceErrors.Comparison?, b2OnTTS: ReferenceErrors.Comparison?
        var voice: String?, resolution: Double?
        if let path = options.optional("reference") {
            let folder = URL(filePath: path)
            let skipped = folder.appending(path: "reference-check.json.skipped")
            if FileManager.default.fileExists(atPath: folder.appending(path: "reference-check.json").path) {
                let check = try JSONDecoder().decode(ReferenceCheck.self,
                                                     from: Data(contentsOf: folder.appending(path: "reference-check.json")))
                mfaOnTTS = ReferenceErrors.comparison(check, label: "MFA on TTS vs TTS markers (the reference's own error)")
                voice = check.voice
                resolution = check.markerResolutionMs
                let markers = try JSONDecoder().decode(MarkerFile.self, from: Data(contentsOf: folder.appending(path: "markers.json")))
                if let ctc = ctcAligner, options.optional("manifest") != nil {
                    let (asr, _, _, _) = try await loadTimestamper(options)
                    var clipsForCheck: [ReferenceCheck.Clip] = []
                    var pairs: [(oracle: WordVerdict, candidate: WordVerdict)] = [], gated = 0
                    for phrase in markers.phrases {
                        let audio = try WhisperKitTimestamper.samples(
                            fromFileAt: folder.appending(path: "corpus/tts/\(phrase.clipID).wav"))
                        let heard = try await asr.wordTimestamps(for: TimestampRequest(clipID: phrase.clipID, samples: audio))
                        let aligned = try await ctc.align(heard, samples: audio, sampleRate: TimestampRequest.sampleRate)
                        clipsForCheck.append(.init(
                            clipID: phrase.clipID, transcript: phrase.transcript, markers: phrase.words,
                            aligned: aligned.map { BaselineWord(word: $0.word.word, start: $0.word.start, end: $0.word.end) }))
                        let result = try harness.compare(
                            transcript: phrase.transcript, samples: audio, sampleRate: TimestampRequest.sampleRate,
                            oracle: phrase.words, candidate: aligned, clipID: phrase.clipID)
                        pairs += result.pairs
                        gated += result.gatedByConfidence
                    }
                    let b2Check = ReferenceCheck.compare(clipsForCheck, voice: markers.voice, aligner: CTCAligner.aligner,
                                                         markerResolutionMs: check.markerResolutionMs)
                    b2OnTTS = ReferenceErrors.comparison(b2Check, label: "b2 on TTS vs TTS markers (ground truth; b2 seeded by live Whisper base.en)")
                    downstream.insert(.compare(pairs, set: "Synthetic (TTS)", oracle: "TTS markers",
                                               inconclusiveByConfidence: gated), at: 0)
                } else {
                    referenceNotes.append("b2 on TTS not run: needs b2 and the Whisper model (--manifest, --model-dir).")
                    downstream.insert(.notEvaluated(set: "Synthetic (TTS)", oracle: "TTS markers",
                                                    reason: "b2 or the Whisper model not loaded"), at: 0)
                }
            } else {
                let why = (try? String(contentsOf: skipped, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "scripts/reference-check.sh was not run"
                referenceNotes.append("TTS comparisons NOT RUN: \(why)")
                downstream.insert(.notEvaluated(set: "Synthetic (TTS)", oracle: "TTS markers", reason: why), at: 0)
            }
        } else {
            referenceNotes.append("TTS comparisons NOT RUN: no --reference folder.")
            downstream.insert(.notEvaluated(set: "Synthetic (TTS)", oracle: "TTS markers", reason: "no --reference folder"), at: 0)
        }
        let referenceErrors = ReferenceErrors(
            mfaOnTTS: mfaOnTTS, b2OnTTS: b2OnTTS,
            b2VsMFAOnVCTK: ctcAligner == nil ? nil : ReferenceErrors.versusBaseline(ctcComparable, label: "b2 vs MFA on VCTK"),
            voice: voice, markerResolutionMs: resolution, notes: referenceNotes)
        let confidence = ctcConfident.isEmpty ? nil
            : WordBoundaryReport.ConfidenceSummary(confidences: ctcConfident.joined().map(\.confidence))

        let cancelPassed = ctcRun?.cancellation.outcome == .pass
        let gateOutcome = Outcome.combine(downstream.map(\.outcome))
        let prerequisites: [ShipDecision.Prerequisite] = [
            .init("Licence on the model card at the pinned commit", ctcRun.map { "\($0.license), verified at `\($0.sourceCommit.prefix(8))`" } ?? "b2 not loaded", met: ctcRun != nil),
            .init("SHA-256 pin", ctcRun.map { "packageSHA256 `\($0.packageSHA256.prefix(16))…`, checked before every load" } ?? "b2 not loaded", met: ctcRun != nil),
            .init("Size on disk", ctcRun.map { String(format: "%.1f MiB (float32)", Double($0.fp32PackageBytes) / 1_048_576) } ?? "b2 not loaded", met: ctcRun != nil),
            .init("Latency on the macos-26 runner", "NOT RUN: waits for the manual workflow Raph adds", met: false),
            .init("Cancel test (cancel at 100 ms, return within about 300 ms)", ctcRun.map { $0.cancellation.outcome.rawValue } ?? "not run", met: cancelPassed),
            .init("Downstream gate (synthetic and VCTK)", gateOutcome.rawValue, met: gateOutcome == .pass),
            .init("`ctcConfidenceMin` tuned on spec 02's tuning speakers", "NOT TUNED: default 0.5 until spec 02's split is on main", met: false),
        ]
        let decision = ShipDecision.decide(gates: downstream, prerequisites: prerequisites,
                                           candidate: CTCAligner.aligner, shipped: WhisperOnly.aligner)

        let config = identity(asrModelID: whisper.asrModelID, aligner: decision.shippedAligner, modelSHA256: nil)
        let digest = try ConfigDigestRecord(config: config)
        notes.append("Whisper words are spec 03's committed replay of WhisperKit base.en on these clips (`fixtures/timestamps/\(replayURL.lastPathComponent)`), so no ASR runs here; refiners read the same 16 kHz audio WhisperKit was given.")
        notes.append("Since the CTO ruling of 2026-11-23 14:05 the ship gate is downstream (spec 07's verdicts, oracle vs b2); spec 03's 40 ms / 85% bar on unpadded starts and ends is a reported target. The clips are spec 03's set (the 8 bundled voices); the number of record is the re-run on spec 02's 12 held-out speakers once spec 02 is on main.")
        notes.append("Nothing was tuned: `ctcConfidenceMin` is the 0.5 default and b1's `intensityDropDB` the 10 dB default, because spec 02's tuning split is not on main.")
        for aligner in aligners {
            let bias = aligner.accuracy.endBias
            notes.append("End-bias diagnostic for `\(aligner.id)` (fitted and measured on these same clips; applied nowhere, not a fix, not the gate): median signed end error \(bias.medianSignedEndErrorMs.map { String(format: "%+.1f ms", $0) } ?? "–"); ends after subtracting it: median \(bias.correctedEnds.medianErrorMs.map { String(format: "%.1f ms", $0) } ?? "–"), within 80 ms \(bias.correctedEnds.shareWithinTolerance.map { String(format: "%.1f%%", $0 * 100) } ?? "–"). Any rule change would have to be chosen on spec 02's tuning speakers.")
        }
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
            aligners: aligners, correlation: correlation, referenceErrors: referenceErrors, ctcConfidence: confidence,
            downstream: downstream, ctc: ctcRun, decision: decision, notes: notes)

        let out = try options.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let json = out.appending(path: "\(report.baseName).json"), md = out.appending(path: "\(report.baseName).md")
        try report.json().write(to: json, options: .atomic)
        try Data((report.markdown() + "\n").utf8).write(to: md, options: .atomic)
        print("boundaries: downstream gate \(decision.gate.rawValue), ship \(decision.ship) (shipped stays \(decision.shippedAligner)) → \(json.path), \(md.path)")
        for g in downstream {
            print("boundaries: \(g.set): \(g.outcome.rawValue), \(g.differing)/\(g.words) verdicts differ, inconclusive \(g.oracleInconclusiveRate ?? .nan) → \(g.candidateInconclusiveRate ?? .nan)")
        }
        print("boundaries: configDigest \(digest.sha256), sourceTreeHash \(sourceTreeHash), commit \(commit), clean \(clean)")
        if aligners.contains(where: { $0.replay?.matchesRecording == false }) {
            log("a run's boundaries differ from the recorded replay: re-record with --record")
            return 4
        }
        switch decision.gate {
        case .pass: return 0
        case .fail: return 1
        case .notEvaluated: return release ? 3 : 0
        }
    }

    /// Cancels a call 100 ms in, five times, on about 20 s of clips (the model's limit) with their words shifted
    /// onto the joined timeline; then checks a normal call still returns boundaries. With all compute units such a
    /// call is over before 100 ms on an M-series Mac, so the trials use a CPU-only load of the same package.
    static func ctcCancelCheck(_ fast: CTCAligner, cpuOnly ctc: CTCAligner, clips: [Clip], samples: [[Float]],
                               words: [[WordTimestamp]]) async throws -> WordBoundaryReport.CTCRun.Cancellation {
        var audio: [Float] = [], timed: [WordTimestamp] = []
        for index in clips.indices where audio.count + samples[index].count <= ctc.manifest.conversion.maxSamples {
            let offset = Double(audio.count) / TimestampRequest.sampleRate
            timed += words[index].map {
                WordTimestamp(word: $0.word, start: $0.start + offset, end: $0.end + offset, probability: $0.probability)
            }
            audio += samples[index]
        }
        let joined = audio, joinedWords = timed
        let rate = TimestampRequest.sampleRate
        let clock = ContinuousClock()
        _ = try await fast.refine(joinedWords, samples: joined, sampleRate: rate)  // warm-up
        let fastMs = milliseconds(try await clock.measure { _ = try await fast.refine(joinedWords, samples: joined, sampleRate: rate) })
        _ = try await ctc.refine(joinedWords, samples: joined, sampleRate: rate)  // warm-up
        let trialMs = milliseconds(try await clock.measure { _ = try await ctc.refine(joinedWords, samples: joined, sampleRate: rate) })
        log("ctc cancel-check: uncancelled call \(Int(fastMs)) ms (all), \(Int(trialMs)) ms (cpuOnly)")
        var returns: [Double] = [], allCancelled = true
        for trial in 1...5 {
            let task = Task { try await ctc.refine(joinedWords, samples: joined, sampleRate: rate) }
            try await Task.sleep(for: .milliseconds(100))
            let cancelledAt = clock.now
            task.cancel()
            let result = await task.result
            returns.append(milliseconds(cancelledAt.duration(to: clock.now)))
            let cancelled: Bool
            if case .failure(let error) = result, error is CancellationError { cancelled = true } else { cancelled = false }
            allCancelled = allCancelled && cancelled
            log("ctc cancel-check: trial \(trial): \(cancelled ? "cancelled" : "not cancelled"), returned \(String(format: "%.1f", returns.last ?? 0)) ms after cancel")
        }
        let after = try await ctc.refine(words[0], samples: samples[0], sampleRate: rate)
        return .init(inputSeconds: Double(joined.count) / rate, uncancelledCallMs: fastMs, computeUnits: "cpuOnly",
                     uncancelledTrialCallMs: trialMs, returnMs: returns, allCancelled: allCancelled,
                     modelStillLoaded: after.count == words[0].count)
    }

    /// Spec 23's identity for one aligner: spec 03's, with the pitch tracker dsp-snap-1 reads.
    static func identity(asrModelID: String, aligner: String, modelSHA256: String?) -> ConfigIdentity {
        ConfigIdentity(asrModelID: asrModelID, pitchTrackerID: aligner == DSPSnapRefiner.aligner ? PYINTracker.trackerID : "none",
                       voicingID: "none", aligner: aligner, alignerModelSHA256: modelSHA256 ?? "none")
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
