// The pitch chart's vertical extent (spec 04, v1): ±12 st, growing in steps of 6 st up to ±24 st, never shrinking
// within a phrase.

import Foundation
import AMCore

public enum PitchAxis {
    /// The smallest allowed extent that holds every frame of `segments` and is at least `previous` (the extent
    /// already shown for this phrase; nil for the first take). Frames beyond the maximum are clipped by the view.
    public static func extent(
        previous: ClosedRange<Double>?, segments: [PitchSegment],
        thresholds: Thresholds.Pitch = Thresholds.current.pitch
    ) -> ClosedRange<Double> {
        let peak = segments.lazy.flatMap(\.frames).map { abs($0.semitones) }.filter(\.isFinite).max() ?? 0
        let floor = previous.map { max(abs($0.lowerBound), abs($0.upperBound)) } ?? thresholds.axisInitialSemitones
        var half = max(thresholds.axisInitialSemitones, min(floor, thresholds.axisMaxSemitones))
        while half < peak, half < thresholds.axisMaxSemitones {
            half = min(half + thresholds.axisStepSemitones, thresholds.axisMaxSemitones)
        }
        return -half...half
    }
}
