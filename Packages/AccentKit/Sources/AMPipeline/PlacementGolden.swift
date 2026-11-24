// Replayed placement goldens for spec 02's smoke set (spec 08 adds, per item, the L1 digest and the placement
// decision before and after suppression; spec 10 adds verdicts). The inputs (transcript, pronunciations, A(w)) and
// the recorded word timings are committed, so the golden test needs no corpus, no tagger and no ASR.

import AMAlignment
import AMCapture
import AMCore
import AMPitch
import AMProsody
import Foundation

/// One smoke item as the detector receives it.
public struct PlacementFixtureItem: Sendable, Hashable, Codable {
    public struct Word: Sendable, Hashable, Codable {
        /// The corpus word id for a labelled speechocean762 word, else nil.
        public let id: String?
        public let index: Int
        public let text: String
        /// ARPAbet with stress digits: the reference pronunciation (speechocean762 ref-phones, else the selected
        /// CMUdict variant).
        public let phones: String
        /// A(w); nil for a word with no placement decision.
        public let accepted: [Int]?

        public init(id: String?, index: Int, text: String, phones: String, accepted: [Int]?) {
            self.id = id
            self.index = index
            self.text = text
            self.phones = phones
            self.accepted = accepted
        }
    }

    /// The recorded-timings clip id, and the file stem of the audio.
    public let item: String
    public let corpus: String
    public let speaker: String
    /// Relative to the smoke folder.
    public let audio: String
    /// SHA-256 of the audio file.
    public let audioSHA256: String
    public let words: [Word]

    public init(item: String, corpus: String, speaker: String, audio: String, audioSHA256: String, words: [Word]) {
        self.item = item
        self.corpus = corpus
        self.speaker = speaker
        self.audio = audio
        self.audioSHA256 = audioSHA256
        self.words = words
    }

    /// The L0 identity: audio, recogniser, pitch tracker and voicing.
    public func l0Key(asrModelID: String) -> String {
        [audioSHA256, asrModelID, PYINTracker.trackerID, ACFVoicing.voicingID].joined(separator: "|")
    }

    public func take(samples: [Float], sampleRate: Double, heard: [WordTimestamp], asrModelID: String) throws
        -> PlacementTake
    {
        PlacementTake(
            samples: samples, sampleRate: sampleRate,
            words: try words.map { word in
                PlacementTake.Word(
                    index: WordIndex(word.index), text: word.text, pronunciation: try Pronunciation(arpabet: word.phones),
                    accepted: word.accepted.map(Set.init))
            },
            heard: heard, l0Key: l0Key(asrModelID: asrModelID))
    }
}

public struct PlacementFixtureFile: Sendable, Hashable, Codable {
    public var formatVersion = 1
    public let attribution: String
    public let items: [PlacementFixtureItem]

    public init(attribution: String, items: [PlacementFixtureItem]) {
        self.attribution = attribution
        self.items = items
    }
}

/// One item's golden: the L1 digest and, per decided word, the decision before and after suppression.
public struct PlacementGolden: Sendable, Hashable, Codable {
    public struct Word: Sendable, Hashable, Codable {
        public let id: String?
        public let index: Int
        public let present: Bool
        public let observedPrimary: Int?
        public let stressConfidence: Confidence?
        public let flaggedBeforeSuppression: Bool
        public let flaggedAfterSuppression: Bool
        public let suppression: String?
    }

    public let item: String
    public let l1Digest: String
    public let words: [Word]
    /// Spec 10: the item's verdict against a native model of the same phrase; nil when the smoke set has none.
    public var verdict: SmokeVerdict?

    public init(item: PlacementFixtureItem, analysis: PlacementAnalysis, verdict: SmokeVerdict? = nil) throws {
        self.verdict = verdict
        self.item = item.item
        l1Digest = try analysis.segmentation.digest()
        let ids = Dictionary(item.words.map { ($0.index, $0.id) }, uniquingKeysWith: { first, _ in first })
        words = analysis.words.map { result in
            Word(
                id: ids[result.word.rawValue] ?? nil, index: result.word.rawValue, present: result.present,
                observedPrimary: result.observed?.primary, stressConfidence: result.decision?.stressConfidence,
                flaggedBeforeSuppression: result.flaggedBeforeSuppression,
                flaggedAfterSuppression: result.flaggedAfterSuppression, suppression: result.suppression?.name)
        }
    }
}

/// Spec 10's verdict for one smoke item: the model item it was scored against and the decision, or why no model
/// served.
public struct SmokeVerdict: Sendable, Hashable, Codable {
    /// The model item; nil when none served.
    public let model: String?
    public let decision: Decision?
    /// Why the item has no decision.
    public let unscored: String?

    public init(model: String?, decision: Decision?, unscored: String? = nil) {
        self.model = model
        self.decision = decision
        self.unscored = unscored
    }

    /// Model candidates for each item that can have one: the other smoke items of the same VCTK phrase, by speaker
    /// (never the item's own speaker). speechocean762 items have no native take, so no candidates.
    public static func candidates(_ items: [PlacementFixtureItem]) -> [String: [PlacementFixtureItem]] {
        func phrase(_ item: PlacementFixtureItem) -> String? {
            item.corpus == "vctk" ? item.item.split(separator: "_").last.map(String.init) : nil
        }
        var out: [String: [PlacementFixtureItem]] = [:]
        for item in items {
            guard let p = phrase(item) else { continue }
            out[item.item] = items.filter { phrase($0) == p && $0.speaker != item.speaker }.sorted { $0.speaker < $1.speaker }
        }
        return out
    }

    /// Scores `item` against the first candidate whose take has every phrase word present.
    public static func score(
        item: PlacementFixtureItem, analysis: PlacementAnalysis,
        candidates: [(item: PlacementFixtureItem, analysis: PlacementAnalysis)]
    ) throws -> SmokeVerdict {
        let words = try item.words.map { word in
            PlacementTake.Word(
                index: WordIndex(word.index), text: word.text, pronunciation: try Pronunciation(arpabet: word.phones),
                accepted: word.accepted.map(Set.init))
        }
        var skipped: [String] = []
        for candidate in candidates {
            do {
                let scoring = try PairScoring.score(
                    words: words, you: analysis, model: candidate.analysis, modelVoice: candidate.item.speaker)
                return SmokeVerdict(model: candidate.item.item, decision: scoring.decision)
            } catch PairScoring.Failure.modelIncomplete(let missing) {
                skipped.append("\(candidate.item.item) misses word \(missing.map { String($0.rawValue) }.joined(separator: ","))")
            }
        }
        return SmokeVerdict(model: nil, decision: nil, unscored: "no complete model take: " + skipped.joined(separator: "; "))
    }
}

public struct PlacementGoldenFile: Sendable, Hashable, Codable {
    public var formatVersion = 1
    public let asrModelID: String
    public let algorithmVersion: Int
    public let thresholdsVersion: Int
    public let items: [PlacementGolden]

    public init(asrModelID: String, items: [PlacementGolden]) {
        self.asrModelID = asrModelID
        algorithmVersion = Versions.algorithmVersion
        thresholdsVersion = Versions.thresholdsVersion
        self.items = items
    }
}

extension DetectorSuppression {
    /// A stable name for reports and goldens.
    public var name: String {
        switch self {
        case .poorTiming: "poorTiming"
        case .lowWordConfidence: "lowWordConfidence"
        case .placement(let reason): reason.rawValue
        }
    }
}
