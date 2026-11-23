// `ACFVoicing` (spec 05, plan §10): the first `VoicingSource`. pYIN may replace it later only under a new
// `voicingID` and a version bump.

import AMCore
import Foundation

/// Voicing by normalised autocorrelation: 40 ms window, 10 ms hop, lags 2–16.7 ms (60–500 Hz). A frame is voiced
/// when its ACF peak is at least `minPeak` and its RMS is above the noise floor + `aboveFloorDB`.
public struct ACFVoicing: VoicingSource {
    public static let voicingID = "acf-1"

    public let thresholds: Thresholds

    public init(thresholds: Thresholds = .current) {
        self.thresholds = thresholds
    }

    public var id: String { Self.voicingID }

    /// One decision per 10 ms frame (a short last frame is zero-padded). The floor is the endpointer's, as finally
    /// known for the take: frames before it settled are judged against the settled value.
    public func voicedFrames(samples: [Float], sampleRate: Double) -> [Bool] {
        TakeAnalysis(samples: samples, sampleRate: sampleRate, thresholds: thresholds).voiced
    }

    /// The streaming decision for one frame against the floor in effect.
    public static func isVoiced(_ frame: FrameFeatures, floorDBFS: Double, thresholds: Thresholds.Voicing) -> Bool {
        frame.acfPeak >= thresholds.minPeak && frame.rmsDBFS > floorDBFS + thresholds.aboveFloorDB
    }
}
