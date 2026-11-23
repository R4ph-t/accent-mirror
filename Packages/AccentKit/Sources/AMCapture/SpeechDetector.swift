// Onset, offset and retraction over the noise floor (spec 05, plan §10). Frame-driven, no clock.

import AMCore
import Foundation

/// A detected start of speech.
public struct Onset: Sendable, Hashable {
    /// `t_onset`: the start of the first frame of the qualifying run, in seconds from the start of the take.
    public let time: Double
    /// `t_detect`: the end of the frame on which the onset rule fired. `detectedAt − time ≤ onsetVoicedWithinMs`.
    public let detectedAt: Double
    /// The floor was still provisional when the onset fired, so it is re-checked when the floor settles.
    public let provisional: Bool
}

/// A stretch of speech frames `[start, end)` that began with an onset.
struct SpeechSegment: Sendable, Hashable {
    let start: Int
    let detect: Int
    var end: Int
    let provisional: Bool
    var retracted = false
}

/// What a frame changed.
enum DetectorEvent: Sendable, Hashable {
    case onset(segment: Int)
    case floorSettled
    case retracted(segment: Int)
}

/// Classifies frames as speech or not, one at a time.
///
/// - Onset: RMS ≥ max(`onsetMinimumDBFS`, floor + `onsetAboveFloorDB`) for `onsetFrames` consecutive frames, with a
///   voiced frame among them, all within `onsetVoicedWithinMs` of the backdated `t_onset`.
/// - Offset: the first frame below floor + `offsetAboveFloorDB` ends the segment; speech resumes only through a new
///   onset.
/// - Retraction: when the floor settles, each segment that began on the provisional floor and whose median RMS is
///   below the settled floor + `retractionAboveFloorDB` is retracted and stops counting as speech.
struct SpeechDetector: Sendable {
    let thresholds: Thresholds
    let frameSeconds: Double
    private let onsetFrames: Int
    private let voicedWithinFrames: Int

    private(set) var floor: NoiseFloor
    private(set) var segments: [SpeechSegment] = []
    private(set) var features: [FrameFeatures] = []
    /// The floor each frame was judged against (the value before the frame updated it).
    private(set) var floorAtFrame: [Double] = []
    /// The frame on which the floor settled, and the value it settled at.
    private(set) var settled: (frame: Int, dBFS: Double)?

    private var speaking = false
    private var runStart: Int?
    private var lastVoiced = Int.min

    init(lastSessionFloorDBFS: Double?, thresholds: Thresholds) {
        self.thresholds = thresholds
        frameSeconds = thresholds.voicing.hopMs / 1000
        onsetFrames = max(1, Int(thresholds.capture.onsetFrames.rounded()))
        voicedWithinFrames = max(
            onsetFrames, Int((thresholds.capture.onsetVoicedWithinMs / thresholds.voicing.hopMs).rounded()))
        floor = NoiseFloor(
            lastSessionDBFS: lastSessionFloorDBFS, capture: thresholds.capture, frameSeconds: frameSeconds)
    }

    var frameCount: Int { features.count }

    /// The segment still open (speech continuing on the last frame), if any.
    var openSegment: Int? { speaking ? segments.indices.last : nil }

    func onset(of segment: SpeechSegment) -> Onset {
        Onset(
            time: Double(segment.start) * frameSeconds, detectedAt: Double(segment.detect + 1) * frameSeconds,
            provisional: segment.provisional)
    }

    /// Frames in segments that still count as speech.
    var speechFrameCount: Int { segments.filter { !$0.retracted }.reduce(0) { $0 + $1.end - $1.start } }

    /// The end (exclusive frame index) of the last frame that still counts as speech, if any.
    var lastSpeechEnd: Int? { segments.last { !$0.retracted }?.end }

    mutating func process(_ frame: FrameFeatures) -> [DetectorEvent] {
        let index = features.count
        let floorNow = floor.dBFS
        let capture = thresholds.capture
        features.append(frame)
        floorAtFrame.append(floorNow)
        var events: [DetectorEvent] = []

        if ACFVoicing.isVoiced(frame, floorDBFS: floorNow, thresholds: thresholds.voicing) { lastVoiced = index }

        if speaking {
            if frame.rmsDBFS >= floorNow + capture.offsetAboveFloorDB {
                segments[segments.count - 1].end = index + 1
            } else {
                speaking = false
            }
        } else {
            let onsetLevel = max(capture.onsetMinimumDBFS, floorNow + capture.onsetAboveFloorDB)
            if frame.rmsDBFS >= onsetLevel {
                let run = runStart ?? index
                runStart = run
                let start = max(run, index - voicedWithinFrames + 1)
                if index - start + 1 >= onsetFrames, lastVoiced >= start {
                    segments.append(
                        SpeechSegment(start: start, detect: index, end: index + 1, provisional: !floor.isSettled))
                    speaking = true
                    runStart = nil
                    floor.reclaim(from: start)
                    events.append(.onset(segment: segments.count - 1))
                }
            } else {
                runStart = nil
            }
        }

        if floor.add(index: index, rms: frame.rmsDBFS, isNonSpeech: !speaking) {
            settled = (index, floor.dBFS)
            events.append(.floorSettled)
            events += retractProvisionalSegments()
        }
        return events
    }

    private mutating func retractProvisionalSegments() -> [DetectorEvent] {
        let bar = floor.dBFS + thresholds.capture.retractionAboveFloorDB
        var events: [DetectorEvent] = []
        for index in segments.indices where segments[index].provisional && !segments[index].retracted {
            let segment = segments[index]
            let levels = features[segment.start..<segment.end].map(\.rmsDBFS)
            guard percentile(50, of: levels) < bar else { continue }
            segments[index].retracted = true
            if index == segments.count - 1 { speaking = false }
            events.append(.retracted(segment: index))
        }
        return events
    }

    /// Per-frame voicing judged against the floor as finally known: frames heard before the floor settled are
    /// judged against the settled value, so a provisional floor never makes a frame voiced in hindsight.
    var voicedFrames: [Bool] {
        features.indices.map { index in
            let reference = settled.map { index <= $0.frame ? $0.dBFS : floorAtFrame[index] } ?? floorAtFrame[index]
            return ACFVoicing.isVoiced(features[index], floorDBFS: reference, thresholds: thresholds.voicing)
        }
    }
}
