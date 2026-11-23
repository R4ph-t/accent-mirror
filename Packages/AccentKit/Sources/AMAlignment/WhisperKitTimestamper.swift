import Foundation
import Synchronization
// WhisperKit is built in Swift 5 language mode and its `WhisperKit` class is not `Sendable`. The one instance here
// is created inside `load` and then owned by this actor, which never hands it out and never overlaps two calls on it
// (`busy`), so the instance is never used from two places at once.
@preconcurrency import WhisperKit

/// Live on-device word timestamps from the SHA-pinned WhisperKit model.
///
/// It loads only from a local, verified folder: `download: false`, model and tokenizer given by path, and
/// `ModelManifest.verify` runs before WhisperKit sees a file, so a hash mismatch fails the load.
public actor WhisperKitTimestamper: WordTimestamper {
    public nonisolated let asrModelID: String
    private let whisper: WhisperKit
    private var busy = false

    /// Greedy decoding with word timestamps, English, WhisperKit's default temperature fallback.
    public static let decodingOptions = DecodingOptions(
        task: .transcribe,
        language: "en",
        temperature: 0,
        usePrefillPrompt: true,
        detectLanguage: false,
        skipSpecialTokens: true,
        withoutTimestamps: false,
        wordTimestamps: true
    )

    private init(asrModelID: String, whisper: WhisperKit) {
        self.asrModelID = asrModelID
        self.whisper = whisper
    }

    /// Verifies `folder` against `manifest`, then loads and prewarms the model from it.
    /// - Parameter folder: the fetched model folder (`model/` and `tokenizer/` inside), e.g.
    ///   `.cache/models/openai_whisper-base.en`.
    public static func load(manifest: ModelManifest, folder: URL) async throws -> WhisperKitTimestamper {
        try manifest.verify(folder: folder)
        let config = WhisperKitConfig(
            modelFolder: folder.appending(path: ModelManifest.modelSubfolder).path,
            tokenizerFolder: folder.appending(path: ModelManifest.tokenizerSubfolder),
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: false
        )
        let whisper = try await WhisperKit(config)
        return WhisperKitTimestamper(asrModelID: manifest.asrModelID, whisper: whisper)
    }

    /// An audio file's samples as 16 kHz mono floats (channels summed), WhisperKit's input format.
    public static func samples(fromFileAt url: URL) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
    }

    /// True while the Core ML models are loaded (cancelling a request must not unload them).
    public var isLoaded: Bool { whisper.modelState == .loaded }

    public func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] {
        try await transcribe(request).words
    }

    /// The recognised text and its words.
    ///
    /// Cancellation (plan §8.2): the call runs inside `withTaskCancellationHandler`; on cancel, WhisperKit's
    /// `TranscriptionCallback` (`@Sendable (TranscriptionProgress) -> Bool?` in WhisperKit 1.1.1) returns `false`,
    /// which stops the decoding loop at the next token, and the call then throws `CancellationError`. WhisperKit
    /// also checks `Task.isCancelled` between its own stages. The model stays loaded.
    public func transcribe(_ request: TimestampRequest) async throws -> (text: String, words: [WordTimestamp]) {
        try Task.checkCancellation()
        guard !busy else { throw TimestamperError.busy }
        busy = true
        defer { busy = false }

        let stop = StopFlag()
        let results = try await withTaskCancellationHandler {
            try await whisper.transcribe(
                audioArray: request.samples,
                decodeOptions: Self.decodingOptions,
                callback: { _ in stop.isSet ? false : nil }
            )
        } onCancel: {
            stop.set()
        }
        try Task.checkCancellation()

        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let words = results.flatMap(\.allWords).map {
            WordTimestamp(word: $0.word, start: decimal($0.start), end: decimal($0.end), probability: decimal($0.probability))
        }
        return (text, words)
    }
}

/// The Double nearest the Float's shortest decimal form (0.24 stays 0.24, not 0.23999999463558197).
private func decimal(_ value: Float) -> Double {
    Double(value.description) ?? Double(value)
}

/// Set once on cancellation, read from WhisperKit's decoding callback on another thread.
private final class StopFlag: Sendable {
    private let flag = Atomic<Bool>(false)
    var isSet: Bool { flag.load(ordering: .acquiring) }
    func set() { flag.store(true, ordering: .releasing) }
}
