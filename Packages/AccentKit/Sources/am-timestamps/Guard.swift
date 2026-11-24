import AMAlignment
import AMAlignmentCTC
import AMCapture
import AMCore
import AMPitch
import AMProsody
import AMTimestampEval
import Foundation

/// `am-timestamps spec11-guard`: spec 11's §4 control, §4a b2 gate and §4b jitter test, measured on one set of
/// thresholds. Spec 23's harness unchanged (`DownstreamHarness.diagnose`: same selector, comparable words, voicing,
/// probabilities and verdict), with only the thresholds swapped. Measures only: no limits, no PASS/FAIL; the caller
/// reads the JSON and applies spec 11's limits.
extension AMTimestamps {
    static let jitterRadiiMs = [20, 40, 80]

    struct GuardParts: Codable, Equatable {
        var inconclusive = 0, syllableCount = 0, longestSyllable = 0, loudestSyllable = 0

        mutating func add(_ part: String) {
            switch part {
            case "inconclusive": inconclusive += 1
            case "syllableCount": syllableCount += 1
            case "longestSyllable": longestSyllable += 1
            default: loudestSyllable += 1
            }
        }
    }

    struct GuardBucket: Codable, Equatable {
        var bucket: String
        var words: Int
        var differing: Int
        var oracleInconclusive: Int
        var candidateInconclusive: Int
    }

    struct GuardErrorBin: Codable, Equatable {
        var bin: String
        var words: Int
        var differing: Int
    }

    struct GuardTransitions: Codable, Equatable {
        var decidedToDecided = 0
        var involvingInconclusive = 0
    }

    struct GuardSplit: Codable, Equatable {
        var oracle: Int
        var candidate: Int
        var candidateGateBypassed: Int
        var gatedWords: Int
    }

    /// Spec 25 (CTO markup 3): flips of words with a nucleus peak within 40 ms of an oracle edge, against words with none.
    struct GuardNearEdge: Codable, Equatable {
        var nearWords = 0, nearFlips = 0, farWords = 0, farFlips = 0
    }

    /// Spec 25 diagnostics on the oracle side (`.nucleus`), per syllable group: P = N_w and nucleus-short counts.
    struct GuardNucleusBucket: Codable, Equatable {
        var bucket: String
        var words: Int
        var countMatch: Int
        var short: Int
    }

    struct GuardComparison: Encodable {
        var id: String
        var candidate: String
        var status: String
        var reason: String?
        var words = 0, differing = 0, oracleInconclusive = 0, candidateInconclusive = 0
        var parts = GuardParts(), onlyCue = GuardParts()
        var bySyllables: [GuardBucket] = []
        var transitions = GuardTransitions()
        var boundaryError: [GuardErrorBin] = []
        var keptUnjittered = 0
        var inconclusiveSplit: GuardSplit?
        var nearEdge: GuardNearEdge?
        var nucleusOracle: [GuardNucleusBucket]?

        static func notEvaluated(id: String, candidate: String, reason: String) -> GuardComparison {
            GuardComparison(id: id, candidate: candidate, status: "notEvaluated", reason: reason)
        }

        init(id: String, candidate: String, status: String, reason: String?) {
            self.id = id
            self.candidate = candidate
            self.status = status
            self.reason = reason
        }

        init(id: String, candidate: String, words list: [DiagnosticWord], keptUnjittered: Int = 0, split: Bool = false) {
            self.init(id: id, candidate: candidate, status: "evaluated", reason: nil)
            words = list.count
            differing = list.count(where: \.flipped)
            oracleInconclusive = list.count { $0.oracle.inconclusive }
            candidateInconclusive = list.count { $0.candidate.inconclusive }
            for word in list where word.flipped {
                let differ = word.differingParts
                for part in differ { parts.add(part) }
                if differ.count == 1 { onlyCue.add(differ[0]) }
                if word.oracle.inconclusive || word.candidate.inconclusive {
                    transitions.involvingInconclusive += 1
                } else {
                    transitions.decidedToDecided += 1
                }
            }
            func bucket(_ label: String, _ group: [DiagnosticWord]) -> GuardBucket {
                GuardBucket(bucket: label, words: group.count, differing: group.count(where: \.flipped),
                            oracleInconclusive: group.count { $0.oracle.inconclusive },
                            candidateInconclusive: group.count { $0.candidate.inconclusive })
            }
            bySyllables = ["1", "2", "3", "4+"].enumerated().map { index, label in
                bucket(label, list.filter { index == 3 ? $0.oracle.syllableCount >= 4 : $0.oracle.syllableCount == index + 1 })
            }
            // Spec 07 gives every timed word at least one syllable; a "0" bucket shows up only if that ever changes.
            let none = list.filter { $0.oracle.syllableCount < 1 }
            if !none.isEmpty { bySyllables.append(bucket("0", none)) }
            boundaryError = VerdictDiagnostics.byBoundaryError(list).map {
                GuardErrorBin(bin: $0.label, words: $0.words, differing: $0.flipped)
            }
            self.keptUnjittered = keptUnjittered
            if list.contains(where: { $0.nucleusNearEdge != nil }) {
                var near = GuardNearEdge()
                for word in list {
                    if word.nucleusNearEdge == true {
                        near.nearWords += 1
                        if word.flipped { near.nearFlips += 1 }
                    } else {
                        near.farWords += 1
                        if word.flipped { near.farFlips += 1 }
                    }
                }
                nearEdge = near
            }
            if list.contains(where: { $0.oracleNucleusAvailable != nil }) {
                nucleusOracle = ["1", "2", "3", "4+"].enumerated().map { index, label in
                    let group = list.filter { index == 3 ? $0.oracle.syllableCount >= 4 : $0.oracle.syllableCount == index + 1 }
                    return GuardNucleusBucket(
                        bucket: label, words: group.count,
                        countMatch: group.count { $0.oracleNucleusAvailable == $0.oracle.syllableCount },
                        short: group.count { $0.oracleNucleusShort == true })
                }
            }
            if split {
                inconclusiveSplit = GuardSplit(
                    oracle: oracleInconclusive, candidate: candidateInconclusive,
                    candidateGateBypassed: list.count { $0.candidateUngated.inconclusive },
                    gatedWords: list.count(where: \.gatedByConfidence))
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, candidate, status, reason, words, differing, oracleInconclusive, candidateInconclusive, parts,
                 onlyCue, bySyllables, transitions, boundaryError, keptUnjittered, inconclusiveSplit, nearEdge, nucleusOracle
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(candidate, forKey: .candidate)
            try c.encode(status, forKey: .status)
            try c.encode(reason, forKey: .reason)
            try c.encode(words, forKey: .words)
            try c.encode(differing, forKey: .differing)
            try c.encode(oracleInconclusive, forKey: .oracleInconclusive)
            try c.encode(candidateInconclusive, forKey: .candidateInconclusive)
            try c.encode(parts, forKey: .parts)
            try c.encode(onlyCue, forKey: .onlyCue)
            try c.encode(bySyllables, forKey: .bySyllables)
            try c.encode(transitions, forKey: .transitions)
            try c.encode(boundaryError, forKey: .boundaryError)
            try c.encode(keptUnjittered, forKey: .keptUnjittered)
            if id == "b2" { try c.encode(inconclusiveSplit, forKey: .inconclusiveSplit) }
            try c.encodeIfPresent(nearEdge, forKey: .nearEdge)
            try c.encodeIfPresent(nucleusOracle, forKey: .nucleusOracle)
        }
    }

    struct GuardSet: Encodable {
        var set: String
        var oracle: String
        var status = "evaluated"
        var reason: String?
        var clips = 0
        var clipsSkipped: [String] = []
        var substituted = 0
        var deleted = 0
        var comparisons: [GuardComparison] = []

        enum CodingKeys: String, CodingKey {
            case set, oracle, status, reason, clips, clipsSkipped, substituted, deleted, comparisons
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(set, forKey: .set)
            try c.encode(oracle, forKey: .oracle)
            try c.encode(status, forKey: .status)
            try c.encode(reason, forKey: .reason)
            try c.encode(clips, forKey: .clips)
            try c.encode(clipsSkipped, forKey: .clipsSkipped)
            try c.encode(substituted, forKey: .substituted)
            try c.encode(deleted, forKey: .deleted)
            try c.encode(comparisons, forKey: .comparisons)
        }
    }

    struct GuardReport: Encodable {
        var formatVersion = 1
        var thresholdsLabel: String
        /// Spec 25: `span` or `nucleus`, the measurement every row used.
        var measurement: String
        var thresholds: Thresholds
        var seed: UInt64
        var asrModelID: String?
        var ctcModel: String?
        var sets: [GuardSet]

        enum CodingKeys: String, CodingKey {
            case formatVersion, thresholdsLabel, measurement, thresholds, seed, asrModelID, ctcModel, sets
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(formatVersion, forKey: .formatVersion)
            try c.encode(thresholdsLabel, forKey: .thresholdsLabel)
            try c.encode(measurement, forKey: .measurement)
            try c.encode(thresholds, forKey: .thresholds)
            try c.encode(seed, forKey: .seed)
            try c.encode(asrModelID, forKey: .asrModelID)
            try c.encode(ctcModel, forKey: .ctcModel)
            try c.encode(sets, forKey: .sets)
        }
    }

    /// One `--vctk-inputs` entry.
    struct GuardInput: Codable {
        var clipID: String
        var audio: String
        var transcript: String
    }

    /// Words of one set, per comparison ID, accumulated over clips.
    struct GuardAccumulator {
        var words: [String: [DiagnosticWord]] = [:]
        var kept: [String: Int] = [:]
        var substituted = 0, deleted = 0, clips = 0
    }

    /// Which rows a run measures (`--rows`, comma-separated; default all). Spec 25's acceptance 1 runs `jitter` alone.
    struct GuardRows {
        var control = true, b2 = true, jitter = true

        init(_ text: String?) throws {
            guard let text else { return }
            let names = Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            guard !names.isEmpty, names.isSubset(of: ["control", "b2", "jitter"]) else {
                throw ToolError.usage("--rows takes a comma-separated list of control, b2, jitter")
            }
            control = names.contains("control")
            b2 = names.contains("b2")
            jitter = names.contains("jitter")
        }
    }

    static func spec11Guard(_ options: Options) async throws -> Int32 {
        var thresholds: Thresholds = try options.optional("thresholds").map {
            try JSONDecoder().decode(Thresholds.self, from: Data(contentsOf: URL(filePath: $0)))
        } ?? .current
        // Spec 25 §4: `--measurement span|nucleus` overrides `prominence.measurement`; nothing else changes.
        if let name = options.optional("measurement") {
            guard let measurement = SyllableMeasurement(name: name) else {
                throw ToolError.usage("--measurement takes span or nucleus")
            }
            thresholds.prominence.measurement = measurement
        }
        let rows = try GuardRows(options.optional("rows"))
        let label = options.optional("label") ?? (options.optional("thresholds") == nil ? "current" : "custom")
        let seed = try options.optional("seed").map { text -> UInt64 in
            guard let value = UInt64(text) else { throw ToolError.usage("--seed takes an unsigned 64-bit integer") }
            return value
        } ?? 0
        let out = try options.url("out")
        guard options.optional("reference") != nil || options.optional("vctk-inputs") != nil else {
            throw ToolError.usage("spec11-guard needs --reference D (synthetic set) and/or --vctk-inputs F (VCTK set)")
        }
        let harness = try DownstreamHarness(thresholds: thresholds)

        var ctc: CTCAligner?
        var ctcModel: String?
        var ctcMissing: String?
        if !rows.b2 {
            ctcMissing = "not run (--rows)"
        } else if let manifestPath = options.optional("ctc-manifest"), let folder = options.optional("ctc-dir") {
            let manifest = try CTCModelManifest(contentsOf: URL(filePath: manifestPath))
            ctc = try await CTCAligner.load(manifest: manifest, folder: URL(filePath: folder),
                                            thresholds: thresholds.wordBoundaries)
            ctcModel = manifest.packageSHA256
            log("loaded \(manifest.aligner)")
        } else {
            ctcMissing = "b2 model not given (--ctc-manifest and --ctc-dir)"
        }

        var sets: [GuardSet] = []
        var asrModelIDs: [String] = []
        let clock = ContinuousClock()

        // VCTK first: run after WhisperKit had loaded, the VCTK pass was about 50 times slower in a dev run (mostly
        // idle CPU; cause not pinned down), so it runs before the synthetic set loads WhisperKit.
        // Sets are written in a fixed order (synthetic, then VCTK) whatever order they run in.
        if let path = options.optional("vctk-inputs") {
            let start = clock.now
            let (set, asrModelID) = try await guardVCTK(
                inputs: URL(filePath: path), options: options, harness: harness, ctc: ctc, ctcMissing: ctcMissing,
                thresholds: thresholds, seed: seed, rows: rows)
            sets.append(set)
            asrModelIDs.append(asrModelID)
            log("\(set.set): \(set.clips) clips in \(String(format: "%.1f", milliseconds(start.duration(to: clock.now)) / 1000)) s")
        }

        if let path = options.optional("reference") {
            let start = clock.now
            let (set, asrModelID) = try await guardSynthetic(
                folder: URL(filePath: path), options: options, harness: harness, ctc: ctc, ctcMissing: ctcMissing,
                thresholds: thresholds, seed: seed, rows: rows)
            sets.append(set)
            asrModelIDs.append(asrModelID)
            log("synthetic: \(set.clips) phrases in \(String(format: "%.1f", milliseconds(start.duration(to: clock.now)) / 1000)) s")
        }
        sets.sort { ($0.oracle == "tts-markers" ? 0 : 1) < ($1.oracle == "tts-markers" ? 0 : 1) }
        let models = Array(Set(asrModelIDs)).sorted()
        let report = GuardReport(thresholdsLabel: label, measurement: thresholds.prominence.measurement.name,
                                 thresholds: thresholds, seed: seed,
                                 asrModelID: models.isEmpty ? nil : models.joined(separator: " | "),
                                 ctcModel: ctcModel, sets: sets)
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(report, to: out)
        for set in sets {
            for row in set.comparisons {
                let share = row.words == 0 ? "-" : String(format: "%.1f%%", Double(row.differing) / Double(row.words) * 100)
                print("spec11-guard [\(thresholds.prominence.measurement.name)]: \(set.set) \(row.id): \(row.status == "evaluated" ? "\(row.differing)/\(row.words) (\(share)), inconclusive \(row.oracleInconclusive) → \(row.candidateInconclusive)" : "NOT EVALUATED (\(row.reason ?? ""))")")
            }
        }
        print("spec11-guard: → \(out.path)")
        return 0
    }

    /// Synthetic set: oracle TTS markers; Whisper base.en live on the TTS audio, as in the diagnostic round.
    static func guardSynthetic(folder: URL, options: Options, harness: DownstreamHarness, ctc: CTCAligner?,
                               ctcMissing: String?, thresholds: Thresholds, seed: UInt64,
                               rows: GuardRows) async throws -> (GuardSet, String) {
        let markers = try JSONDecoder().decode(MarkerFile.self, from: Data(contentsOf: folder.appending(path: "markers.json")))
        let mfa = try JSONDecoder().decode(WordBaseline.self, from: Data(contentsOf: folder.appending(path: "mfa-alignment.json")))
        let mfaWords = Dictionary(uniqueKeysWithValues: mfa.clips.map { ($0.clipID, $0.words) })
        let (asr, manifest, _, _) = try await loadTimestamper(options)
        var run = GuardAccumulator()
        for phrase in markers.phrases {
            let audio = try WhisperKitTimestamper.samples(fromFileAt: folder.appending(path: "corpus/tts/\(phrase.clipID).wav"))
            let heard = try await asr.wordTimestamps(for: TimestampRequest(clipID: phrase.clipID, samples: audio))
            // The control of record, as `diagnostics` builds it: MFA's spans on the TTS audio on the gate's comparable
            // words (the live Whisper words match them too), each carrying that Whisper word's probability.
            let tokens = harness.tokens(phrase.transcript)
            let mfaPhrase = mfaWords[phrase.clipID] ?? []
            let mfaIndex = Tokens.match(tokens: tokens, words: mfaPhrase.map(\.word))
            let heardIndex = Tokens.match(tokens: tokens, words: heard.map(\.word))
            var control: [Int: ConfidentWord] = [:]
            for position in tokens.indices {
                guard let m = mfaIndex[position], let h = heardIndex[position] else { continue }
                let span = mfaPhrase[m]
                control[position] = .ungated(WordTimestamp(word: span.word, start: span.start, end: span.end,
                                                           probability: heard[h].probability))
            }
            try await guardClip(clipID: phrase.clipID, transcript: phrase.transcript, samples: audio, oracle: phrase.words,
                                heard: heard, control: rows.control ? control : nil, harness: harness, ctc: ctc,
                                thresholds: thresholds, seed: seed, rows: rows, into: &run)
        }
        var set = GuardSet(set: "synthetic", oracle: "tts-markers")
        set.comparisons = [rows.control
            ? GuardComparison(id: "control", candidate: "mfa-on-tts", words: run.words["control"] ?? [])
            : .notEvaluated(id: "control", candidate: "mfa-on-tts", reason: "not run (--rows)")]
        finish(&set, run: run, ctcMissing: ctcMissing, rows: rows)
        return (set, manifest.asrModelID)
    }

    /// VCTK set: oracle the MFA word baseline; Whisper words from a replay directory.
    static func guardVCTK(inputs: URL, options: Options, harness: DownstreamHarness, ctc: CTCAligner?,
                          ctcMissing: String?, thresholds: Thresholds, seed: UInt64,
                          rows: GuardRows) async throws -> (GuardSet, String) {
        let clips = try JSONDecoder().decode([GuardInput].self, from: Data(contentsOf: inputs))
        let baseline = try JSONDecoder().decode(WordBaseline.self, from: Data(contentsOf: try options.url("vctk-baseline")))
        let spans = Dictionary(uniqueKeysWithValues: baseline.clips.map { ($0.clipID, $0.words) })
        let whisper = try FixtureTimestamper(directory: try options.url("vctk-replay"))
        var run = GuardAccumulator()
        var skipped: [String] = []
        for clip in clips {
            guard let oracle = spans[clip.clipID] else { skipped.append("\(clip.clipID): not in the MFA baseline"); continue }
            guard let recording = whisper.recording(for: clip.clipID) else {
                skipped.append("\(clip.clipID): not in the Whisper replay")
                continue
            }
            let samples = try WhisperKitTimestamper.samples(fromFileAt: URL(filePath: clip.audio))
            try await guardClip(clipID: clip.clipID, transcript: clip.transcript, samples: samples, oracle: oracle,
                                heard: recording.words, control: nil, harness: harness, ctc: ctc,
                                thresholds: thresholds, seed: seed, rows: rows, into: &run)
        }
        if !skipped.isEmpty { log("skipped: \(skipped.joined(separator: "; "))") }
        var set = GuardSet(set: options.optional("set-name") ?? "vctk", oracle: "mfa")
        set.clipsSkipped = skipped
        finish(&set, run: run, ctcMissing: ctcMissing, rows: rows)
        return (set, whisper.asrModelID)
    }

    /// The b2 and jitter rows, the set's counts and its status.
    static func finish(_ set: inout GuardSet, run: GuardAccumulator, ctcMissing: String?, rows: GuardRows) {
        set.clips = run.clips
        set.substituted = run.substituted
        set.deleted = run.deleted
        if let ctcMissing {
            set.comparisons.append(.notEvaluated(id: "b2", candidate: CTCAligner.aligner, reason: ctcMissing))
        } else {
            set.comparisons.append(GuardComparison(id: "b2", candidate: CTCAligner.aligner, words: run.words["b2"] ?? [],
                                                   split: true))
        }
        for radius in jitterRadiiMs {
            let id = "jitter-\(radius)"
            set.comparisons.append(rows.jitter
                ? GuardComparison(id: id, candidate: "oracle ±\(radius) ms", words: run.words[id] ?? [],
                                  keptUnjittered: run.kept[id] ?? 0)
                : .notEvaluated(id: id, candidate: "oracle ±\(radius) ms", reason: "not run (--rows)"))
        }
        if run.clips == 0 {
            set.status = "notEvaluated"
            set.reason = "no clips evaluated"
        }
    }

    /// One clip: the control (synthetic only), b2 and the three jitter runs, each through spec 23's `diagnose`.
    static func guardClip(clipID: String, transcript: String, samples: [Float], oracle: [BaselineWord],
                          heard: [WordTimestamp], control: [Int: ConfidentWord]?, harness: DownstreamHarness,
                          ctc: CTCAligner?, thresholds: Thresholds, seed: UInt64, rows: GuardRows,
                          into run: inout GuardAccumulator) async throws {
        let rate = TimestampRequest.sampleRate
        let duration = Double(samples.count) / rate
        // Spec 04's track, once per clip: `.nucleus` finds its nuclei from it, and in both modes it gives the
        // near-edge diagnostic (spec 25, CTO markup 3). `.span` output doesn't read it.
        let pitch = try await PYINTracker(thresholds: thresholds.pitch).track(samples, sampleRate: rate)
        func diagnose(_ id: String, _ candidate: [Int: ConfidentWord]) throws -> DownstreamHarness.Diagnosed {
            let result = try harness.diagnose(transcript: transcript, samples: samples, sampleRate: rate, oracle: oracle,
                                              candidate: candidate, recognised: heard, clipID: clipID, pitch: pitch)
            run.words[id, default: []] += result.words
            return result
        }
        // The Whisper-unmatched counts depend only on the oracle and the recogniser's words: the same for every row.
        var unmatched: (substituted: Int, deleted: Int)?
        if let control {
            let r = try diagnose("control", control)
            unmatched = (r.substituted, r.deleted)
        }
        if let ctc {
            let aligned = try await ctc.align(heard, samples: samples, sampleRate: rate)
            // spec 23's gate: 0 probability below `ctcConfidenceMin`. `diagnose` calls `spanProbability()` with the
            // shipped minimum, so a swapped minimum is applied by mapping each confidence to 0 (below it) or 1.
            let minimum = thresholds.wordBoundaries.ctcConfidenceMin
            let gated = minimum == Thresholds.current.wordBoundaries.ctcConfidenceMin ? aligned : aligned.map {
                ConfidentWord(word: $0.word, confidence: $0.confidence < minimum ? 0 : 1)
            }
            let r = try diagnose("b2", harness.matched(gated, transcript: transcript))
            unmatched = unmatched ?? (r.substituted, r.deleted)
        }

        // Jitter: the comparable words as b2's (oracle-timed, Whisper-matched, with a pronunciation; b2 keeps
        // Whisper's words one for one, so its matches are Whisper's), each carrying the Whisper word's probability.
        let phrase = harness.selector.expectedPhrase(for: PhraseText(text: transcript, origin: .starter))
        let tokens = phrase.words.map { Tokens.normalize($0.text) }
        let oracleIndex = Tokens.match(tokens: tokens, words: oracle.map(\.word))
        let whisper = harness.matched(heard.map(ConfidentWord.ungated), transcript: transcript)
        let positions = phrase.words.indices.filter {
            oracleIndex[$0] != nil && whisper[$0] != nil && phrase.words[$0].pronunciation != nil
        }
        let spans = positions.map { oracle[oracleIndex[$0]!] }
        for radius in jitterRadiiMs where rows.jitter {
            let id = "jitter-\(radius)"
            let moved = Jitter.jitter(spans.map { Jitter.Span(start: $0.start, end: $0.end) }, duration: duration,
                                      radiusMs: radius, seed: seed, clipID: clipID)
            var candidate: [Int: ConfidentWord] = [:]
            for (index, position) in positions.enumerated() {
                candidate[position] = .ungated(WordTimestamp(
                    word: spans[index].word, start: moved[index].span.start, end: moved[index].span.end,
                    probability: whisper[position]!.word.probability))
            }
            run.kept[id, default: 0] += moved.count(where: \.kept)
            let r = try diagnose(id, candidate)
            unmatched = unmatched ?? (r.substituted, r.deleted)
        }
        run.substituted += unmatched?.substituted ?? 0
        run.deleted += unmatched?.deleted ?? 0
        run.clips += 1
    }
}

extension DownstreamHarness {
    /// Spec 23's harness with only the thresholds swapped (spec 11 §4a): the segmenter and its voicing read `thresholds`.
    init(thresholds: Thresholds) throws {
        selector = try PronunciationSelector.bundled()
        segmenter = SyllableSegmenter(voicing: ACFVoicing(thresholds: thresholds), thresholds: thresholds)
    }
}
