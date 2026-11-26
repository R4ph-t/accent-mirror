// Per-sound pronunciation judging (sound-judging plan, 2026-11-25): the contract the result screen reads.
// Spec 28 turned scoring off; Raph reversed that for sounds only (2026-11-25). Stress and intonation verdicts stay
// off. A flagged sound means "check this sound", never "wrong": the judge flags about 3.5% of sounds that human
// raters scored fully correct on learner speech.

import Foundation

/// The outcome of judging one take's sounds. `AnalysisResult.sounds` is nil for takes saved before judging existed.
public enum SoundJudgementOutcome: Sendable, Hashable, Codable {
    case judged(SoundJudgement)
    /// The judge didn't run: no model in the bundle, the model failed to load, or the take couldn't be judged.
    case unavailable(SoundJudgementUnavailable)
}

public enum SoundJudgementUnavailable: String, Sendable, Hashable, Codable, CaseIterable {
    /// The model isn't bundled or doesn't verify against its manifest.
    case modelNotInstalled
    /// The model is bundled but Core ML failed to load or run it.
    case modelFailed
    /// The take is shorter than the model's minimum input or longer than its maximum.
    case takeOutOfRange
    /// No word in the phrase has a dictionary pronunciation.
    case nothingJudgeable
}

public struct SoundJudgement: Sendable, Hashable, Codable {
    /// The pinned model, e.g. `wav2vec2-lv-60-espeak-cv-ft@<commit>#<first 8 of packageSHA256>`.
    public let modelID: String
    /// The GOP and calibration algorithm, e.g. `gop-sf-1`. Bump when the same posteriors can give other flags.
    public let judgeID: String
    /// The calibrated P(error) above which a sound is flagged (`Thresholds.soundJudging.errorThreshold`: 0.13 for
    /// `gop-sf-2`, 0.22 for `gop-sf-1`).
    public let errorThreshold: Double
    /// One entry per phrase word, in phrase order.
    public let words: [JudgedWord]

    public init(modelID: String, judgeID: String, errorThreshold: Double, words: [JudgedWord]) {
        self.modelID = modelID
        self.judgeID = judgeID
        self.errorThreshold = errorThreshold
        self.words = words
    }

    /// Flagged sounds, least confident first (the result screen shows the top three).
    public var flaggedSounds: [(word: JudgedWord, phone: JudgedPhone)] {
        words.flatMap { word in word.phones.filter(\.flagged).map { (word: word, phone: $0) } }
            .sorted { $0.phone.confidence < $1.phone.confidence }
    }
}

public struct JudgedWord: Sendable, Hashable, Codable {
    public let index: WordIndex
    public let text: String
    /// The word on your take's timeline (from the judge's own CTC alignment); nil when unjudged.
    public let youRange: TimeRange?
    /// The same word on the native recording's timeline (from its stored word timings); nil when unknown.
    public let modelRange: TimeRange?
    public let state: State

    public enum State: Sendable, Hashable, Codable {
        /// One entry per expected ARPAbet phone of the chosen dictionary variant, in order.
        case judged([JudgedPhone])
        case unjudged(UnjudgedReason)
    }

    public enum UnjudgedReason: String, Sendable, Hashable, Codable, CaseIterable {
        /// Not in CMUdict (or a token the judge can't map): left unjudged, never guessed.
        case notInDictionary
    }

    public init(index: WordIndex, text: String, youRange: TimeRange?, modelRange: TimeRange?, state: State) {
        self.index = index
        self.text = text
        self.youRange = youRange
        self.modelRange = modelRange
        self.state = state
    }

    public var phones: [JudgedPhone] {
        if case .judged(let phones) = state { phones } else { [] }
    }

    /// A word is flagged when any of its sounds is.
    public var flagged: Bool { phones.contains(where: \.flagged) }
}

public struct JudgedPhone: Sendable, Hashable, Codable {
    /// The expected ARPAbet phone, stress digits stripped (e.g. `TH`, `IY`), except that unstressed AH stays `AH0`
    /// (schwa, "a" as in about) while AH1 and AH2 are `AH` ("u" as in cup). Designer ruling, 2026-11-25.
    public let phone: String
    /// Segmentation-free GOP, a log posterior ratio, <= 0. Composite units (vowel+R, AH0+L) give both members the
    /// unit's score.
    public let gop: Double
    /// 1 − calibrated P(error), in 0…1. Lower is more likely mispronounced.
    public let confidence: Double
    public let flagged: Bool
    /// The strongest competitor in the GOP denominator, when it beat every acceptable form; nil otherwise.
    public let heardInstead: HeardInstead?
    /// Where the sound sits on your take's timeline (CTC forced alignment, 20 ms frames).
    public let youRange: TimeRange?

    public init(phone: String, gop: Double, confidence: Double, flagged: Bool, heardInstead: HeardInstead?,
                youRange: TimeRange?) {
        self.phone = phone
        self.gop = gop
        self.confidence = confidence
        self.flagged = flagged
        self.heardInstead = heardInstead
        self.youRange = youRange
    }
}

public enum HeardInstead: Sendable, Hashable, Codable {
    /// Another sound, as the model's espeak IPA token (e.g. `s` for an expected TH).
    case sound(String)
    /// The sound seems to be missing.
    case nothing
}
