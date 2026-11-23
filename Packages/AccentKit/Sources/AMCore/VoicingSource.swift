// The voicing seam (plan §10). It lives in AMCore so spec 05 (`ACFVoicing`) and spec 07 (the syllable segmenter)
// can both use it without importing each other. No implementation here.

import Foundation

/// Decides, per 10 ms frame, whether a take is voiced.
public protocol VoicingSource: Sendable {
    /// The `voicingID` recorded in `ConfigIdentity` (for example `acf-1`). A new algorithm gets a new ID.
    var id: String { get }

    /// One decision per 10 ms frame of `samples` (mono, at `sampleRate` Hz): frame `i` starts at `i × 10 ms`.
    func voicedFrames(samples: [Float], sampleRate: Double) -> [Bool]
}

/// Frame hop shared by voicing and pitch (10 ms).
public let voicingFrameDuration: Double = 0.010
