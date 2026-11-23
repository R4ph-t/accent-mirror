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

    public init(item: PlacementFixtureItem, analysis: PlacementAnalysis) throws {
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
