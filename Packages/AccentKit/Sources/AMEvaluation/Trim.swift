// The VCTK trim (spec 02, Open question 2, built with the default): cut at the first and last frame above the
// spec 05 onset level, keep 200 ms of pre-roll and 300 ms of tail, and reject (and report) any clip outside 2–6 s
// rather than cutting speech. The same rule for every speaker.
//
// This applies spec 05's level rule directly from `Thresholds.capture` (AMEvaluation depends on AMCore only): 10 ms
// frames; floor = the `floorPercentile` of frame RMS, clamped to [floorClampLow, floorClampHigh]; a frame is above
// the onset level at RMS ≥ max(onsetMinimumDBFS, floor + onsetAboveFloorDB); speech starts at the first run of
// `onsetFrames` such frames and ends at the last. Spec 05's voicing condition is not applied; moving the trim onto
// spec 05's detector is a follow-up (see the spec's implementation notes).

import Foundation
import AMCore

public struct TrimRule: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        /// Keep samples in `range`.
        case keep(range: Range<Int>)
        /// No speech found.
        case noSpeech
        /// The cut clip (with pre-roll and tail) is outside 2–6 s; it is reported, never cut further.
        case outOfRange(seconds: Double)
    }

    public let capture: Thresholds.Capture
    /// Tail kept after the last speech frame (Open question 2 default).
    public let tailMs = 300.0
    /// The accepted clip length (§6.2).
    public let minimumSeconds = 2.0
    public let maximumSeconds = 6.0

    public init(thresholds: Thresholds = .current) { capture = thresholds.capture }

    public func apply(samples: [Float], sampleRate: Double) -> Outcome {
        let frame = max(1, Int((sampleRate * 0.010).rounded()))
        let frameCount = samples.count / frame
        guard frameCount > 0 else { return .noSpeech }
        var levels = [Double](repeating: -120, count: frameCount)
        for f in 0..<frameCount {
            var sum = 0.0
            for s in samples[(f * frame)..<((f + 1) * frame)] { sum += Double(s) * Double(s) }
            let rms = (sum / Double(frame)).squareRoot()
            levels[f] = rms > 0 ? 20 * log10(rms) : -120
        }
        let sorted = levels.sorted()
        let floorIndex = min(sorted.count - 1, Int(Double(sorted.count - 1) * capture.floorPercentile / 100))
        let floor = min(max(sorted[floorIndex], capture.floorClampLowDBFS), capture.floorClampHighDBFS)
        let level = max(capture.onsetMinimumDBFS, floor + capture.onsetAboveFloorDB)
        let run = Int(capture.onsetFrames)
        var first: Int?
        var lastEnd: Int?
        var current = 0
        for f in 0..<frameCount {
            current = levels[f] >= level ? current + 1 : 0
            if current >= run {
                if first == nil { first = f - run + 1 }
                lastEnd = f + 1
            }
        }
        guard let first, let lastEnd else { return .noSpeech }
        let start = max(0, first * frame - Int(sampleRate * capture.preRollMs / 1000))
        let end = min(samples.count, lastEnd * frame + Int(sampleRate * tailMs / 1000))
        let seconds = Double(end - start) / sampleRate
        guard seconds >= minimumSeconds, seconds <= maximumSeconds else { return .outOfRange(seconds: seconds) }
        return .keep(range: start..<end)
    }
}
