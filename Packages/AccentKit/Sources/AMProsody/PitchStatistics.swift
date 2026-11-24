// The pure measure helpers the shipped description (spec 28 §4a) and scoring (spec 10) both read: P10–P90, the
// least-squares slope, nPVI and the final window. Moved down from `AMScoring` (spec 28) so the shipped path doesn't
// link the verdict code; `AMScoring` calls these, there is no second copy.

import AMCore
import Foundation

public enum PitchStatistics {
    /// P90 − P10 in st (linear-interpolated percentiles, the band's); nil with no frame.
    public static func range(_ values: [Double], thresholds: Thresholds.Band) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return percentile(sorted, thresholds.upperPercentile) - percentile(sorted, thresholds.lowerPercentile)
    }

    /// The `p`th percentile of sorted values, linearly interpolated.
    public static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let position = p / 100 * Double(sorted.count - 1)
        let lo = Int(position.rounded(.down))
        let hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (position - Double(lo)) * (sorted[hi] - sorted[lo])
    }

    /// Least-squares slope of semitones on seconds; nil when every frame has the same time.
    public static func slope(_ points: [(t: Double, st: Double)]) -> Double? {
        let n = Double(points.count)
        let meanT = points.reduce(0) { $0 + $1.t } / n
        let meanS = points.reduce(0) { $0 + $1.st } / n
        let sxx = points.reduce(0) { $0 + ($1.t - meanT) * ($1.t - meanT) }
        guard sxx > 0 else { return nil }
        return points.reduce(0) { $0 + ($1.t - meanT) * ($1.st - meanS) } / sxx
    }

    /// nPVI = 100 × mean |d_k − d_k+1| / ((d_k + d_k+1) / 2); nil with fewer than 3 syllables.
    public static func npvi(_ durations: [Double]) -> Double? {
        guard durations.count >= 3 else { return nil }
        var sum = 0.0
        for k in 0..<(durations.count - 1) {
            let a = durations[k], b = durations[k + 1]
            let mean = (a + b) / 2
            if mean > 0 { sum += abs(a - b) / mean }
        }
        return 100 * sum / Double(durations.count - 1)
    }
}

/// The final window of one take (§11): its voiced frames and their least-squares slope.
public struct FinalWindow: Sendable, Hashable {
    /// Voiced frames in the window (200 ms, or 300 ms when 200 ms holds too few).
    public let voicedFrames: Int
    /// Least-squares slope in st/s; nil with fewer than `finalDirection.minVoicedFrames` voiced frames.
    public let slope: Double?

    /// The final 200 ms of voiced frames ending at the last voiced frame inside `material` (the take's comparable
    /// words, whatever their class); extended back to 300 ms when 200 ms holds fewer than the minimum.
    public init(
        pitch: [PitchSegment], material: [TimeRange], hopSeconds hop: Double,
        thresholds: Thresholds.FinalDirection = Thresholds.current.finalDirection
    ) {
        // (centre time, semitones) of every voiced frame inside the material.
        let voiced: [(t: Double, st: Double)] = pitch.flatMap { segment in
            segment.frames.enumerated().compactMap { j, frame -> (Double, Double)? in
                let t = segment.start + (Double(j) + 0.5) * hop
                guard frame.voiced, material.contains(where: { $0.start <= t && t <= $0.end }) else { return nil }
                return (t, frame.semitones)
            }
        }
        guard let last = voiced.max(by: { $0.t < $1.t })?.t else {
            self.init(voicedFrames: 0, slope: nil)
            return
        }
        let minimum = Int(thresholds.minVoicedFrames)
        // A frame is in a window of length w when its centre is within w of the last centre (half-open, so 200 ms
        // holds 20 frames at a 10 ms hop).
        func window(_ ms: Double) -> [(t: Double, st: Double)] {
            voiced.filter { last - $0.t < ms / 1000 - hop / 2 }
        }
        var frames = window(thresholds.windowMs)
        if frames.count < minimum { frames = window(thresholds.extendedWindowMs) }
        self.init(voicedFrames: frames.count, slope: frames.count >= minimum ? PitchStatistics.slope(frames) : nil)
    }

    public init(voicedFrames: Int, slope: Double?) {
        self.voicedFrames = voicedFrames
        self.slope = slope
    }
}
