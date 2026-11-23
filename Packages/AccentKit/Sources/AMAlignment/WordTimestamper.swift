import Foundation

/// One recognised word and where it sits in the take, in seconds from the start of the audio.
public struct WordTimestamp: Codable, Sendable, Equatable {
    /// The word as the recogniser wrote it (may carry punctuation or a leading space).
    public var word: String
    public var start: Double
    public var end: Double
    /// The recogniser's word probability, 0–1.
    public var probability: Double

    public init(word: String, start: Double, end: Double, probability: Double) {
        self.word = word
        self.start = start
        self.end = end
        self.probability = probability
    }
}

/// What a timestamper is asked to transcribe: a clip identifier and its audio as 16 kHz mono samples.
/// Replay uses only the identifier; live ASR uses only the samples.
public struct TimestampRequest: Sendable {
    public var clipID: String
    public var samples: [Float]

    public static let sampleRate: Double = 16_000

    public init(clipID: String, samples: [Float]) {
        self.clipID = clipID
        self.samples = samples
    }
}

/// Word timings for a take, from live on-device ASR (`WhisperKitTimestamper`) or from recorded JSON
/// (`FixtureTimestamper`, which CI uses; CI never runs ASR).
public protocol WordTimestamper: Sendable {
    /// `<model>@<upstream commit>#<first 8 hex of the model SHA-256>`, e.g. `openai_whisper-base.en@0f63…#a59b5631`.
    var asrModelID: String { get }

    /// The words in the take, in order. Throws `CancellationError` if the calling task is cancelled.
    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp]
}

public enum TimestamperError: Error, Equatable, Sendable {
    /// No recording exists for this clip.
    case notRecorded(clipID: String)
    /// A recording, or the replay manifest, names a different model than the one being replayed.
    case modelMismatch(expected: String, found: String)
    /// The timestamper is already transcribing; requests are not overlapped (the coordinator is spec 12).
    case busy
}
