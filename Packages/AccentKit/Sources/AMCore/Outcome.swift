// What the pipeline returns for one request (plan §1). Persistence is reported separately (§8.3).

import Foundation

public struct AnalysisResponse: Sendable, Hashable, Codable {
    public let requestID: RequestID
    public let identity: AnalysisIdentity
    public let outcome: AnalysisOutcome

    public init(requestID: RequestID, identity: AnalysisIdentity, outcome: AnalysisOutcome) {
        self.requestID = requestID
        self.identity = identity
        self.outcome = outcome
    }
}

public enum AnalysisOutcome: Sendable, Hashable, Codable {
    /// Carries a `Verdict`.
    case analysed(AnalysisResult)
    /// User-correctable; Designer's order, first only.
    case takeProblem(TakeProblem)
    /// Our side or the system; never blamed on the user.
    case failed(OperationalError)
    /// Superseded or stopped; never shown, never saved.
    case cancelled

    enum AnalysedCodingKeys: String, CodingKey { case _0 = "result" }
    enum TakeProblemCodingKeys: String, CodingKey { case _0 = "problem" }
    enum FailedCodingKeys: String, CodingKey { case _0 = "error" }
}

/// User-correctable problems, declared in Designer's priority order. Only the first that applies is shown.
public enum TakeProblem: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case noMicrophone, micDenied, noSpeech, tooShort, tooQuiet, clipped, wordsDontMatch

    public static func < (lhs: TakeProblem, rhs: TakeProblem) -> Bool { lhs.rank < rhs.rank }

    private var rank: Int { Self.allCases.firstIndex(of: self)! }

    /// The one problem to report from everything that applies, or nil when nothing does.
    public static func first(of problems: some Sequence<TakeProblem>) -> TakeProblem? { problems.min() }
}

/// Failures on our side or the system's. Storage failures are not here: they are `PersistenceStatus` (§8.3).
public enum OperationalError: Sendable, Hashable, Codable {
    case modelUnavailable(ModelFailure)
    case inferenceFailed(stage: Stage)
    case referenceCacheCorrupt(RecordingID)
    case audioUnreadable

    enum ModelUnavailableCodingKeys: String, CodingKey { case _0 = "failure" }
    enum ReferenceCacheCorruptCodingKeys: String, CodingKey { case _0 = "recording" }
}

/// Why a model could not be used. Policy (§1.3): retry the load once on the next request.
public enum ModelFailure: String, Sendable, Hashable, Codable, CaseIterable {
    /// The weights are not on the device.
    case notInstalled
    /// The weights don't match their pinned SHA-256.
    case checksumMismatch
    /// The framework refused to load or compile the model.
    case loadFailed
}

/// The pipeline stage an inference failure came from.
public enum Stage: String, Sendable, Hashable, Codable, CaseIterable {
    case decodeAudio, recogniseWords, trackPitch, detectVoicing, alignWords, segmentSyllables, measureStress
    case mapTime, compare
}
