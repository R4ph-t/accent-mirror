// One `synthref run`: engine choice, voice verification on the verification items, the reference choice, the
// end-to-end check (ii) and the synthetic negative set, written as one report whose first line is the
// `syntheticReference` header. Anything that cannot run says NOT EVALUATED with the reason; nothing here is a pass by
// default, and nothing here feeds tuning, the smoke set or a main gate.

import AMAlignment
import AMCapture
import AMCore
import AMEvaluation
import AMPipeline
import AMPitch
import Foundation

public struct RunOptions: Sendable {
    public var repositoryRoot: URL
    public var offline = false
    /// ElevenLabs voice IDs to verify (used only with a key).
    public var elevenLabsVoices: [String] = []
    /// Mac voice identifiers to verify; empty means every installed Premium English voice.
    public var macVoices: [String] = []
    /// Trimmed VCTK clips (`trim-report.json` + `<speaker>/<speaker>_<phrase>.flac`).
    public var vctk: URL
    /// Replayed word timings for VCTK tuning speakers' clips (FixtureTimestamper layout).
    public var vctkTimings: URL
    public var speechOcean: URL
    public var speechOceanTimings: URL
    public var reportDirectory: URL
    public var manifest: URL
    public var environment: [String: String] = ProcessInfo.processInfo.environment

    public init(repositoryRoot root: URL) {
        repositoryRoot = root
        vctk = root.appendingPathComponent("eval-cache/vctk/current")
        vctkTimings = root.appendingPathComponent("eval-cache/vctk-tuning-timings")
        speechOcean = root.appendingPathComponent("eval-cache/speechocean762/current")
        speechOceanTimings = root.appendingPathComponent("eval-cache/speechocean762-timings")
        reportDirectory = root.appendingPathComponent("eval-cache/tts/reports")
        manifest = root.appendingPathComponent("fixtures/tts/digests.json")
    }
}

public struct SynthRefRun {
    public let options: RunOptions
    public private(set) var lines: [String] = []
    var entries: [DigestManifest.Entry] = []
    var apiCalls = 0
    var cacheHits = 0

    public init(options: RunOptions) { self.options = options }

    mutating func say(_ line: String) {
        lines.append(line)
        print(line)
    }

    /// Runs every section and returns the report's lines.
    public mutating func run() async throws -> [String] {
        let choice = EngineChoice.choose(environment: options.environment, offline: options.offline)
        say(choice.headerLine)
        let thresholds = Thresholds.current
        let set = try VerificationSet.build(dictionary: try .bundled(), stressShifts: try .bundled())
        let characters = set.items.map { SSML.elevenLabs([SpokenWord(text: $0.word, arpabet: $0.arpabet)]).count }
            .reduce(0, +)
        say("verification items: \(set.targets.count) CPO target words, \(set.traps.count) stress traps "
            + "(\(set.traps.joined(separator: ", "))), \(set.items.count) items (correct + moved), "
            + "\(characters) characters per voice as ElevenLabs SSML")
        say("thresholds: initial, untuned (thresholdsVersion \(Versions.thresholdsVersion)); moved ≥ "
            + "\(thresholds.agreement.voiceMovedStressMin), correct ≥ \(thresholds.agreement.voiceCorrectStressMin), "
            + "positive-set placement FP ≤ \(thresholds.agreement.placementDiffPairsMax)")

        let installed = InstalledVoices.english()
        say("installed English voices: \(installed.count) (Premium \(installed.count { $0.quality == .premium }), "
            + "Enhanced \(installed.count { $0.quality == .enhanced })); none downloaded")
        for voice in installed { say("  voice: \(voice.line)") }

        var engines: [any SpeechEngine] = []
        switch choice {
        case .elevenLabs(let key):
            if options.elevenLabsVoices.isEmpty {
                say("ElevenLabs: NOT EVALUATED (no voice IDs given: --elevenlabs-voice <id>)")
            }
            engines += options.elevenLabsVoices.map {
                ElevenLabsEngine(key: key, voiceID: $0, transport: URLSessionTransport())
            }
        case .macFallback(let reason):
            say("ElevenLabs: NOT RUN (\(reason)); every metric below is labelled mac-premium-fallback (\(reason))")
        }
        let premium = InstalledVoices.fallbackCandidates(installed)
            .filter { options.macVoices.isEmpty || options.macVoices.contains($0.identifier) }
        if premium.isEmpty {
            say("Mac Premium fallback: NOT EVALUATED (no Premium English voice installed; the tool never downloads "
                + "voices; Enhanced and standard voices are not fallback voices)")
        }
        engines += premium.map { MacPremiumEngine(voice: $0) }

        let positive = positiveSetStatus()
        say("positive set: \(positive.text)")
        let tuning = try await tuningTakes(thresholds: thresholds)
        say("VCTK tuning takes with replayed word timings: \(tuning.takes.count)\(tuning.note.map { " (\($0))" } ?? "")")

        var verifications: [VoiceVerification] = []
        let cache = TTSCache.default(repositoryRoot: options.repositoryRoot)
        for engine in engines {
            do {
                verifications.append(try await verify(
                    engine, set: set, cache: cache, tuning: tuning.takes, positive: positive, thresholds: thresholds))
            } catch {
                say("voice \(engine.identity.label): NOT EVALUATED (\(error))")
            }
        }

        let reference = VoiceSelection.reference(verifications)
        if let reference {
            say("reference voice: \(reference.voice.label) (\(reference.voice.kind == .elevenlabs ? "default" : "fallback"))")
        } else {
            say("reference voice: none passed verification. End-to-end check (ii): NOT EVALUATED; the release is "
                + "blocked until CTO decides")
        }
        try await endToEnd(reference: reference, engines: engines, cache: cache, thresholds: thresholds)
        try await negativeSet(tuning: tuning.takes, thresholds: thresholds)

        say("API calls \(apiCalls), cache hits \(cacheHits); audio only under eval-cache/tts/ (git-ignored)")
        let manifest = DigestManifest(
            syntheticReference: choice.syntheticReference.description, items: set.items.map(\.id), entries: entries)
        try manifest.write(to: options.manifest)
        say("digest manifest: \(manifest.entries.count) renderings, \(manifest.totalCharacters) characters")
        return lines
    }

    // MARK: Voice verification

    mutating func render(_ request: SynthesisRequest, _ engine: any SpeechEngine, cache: TTSCache) async throws
        -> CachedRendering
    {
        let rendering = try await cache.render(request, with: engine)
        if rendering.cacheHit { cacheHits += 1 } else if engine.identity.kind == .elevenlabs { apiCalls += 1 }
        entries.append(DigestManifest.Entry(rendering.key, digest: rendering.digest))
        return rendering
    }

    mutating func verify(
        _ engine: any SpeechEngine, set: VerificationSet, cache: TTSCache, tuning: [NativeTake],
        positive: PositiveSetStatus, thresholds: Thresholds
    ) async throws -> VoiceVerification {
        var observations: [ItemObservation] = []
        var pairs: [String: (correct: SynthesizedAudio?, moved: SynthesizedAudio?)] = [:]
        for item in set.items {
            let rendering = try await render(
                SynthesisRequest(words: [SpokenWord(text: item.word, arpabet: item.arpabet)]), engine, cache: cache)
            observations.append(try await ItemObservation.observe(
                item, audio: rendering.audio, l0Key: rendering.digest, thresholds: thresholds))
            switch item.variant {
            case .correct: pairs[item.word, default: (nil, nil)].correct = rendering.audio
            case .moved: pairs[item.word, default: (nil, nil)].moved = rendering.audio
            }
        }
        let ssml = SSMLCheck.check(pairs.compactMapValues { p in p.correct.flatMap { c in p.moved.map { (c, $0) } } })

        // The voice as the reference for the VCTK tuning speakers only.
        var outcomes: [TuningPairOutcome] = []
        let selector = try PronunciationSelector.bundled()
        var references: [String: (words: [PlacementTake.Word], analysis: PlacementAnalysis)] = [:]
        for take in tuning {
            if references[take.phrase] == nil, let text = CPOSet.phrases[take.phrase] {
                let words = try SyntheticScoring.words(text: text.lowercased(), selector: selector)
                let rendering = try await render(
                    SynthesisRequest(words: words.map { SpokenWord(text: $0.text) }), engine, cache: cache)
                references[take.phrase] = (words, try await SyntheticScoring.analyse(
                    samples: rendering.audio.samples, words: words,
                    heard: SyntheticScoring.heard(rendering.audio, words: words), l0Key: rendering.digest,
                    thresholds: thresholds))
            }
            guard let reference = references[take.phrase],
                let scoring = try? SyntheticScoring.score(
                    words: reference.words, you: take.analysis, reference: reference.analysis,
                    voice: engine.identity.label, thresholds: thresholds)
            else { continue }
            outcomes.append(TuningPairOutcome(
                speaker: take.speaker, phrase: take.phrase,
                placementDiff: !SyntheticScoring.placementWords(scoring).isEmpty))
        }
        let fp = PlacementFalsePositives.line(outcomes, positiveSet: positive, thresholds: thresholds)
        let verification = VoiceVerification(
            voice: engine.identity, observations: observations, ssml: ssml, placementFP: fp, thresholds: thresholds)
        say("voice \(engine.identity.label):")
        say("  \(Self.describe(verification.moved))")
        say("  \(Self.describe(verification.correct))")
        say("  \(Self.describe(fp))")
        say("  \(ssml.line)")
        say("  \(verification.trapLine)")
        say("  kept: \(verification.kept ? "yes" : "no")")
        return verification
    }

    // MARK: Positive set and tuning takes

    func positiveSetStatus() -> PositiveSetStatus {
        let root = options.repositoryRoot
        guard let manifest = try? VCTKEvalSpeakersManifest.load(root.appendingPathComponent("fixtures/vctk/eval-speakers.json")),
            let table = try? VCTKSubPhraseTable.load(root.appendingPathComponent("fixtures/vctk/sub-phrases.json")),
            let kept = keptClips()
        else {
            return .notEvaluated(shortfalls: ["no trimmed VCTK cache"], blockedOn: "a local VCTK cache (scripts/fetch-vctk-eval.sh)")
        }
        return VCTKPairs(manifest: manifest, available: Set(kept), phrases: table.evaluationPhrases).status()
    }

    func keptClips() -> [VCTKClip]? {
        guard let data = try? Data(contentsOf: options.vctk.appendingPathComponent("trim-report.json")),
            let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kept = report["kept"] as? [String]
        else { return nil }
        return kept.compactMap { name in
            let parts = name.split(separator: "_")
            return parts.count == 2 ? VCTKClip(speaker: String(parts[0]), phrase: String(parts[1])) : nil
        }
    }

    /// Tuning speakers' takes of CPO's phrases that have replayed word timings, analysed with the shipped stages.
    func tuningTakes(thresholds: Thresholds) async throws -> (takes: [NativeTake], note: String?) {
        let manifest = try VCTKEvalSpeakersManifest.load(
            options.repositoryRoot.appendingPathComponent("fixtures/vctk/eval-speakers.json"))
        guard let kept = keptClips() else { return ([], "no trimmed VCTK cache") }
        guard FileManager.default.fileExists(atPath: options.vctkTimings.appendingPathComponent(ReplayManifest.fileName).path)
        else {
            return ([], "no replayed word timings for VCTK tuning speakers at \(options.vctkTimings.lastPathComponent)/; "
                + "recording them needs an am-eval record-timings set, which spec 22 does not add")
        }
        let timings = try FixtureTimestamper(directory: options.vctkTimings)
        let speakers = Dictionary(manifest.tuningSpeakers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let selector = try PronunciationSelector.bundled()
        var takes: [NativeTake] = []
        for clip in kept {
            guard let speaker = speakers[clip.speaker], let text = CPOSet.phrases[clip.phrase] else { continue }
            let id = "\(clip.speaker)_\(clip.phrase)"
            guard timings.recording(for: id) != nil else { continue }
            let url = options.vctk.appendingPathComponent("\(clip.speaker)/\(id).flac")
            let (raw, rate) = try AudioFiles.readMono(url)
            let samples = try AudioFiles.resample(raw, from: rate, to: 16_000)
            let words = try SyntheticScoring.words(text: text.lowercased(), selector: selector)
            let heard = try await timings.wordTimestamps(for: TimestampRequest(clipID: id, samples: []))
            let analysis = try await SyntheticScoring.analyse(
                samples: samples, words: words, heard: heard, l0Key: id, thresholds: thresholds)
            takes.append(NativeTake(
                speaker: speaker, phrase: clip.phrase, samples: samples, words: words, heard: heard, analysis: analysis))
        }
        return (takes, nil)
    }

    // MARK: End-to-end (ii)

    mutating func endToEnd(
        reference: VoiceVerification?, engines: [any SpeechEngine], cache: TTSCache, thresholds: Thresholds
    ) async throws {
        guard let reference, let engine = engines.first(where: { $0.identity == reference.voice }) else {
            say("End-to-end check (ii): NOT EVALUATED (no verified synthetic reference)")
            return
        }
        guard let corpus = try? SpeechOceanFiles(root: options.speechOcean),
            let timings = try? FixtureTimestamper(directory: options.speechOceanTimings)
        else {
            say("End-to-end check (ii): NOT EVALUATED (no speechocean762 corpus or replayed timings in eval-cache/)")
            return
        }
        let labels = try SpeechOceanLabels.parseFixture(String(
            contentsOf: options.repositoryRoot.appendingPathComponent("fixtures/speechocean762/labels.tsv"), encoding: .utf8))
        let sets = SpeechOceanSets(labels: labels)
        let path = EndToEndPath(scorer: PipelineEndToEndScorer(
            corpus: corpus, timings: timings, cache: cache, engine: engine, selector: try .bundled()))
        let shipped = try FoldConfig(
            identity: ConfigIdentity(
                asrModelID: "replayed-word-timings", pitchTrackerID: PYINTracker.trackerID,
                voicingID: ACFVoicing.voicingID),
            thresholds: thresholds)
        let recall = try await path.run(config: shipped, words: sets.recall)
        let hits = sets.recall.count { recall[$0.id] == true }
        say("End-to-end check (ii), \(reference.voice.label): recall \(hits) of \(sets.recall.count) under the shipped "
            + "config (reported; the fold-trained run goes through FoldRunner with the shared-detector path, spec 11)")
        let fp = EndToEndReport.falsePositiveLine(
            flags: try await path.run(config: shipped, words: sets.cleanFalsePositive), clean: sets.cleanFalsePositive)
        say(Self.describe(fp) + " (spec 11 gates it)")
    }

    // MARK: Negative set

    mutating func negativeSet(tuning: [NativeTake], thresholds: Thresholds) async throws {
        let rubberBand = RubberBandCLI.locate()
        if rubberBand == nil { say("Rubber Band: NOT EVALUATED (CLI not installed; never linked, never installed by this tool)") }
        guard !tuning.isEmpty else {
            say("Synthetic negative set: NOT EVALUATED (no analysed VCTK tuning takes)")
            return
        }
        guard let magnitudes = NativeContrast.magnitudes(tuning.flatMap(\.contrasts)) else {
            say("Synthetic negative set: NOT EVALUATED (no clear native contrast to calibrate on)")
            return
        }
        for level in MagnitudeLevel.allCases {
            if let m = magnitudes[level] {
                say(String(format: "magnitude %@: +%.2f st, ×%.2f duration, +%.1f dB", level.rawValue, m.semitones,
                           m.durationRatio, m.gainDB))
            }
        }
        let builder = NegativeSetBuilder(
            magnitudes: magnitudes, rubberBand: rubberBand,
            scratch: options.repositoryRoot.appendingPathComponent("eval-cache/tts/negative-scratch"),
            thresholds: thresholds)
        var edited: [EditedWord] = []
        for take in tuning { edited += try await builder.edits(of: take) }
        for dsp in DSP.allCases where dsp == .tdpsola || rubberBand != nil {
            say(Self.describe(NegativeSetMetrics.whichSyllable(edited, dsp: dsp, thresholds: thresholds)))
            say(Self.describe(NegativeSetMetrics.controls(edited, dsp: dsp, thresholds: thresholds)))
        }
        say(Self.describe(NegativeSetMetrics.dspAgreement(edited, thresholds: thresholds)))
        let shifts = edited.filter(\.isEdit).compactMap(\.achievedSemitones).sorted()
        if !shifts.isEmpty { say(String(format: "re-measured F0 shift on edits: median %+.2f st", shifts[shifts.count / 2])) }
    }

    static func describe(_ m: MetricResult) -> String {
        let value = m.value.map { String(format: "%.3f", $0) } ?? "–"
        let gate = m.gate.map { " gate \($0.direction == .atLeast ? "≥" : "≤") \($0.bound)" } ?? ""
        return "\(m.name): n \(m.n), value \(value),\(gate): \(m.status.text)"
    }

    /// Writes the report under `reportDirectory` (git-ignored) and returns its URL.
    public func writeReport() throws -> URL {
        try FileManager.default.createDirectory(at: options.reportDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let url = options.reportDirectory.appendingPathComponent("synthref-\(stamp).md")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
