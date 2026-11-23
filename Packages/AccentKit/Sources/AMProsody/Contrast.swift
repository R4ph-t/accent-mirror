// Contrast C and weak length W (spec 08, plan §2). Both use raw durations: the lengthening discount applies to
// prominence only. Triggering diffs from them is spec 10's.

import AMCore
import Foundation

public enum Contrast {
    /// C = median(A over S) / median(A over U), A_i = dur_i × 10^(e_i / 20) with e floored at
    /// `energyMinimumDBFS`. Nil when S or U is empty or median(A over U) is 0.
    public static func contrast(
        _ syllables: [ProminenceFeatures], stressed: [Int], unstressed: [Int],
        thresholds: Thresholds.Prominence = Thresholds.current.prominence
    ) -> Double? {
        let amplitude = syllables.map { $0.duration * pow(10, max($0.energyDBFS, thresholds.energyMinimumDBFS) / 20) }
        guard let s = median(stressed.map { amplitude[$0] }), let u = median(unstressed.map { amplitude[$0] }), u > 0
        else { return nil }
        return s / u
    }

    /// W = median dur(U) / median dur(S), as a fraction (0.5 = 50%). Nil when S or U is empty or median dur(S) is 0.
    public static func weakLength(_ syllables: [ProminenceFeatures], stressed: [Int], unstressed: [Int]) -> Double? {
        guard let s = median(stressed.map { syllables[$0].duration }), s > 0,
            let u = median(unstressed.map { syllables[$0].duration })
        else { return nil }
        return u / s
    }

    /// The median; the mean of the middle two for an even count.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
