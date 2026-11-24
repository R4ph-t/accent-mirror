// Per-syllable prominence (spec 08, plan §2). P is a weighted mean of z-scored duration, energy and peak pitch over
// the comparable syllable set the caller passes in; the set is reference-dependent (L2 in §9.2), so nothing here
// chooses it. The lengthening discount applies to the duration feature only; contrast and weak length use raw
// durations (`Contrast`).

import AMCore
import AMPitch
import Foundation

/// The raw L1 features of one syllable that prominence reads.
public struct ProminenceFeatures: Sendable, Hashable, Codable {
    /// d, seconds, before any discount.
    public let duration: Double
    /// e, mean RMS in dBFS. Floored at `prominence.energyMinimumDBFS` when prominence is computed.
    public let energyDBFS: Double
    /// p, peak F0 in st re the speaker's median; nil with fewer than `pitchMinVoicedFrames` voiced frames.
    public let peakSemitones: Double?
    /// Last syllable before the take's end or a pause (spec 07): its log duration is discounted by ln λ.
    public let lengtheningExposed: Bool

    public init(duration: Double, energyDBFS: Double, peakSemitones: Double?, lengtheningExposed: Bool) {
        self.duration = duration
        self.energyDBFS = energyDBFS
        self.peakSemitones = peakSemitones
        self.lengtheningExposed = lengtheningExposed
    }

    /// A segmented syllable's features, with p read from the speaker's pitch track: over the syllable's span, or
    /// over its nucleus region in `.nucleus` mode (spec 25 §3).
    public init(_ syllable: SegmentedSyllable, pitch: PitchTrack, thresholds: Thresholds.Prominence) {
        self.init(
            duration: syllable.duration, energyDBFS: syllable.energyDBFS,
            peakSemitones: pitch.peakSemitones(
                in: syllable.nucleus?.region ?? syllable.range, minVoicedFrames: Int(thresholds.pitchMinVoicedFrames)),
            lengtheningExposed: syllable.lengtheningExposed)
    }
}

public enum Prominence {
    /// The shortest duration the log takes. Algorithm constant, not a threshold: it only keeps ln finite for a
    /// zero-length syllable, which spec 07 can report for a degenerate span.
    static let minimumDurationS = 0.001

    /// P_i for each syllable of the comparable set, in the order given; nil when fewer than 2 syllables (prominence
    /// is unavailable). A feature with fewer than 2 values drops out; the sd floors keep z finite on zero variance.
    public static func scores(
        _ syllables: [ProminenceFeatures], lambda: Double, thresholds: Thresholds.Prominence = Thresholds.current.prominence
    ) -> [Double]? {
        guard syllables.count >= 2 else { return nil }
        let discount = log(max(lambda, 1))
        let duration = syllables.map { log(max($0.duration, minimumDurationS)) - ($0.lengtheningExposed ? discount : 0) }
        let energy = syllables.map { max($0.energyDBFS, thresholds.energyMinimumDBFS) }
        let pitch = syllables.map(\.peakSemitones)
        let features: [(values: [Double?], weight: Double, floor: Double)] = [
            (duration, thresholds.durationWeight, thresholds.durationFloorLn),
            (energy, thresholds.energyWeight, thresholds.energyFloorDB),
            (pitch, thresholds.pitchWeight, thresholds.pitchFloorSemitones),
        ]
        let z = features.map { feature in (zScores(feature.values, floor: feature.floor), feature.weight) }
        return syllables.indices.map { i in
            var sum = 0.0, weights = 0.0
            for (values, weight) in z {
                guard let value = values[i] else { continue }
                sum += weight * value
                weights += weight
            }
            // d and e are present for every syllable, so `weights` is never 0 here.
            return weights > 0 ? sum / weights : 0
        }
    }

    /// P_i with the current λ.
    public static func scores(
        _ syllables: [ProminenceFeatures], thresholds: Thresholds.Prominence = Thresholds.current.prominence
    ) -> [Double]? {
        scores(syllables, lambda: thresholds.lengtheningLambda, thresholds: thresholds)
    }

    /// z = (x − mean) / max(population sd, floor) over the present values; all nil when fewer than 2 are present.
    static func zScores(_ values: [Double?], floor: Double) -> [Double?] {
        let present = values.compactMap { $0 }
        guard present.count >= 2 else { return values.map { _ in nil } }
        let mean = present.reduce(0, +) / Double(present.count)
        let variance = present.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(present.count)
        let sd = max(variance.squareRoot(), floor)
        return values.map { $0.map { ($0 - mean) / sd } }
    }

    /// Display prominence: P min-max normalised to 0–1 within the take, for the strip bars and the secondary rule.
    /// A take whose P are all equal shows 0 everywhere.
    public static func display(_ scores: [Double]) -> [Double] {
        guard let low = scores.min(), let high = scores.max(), high > low else { return scores.map { _ in 0 } }
        return scores.map { ($0 - low) / (high - low) }
    }
}
