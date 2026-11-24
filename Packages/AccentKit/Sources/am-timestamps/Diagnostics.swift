import AMAlignment
import AMAlignmentCTC
import AMCore
import AMProsody
import AMTimestampEval
import Foundation

/// `am-timestamps diagnostics`: the CTO diagnostic round on spec 23's downstream gate (decision on #27, 2026-11-23).
/// Same harness, verdict function, thresholds, sets and comparability rules as the gate in the cfd62cd8 report.
/// Measures only: it changes no shipped behaviour, no threshold and decides no aligner.
extension AMTimestamps {
    /// One oracle/candidate pair on one set, with the item 3 breakdown and item 4 split.
    struct DiagnosticPair: Codable {
        var set: String
        var oracle: String
        var candidate: String
        var note: String?
        var notRun: String?
        var diff: VerdictDiagnostics.Diff?
        var cues: VerdictDiagnostics.Cues?
        var bySyllableCount: [VerdictDiagnostics.Bin]?
        var byTransition: [VerdictDiagnostics.Bin]?
        var byBoundaryError: [VerdictDiagnostics.Bin]?
        var inconclusiveSplit: VerdictDiagnostics.InconclusiveSplit?
        /// Phrase words the oracle times (with a pronunciation) that the recogniser's words do not match: out of
        /// the comparable words by the gate's rule, so out of every diff here.
        var recogniserSubstituted: Int?
        var recogniserDeleted: Int?
        /// Flipped words, for the control and b2 only.
        var flippedWords: [DiagnosticWord]?

        init(set: String, oracle: String, candidate: String, note: String? = nil, notRun: String) {
            self.set = set
            self.oracle = oracle
            self.candidate = candidate
            self.note = note
            self.notRun = notRun
        }

        init(set: String, oracle: String, candidate: String, note: String? = nil, words: [DiagnosticWord],
             substituted: Int, deleted: Int, keepFlipped: Bool) {
            self.set = set
            self.oracle = oracle
            self.candidate = candidate
            self.note = note
            diff = VerdictDiagnostics.diff(words)
            cues = VerdictDiagnostics.cues(words)
            bySyllableCount = VerdictDiagnostics.bySyllableCount(words)
            byTransition = VerdictDiagnostics.byTransition(words)
            byBoundaryError = VerdictDiagnostics.byBoundaryError(words)
            inconclusiveSplit = VerdictDiagnostics.inconclusiveSplit(words)
            recogniserSubstituted = substituted
            recogniserDeleted = deleted
            flippedWords = keepFlipped ? words.filter(\.flipped) : nil
        }
    }

    struct DiagnosticsReport: Codable {
        struct Identity: Codable {
            var evaluatedCommit: String
            var cleanTree: Bool
            var sourceTreeHash: String
            var shippedConfigDigest: String
            var configDigests: [String: String]
            var corpusManifestHash: String
            var labelFile: String
            var labelHash: String
            var asrModelID: String
            var whisperReplay: String
            var liveWhisperManifest: String?
            var ctcPackageSHA256: String?
            var markersSHA256: String?
            var mfaOnTTSSHA256: String?
            var ttsAudioHash: String?
            var ctcConfidenceMin: Double
            var verdictDiffMax: Double
            var inconclusiveRiseMaxPoints: Double
            var toolchain: TimestampReport.Toolchain
        }

        struct GateCheck: Codable {
            var set: String
            var gateWords: Int
            var gateDiffering: Int
            var gateInconclusiveByConfidence: Int
            var words: Int
            var differing: Int
            var gatedByConfidence: Int
            var matches: Bool
        }

        var generatedAt: Date
        var gateReport: String
        var identity: Identity
        var control: [DiagnosticPair]
        var ranking: [DiagnosticPair]
        var gateCheck: [GateCheck]
        var notes: [String]
    }

    static func diagnostics(_ options: Options) async throws -> Int32 {
        let repo = try options.url("repo")
        let release = options.flag("release")
        let commit = try shell("git", "rev-parse", "HEAD", in: repo)
        let clean = try shell("git", "status", "--porcelain", in: repo).isEmpty
        if release && !clean {
            log("the working tree is dirty: a release report must come from a clean tree (commit first)")
            return 2
        }
        let sourceTreeHash = SourceTree.hash(lsTree: try shell("git", "ls-tree", "-r", "--full-tree", commit, in: repo))
        let clips = try clips(options).present
        let transcripts = try clips.map { try $0.text() }
        let corpusHash = CorpusHash.hash(fileSHA256s: try clips.map { try Digest.sha256(fileAt: $0.audio) })
        let baselineURL = try options.url("baseline")
        let baseline = try JSONDecoder().decode(WordBaseline.self, from: Data(contentsOf: baselineURL))
        let spans = Dictionary(uniqueKeysWithValues: baseline.clips.map { ($0.clipID, $0.words) })
        let replayURL = try options.url("replay")
        let whisper = try FixtureTimestamper(directory: replayURL)
        let harness = try DownstreamHarness()
        let snap = DSPSnapRefiner()

        let manifest = try CTCModelManifest(contentsOf: try options.url("ctc-manifest"))
        let ctcFolder = try options.url("ctc-dir")
        try manifest.verify(folder: ctcFolder)
        let ctc = try await CTCAligner.load(manifest: manifest, folder: ctcFolder)
        log("loaded \(manifest.aligner)")

        // Runs one set: every candidate of `candidates(index)` against the oracle, word by word.
        struct SetRun { var words: [DiagnosticWord] = []; var substituted = 0; var deleted = 0 }

        // VCTK: oracle MFA; Whisper is spec 03's replay, b1 and b2 refine it.
        var vctk: [String: SetRun] = [:]
        for (index, clip) in clips.enumerated() {
            let samples = try WhisperKitTimestamper.samples(fromFileAt: clip.audio)
            let heard = try await whisper.wordTimestamps(for: TimestampRequest(clipID: clip.id, samples: []))
            let rate = TimestampRequest.sampleRate
            let candidates: [(String, [ConfidentWord])] = [
                (WhisperOnly.aligner, heard.map(ConfidentWord.ungated)),
                (DSPSnapRefiner.aligner, try await snap.snap(heard, samples: samples, sampleRate: rate).words.map(ConfidentWord.ungated)),
                (CTCAligner.aligner, try await ctc.align(heard, samples: samples, sampleRate: rate)),
            ]
            for (id, words) in candidates {
                let result = try harness.diagnose(
                    transcript: transcripts[index], samples: samples, sampleRate: rate, oracle: spans[clip.id] ?? [],
                    candidate: harness.matched(words, transcript: transcripts[index]), recognised: heard, clipID: clip.id)
                vctk[id, default: SetRun()].words += result.words
                vctk[id, default: SetRun()].substituted += result.substituted
                vctk[id, default: SetRun()].deleted += result.deleted
            }
        }
        log("VCTK: \(clips.count) clips")

        // Synthetic: oracle TTS markers; Whisper base.en live on the TTS audio, as it seeds b2 in the gate.
        var synthetic: [String: SetRun] = [:]
        var syntheticNotRun: String?
        var markersSHA: String?, mfaSHA: String?, ttsHash: String?, liveManifest: String?
        let controlID = "MFA on TTS", controlAllID = "MFA on TTS (all marker∩MFA words, probability 1)"
        if let path = options.optional("reference"), options.optional("manifest") != nil {
            let folder = URL(filePath: path)
            let markersURL = folder.appending(path: "markers.json"), mfaURL = folder.appending(path: "mfa-alignment.json")
            let markers = try JSONDecoder().decode(MarkerFile.self, from: Data(contentsOf: markersURL))
            let mfa = try JSONDecoder().decode(WordBaseline.self, from: Data(contentsOf: mfaURL))
            let mfaWords = Dictionary(uniqueKeysWithValues: mfa.clips.map { ($0.clipID, $0.words) })
            markersSHA = try Digest.sha256(fileAt: markersURL)
            mfaSHA = try Digest.sha256(fileAt: mfaURL)
            liveManifest = relative(try options.url("manifest"), to: repo)
            let (asr, _, _, _) = try await loadTimestamper(options)
            var audioSHAs: [String] = []
            for phrase in markers.phrases {
                let wav = folder.appending(path: "corpus/tts/\(phrase.clipID).wav")
                audioSHAs.append(try Digest.sha256(fileAt: wav))
                let audio = try WhisperKitTimestamper.samples(fromFileAt: wav)
                let rate = TimestampRequest.sampleRate
                let heard = try await asr.wordTimestamps(for: TimestampRequest(clipID: phrase.clipID, samples: audio))
                var keyed: [(String, [Int: ConfidentWord], [WordTimestamp])] = []
                for (id, words) in [
                    (WhisperOnly.aligner, heard.map(ConfidentWord.ungated)),
                    (DSPSnapRefiner.aligner, try await snap.snap(heard, samples: audio, sampleRate: rate).words.map(ConfidentWord.ungated)),
                    (CTCAligner.aligner, try await ctc.align(heard, samples: audio, sampleRate: rate)),
                ] {
                    keyed.append((id, harness.matched(words, transcript: phrase.transcript), heard))
                }
                // The control: MFA's spans on the TTS audio, on the gate's comparable words (the phrase words the
                // live Whisper words also match), carrying that Whisper word's probability, as the gate's oracle
                // run does. No confidence gate.
                let tokens = harness.tokens(phrase.transcript)
                let mfaPhrase = mfaWords[phrase.clipID] ?? []
                let mfaIndex = Tokens.match(tokens: tokens, words: mfaPhrase.map(\.word))
                let heardIndex = Tokens.match(tokens: tokens, words: heard.map(\.word))
                var control: [Int: ConfidentWord] = [:], controlAll: [Int: ConfidentWord] = [:]
                for position in tokens.indices {
                    guard let m = mfaIndex[position] else { continue }
                    let span = mfaPhrase[m]
                    controlAll[position] = .ungated(WordTimestamp(word: span.word, start: span.start, end: span.end, probability: 1))
                    if let h = heardIndex[position] {
                        control[position] = .ungated(WordTimestamp(word: span.word, start: span.start, end: span.end,
                                                                   probability: heard[h].probability))
                    }
                }
                keyed.append((controlID, control, heard))
                keyed.append((controlAllID, controlAll, mfaPhrase.map { WordTimestamp(word: $0.word, start: $0.start, end: $0.end, probability: 1) }))
                for (id, candidate, recognised) in keyed {
                    let result = try harness.diagnose(
                        transcript: phrase.transcript, samples: audio, sampleRate: rate, oracle: phrase.words,
                        candidate: candidate, recognised: recognised, clipID: phrase.clipID)
                    synthetic[id, default: SetRun()].words += result.words
                    synthetic[id, default: SetRun()].substituted += result.substituted
                    synthetic[id, default: SetRun()].deleted += result.deleted
                }
            }
            ttsHash = CorpusHash.hash(fileSHA256s: audioSHAs)
            log("synthetic: \(markers.phrases.count) phrases")
        } else {
            syntheticNotRun = "needs --reference (scripts/reference-check.sh's output) and the Whisper model (--manifest, --model-dir)"
        }

        func pair(_ runs: [String: SetRun], _ id: String, set: String, oracle: String, keep: Bool, note: String? = nil) -> DiagnosticPair {
            guard let run = runs[id] else {
                return DiagnosticPair(set: set, oracle: oracle, candidate: id, note: note,
                                      notRun: syntheticNotRun ?? "no words")
            }
            return DiagnosticPair(set: set, oracle: oracle, candidate: id, note: note, words: run.words,
                                  substituted: run.substituted, deleted: run.deleted, keepFlipped: keep)
        }
        let control = [
            pair(synthetic, controlID, set: "Synthetic (TTS)", oracle: "TTS markers", keep: true,
                 note: "The control of record: the gate's comparable words (the live Whisper words match them too), each carrying that Whisper word's probability on both sides, as the gate's oracle run does."),
            pair(synthetic, controlAllID, set: "Synthetic (TTS)", oracle: "TTS markers", keep: false,
                 note: "Sensitivity only: every phrase word both the markers and MFA time, probability 1 on both sides (no Whisper in the loop)."),
        ]
        var ranking: [DiagnosticPair] = []
        for id in [WhisperOnly.aligner, DSPSnapRefiner.aligner, CTCAligner.aligner] {
            ranking.append(pair(synthetic, id, set: "Synthetic (TTS)", oracle: "TTS markers", keep: id == CTCAligner.aligner))
        }
        for id in [WhisperOnly.aligner, DSPSnapRefiner.aligner, CTCAligner.aligner] {
            ranking.append(pair(vctk, id, set: "VCTK", oracle: "MFA word baseline", keep: id == CTCAligner.aligner))
        }

        // Reproduces the gate? Read-only check against the gate report's downstream rows.
        var gateCheck: [DiagnosticsReport.GateCheck] = []
        let gateURL = try options.url("gate-report")
        if let object = try JSONSerialization.jsonObject(with: Data(contentsOf: gateURL)) as? [String: Any],
           let rows = object["downstream"] as? [[String: Any]] {
            for row in rows {
                guard let set = row["set"] as? String,
                      let mine = ranking.first(where: { $0.set == set && $0.candidate == CTCAligner.aligner }),
                      let diff = mine.diff, let split = mine.inconclusiveSplit else { continue }
                let words = row["words"] as? Int ?? -1, differing = row["differing"] as? Int ?? -1
                let gated = row["inconclusiveByConfidence"] as? Int ?? -1
                gateCheck.append(.init(set: set, gateWords: words, gateDiffering: differing,
                                       gateInconclusiveByConfidence: gated, words: diff.words, differing: diff.differing,
                                       gatedByConfidence: split.gatedWords,
                                       matches: words == diff.words && differing == diff.differing && gated == split.gatedWords))
            }
        }

        var digests: [String: String] = [:]
        for id in [WhisperOnly.aligner, DSPSnapRefiner.aligner, CTCAligner.aligner] {
            digests[id] = try configDigest(identity(asrModelID: whisper.asrModelID, aligner: id,
                                                    modelSHA256: id == CTCAligner.aligner ? manifest.packageSHA256 : nil))
        }
        let thresholds = Thresholds.current.wordBoundaries
        let report = DiagnosticsReport(
            generatedAt: Date(), gateReport: relative(gateURL, to: repo),
            identity: .init(
                evaluatedCommit: commit, cleanTree: clean, sourceTreeHash: sourceTreeHash,
                shippedConfigDigest: try configDigest(identity(asrModelID: whisper.asrModelID, aligner: WhisperOnly.aligner, modelSHA256: nil)),
                configDigests: digests, corpusManifestHash: corpusHash, labelFile: relative(baselineURL, to: repo),
                labelHash: try Digest.sha256(fileAt: baselineURL), asrModelID: whisper.asrModelID,
                whisperReplay: relative(replayURL, to: repo), liveWhisperManifest: liveManifest,
                ctcPackageSHA256: manifest.packageSHA256, markersSHA256: markersSHA, mfaOnTTSSHA256: mfaSHA,
                ttsAudioHash: ttsHash, ctcConfidenceMin: thresholds.ctcConfidenceMin,
                verdictDiffMax: thresholds.verdictDiffMax, inconclusiveRiseMaxPoints: thresholds.inconclusiveRiseMaxPoints,
                toolchain: try toolchain()),
            control: control, ranking: ranking, gateCheck: gateCheck, notes: [])

        let out = try options.url("out")
        let name = options.optional("name") ?? "word-boundaries-diagnostics"
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let json = out.appending(path: "\(name).json"), md = out.appending(path: "\(name).md")
        try writeJSON(report, to: json)
        try Data((DiagnosticsMarkdown.render(report, jsonName: json.lastPathComponent) + "\n").utf8).write(to: md, options: .atomic)
        for row in control + ranking {
            print("diagnostics: \(row.set) \(row.oracle) vs \(row.candidate): \(row.diff.map { "\($0.differing)/\($0.words)" } ?? "NOT RUN")")
        }
        for check in gateCheck { print("diagnostics: gate reproduced on \(check.set): \(check.matches)") }
        print("diagnostics: → \(json.path), \(md.path)")
        return gateCheck.allSatisfy(\.matches) ? 0 : 4
    }
}
