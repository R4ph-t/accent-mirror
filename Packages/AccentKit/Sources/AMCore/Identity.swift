// Identity of an analysis (plan §6.6, §8.1, §9.1, §9.2).

import Foundation

/// Which code and configuration produced a result. Version numbers are monotonic integers, not semver (§9.1).
public struct ConfigIdentity: Sendable, Hashable, Codable {
    public let algorithmVersion: Int
    public let thresholdsVersion: Int
    public let contractVersion: Int
    public let asrModelID: String
    public let pitchTrackerID: String
    public let voicingID: String
    /// The word-boundary refiner run after ASR (spec 23): `whisper` (unrefined), `dsp-snap-1` or `ctc-w2v2b960-1`.
    public let aligner: String

    public init(
        algorithmVersion: Int = Versions.algorithmVersion, thresholdsVersion: Int = Versions.thresholdsVersion,
        contractVersion: Int = Versions.contractVersion, asrModelID: String, pitchTrackerID: String, voicingID: String,
        aligner: String
    ) {
        self.algorithmVersion = algorithmVersion
        self.thresholdsVersion = thresholdsVersion
        self.contractVersion = contractVersion
        self.asrModelID = asrModelID
        self.pitchTrackerID = pitchTrackerID
        self.voicingID = voicingID
        self.aligner = aligner
    }
}

/// Which native reference a take was compared with. Part of the L2 cache key (§9.2).
public struct ReferenceIdentity: Sendable, Hashable, Codable {
    public let phraseID: PhraseID
    public let recordingID: RecordingID
    public let recordingSHA256: String
    public let transcriptRevision: Int
    public let pronunciationOverridesHash: String
    public let targetsHash: String
    public let nativeSetHash: String

    public init(
        phraseID: PhraseID, recordingID: RecordingID, recordingSHA256: String, transcriptRevision: Int,
        pronunciationOverridesHash: String, targetsHash: String, nativeSetHash: String
    ) {
        self.phraseID = phraseID
        self.recordingID = recordingID
        self.recordingSHA256 = recordingSHA256
        self.transcriptRevision = transcriptRevision
        self.pronunciationOverridesHash = pronunciationOverridesHash
        self.targetsHash = targetsHash
        self.nativeSetHash = nativeSetHash
    }
}

/// Everything that determines one analysis: your audio, the reference and the configuration.
public struct AnalysisIdentity: Sendable, Hashable, Codable {
    public let takeAudioSHA256: String
    public let reference: ReferenceIdentity
    public let config: ConfigIdentity

    public init(takeAudioSHA256: String, reference: ReferenceIdentity, config: ConfigIdentity) {
        self.takeAudioSHA256 = takeAudioSHA256
        self.reference = reference
        self.config = config
    }
}

/// What a request analyses. Stale responses are rejected by request ID plus inputs (§8.1).
public struct AnalysisInputs: Sendable, Hashable, Codable {
    public let takeAudioSHA256: String
    public let reference: ReferenceIdentity

    public init(takeAudioSHA256: String, reference: ReferenceIdentity) {
        self.takeAudioSHA256 = takeAudioSHA256
        self.reference = reference
    }
}

/// One request to the pipeline (§8.1). `generation` increases with each request the coordinator issues.
public struct AnalysisRequest: Sendable, Hashable, Codable {
    public let id: RequestID
    public let generation: Int
    public let inputs: AnalysisInputs
    public let config: ConfigIdentity

    public init(id: RequestID = RequestID(), generation: Int, inputs: AnalysisInputs, config: ConfigIdentity) {
        self.id = id
        self.generation = generation
        self.inputs = inputs
        self.config = config
    }

    public var identity: AnalysisIdentity {
        AnalysisIdentity(takeAudioSHA256: inputs.takeAudioSHA256, reference: inputs.reference, config: config)
    }
}

/// SHA-256 of the canonical JSON of `ConfigIdentity` plus the full `Thresholds` (§6.6). Reports name themselves
/// after its first 8 hex characters.
public func configDigest(_ config: ConfigIdentity, thresholds: Thresholds = .current) throws -> String {
    struct Digested: Encodable {
        let config: ConfigIdentity
        let thresholds: Thresholds
    }
    return try CanonicalJSON.sha256(Digested(config: config, thresholds: thresholds))
}
