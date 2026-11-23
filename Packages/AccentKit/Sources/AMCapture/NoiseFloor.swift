// The noise floor (spec 05, plan §10): provisional until it settles, then tracked over non-speech frames.

import AMCore
import Foundation

/// The noise-floor estimate, fed one frame at a time.
///
/// Provisional at first (the device's last-session floor, else `provisionalFloorDBFS`). It settles by rule (a), once
/// `settleNonSpeechMs` of non-speech frames exist (their P10), or rule (b), from `settleStationaryAfterS` on, when
/// the frames of the last `settleStationaryAfterS` are stationary (P90 − P10 < `stationarySpreadDB`; their P10).
/// After that it tracks the P10 of the non-speech frames in the last `floorWindowS`, and keeps its value while there
/// are none.
/// Settled and tracked values are clamped to `floorClampLowDBFS…floorClampHighDBFS`.
struct NoiseFloor: Sendable {
    private let capture: Thresholds.Capture
    private let settleFrames: Int
    private let windowFrames: Int
    private let stationaryAfterFrames: Int

    private(set) var dBFS: Double
    private(set) var isSettled = false
    /// Non-speech frames as (index, RMS). Before settling: all of them. After: those inside the tracking window.
    private var nonSpeech: [(index: Int, rms: Double)] = []
    /// The RMS of every frame in the last `settleStationaryAfterS`, for rule (b).
    private var recent: [Double] = []

    init(lastSessionDBFS: Double?, capture: Thresholds.Capture, frameSeconds: Double) {
        self.capture = capture
        settleFrames = max(1, Int((capture.settleNonSpeechMs / 1000 / frameSeconds).rounded()))
        windowFrames = max(1, Int((capture.floorWindowS / frameSeconds).rounded()))
        stationaryAfterFrames = max(1, Int((capture.settleStationaryAfterS / frameSeconds).rounded()))
        dBFS = Self.clamp(lastSessionDBFS ?? capture.provisionalFloorDBFS, capture)
    }

    private static func clamp(_ value: Double, _ capture: Thresholds.Capture) -> Double {
        min(max(value, capture.floorClampLowDBFS), capture.floorClampHighDBFS)
    }

    /// Frames from `index` on turned out to be speech (an onset was backdated over them): forget them as non-speech.
    mutating func reclaim(from index: Int) {
        nonSpeech.removeAll { $0.index >= index }
    }

    /// Adds frame `index` (frames arrive in order). Returns true on the frame the floor settles.
    mutating func add(index: Int, rms: Double, isNonSpeech: Bool) -> Bool {
        recent.append(rms)
        if recent.count > stationaryAfterFrames { recent.removeFirst(recent.count - stationaryAfterFrames) }
        if isNonSpeech { nonSpeech.append((index, rms)) }

        if isSettled {
            nonSpeech.removeAll { $0.index <= index - windowFrames }
            if !nonSpeech.isEmpty {
                dBFS = Self.clamp(percentile(capture.floorPercentile, of: nonSpeech.map(\.rms)), capture)
            }
            return false
        }

        if nonSpeech.count >= settleFrames {
            settle(at: percentile(capture.floorPercentile, of: nonSpeech.map(\.rms)), index: index)
            return true
        }
        if recent.count == stationaryAfterFrames,
            percentile(90, of: recent) - percentile(10, of: recent) < capture.stationarySpreadDB
        {
            settle(at: percentile(capture.floorPercentile, of: recent), index: index)
            return true
        }
        return false
    }

    private mutating func settle(at value: Double, index: Int) {
        isSettled = true
        dBFS = Self.clamp(value, capture)
        nonSpeech.removeAll { $0.index <= index - windowFrames }
    }
}
