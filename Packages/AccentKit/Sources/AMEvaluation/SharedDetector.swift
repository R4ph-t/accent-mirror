// The shared-detector validation mode's runner (plan §6.3). Per utterance: corpus audio, corpus transcript and per
// word the accepted set A(w); no native take. The detector (spec 08) runs L0, L1, prominence, exposure discount,
// observed stress, confidence and the app's `placementDecision`; this runner counts its flags before and after
// suppression. The gate is on "after".

import Foundation

/// Where A(w) came from.
public enum AcceptedSetSource: String, Sendable, Hashable, Codable {
    /// The primary of the corpus `ref-phones` stress digits.
    case corpusRefPhones
    /// The CMUdict POS-selected variant (spec 06), when the ref-phones mark no primary.
    case dictionary
}

/// The accepted primaries of one word in the shared-detector mode.
public struct AcceptedSet: Sendable, Hashable, Codable {
    public let primaries: Set<Int>
    public let source: AcceptedSetSource

    public init(primaries: Set<Int>, source: AcceptedSetSource) {
        self.primaries = primaries
        self.source = source
    }
}

/// The dictionary fallback for A(w): spec 06's POS-selected CMUdict variant, by word position in its transcript.
public protocol DictionaryPrimaryLookup: Sendable {
    /// The primary syllable index of `words[index]` in this transcript, or nil if CMUdict has no usable variant.
    func primary(of words: [String], at index: Int, syllableCount: Int) -> Int?
}

public enum SharedDetectorAcceptedSet {
    /// A(w) = the ref-phones primary; else the dictionary's; else nil (the word is excluded and reported).
    public static func of(
        _ word: SpeechOceanWord, transcript: [String], dictionary: (any DictionaryPrimaryLookup)?
    ) -> AcceptedSet? {
        if let primary = word.refPrimary { return AcceptedSet(primaries: [primary], source: .corpusRefPhones) }
        if let primary = dictionary?.primary(of: transcript, at: word.index, syllableCount: word.syllableCount) {
            return AcceptedSet(primaries: [primary], source: .dictionary)
        }
        return nil
    }
}

/// One utterance as the detector receives it.
public struct DetectorUtterance: Sendable, Hashable {
    public struct Word: Sendable, Hashable {
        public let id: String
        public let index: Int
        public let text: String
        public let syllableCount: Int
        public let accepted: AcceptedSet
    }

    public let id: String
    public let speaker: String
    /// 16 kHz corpus WAV.
    public let audio: URL
    public let transcript: [String]
    /// The words to decide (the set's words in this utterance with an A(w)).
    public let words: [Word]
}

/// Why a raw placement flag was suppressed (§6.3).
public enum PlacementSuppression: String, Sendable, Hashable, Codable, CaseIterable {
    case poorTiming
    case lowWordConfidence
    case lowSyllableConfidence
    case missingTarget
    case exposedSyllable
    /// Stress confidence below high (spec 08, §3.3: a placement flag needs high stress confidence).
    case stressConfidenceBelowHigh
}

/// The detector's verdict on one word.
public struct PlacementOutcome: Sendable, Hashable, Codable {
    /// The word is `present` in this take (its syllables are comparable).
    public let present: Bool
    /// The observed primary ∉ A(w), before any suppression.
    public let flaggedBeforeSuppression: Bool
    /// The suppression that removed the flag, if any.
    public let suppression: PlacementSuppression?

    public init(present: Bool, flaggedBeforeSuppression: Bool, suppression: PlacementSuppression?) {
        self.present = present
        self.flaggedBeforeSuppression = flaggedBeforeSuppression
        self.suppression = suppression
    }

    public var flaggedAfterSuppression: Bool { present && flaggedBeforeSuppression && suppression == nil }
}

/// The shared detector. Spec 08's real one is `am-eval`'s `ReplayedPlacementDetector` over AMPipeline's stages.
public protocol PlacementDetector: Sendable {
    var id: String { get }
    /// Word id → outcome, for the utterance's words.
    func placements(for utterance: DetectorUtterance, config: FoldConfig) async throws -> [String: PlacementOutcome]
}

/// Where the runner finds an utterance's audio and transcript.
public protocol SpeechOceanCorpus: Sendable {
    func audioURL(utterance: String) -> URL
    func transcript(utterance: String) -> [String]
}

/// Per-word results of one shared-detector run over a set.
public struct SharedDetectorResults: Sendable, Hashable {
    public struct Row: Sendable, Hashable {
        public let word: SpeechOceanWord
        /// nil when the word was excluded before the detector (no A(w)).
        public let outcome: PlacementOutcome?
    }

    public let rows: [Row]

    /// Words with no A(w), excluded and reported.
    public var excluded: [SpeechOceanWord] { rows.filter { $0.outcome == nil }.map(\.word) }
    /// The comparable set: words present in their take.
    public var comparable: [Row] { rows.filter { $0.outcome?.present == true } }

    /// Units for a rate over the whole set (absent or excluded words count as not flagged).
    public func units(afterSuppression: Bool) -> [ScoredUnit] {
        rows.map { row in
            let flagged = afterSuppression
                ? row.outcome?.flaggedAfterSuppression == true
                : (row.outcome?.present == true && row.outcome?.flaggedBeforeSuppression == true)
            return ScoredUnit(speaker: row.word.speaker, phrase: row.word.text, hit: flagged)
        }
    }

    /// Placement diffs after suppression (for the 157 unintelligible words: must be 0).
    public var placementDiffs: Int { rows.filter { $0.outcome?.flaggedAfterSuppression == true }.count }
}

public struct SharedDetectorRunner: Sendable {
    public let detector: any PlacementDetector
    public let corpus: any SpeechOceanCorpus
    public let dictionary: (any DictionaryPrimaryLookup)?

    public init(
        detector: any PlacementDetector, corpus: any SpeechOceanCorpus, dictionary: (any DictionaryPrimaryLookup)?
    ) {
        self.detector = detector
        self.corpus = corpus
        self.dictionary = dictionary
    }

    /// Runs the detector over `words`, one call per utterance.
    public func run(_ words: [SpeechOceanWord], config: FoldConfig) async throws -> SharedDetectorResults {
        var rows: [SharedDetectorResults.Row] = []
        let byUtterance = Dictionary(grouping: words, by: \.utterance)
        for utterance in byUtterance.keys.sorted() {
            let members = byUtterance[utterance]!.sorted { $0.index < $1.index }
            let transcript = corpus.transcript(utterance: utterance)
            var detectorWords: [DetectorUtterance.Word] = []
            for word in members {
                if let accepted = SharedDetectorAcceptedSet.of(word, transcript: transcript, dictionary: dictionary) {
                    detectorWords.append(
                        .init(
                            id: word.id, index: word.index, text: word.text, syllableCount: word.syllableCount,
                            accepted: accepted))
                }
            }
            var outcomes: [String: PlacementOutcome] = [:]
            if !detectorWords.isEmpty {
                outcomes = try await detector.placements(
                    for: DetectorUtterance(
                        id: utterance, speaker: members[0].speaker, audio: corpus.audioURL(utterance: utterance),
                        transcript: transcript, words: detectorWords),
                    config: config)
            }
            let decided = Set(detectorWords.map(\.id))
            for word in members {
                let outcome = decided.contains(word.id)
                    ? (outcomes[word.id] ?? PlacementOutcome(present: false, flaggedBeforeSuppression: false, suppression: nil))
                    : nil
                rows.append(.init(word: word, outcome: outcome))
            }
        }
        return SharedDetectorResults(rows: rows)
    }
}

/// The shared-detector path for the fold runner.
public struct SharedDetectorPath: EvaluationPath {
    public let runner: SharedDetectorRunner
    public var name: String { "shared-detector" }

    public init(runner: SharedDetectorRunner) { self.runner = runner }

    public func run(config: FoldConfig, words: [SpeechOceanWord]) async throws -> [String: Bool] {
        let results = try await runner.run(words, config: config)
        return Dictionary(uniqueKeysWithValues: results.rows.map { ($0.word.id, $0.outcome?.flaggedAfterSuppression == true) })
    }
}
