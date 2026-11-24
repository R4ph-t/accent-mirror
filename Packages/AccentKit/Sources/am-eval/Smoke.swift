// Spec 08's smoke-set placement goldens and the word-timing recorder. Recording runs WhisperKit locally, once; the
// goldens replay those timings, so `make test` (AMPipelineTests) checks them with no ASR, corpus or tagger.

import AMAlignment
import AMCore
import AMEvaluation
import AMPipeline
import Foundation

let smokeAttribution = "Word timings recognised from the smoke set's audio (fixtures/smoke/ATTRIBUTION.md): "
    + "speechocean762 (OpenSLR 101, SpeechOcean) and CSTR VCTK Corpus 0.92, both CC BY 4.0"

/// The smoke set's clip id for a manifest file: its file stem.
func smokeClipID(_ file: SmokeManifest.File) -> String {
    URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
}

func recordTimingsCommand(_ args: Arguments, root: URL) async throws -> Int32 {
    let model = Paths.whisperModel
    let modelDir = args.value("model-dir").map(URL.init(fileURLWithPath:))
        ?? (ProcessInfo.processInfo.environment["MODELS_CACHE"].map(URL.init(fileURLWithPath:))
            ?? root.appendingPathComponent(".cache/models")).appendingPathComponent(model)
    let manifest = root.appendingPathComponent("Resources/Models/\(model)/manifest.json")
    let clips: [(id: String, audio: URL)]
    let out: URL
    let attribution: String
    switch try args.required("set") {
    case "smoke":
        let dir = root.appendingPathComponent(Paths.smoke)
        let smoke = try SmokeManifest.load(dir.appendingPathComponent("manifest.json"))
        clips = smoke.files.map { (smokeClipID($0), dir.appendingPathComponent($0.path)) }
        out = args.value("out").map(URL.init(fileURLWithPath:))
            ?? root.appendingPathComponent("\(Paths.smokeDetector)/timestamps")
        attribution = smokeAttribution
    case "positive":
        let root = root
        let manifest = try VCTKEvalSpeakersManifest.load(root.appendingPathComponent(Paths.evalSpeakers))
        let cacheDir = args.value("vctk").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.vctkCache)
        guard let cache = PositiveCache(cacheDir) else {
            throw CLIError.failed("no trimmed VCTK cache at \(cacheDir.path) (scripts/fetch-vctk-eval.sh)")
        }
        clips = cache.timingClips(manifest: manifest).map {
            ("\($0.speaker)_\($0.phrase)", vctkAudio(cacheDir, speaker: $0.speaker, phrase: $0.phrase))
        }
        out = args.value("out").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.vctkTimings)
        attribution = vctkAttribution
    case "l2-shared":
        let corpusDir = args.value("corpus").map(URL.init(fileURLWithPath:))
            ?? cacheURL(root, Paths.so762Cache)
        let corpus = try SpeechOceanCorpusFiles(root: corpusDir)
        let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
        let sets = SpeechOceanSets(labels: labels)
        let utterances = Set((sets.recall + sets.cleanFalsePositive + sets.unintelligible).map(\.utterance)).sorted()
        clips = utterances.map { ($0, corpus.audioURL(utterance: $0)) }
        out = args.value("out").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.so762Timings)
        attribution = "speechocean762 (OpenSLR 101, SpeechOcean), CC BY 4.0; local evaluation cache, never committed"
    case "vctk-tuning":
        // Spec 11: the VCTK tuning speakers' takes, for the tuning objective and the guard on tuning data.
        let manifest = try VCTKEvalSpeakersManifest.load(root.appendingPathComponent(Paths.evalSpeakers))
        let cacheDir = args.value("vctk").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.vctkCache)
        guard let cache = PositiveCache(cacheDir) else {
            throw CLIError.failed("no trimmed VCTK cache at \(cacheDir.path) (scripts/fetch-vctk-eval.sh)")
        }
        clips = cache.tuningClips(manifest: manifest).map {
            ("\($0.speaker)_\($0.phrase)", vctkAudio(cacheDir, speaker: $0.speaker, phrase: $0.phrase))
        }
        out = args.value("out").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.vctkTuningTimings)
        attribution = vctkAttribution
    case "l2-tuning":
        // Spec 11: every utterance the tuning pool and the release's L2 rows read (the tuning-correct train-half
        // words and the 1,868-word supplementary set on top of l2-shared's sets). Use with --append.
        let corpusDir = args.value("corpus").map(URL.init(fileURLWithPath:))
            ?? cacheURL(root, Paths.so762Cache)
        let corpus = try SpeechOceanCorpusFiles(root: corpusDir)
        let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
        let sets = SpeechOceanSets(labels: labels)
        let words = sets.recall + sets.cleanFalsePositive + sets.unintelligible + sets.tuningCorrect
            + sets.supplementaryFalsePositive
        clips = Set(words.map(\.utterance)).sorted().map { ($0, corpus.audioURL(utterance: $0)) }
        out = args.value("out").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.so762Timings)
        attribution = "speechocean762 (OpenSLR 101, SpeechOcean), CC BY 4.0; local evaluation cache, never committed"
    case let other:
        throw CLIError.usage("record-timings --set smoke|l2-shared|l2-tuning|positive|vctk-tuning (got \(other))")
    }
    // --append keeps an existing recording directory's clips and records only the missing ones (spec 11).
    var kept: [ReplayManifest.Entry] = []
    var todo = clips
    if args.flag("append"),
        let data = try? Data(contentsOf: out.appendingPathComponent(ReplayManifest.fileName)),
        let existing = try? JSONDecoder().decode(ReplayManifest.self, from: data)
    {
        let wanted = Set(clips.map(\.id))
        kept = existing.clips.filter { wanted.contains($0.clipID) }
        let have = Set(kept.map(\.clipID))
        todo = clips.filter { !have.contains($0.id) }
        print("record-timings: --append keeps \(kept.count) recorded clips, records \(todo.count)")
    }
    print("record-timings: \(todo.count) clips with \(model) → \(out.path)")
    let replay = try await recordTimings(
        todo, modelDir: modelDir, manifest: manifest, attribution: attribution, out: out, keeping: kept)
    print("record-timings: wrote \(replay.clips.count) recordings; recordingsSHA256 \(replay.recordingsSHA256)")
    return 0
}

/// Builds the smoke set's detector inputs from the corpora: transcripts, reference pronunciations and A(w).
func buildSmokeInputs(root: URL, corpusDir: URL) throws -> PlacementFixtureFile {
    let smoke = try SmokeManifest.load(root.appendingPathComponent("\(Paths.smoke)/manifest.json"))
    let corpus = try SpeechOceanCorpusFiles(root: corpusDir)
    let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
    let byID = Dictionary(labels.words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let selector = try PronunciationSelector.bundled()
    let dictionary = try PronouncingDictionary.bundled()
    let lookup = SelectorPrimaryLookup(selector: selector)
    struct Baseline: Decodable {
        struct Clip: Decodable {
            struct Word: Decodable { let word: String }
            let clipID: String
            let words: [Word]
        }
        let clips: [Clip]
    }
    let baseline = try JSONDecoder().decode(
        Baseline.self, from: Data(contentsOf: root.appendingPathComponent(Paths.mfaBaseline)))
    var items: [PlacementFixtureItem] = []
    for file in smoke.files {
        var words: [PlacementFixtureItem.Word] = []
        if file.corpus == "speechocean762" {
            let transcript = corpus.transcript(utterance: file.item)
            let decided = Dictionary(file.words.compactMap { byID[$0.id] }.map { ($0.index, $0) },
                                     uniquingKeysWith: { first, _ in first })
            for (index, text) in transcript.enumerated() {
                let label = decided[index]
                let phones = referencePhones(
                    label?.refPhones, corpus.phones(utterance: file.item, index: index), text: text,
                    dictionary: dictionary)
                let accepted = label.flatMap {
                    SharedDetectorAcceptedSet.of($0, transcript: transcript, dictionary: lookup)
                }.map { Array($0.primaries).sorted() }
                words.append(.init(id: label?.id, index: index, text: text, phones: phones, accepted: accepted))
            }
        } else {
            // VCTK shared text, as read by every speaker (spec 03's MFA baseline holds p225's words).
            guard let clip = baseline.clips.first(where: { $0.clipID.hasSuffix("_\(file.item)") }) else {
                throw CLIError.failed("no transcript for VCTK \(file.item)")
            }
            // A bundled-voice phrase: the starter rule (overrides only, no tagger), so stress-shift words are
            // expectedAmbiguous and get no decision.
            words = starterPhraseWords(
                clip.words.map(\.word).joined(separator: " "), selector: selector, dictionary: dictionary)
        }
        items.append(PlacementFixtureItem(
            item: smokeClipID(file), corpus: file.corpus, speaker: file.speaker, audio: file.path,
            audioSHA256: file.sha256, words: words))
    }
    return PlacementFixtureFile(attribution: smokeAttribution, items: items)
}

func encodeFixture<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value) + Data("\n".utf8)
}

/// Checks (or with `--record`, writes) the smoke set's L1 digests and placements before and after suppression.
func smokeDetector(_ args: Arguments, root: URL) async throws -> Int32 {
    let dir = root.appendingPathComponent(Paths.smokeDetector)
    let inputsURL = dir.appendingPathComponent("inputs.json")
    if args.flag("build-inputs") {
        let corpus = args.value("corpus").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.so762Cache)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encodeFixture(try buildSmokeInputs(root: root, corpusDir: corpus)).write(to: inputsURL, options: .atomic)
        print("smoke-detector: wrote \(inputsURL.path)")
    }
    let inputs = try JSONDecoder().decode(PlacementFixtureFile.self, from: Data(contentsOf: inputsURL))
    let timings = try FixtureTimestamper(directory: dir.appendingPathComponent("timestamps"))
    var analyses: [String: PlacementAnalysis] = [:]
    for item in inputs.items {
        analyses[item.item] = try await analysePlacement(
            item, audio: root.appendingPathComponent("\(Paths.smoke)/\(item.audio)"), timings: timings,
            thresholds: .current)
    }
    // Spec 10: each VCTK item's verdict against another smoke speaker of its phrase (never a rate gate).
    let candidates = SmokeVerdict.candidates(inputs.items)
    let goldens = try inputs.items.map { item in
        let verdict = try candidates[item.item].map { models in
            try SmokeVerdict.score(
                item: item, analysis: analyses[item.item]!, candidates: models.map { ($0, analyses[$0.item]!) })
        }
        return try PlacementGolden(item: item, analysis: analyses[item.item]!, verdict: verdict)
    }
    for golden in goldens { if let v = golden.verdict { print("smoke-detector: verdict \(golden.item) vs \(v.model ?? "–"): \(v.decision.map { "\($0)" } ?? v.unscored ?? "–")") } }
    let file = PlacementGoldenFile(asrModelID: timings.asrModelID, items: goldens)
    let words = goldens.flatMap(\.words)
    print("smoke-detector: \(goldens.count) items, \(words.count) decided words, \(words.count(where: \.present)) present; flagged before suppression \(words.count(where: \.flaggedBeforeSuppression)), after \(words.count(where: \.flaggedAfterSuppression)) (never a rate gate)")
    let goldenURL = dir.appendingPathComponent("goldens.json")
    if args.flag("record") {
        try encodeFixture(file).write(to: goldenURL, options: .atomic)
        print("smoke-detector: recorded \(goldenURL.path)")
        return 0
    }
    let committed = try JSONDecoder().decode(PlacementGoldenFile.self, from: Data(contentsOf: goldenURL))
    let differing = zip(committed.items, file.items).filter { $0 != $1 }.map(\.0.item)
    let same = committed == file
    print("smoke-detector: goldens \(same ? "match" : "DIFFER (\(differing.joined(separator: ", ")))")")
    return same ? 0 : 1
}
