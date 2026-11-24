// A speaker's pitch line and the post-processing every tracker's per-frame F0 goes through (spec 04): voiced runs
// shorter than `minVoicedRunMs` are dropped, a median filter and octave-jump repair run on the voiced frames, and the
// line is put in semitones re the speaker's median F0, bridged over short unvoiced stretches and broken at pauses.

import Foundation
import AMCore

/// One speaker's pitch: 10 ms frames in semitones re `medianF0Hz`, one segment per stretch between pauses.
///
/// Frame `k` of a segment is the cell `[start + k·hop, start + (k+1)·hop)`, the same cells as `VoicingSource`.
/// Bridged frames carry `voiced = false`. Empty exactly when no frame was voiced; `medianF0Hz` is nil then.
public struct PitchTrack: Sendable, Hashable {
    public let segments: [PitchSegment]
    /// The speaker's median F0 over voiced frames; nil when there are none.
    public let medianF0Hz: Double?
    /// Seconds between frames.
    public let hopSeconds: Double

    /// True when no frame is voiced: callers report pitch measures as `.unavailable(.noVoicedFrames)`.
    public var isEmpty: Bool { segments.isEmpty }

    /// Voiced (not bridged) frames over all segments.
    public var voicedFrameCount: Int {
        segments.reduce(0) { $0 + $1.frames.count(where: \.voiced) }
    }

    /// Builds the track from one F0 estimate per 10 ms frame (nil or non-positive: unvoiced). Frame `i` is the cell
    /// starting at `i × hopMs`.
    public init(frameF0Hz: [Double?], thresholds: Thresholds.Pitch = Thresholds.current.pitch) {
        let hopSeconds = thresholds.hopMs / 1000
        let log2F0 = PitchContour.voicedLog2F0(frameF0Hz, thresholds: thresholds)
        let voiced = log2F0.compactMap { $0 }
        guard !voiced.isEmpty else {
            self.init(uncheckedSegments: [], medianF0Hz: nil, hopSeconds: hopSeconds)
            return
        }
        let medianLog2 = PitchContour.median(voiced)
        let segments = PitchContour.segments(
            log2F0: log2F0, medianLog2: medianLog2, hopSeconds: hopSeconds, thresholds: thresholds)
        self.init(uncheckedSegments: segments, medianF0Hz: exp2(medianLog2), hopSeconds: hopSeconds)
    }

    private init(uncheckedSegments: [PitchSegment], medianF0Hz: Double?, hopSeconds: Double) {
        self.segments = uncheckedSegments
        self.medianF0Hz = medianF0Hz
        self.hopSeconds = hopSeconds
    }

    /// The highest voiced frame in `range` (by cell centre), in st re the median; nil with fewer than
    /// `minVoicedFrames` voiced frames there (spec 08's p_i, plan §2).
    public func peakSemitones(
        in range: TimeRange,
        minVoicedFrames: Int = Int(Thresholds.current.prominence.pitchMinVoicedFrames)
    ) -> Double? {
        var count = 0
        var peak = -Double.infinity
        for segment in segments {
            for (k, frame) in segment.frames.enumerated() where frame.voiced {
                let centre = segment.start + (Double(k) + 0.5) * hopSeconds
                guard range.contains(centre) else { continue }
                count += 1
                peak = max(peak, frame.semitones)
            }
        }
        return count >= max(minVoicedFrames, 1) ? peak : nil
    }
}

/// A stored track reads back exactly as it was built (spec 12's L0 cache): no post-processing runs again.
extension PitchTrack: Codable {
    enum CodingKeys: String, CodingKey { case segments, medianF0Hz, hopSeconds }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let segments = try container.decode([PitchSegment].self, forKey: .segments)
        let median = try container.decodeIfPresent(Double.self, forKey: .medianF0Hz)
        let hop = try container.decode(Double.self, forKey: .hopSeconds)
        guard hop > 0, hop.isFinite, segments.isEmpty == (median == nil) else {
            throw DecodingError.dataCorruptedError(
                forKey: .hopSeconds, in: container, debugDescription: "PitchTrack needs hop > 0 and a median iff voiced")
        }
        self.init(uncheckedSegments: segments, medianF0Hz: median, hopSeconds: hop)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segments, forKey: .segments)
        try container.encodeIfPresent(medianF0Hz, forKey: .medianF0Hz)
        try container.encode(hopSeconds, forKey: .hopSeconds)
    }
}

/// The post-processing steps, as pure functions over per-frame log2 F0 (nil: unvoiced).
enum PitchContour {
    /// Octave repair looks this many frames either side for its local reference (pyin-1 algorithm constant).
    static let octaveRepairHalfWindowFrames = 10
    /// A frame this close (st) to one octave from its local reference is an octave jump (pyin-1 algorithm constant).
    static let octaveRepairToleranceSemitones = 3.0

    /// Drops short voiced runs, median-filters each remaining run, then repairs octave jumps.
    static func voicedLog2F0(_ frameF0Hz: [Double?], thresholds: Thresholds.Pitch) -> [Double?] {
        var log2F0: [Double?] = frameF0Hz.map { f0 in
            guard let f0, f0.isFinite, f0 > 0 else { return nil }
            return log2(f0)
        }
        for run in voicedRuns(log2F0) where Double(run.count) * thresholds.hopMs < thresholds.minVoicedRunMs {
            for i in run { log2F0[i] = nil }
        }
        let halfMedian = max(Int(thresholds.medianFilterFrames) / 2, 0)
        for run in voicedRuns(log2F0) {
            let filtered = medianFiltered(run.map { log2F0[$0]! }, halfWindow: halfMedian)
            for (offset, i) in run.enumerated() { log2F0[i] = filtered[offset] }
        }
        return octaveRepaired(log2F0)
    }

    /// Maximal runs of consecutive voiced frames.
    static func voicedRuns(_ log2F0: [Double?]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for i in 0...log2F0.count {
            let voiced = i < log2F0.count && log2F0[i] != nil
            if voiced, start == nil { start = i }
            if !voiced, let s = start {
                runs.append(s..<i)
                start = nil
            }
        }
        return runs
    }

    /// A centred running median. Near the run's ends the window shrinks symmetrically, so a steady glide keeps its
    /// end points.
    static func medianFiltered(_ values: [Double], halfWindow: Int) -> [Double] {
        values.indices.map { i in
            let half = min(halfWindow, i, values.count - 1 - i)
            return median(Array(values[(i - half)...(i + half)]))
        }
    }

    /// Moves a voiced frame by an octave when it sits about an octave from the median of the voiced frames within
    /// `octaveRepairHalfWindowFrames` of it. Neighbours count across unvoiced frames, so a jump the tracker split
    /// off into its own short run is still repaired.
    static func octaveRepaired(_ log2F0: [Double?]) -> [Double?] {
        let half = octaveRepairHalfWindowFrames
        let tolerance = octaveRepairToleranceSemitones / 12
        return log2F0.indices.map { i in
            guard let value = log2F0[i] else { return nil }
            let neighbours = log2F0[max(0, i - half)...min(log2F0.count - 1, i + half)].compactMap { $0 }
            let delta = value - median(neighbours)
            if abs(delta - 1) <= tolerance { return value - 1 }
            if abs(delta + 1) <= tolerance { return value + 1 }
            return value
        }
    }

    /// Semitone segments: unvoiced stretches up to `lineBreakMs` are bridged linearly, longer ones break the line.
    /// Leading and trailing unvoiced frames belong to no segment.
    static func segments(
        log2F0: [Double?], medianLog2: Double, hopSeconds: Double, thresholds: Thresholds.Pitch
    ) -> [PitchSegment] {
        let voiced = log2F0.indices.compactMap { i in log2F0[i].map { (index: i, st: 12 * ($0 - medianLog2)) } }
        var segments: [PitchSegment] = []
        var startIndex = voiced[0].index
        var frames = [PitchFrame(semitones: voiced[0].st, voiced: true)]
        for (previous, next) in zip(voiced, voiced.dropFirst()) {
            let gap = next.index - previous.index - 1
            if Double(gap) * thresholds.hopMs > thresholds.lineBreakMs {
                segments.append(PitchSegment(start: Double(startIndex) * hopSeconds, frames: frames))
                startIndex = next.index
                frames = []
            } else if gap > 0 {
                for k in 1...gap {
                    let t = Double(k) / Double(gap + 1)
                    frames.append(PitchFrame(semitones: previous.st + t * (next.st - previous.st), voiced: false))
                }
            }
            frames.append(PitchFrame(semitones: next.st, voiced: true))
        }
        segments.append(PitchSegment(start: Double(startIndex) * hopSeconds, frames: frames))
        return segments
    }

    /// The median of a non-empty array (mean of the middle two for an even count).
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
