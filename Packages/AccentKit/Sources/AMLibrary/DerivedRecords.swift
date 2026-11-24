// What the library stores for the pipeline (spec 12, plan §9.2): derived analyses as opaque records, an identity key
// plus encoded bytes. `AMPipeline` owns the L0/L1/L2 types and their encoding; the library only keeps the bytes, so it
// depends on AMCore alone. `ReferenceSet` (spec 15) and `TakePersisting` (spec 16) are declared here over those
// records, and `AMPipeline` adapts them.

import AMCore
import Foundation

/// One derived analysis, encoded. A reader whose expected key differs treats the record as a miss, never an error.
public struct DerivedRecord: Sendable, Hashable, Codable {
    /// The cache level (plan §9.2).
    public enum Level: String, Sendable, Hashable, Codable, CaseIterable {
        /// Frame-level features and ASR words of one recording.
        case l0
        /// Alignment, syllables and raw prominence features of one recording against its transcript.
        case l1
        /// A take compared with one reference.
        case l2
    }

    public let level: Level
    /// The identity the bytes were computed for (the cache key, as text).
    public let key: String
    public let bytes: Data

    public init(level: Level, key: String, bytes: Data) {
        self.level = level
        self.key = key
        self.bytes = bytes
    }
}

/// One native recording of a phrase with its stored analysis (L0 and L1 in one record).
public struct NativeRecording: Sendable, Hashable {
    public let id: RecordingID
    /// The reader, for example `p225`: named in a placement row ("like p225") and kept out of its own A(w).
    public let voice: String
    /// The recording's audio SHA-256; the band's native-set hash is built from these.
    public let audioSHA256: String
    /// The recording's L0/L1 analysis, as `AMPipeline` encoded it.
    public let analysis: DerivedRecord

    public init(id: RecordingID, voice: String, audioSHA256: String, analysis: DerivedRecord) {
        self.id = id
        self.voice = voice
        self.audioSHA256 = audioSHA256
        self.analysis = analysis
    }
}

public enum ReferenceSetError: Error, Sendable, Hashable {
    /// A stored analysis can't be read. The pipeline asks for one rebuild; a second failure is reported.
    case cacheCorrupt(RecordingID)
    /// No such recording for this phrase.
    case notFound(RecordingID)
}

/// The native side of a phrase: each recording's precomputed analysis and identity. The pipeline never recomputes
/// the reference during a take; it reads these records and, when one is corrupt, asks for a rebuild once.
public protocol ReferenceSet: Sendable {
    /// The identity of `voice`'s recording of `phrase`. Cheap and synchronous (the coordinator records it when it
    /// issues a request); it must not need the stored analysis.
    func identity(phrase: PhraseID, voice: RecordingID) -> ReferenceIdentity

    /// Every native recording of `phrase`, the selectable voices and the band's other readers alike.
    func natives(phrase: PhraseID) async throws(ReferenceSetError) -> [NativeRecording]

    /// Rebuilds `recording`'s stored analysis (the silent rebuild after a corrupt read).
    func rebuild(_ recording: RecordingID, phrase: PhraseID) async throws(ReferenceSetError)
}

/// One analysed take to save: its audio and its derived records.
public struct TakeRecord: Sendable, Hashable {
    public let takeID: TakeID
    public let phraseID: PhraseID
    /// The native recording the take was compared with.
    public let recording: RecordingID
    public let recordedAt: Date
    public let audioSHA256: String
    /// 16 kHz mono Float32 (spec 14's capture format).
    public let samples: [Float]
    /// L0, L1 and L2 for this take, as `AMPipeline` encoded them.
    public let derived: [DerivedRecord]
    /// The analysis the records come from (spec 16 keeps it in the take's manifest).
    public let identity: AnalysisIdentity?

    public init(
        takeID: TakeID, phraseID: PhraseID, recording: RecordingID, recordedAt: Date, audioSHA256: String,
        samples: [Float], derived: [DerivedRecord], identity: AnalysisIdentity? = nil
    ) {
        self.takeID = takeID
        self.phraseID = phraseID
        self.recording = recording
        self.recordedAt = recordedAt
        self.audioSHA256 = audioSHA256
        self.samples = samples
        self.derived = derived
        self.identity = identity
    }
}

/// What a save did: the stored take, and a prune that failed after it (plan §8.3).
public struct SavedTake: Sendable, Hashable {
    public let id: TakeID
    public let pruneFailure: StorageError?

    public init(id: TakeID, pruneFailure: StorageError? = nil) {
        self.id = id
        self.pruneFailure = pruneFailure
    }
}

/// The take store (spec 16 implements it on disk). Only `analysed` takes are offered.
public protocol TakePersisting: Sendable {
    func save(_ take: TakeRecord) async throws(StorageError) -> SavedTake
}
