// What a take that clipped gets (Designer addendum v3.5 I4). Two tiers, never red:
// (A) unmeasurable: the take problem `clipped` (spec 05's share of clipped speech frames); the take isn't saved.
// (B) measures valid: the take is saved, and card 1 adds one quiet line when a contiguous run of 10 ms frames peaking
//     at −1 dBFS or more lasts 50 ms or longer. Shorter spikes aren't announced after the take: E5 already flashed
//     "Too loud" while recording.

import Accelerate
import AMCore
import Foundation

public enum ClippingTier: Sendable, Hashable {
    /// Nothing to say about clipping.
    case none
    /// Tier B: saved as a result, with the quiet line.
    case clippedSaved
    /// Tier A: too loud to measure, not saved.
    case unmeasurable

    /// The frame peak that counts as clipping: E5's "Too loud" level.
    public static let levelDBFS = -1.0
    /// The meter's frame.
    public static let frameSeconds = 0.01
    /// The shortest run the quiet line announces.
    public static let minimumRunSeconds = 0.05

    /// The tier for a take's outcome: `takeProblem` is the coordinator's (only `clipped` matters), `samples` the
    /// kept audio of a take that was measured.
    public static func classify(takeProblem: TakeProblem?, samples: [Float], sampleRate: Double) -> ClippingTier {
        if takeProblem == .clipped { return .unmeasurable }
        guard takeProblem == nil else { return .none }
        return longestRunSeconds(samples, sampleRate: sampleRate) >= minimumRunSeconds - 1e-9 ? .clippedSaved : .none
    }

    /// The longest contiguous run of 10 ms frames whose peak is at −1 dBFS or more, in seconds. A trailing partial
    /// frame isn't counted.
    public static func longestRunSeconds(_ samples: [Float], sampleRate: Double) -> Double {
        let frame = Int((sampleRate * frameSeconds).rounded())
        guard frame > 0, samples.count >= frame else { return 0 }
        let threshold = Float(pow(10, levelDBFS / 20))
        var longest = 0
        var run = 0
        samples.withUnsafeBufferPointer { buffer in
            var start = 0
            while start + frame <= buffer.count {
                let peak = vDSP.maximumMagnitude(UnsafeBufferPointer(rebasing: buffer[start..<start + frame]))
                run = peak >= threshold ? run + 1 : 0
                longest = max(longest, run)
                start += frame
            }
        }
        return Double(longest) * Double(frame) / sampleRate
    }
}
