// The cache levels (plan §9.2): L0 frame features and ASR words, L1 alignment and syllables, L2 the comparison with
// one reference. Each value carries the key it was computed for, encodes to an `AMLibrary.DerivedRecord`, and a
// record whose key differs reads as a miss. A miss recomputes; it is never an error.

import AMAlignment
import AMCore
import AMLibrary
import AMPitch
import AMProsody
import Foundation

public enum AnalysisVersions {
    /// Bump when L0's frame features (voicing, pitch, the ASR input) change for the same audio.
    public static let featureVersion = 1
}

/// L0: `takeAudioSHA256 + featureVersion + asrModelID + pitchTrackerID + voicingID`.
public struct L0Key: Sendable, Hashable, Codable {
    public let takeAudioSHA256: String
    public let featureVersion: Int
    public let asrModelID: String
    public let pitchTrackerID: String
    public let voicingID: String

    public init(
        takeAudioSHA256: String, featureVersion: Int = AnalysisVersions.featureVersion, asrModelID: String,
        pitchTrackerID: String, voicingID: String
    ) {
        self.takeAudioSHA256 = takeAudioSHA256
        self.featureVersion = featureVersion
        self.asrModelID = asrModelID
        self.pitchTrackerID = pitchTrackerID
        self.voicingID = voicingID
    }

    /// The key as stored in a `DerivedRecord`: SHA-256 of its canonical JSON.
    public var text: String { (try? CanonicalJSON.sha256(self)) ?? "" }
}

/// L1: the L0 key + `transcriptRevision + pronunciationHash + algorithmVersion`, and the word-boundary source (spec 23)
/// whose refined timings L1 is built on.
public struct L1Key: Sendable, Hashable, Codable {
    public let l0: L0Key
    public let transcriptRevision: Int
    public let pronunciationHash: String
    public let algorithmVersion: Int
    public let aligner: String

    public init(
        l0: L0Key, transcriptRevision: Int, pronunciationHash: String,
        algorithmVersion: Int = Versions.algorithmVersion, aligner: String
    ) {
        self.l0 = l0
        self.transcriptRevision = transcriptRevision
        self.pronunciationHash = pronunciationHash
        self.algorithmVersion = algorithmVersion
        self.aligner = aligner
    }

    public var text: String { (try? CanonicalJSON.sha256(self)) ?? "" }
}

/// L2: the L1 key + `ReferenceIdentity + thresholdsVersion + scoringMode` (spec 28: an `.on` comparison is never
/// served for an `.off` request, or the other way round).
public struct L2Key: Sendable, Hashable, Codable {
    public let l1: L1Key
    public let reference: ReferenceIdentity
    public let thresholdsVersion: Int
    public let scoringMode: ScoringMode

    public init(
        l1: L1Key, reference: ReferenceIdentity, thresholdsVersion: Int = Versions.thresholdsVersion,
        scoringMode: ScoringMode
    ) {
        self.l1 = l1
        self.reference = reference
        self.thresholdsVersion = thresholdsVersion
        self.scoringMode = scoringMode
    }

    public var text: String { (try? CanonicalJSON.sha256(self)) ?? "" }
}

/// One take's frame-level analysis: quality, voicing, pitch and the recogniser's words.
public struct L0Analysis: Sendable, Equatable, Codable {
    public let key: L0Key
    /// Everything spec 05's take-quality pass found (empty for a clean take).
    public let takeProblems: [TakeProblem]
    /// One voicing decision per 10 ms frame (spec 05).
    public let voiced: [Bool]
    public let pitch: PitchTrack
    /// The recogniser's words as recognised, before any boundary refinement.
    public let words: [WordTimestamp]
}

/// One take against its transcript: refined word timings, the alignment and its summary, syllables and pitch. No
/// observed stress or placement decision (spec 28): records written before still decode, their extra keys ignored.
public struct L1Analysis: Sendable, Equatable, Codable {
    public let key: L1Key
    /// The words after the boundary source (spec 23); what alignment and syllables were built on.
    public let words: [WordTimestamp]
    public let summary: AlignmentSummary
    public let analysis: TakeProsody
}

/// Your take compared with one reference: the outcome and what evaluation reads beside it.
public struct L2Analysis: Sendable, Hashable, Codable {
    public let key: L2Key
    /// `analysed` or `takeProblem` (wordsDontMatch, or the quality problems the decision procedure reports).
    public let outcome: AnalysisOutcome
    public let applicability: ApplicabilityTable
    public let measures: [MeasureKind: MeasureState<Double>]
    /// The model's own value of each measure it has (spec 10).
    public let modelValues: [MeasureKind: Double]
    /// Any phrase word logged `referenceAnomaly`.
    public let referenceAnomaly: Bool
    /// Spec 09: share of your comparable voiced frames inside the native band; nil with none.
    public let bandCoverage: Double?

    /// The decision procedure's answer, as the agreement harness reads it.
    public var decision: Decision? {
        switch outcome {
        case .analysed(let result): .verdict(result.verdict)
        case .takeProblem(let problem): .takeProblem(problem)
        case .failed, .cancelled: nil
        }
    }
}

/// A native recording's stored analysis: its L0 and L1, built by `Analyzer.analyseNative` (spec 15 stores it).
public struct NativeAnalysis: Sendable, Equatable, Codable {
    public let l0: L0Analysis
    public let l1: L1Analysis
}

/// Encoding into and out of the library's opaque records.
public enum DerivedCoding {
    public static func record(_ value: L0Analysis) throws -> DerivedRecord {
        DerivedRecord(level: .l0, key: value.key.text, bytes: try encode(value))
    }

    public static func record(_ value: L1Analysis) throws -> DerivedRecord {
        DerivedRecord(level: .l1, key: value.key.text, bytes: try encode(value))
    }

    public static func record(_ value: L2Analysis) throws -> DerivedRecord {
        DerivedRecord(level: .l2, key: value.key.text, bytes: try encode(value))
    }

    /// A native recording's L0 and L1 in one record, keyed by its L1 key.
    public static func record(_ value: NativeAnalysis) throws -> DerivedRecord {
        DerivedRecord(level: .l1, key: value.l1.key.text, bytes: try encode(value))
    }

    /// The value in `record`, or nil when its key isn't `key` or its bytes don't decode: a miss.
    public static func value<T: Decodable>(_ type: T.Type, in record: DerivedRecord, key: String) -> T? {
        guard record.key == key else { return nil }
        return try? JSONDecoder().decode(T.self, from: record.bytes)
    }

    /// The native analysis in `record` whatever its key, or nil when the bytes don't decode.
    public static func native(in record: DerivedRecord) -> NativeAnalysis? {
        guard let native = try? JSONDecoder().decode(NativeAnalysis.self, from: record.bytes),
            native.l1.key.text == record.key
        else { return nil }
        return native
    }

    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

/// An in-memory cache for one level: at most `capacity` values, the oldest dropped first.
struct LevelCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(capacity: Int) { self.capacity = max(capacity, 1) }

    subscript(key: Key) -> Value? { values[key] }

    mutating func insert(_ value: Value, for key: Key) {
        if values.updateValue(value, forKey: key) == nil { order.append(key) }
        while order.count > capacity { values[order.removeFirst()] = nil }
    }

    var count: Int { values.count }
}
