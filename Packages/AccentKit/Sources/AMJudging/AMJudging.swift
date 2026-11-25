// AMJudging: per-sound pronunciation judging on device (sound-judging plan, 2026-11-25).
// facebook/wav2vec2-lv-60-espeak-cv-ft (Apache-2.0) in Core ML gives CTC log-posteriors over espeak IPA tokens; a
// segmentation-free GOP (after Cao et al.) scores each expected ARPAbet phone, a per-phone logistic calibration turns
// it into P(error), and a sound is flagged above the frozen threshold. Depends on AMCore and Apple frameworks only.
//
// This file is the agreed interface. sj-engine fills in the bodies; sj-wire calls only what is declared here.

import AMCore
import Foundation

/// One phrase word as the judge expects it.
public struct ExpectedWord: Sendable, Hashable {
    public let index: WordIndex
    public let text: String
    /// Every CMUdict variant for the word, ARPAbet with stress digits (e.g. `["DH", "AH0"]`), dictionary order. Empty
    /// means out of vocabulary: the word is reported `.unjudged(.notInDictionary)`. The judge picks one variant per
    /// word greedily by CTC likelihood, as the spike did.
    public let variants: [[String]]
    /// The word on the native recording's timeline, copied into `JudgedWord.modelRange`.
    public let modelRange: TimeRange?

    public init(index: WordIndex, text: String, variants: [[String]], modelRange: TimeRange? = nil) {
        self.index = index
        self.text = text
        self.variants = variants
        self.modelRange = modelRange
    }
}

/// CTC log-posteriors from the model: `frames` rows of `vocabularySize` log-softmax values, row-major, 20 ms a frame.
public struct LogPosteriors: Sendable, Hashable {
    public let frames: Int
    public let vocabularySize: Int
    public let values: [Float]
    public static let frameSeconds = 0.02

    public init(frames: Int, vocabularySize: Int, values: [Float]) {
        precondition(values.count == frames * vocabularySize, "LogPosteriors: values must be frames × vocabularySize")
        self.frames = frames
        self.vocabularySize = vocabularySize
        self.values = values
    }
}

public enum SoundJudgeError: Error, Sendable, Hashable {
    case notImplemented
    case modelNotInstalled
    case modelFailed(String)
    case takeOutOfRange(seconds: Double)
}

/// The pure part: posteriors + expected words -> judged words. Deterministic; what the parity fixtures test.
public enum SoundScorer {
    public static let judgeID = "gop-sf-1"

    public static func judge(_ posteriors: LogPosteriors, words: [ExpectedWord]) -> [JudgedWord] {
        // sj-engine: ARPAbet -> espeak units with the spike's lenient classes, variant choice, GOP, calibration,
        // threshold, heard-instead and CTC forced alignment for `youRange`.
        words.map { JudgedWord(index: $0.index, text: $0.text, youRange: nil, modelRange: $0.modelRange,
                               state: .unjudged(.notInDictionary)) }
    }
}

/// The model-owning part: loads the bundled Core ML package once (off the main actor), then judges 16 kHz mono takes.
/// Cancellable: checks `Task.isCancelled` between the forward pass and scoring.
public actor SoundJudge {
    /// The folder name under `Contents/Resources/Models/` and under `MODELS_CACHE`.
    public static let modelFolderName = "wav2vec2-lv-60-espeak-cv-ft"

    public nonisolated let modelID: String

    init(modelID: String) {
        self.modelID = modelID
    }

    /// Loads and verifies the model in `folder` (the bundled `Models/wav2vec2-lv-60-espeak-cv-ft`).
    public static func load(folder: URL) async throws -> SoundJudge {
        throw SoundJudgeError.notImplemented
    }

    /// Normalises, pads to the compiled bucket, runs the model and scores. `samples` are 16 kHz mono floats.
    public func judge(samples: [Float], words: [ExpectedWord]) async throws -> SoundJudgement {
        throw SoundJudgeError.notImplemented
    }
}
