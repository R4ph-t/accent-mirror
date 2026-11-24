// What one analysis reads (spec 12): your take's audio and the phrase as the pipeline sees it.

import AMAlignment
import AMCore
import AMProsody
import Foundation

/// One take: 16 kHz mono Float32 (spec 14's capture format) and its SHA-256.
public struct TakeAudio: Sendable, Hashable {
    public static let sampleRate: Double = 16_000

    public let samples: [Float]
    /// The take's identity in every cache key and in `AnalysisIdentity`.
    public let sha256: String
    /// What a replaying timestamper looks the take up by (tests and evaluation); the SHA-256 for a live take.
    public let clipID: String
    public let recordedAt: Date

    /// `sha256` defaults to the SHA-256 of the samples as little-endian Float32 bytes.
    public init(samples: [Float], sha256: String? = nil, clipID: String? = nil, recordedAt: Date = Date()) {
        let digest = sha256 ?? Self.sha256(of: samples)
        self.samples = samples
        self.sha256 = digest
        self.clipID = clipID ?? digest
        self.recordedAt = recordedAt
    }

    /// SHA-256 of the samples as little-endian Float32 bytes.
    public static func sha256(of samples: [Float]) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(samples.count * 4)
        for sample in samples {
            withUnsafeBytes(of: sample.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }
        return SHA256Digest.hex(of: bytes)
    }

    /// The take's ID in the result and the store: derived from its audio, so the same take keeps its ID.
    public var takeID: TakeID { TakeID("take-" + sha256.prefix(16)) }

    public var duration: Double { Double(samples.count) / Self.sampleRate }
}

/// The phrase as the pipeline reads it: each word with its pronunciation and A(w), and the transcript revision.
public struct PhraseInput: Sendable, Hashable {
    public let id: PhraseID
    /// Every transcript word, in order.
    public let words: [PlacementTake.Word]
    /// Bumped by a committed transcript edit (it invalidates L1).
    public let transcriptRevision: Int

    public init(id: PhraseID, words: [PlacementTake.Word], transcriptRevision: Int = 0) {
        self.id = id
        self.words = words
        self.transcriptRevision = transcriptRevision
    }

    /// Spec 07's hash of the pronunciations, part of the L1 key.
    public var pronunciationHash: String {
        SyllableSegmenter.pronunciationHash(Dictionary(uniqueKeysWithValues: words.map { ($0.index, $0.pronunciation) }))
    }
}
