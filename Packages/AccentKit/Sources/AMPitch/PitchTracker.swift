// The pitch seam (CTO decision 3): our own trackers behind one protocol. A new algorithm (for example CREPE via
// Core ML) is a new type with a new `id` and a version bump, never a change to an existing one.

import Foundation
import AMCore

/// Turns mono audio into one pitch line per speaker (spec 04).
public protocol PitchTracker: Sendable {
    /// The `pitchTrackerID` recorded in `ConfigIdentity` (for example `pyin-1`).
    var id: String { get }

    /// Tracks `samples` (mono, at `sampleRate` Hz). Throws `CancellationError` when the task is cancelled, and
    /// returns no partial track. A take with no voiced frames gives an empty track, never 0 st or NaN.
    func track(_ samples: [Float], sampleRate: Double) async throws -> PitchTrack
}

public enum PitchTrackingError: Error, Equatable, Sendable {
    /// The rate is not finite, or too low to search up to `Thresholds.Pitch.maxF0Hz`.
    case unsupportedSampleRate(Double)
}
