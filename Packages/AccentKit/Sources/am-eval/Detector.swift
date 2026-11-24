// Spec 08's real `PlacementDetector` for the shared-detector mode (§6.3), and the corpus and timing plumbing it
// reads. The stages and the placement rule are AMPipeline's `StressPlacementDetector` and AMProsody's
// `placementDecision`; this file only adapts them to spec 02's protocol. Word timings are replayed (recorded once by
// `am-eval record-timings`); nothing here runs ASR except that command, and nothing touches the network.

import AMAlignment
import AMCore
import AMEvaluation
import AMPipeline
import AMProsody
import Foundation

// MARK: - speechocean762 on disk

/// The fetched speechocean762 corpus: transcripts, WAV paths and the per-word reference phones.
struct SpeechOceanCorpusFiles: SpeechOceanCorpus {
    let root: URL
    private let texts: [String: [String]]
    private let wavs: [String: String]
    /// utterance → word index → ARPAbet with stress digits (`resource/text-phone`).
    private let phones: [String: [Int: String]]

    init(root: URL) throws {
        self.root = root
        var texts: [String: [String]] = [:], wavs: [String: String] = [:]
        for half in ["train", "test"] {
            for line in try Self.lines(root.appendingPathComponent("\(half)/text")) {
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                texts[parts[0]] = parts[1].split(separator: " ").map(String.init)
            }
            for line in try Self.lines(root.appendingPathComponent("\(half)/wav.scp")) {
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                if parts.count == 2 { wavs[parts[0]] = parts[1] }
            }
        }
        var phones: [String: [Int: String]] = [:]
        for line in try Self.lines(root.appendingPathComponent("resource/text-phone")) {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            let key = parts[0].split(separator: ".")
            guard parts.count == 2, key.count == 2, let index = Int(key[1]) else { continue }
            // "K_B AO0_I L_E" → "K AO0 L"
            let arpabet = parts[1].split(separator: " ").map { $0.split(separator: "_").first.map(String.init) ?? "" }
            phones[String(key[0]), default: [:]][index] = arpabet.joined(separator: " ")
        }
        self.texts = texts
        self.wavs = wavs
        self.phones = phones
    }

    static func lines(_ url: URL) throws -> [Substring] {
        try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
    }

    func audioURL(utterance: String) -> URL { root.appendingPathComponent(wavs[utterance] ?? "missing/\(utterance).WAV") }
    func transcript(utterance: String) -> [String] { texts[utterance] ?? [] }
    func phones(utterance: String, index: Int) -> String? { phones[utterance]?[index] }
}

// MARK: - Pronunciations and A(w)

/// Spec 06's POS-selected CMUdict variant for the dictionary fallback of A(w) (§6.3).
struct SelectorPrimaryLookup: DictionaryPrimaryLookup {
    let selector: PronunciationSelector

    func primary(of words: [String], at index: Int, syllableCount: Int) -> Int? {
        let expected = selector.expectedPhrase(for: PhraseText(
            text: words.joined(separator: " "), origin: .imported(persisted: [:])))
        guard index < expected.words.count, let pattern = expected.words[index].expectedPattern,
            pattern.count == syllableCount
        else { return nil }
        return pattern.firstIndex(of: .primary)
    }
}

/// The first candidate that parses as a pronunciation (the corpus has a vowel without a stress digit, "HERE"
/// `HH IH AH0`), else `fallbackPhones`.
func referencePhones(_ candidates: String?..., text: String, dictionary: PronouncingDictionary) -> String {
    for candidate in candidates {
        if let candidate, (try? Pronunciation(arpabet: candidate)) != nil { return candidate }
    }
    return fallbackPhones(text, dictionary: dictionary)
}

/// A pronunciation for a word with no reference phones: CMUdict's first variant, else one schwa per spelling
/// syllable (an out-of-vocabulary word still needs a syllable count to be segmented).
func fallbackPhones(_ text: String, dictionary: PronouncingDictionary) -> String {
    let folded = WordText.fold(text)
    if let first = dictionary.pronunciations(of: folded).first { return first.arpabet }
    let count = max(Syllabifier.spellingSyllables(of: folded).count, 1)
    return Array(repeating: "AH0", count: count).joined(separator: " ")
}

// MARK: - The detector

/// Spec 08's shared detector over replayed word timings.
struct ReplayedPlacementDetector: PlacementDetector {
    let corpus: SpeechOceanCorpusFiles
    let timings: FixtureTimestamper
    /// Labelled word id → ref-phones (the label fixture), for the decided words.
    let refPhones: [String: String]
    let dictionary: PronouncingDictionary

    var id: String { "spec08-shared-detector" }

    func placements(for utterance: DetectorUtterance, config: FoldConfig) async throws -> [String: PlacementOutcome] {
        let decided = Dictionary(utterance.words.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let words = utterance.transcript.enumerated().map { index, text in
            let word = decided[index]
            let phones = referencePhones(
                word.flatMap { refPhones[$0.id] }, corpus.phones(utterance: utterance.id, index: index), text: text,
                dictionary: dictionary)
            return PlacementFixtureItem.Word(
                id: word?.id, index: index, text: text, phones: phones,
                accepted: word.map { Array($0.accepted.primaries).sorted() })
        }
        let item = PlacementFixtureItem(
            item: utterance.id, corpus: "speechocean762", speaker: utterance.speaker, audio: utterance.audio.path,
            audioSHA256: try sha256(of: utterance.audio), words: words)
        let analysis = try await analyse(item, audio: utterance.audio, config: config.thresholds)
        var outcomes: [String: PlacementOutcome] = [:]
        for result in analysis.words {
            guard let id = decided[result.word.rawValue]?.id else { continue }
            outcomes[id] = PlacementOutcome(
                present: result.present, flaggedBeforeSuppression: result.flaggedBeforeSuppression,
                suppression: result.suppression.map(PlacementSuppression.init))
        }
        return outcomes
    }

    func analyse(_ item: PlacementFixtureItem, audio: URL, config: Thresholds) async throws -> PlacementAnalysis {
        try await analysePlacement(item, audio: audio, timings: timings, thresholds: config)
    }
}

/// Runs the shipped stages on one item with replayed timings (shared by the l2-shared run and the smoke goldens).
func analysePlacement(
    _ item: PlacementFixtureItem, audio: URL, timings: FixtureTimestamper, thresholds: Thresholds
) async throws -> PlacementAnalysis {
    let (samples, rate) = try AudioFiles.readMono(audio)
    let mono16k = try AudioFiles.resample(samples, from: rate, to: 16_000)
    let heard = try await timings.wordTimestamps(for: TimestampRequest(clipID: item.item, samples: []))
    let take = try item.take(samples: mono16k, sampleRate: 16_000, heard: heard, asrModelID: timings.asrModelID)
    return try await StressPlacementDetector.bundled(thresholds: thresholds).analyse(take)
}

extension PlacementSuppression {
    init(_ suppression: DetectorSuppression) {
        switch suppression {
        case .poorTiming: self = .poorTiming
        case .lowWordConfidence: self = .lowWordConfidence
        case .placement(.lowSyllableConfidence): self = .lowSyllableConfidence
        case .placement(.exposedSyllable): self = .exposedSyllable
        case .placement(.stressConfidenceBelowHigh): self = .stressConfidenceBelowHigh
        }
    }
}

// MARK: - Recording word timings (local only; never CI)

/// Runs WhisperKit over `clips` (id → audio file) and writes replay JSON plus `manifest.json`.
func recordTimings(
    _ clips: [(id: String, audio: URL)], modelDir: URL, manifest: URL, attribution: String, out: URL,
    keeping kept: [ReplayManifest.Entry] = []
) async throws -> ReplayManifest {
    let model = try ModelManifest(contentsOf: manifest)
    try model.verify(folder: modelDir)
    let whisper = try await WhisperKitTimestamper.load(manifest: model, folder: modelDir)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var entries: [ReplayManifest.Entry] = kept
    for (n, clip) in clips.enumerated() {
        let samples = try WhisperKitTimestamper.samples(fromFileAt: clip.audio)
        let (text, words) = try await whisper.transcribe(TimestampRequest(clipID: clip.id, samples: samples))
        let recording = RecordedTimestamps(
            clipID: clip.id, audioSHA256: try sha256(of: clip.audio), asrModelID: model.asrModelID, text: text,
            words: words)
        let file = "\(clip.id).json"
        let data = try encoder.encode(recording) + Data("\n".utf8)
        try data.write(to: out.appendingPathComponent(file), options: .atomic)
        entries.append(.init(clipID: clip.id, file: file, sha256: SHA256Digest.hex(of: data)))
        if (n + 1) % 100 == 0 { print("record-timings: \(n + 1) of \(clips.count)") }
    }
    entries.sort { $0.clipID < $1.clipID }
    let replay = ReplayManifest(asrModelID: model.asrModelID, attribution: attribution, clips: entries)
    try (encoder.encode(replay) + Data("\n".utf8))
        .write(to: out.appendingPathComponent(ReplayManifest.fileName), options: .atomic)
    return replay
}
