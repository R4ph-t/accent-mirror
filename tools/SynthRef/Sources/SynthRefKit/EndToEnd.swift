// End-to-end check (ii) (plan §6.3): each speechocean762 utterance's text, rendered by a verified synthetic voice, is
// the model take; the learner's take goes through the real comparison path (spec 10) with A(w) including the voice's
// observed primary. It plugs into spec 02's fold runner as an `EvaluationPath`, so in every outer fold it runs with
// the same fold-trained config as the shared-detector path. Its FP uses the shipped config on the clean 1,400.
// Reported, never gated here (gating is spec 11).

import AMAlignment
import AMCore
import AMEvaluation
import AMPipeline
import Foundation

/// Scores one utterance's words end to end under `thresholds`.
public protocol EndToEndUtteranceScorer: Sendable {
    /// Word id → flagged (a placement row on that word), for `words` of one utterance.
    func flags(utterance: String, words: [SpeechOceanWord], thresholds: Thresholds) async throws -> [String: Bool]
}

public struct EndToEndPath: EvaluationPath {
    public let scorer: any EndToEndUtteranceScorer
    public var name: String { "end-to-end (ii)" }

    public init(scorer: any EndToEndUtteranceScorer) { self.scorer = scorer }

    /// One scorer call per utterance, all under `config`'s thresholds. A word the scorer leaves out is not flagged.
    public func run(config: FoldConfig, words: [SpeechOceanWord]) async throws -> [String: Bool] {
        var out = Dictionary(uniqueKeysWithValues: words.map { ($0.id, false) })
        let byUtterance = Dictionary(grouping: words, by: \.utterance)
        for utterance in byUtterance.keys.sorted() {
            let members = byUtterance[utterance]!.sorted { $0.index < $1.index }
            let flags = try await scorer.flags(utterance: utterance, words: members, thresholds: config.thresholds)
            for word in members { out[word.id] = flags[word.id] ?? false }
        }
        return out
    }
}

public enum EndToEndReport {
    /// FP for (ii): flagged share of the clean 1,400 under the shipped config. Reported (spec 11 gates it at
    /// `agreement.endToEndFalsePositiveMax`).
    public static func falsePositiveLine(flags: [String: Bool], clean: [SpeechOceanWord]) -> MetricResult {
        let units = clean.map { ScoredUnit(speaker: $0.speaker, phrase: $0.text, hit: flags[$0.id] == true) }
        let hits = units.filter(\.hit).count
        return MetricResult(
            name: "End-to-end (ii) false positives, clean 1,400, shipped config", layer: .shippedConfigCheck,
            n: units.count, value: units.isEmpty ? nil : Double(hits) / Double(units.count), gate: nil,
            status: units.isEmpty ? .notEvaluated(n: 0, minimum: 1) : .reported,
            intervals: units.isEmpty ? [] : [Statistics.wilson(successes: hits, n: units.count)])
    }
}

/// speechocean762 on disk: transcripts and WAV paths (the corpus layout spec 02 fetches).
public struct SpeechOceanFiles: Sendable {
    public let root: URL
    let texts: [String: [String]]
    let wavs: [String: String]

    public init(root: URL) throws {
        self.root = root
        var texts: [String: [String]] = [:], wavs: [String: String] = [:]
        for half in ["train", "test"] {
            for line in try String(contentsOf: root.appendingPathComponent("\(half)/text"), encoding: .utf8)
                .split(whereSeparator: \.isNewline)
            {
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                if parts.count == 2 { texts[parts[0]] = parts[1].split(separator: " ").map(String.init) }
            }
            for line in try String(contentsOf: root.appendingPathComponent("\(half)/wav.scp"), encoding: .utf8)
                .split(whereSeparator: \.isNewline)
            {
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                if parts.count == 2 { wavs[parts[0]] = parts[1] }
            }
        }
        self.texts = texts
        self.wavs = wavs
    }

    public func transcript(_ utterance: String) -> [String] { texts[utterance] ?? [] }
    public func audioURL(_ utterance: String) -> URL? { wavs[utterance].map { root.appendingPathComponent($0) } }
}

/// The real scorer: the voice renders the transcript (cached by digest), both takes go through the shipped stages,
/// then `SyntheticScoring.score`. The learner's word timings are replayed (spec 02's recorded timings), never ASR.
public struct PipelineEndToEndScorer: EndToEndUtteranceScorer {
    public let corpus: SpeechOceanFiles
    public let timings: FixtureTimestamper
    public let cache: TTSCache
    public let engine: any SpeechEngine
    public let selector: PronunciationSelector

    public init(
        corpus: SpeechOceanFiles, timings: FixtureTimestamper, cache: TTSCache, engine: any SpeechEngine,
        selector: PronunciationSelector
    ) {
        self.corpus = corpus
        self.timings = timings
        self.cache = cache
        self.engine = engine
        self.selector = selector
    }

    public func flags(utterance: String, words: [SpeechOceanWord], thresholds: Thresholds) async throws
        -> [String: Bool]
    {
        let transcript = corpus.transcript(utterance)
        guard !transcript.isEmpty, let audioURL = corpus.audioURL(utterance) else { return [:] }
        // The decided words use the corpus ref-phones, as the shared detector does.
        let overrides = Dictionary(
            words.filter { (try? Pronunciation(arpabet: $0.refPhones)) != nil }.map { ($0.index, $0.refPhones) },
            uniquingKeysWith: { a, _ in a })
        let phrase = try SyntheticScoring.words(
            text: transcript.joined(separator: " ").lowercased(), selector: selector, overrides: overrides)
        guard phrase.count == transcript.count else { return [:] }

        let rendering = try await cache.render(
            SynthesisRequest(words: phrase.map { SpokenWord(text: $0.text) }), with: engine)
        let reference = try await SyntheticScoring.analyse(
            samples: rendering.audio.samples, words: phrase,
            heard: SyntheticScoring.heard(rendering.audio, words: phrase), l0Key: rendering.digest,
            thresholds: thresholds)

        let (raw, rate) = try AudioFiles.readMono(audioURL)
        let samples = try AudioFiles.resample(raw, from: rate, to: 16_000)
        let heard = try await timings.wordTimestamps(for: TimestampRequest(clipID: utterance, samples: []))
        let you = try await SyntheticScoring.analyse(
            samples: samples, words: phrase, heard: heard, l0Key: utterance, thresholds: thresholds)
        let flagged: Set<WordIndex>
        do {
            flagged = SyntheticScoring.placementWords(try SyntheticScoring.score(
                words: phrase, you: you, reference: reference, voice: engine.identity.label, thresholds: thresholds))
        } catch PairScoring.Failure.modelIncomplete {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: words.map { ($0.id, flagged.contains(WordIndex($0.index))) })
    }
}
