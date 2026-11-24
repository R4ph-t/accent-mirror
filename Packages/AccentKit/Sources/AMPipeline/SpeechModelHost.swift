// The speech model host (spec 12, plan §1, §8.2): loads the recogniser from a folder it is given, checks the pinned
// SHA-256s first, warms it up off the main actor, and owns the load policy. A cancelled request never tears the
// model down.

import AMAlignment
import AMCore
import Foundation

/// Why the recogniser can't be used, as a thrown error (`OperationalError.modelUnavailable`).
public struct ModelUnavailable: Error, Sendable, Hashable {
    public let failure: ModelFailure
    public init(_ failure: ModelFailure) { self.failure = failure }
}

public actor SpeechModelHost {
    /// Loads the recogniser. Throws `ModelUnavailable`, a `ModelVerificationError`, or anything else (a failed load).
    public typealias Loader = @Sendable () async throws -> any WordTimestamper

    /// The recogniser's `asrModelID`, known from its manifest before it loads.
    public nonisolated let asrModelID: String
    private let loader: Loader
    private var state: State = .idle
    /// Loads started (tests check the retry-once policy and that a cancel never reloads).
    public private(set) var loadAttempts = 0

    private enum State {
        case idle
        case loading(Task<any WordTimestamper, any Error>)
        case ready(any WordTimestamper)
        /// `retry`: whether the next request may load again (plan §1: once).
        case failed(ModelFailure, retry: Bool)
    }

    public init(asrModelID: String, load: @escaping Loader) {
        self.asrModelID = asrModelID
        self.loader = load
    }

    /// A host whose recogniser is already loaded (replayed word timings in tests and evaluation).
    public init(ready timestamper: any WordTimestamper) {
        asrModelID = timestamper.asrModelID
        loader = { timestamper }
        state = .ready(timestamper)
    }

    /// The pinned WhisperKit model in `folder` (the app's bundle path in spec 21; `MODELS_CACHE` for tools). Nothing
    /// is ever downloaded: a missing folder or file is `notInstalled`, a hash mismatch `checksumMismatch`, anything
    /// WhisperKit refuses `loadFailed`. A loaded model is warmed up on 1 s of silence.
    public static func whisperKit(folder: URL, manifest: ModelManifest) -> SpeechModelHost {
        SpeechModelHost(asrModelID: manifest.asrModelID) {
            guard FileManager.default.fileExists(atPath: folder.path) else { throw ModelUnavailable(.notInstalled) }
            let whisper = try await WhisperKitTimestamper.load(manifest: manifest, folder: folder)
            _ = try? await whisper.wordTimestamps(
                for: TimestampRequest(
                    clipID: "warm-up", samples: [Float](repeating: 0, count: Int(TimestampRequest.sampleRate))))
            return whisper
        }
    }

    /// Starts loading now (at app launch) so the first take doesn't wait; a no-op once loaded or loading.
    public func prepare() {
        if case .idle = state { startLoad() }
    }

    /// The loaded recogniser. A request made while it loads waits for the load (Open question 1). After a failure
    /// the next request retries the load once; a second failure is reported, and later requests get it without a
    /// reload.
    public func timestamper() async throws(ModelUnavailable) -> any WordTimestamper {
        switch state {
        case .ready(let timestamper):
            return timestamper
        case .failed(let failure, retry: false):
            throw ModelUnavailable(failure)
        case .idle, .failed(_, retry: true):
            startLoad()
        case .loading:
            break
        }
        guard case .loading(let task) = state else { throw ModelUnavailable(.loadFailed) }
        let wasRetry = loadAttempts > 1
        do {
            let timestamper = try await task.value
            if case .loading = state { state = .ready(timestamper) }
            return timestamper
        } catch {
            let failure = Self.failure(of: error)
            if case .loading = state { state = .failed(failure, retry: !wasRetry) }
            throw ModelUnavailable(failure)
        }
    }

    /// True while a recogniser is loaded.
    public var isLoaded: Bool {
        if case .ready = state { return true }
        return false
    }

    private func startLoad() {
        loadAttempts += 1
        let loader = self.loader
        // Unstructured on purpose: a request cancelled while the model loads must not cancel the load.
        state = .loading(Task.detached(priority: .userInitiated) { try await loader() })
    }

    static func failure(of error: any Error) -> ModelFailure {
        switch error {
        case let unavailable as ModelUnavailable: unavailable.failure
        case ModelVerificationError.missing: .notInstalled
        case ModelVerificationError.mismatch, ModelVerificationError.manifestInconsistent: .checksumMismatch
        case let error as CocoaError where error.code == .fileReadNoSuchFile: .notInstalled
        default: .loadFailed
        }
    }
}
