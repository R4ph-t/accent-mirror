// Spec 26 §1: the nucleus count grid, tuned against detection only. The pre-declared fixed grid, the tuning-only input
// guard, the per-point metrics (count-match rate, vowel-inside share, region–vowel IoU) and the choice rule (floor,
// objective, tie-breaks). Detection itself (envelope, pYIN voicing, peaks, the DP) runs in `am-eval nucleus-count`,
// which hands each clip's per-point outcome here. Nothing here reads a verdict, a flip or a gate number: the inputs
// carry MFA boundaries, allowed counts, assigned nuclei and MFA vowel intervals only.

import AMCore
import Foundation

public enum NucleusCountGrid {
    /// One grid point: the four tuned nucleus keys. Every other nucleus key stays at spec 25's value.
    public struct Point: Sendable, Hashable, Codable, CustomStringConvertible {
        public let minProminenceDB: Double
        public let minSeparationMs: Double
        public let regionDropDB: Double
        public let voicedWithinMs: Double

        public init(minProminenceDB: Double, minSeparationMs: Double, regionDropDB: Double, voicedWithinMs: Double) {
            self.minProminenceDB = minProminenceDB
            self.minSeparationMs = minSeparationMs
            self.regionDropDB = regionDropDB
            self.voicedWithinMs = voicedWithinMs
        }

        public var description: String {
            String(format: "prom %.1f dB, sep %.0f ms, drop %.0f dB, voiced ±%.0f ms",
                   minProminenceDB, minSeparationMs, regionDropDB, voicedWithinMs)
        }

        /// The thresholds with this point's four keys set.
        public func applied(to thresholds: Thresholds) -> Thresholds {
            var t = thresholds
            t.nucleus.minProminenceDB = minProminenceDB
            t.nucleus.minSeparationMs = minSeparationMs
            t.nucleus.regionDropDB = regionDropDB
            t.nucleus.voicedWithinMs = voicedWithinMs
            return t
        }
    }

    // The pre-declared grid (spec 26 §1), written before any run. No value outside it is ever used.
    public static let minProminenceDB: [Double] = [1.5, 2.0, 2.5, 3.0, 4.0]
    public static let minSeparationMs: [Double] = [50, 60, 70, 90]
    public static let regionDropDB: [Double] = [3, 6, 9]
    /// §1a: {0, 30} after a tracker offset fix, {0, 30, 60} for a real pYIN lag (this build: real lag).
    public static let voicedWithinMsRealLag: [Double] = [0, 30, 60]
    public static let voicedWithinMsOffsetFixed: [Double] = [0, 30]
    /// Spec 25's initial values (the last tie-break measures distance to them, in grid steps).
    public static let initial = Point(minProminenceDB: 3.0, minSeparationMs: 70, regionDropDB: 6, voicedWithinMs: 0)
    /// The vowel-inside floor (CTO decision 5): share of assigned peaks inside an MFA vowel widened by `vowelToleranceS`.
    public static let vowelInsideFloor = 0.90
    public static let vowelToleranceS = 0.010

    /// Every point, in a fixed order (prominence, separation, drop, voicing tolerance).
    public static func points(voicedWithinMs: [Double]) -> [Point] {
        minProminenceDB.flatMap { prominence in
            minSeparationMs.flatMap { separation in
                regionDropDB.flatMap { drop in
                    voicedWithinMs.map {
                        Point(minProminenceDB: prominence, minSeparationMs: separation, regionDropDB: drop, voicedWithinMs: $0)
                    }
                }
            }
        }
    }

    /// Distance to spec 25's initial values in grid steps (L1 over the four keys).
    public static func stepsFromInitial(_ point: Point, voicedWithinMs: [Double]) -> Int {
        func steps(_ grid: [Double], _ a: Double, _ b: Double) -> Int {
            abs((grid.firstIndex(of: a) ?? 0) - (grid.firstIndex(of: b) ?? 0))
        }
        return steps(minProminenceDB, point.minProminenceDB, initial.minProminenceDB)
            + steps(minSeparationMs, point.minSeparationMs, initial.minSeparationMs)
            + steps(regionDropDB, point.regionDropDB, initial.regionDropDB)
            + steps(voicedWithinMs, point.voicedWithinMs, initial.voicedWithinMs)
    }

    // MARK: Inputs

    public enum InputError: Error, Equatable, CustomStringConvertible {
        /// A clip from a speaker outside the VCTK split's tuning list (held-out, or not VCTK at all: synthetic, L2).
        case notTuning(clipID: String, speaker: String)

        public var description: String {
            switch self {
            case .notTuning(let clip, let speaker):
                "nucleus-count reads VCTK tuning speakers only; \(clip) (speaker \(speaker)) is not one"
            }
        }
    }

    /// One tuning clip's detection truth: MFA's vowel intervals. Words come with each point's outcome.
    public struct Clip: Sendable, Hashable {
        public let clipID: String
        public let speaker: String
        /// MFA vowel (nucleus) intervals, seconds.
        public let vowels: [ClosedRange<Double>]

        public init(clipID: String, speaker: String, vowels: [ClosedRange<Double>]) {
            self.clipID = clipID
            self.speaker = speaker
            self.vowels = vowels
        }
    }

    /// Refuses any clip whose speaker isn't in the split manifest's tuning list (spec 26 Guardrails).
    public static func validate(_ clips: [Clip], split: VCTKSplitManifest) throws(InputError) {
        let tuning = Set(split.tuning)
        for clip in clips where !tuning.contains(clip.speaker) {
            throw .notTuning(clipID: clip.clipID, speaker: clip.speaker)
        }
    }

    /// One comparable word's outcome at one point: N_w, P and whether it is nucleus-short.
    public struct WordOutcome: Sendable, Hashable {
        public let allowed: [Int]
        public let available: Int
        public let short: Bool
        /// The count the DP gave it is not the context count (a reduced form or CMUdict alternate).
        public let nonContextCount: Bool

        public init(allowed: [Int], available: Int, short: Bool, nonContextCount: Bool = false) {
            self.allowed = allowed
            self.available = available
            self.short = short
            self.nonContextCount = nonContextCount
        }

        /// The objective's unit: P ∈ N_w for a word that isn't nucleus-short.
        public var countMatch: Bool { !short && allowed.contains(available) }
    }

    /// One assigned nucleus: its peak and region.
    public struct AssignedNucleus: Sendable, Hashable {
        public let peak: Double
        public let region: ClosedRange<Double>

        public init(peak: Double, region: ClosedRange<Double>) {
            self.peak = peak
            self.region = region
        }
    }

    /// One clip at one point.
    public struct ClipOutcome: Sendable, Hashable {
        public let words: [WordOutcome]
        public let nuclei: [AssignedNucleus]

        public init(words: [WordOutcome], nuclei: [AssignedNucleus]) {
            self.words = words
            self.nuclei = nuclei
        }
    }

    // MARK: Metrics

    public struct Metrics: Sendable, Hashable, Codable {
        public let point: Point
        public let words: Int
        public let countMatched: Int
        public let assignedPeaks: Int
        public let peaksInsideVowel: Int
        /// Median IoU between each assigned nucleus's region and its best-overlapping MFA vowel (0 with none).
        public let medianIoU: Double
        public let short: Int
        public let nonContextCounts: Int

        public var countMatchRate: Double { words == 0 ? 0 : Double(countMatched) / Double(words) }
        public var vowelInsideShare: Double { assignedPeaks == 0 ? 0 : Double(peaksInsideVowel) / Double(assignedPeaks) }
        public var feasible: Bool { assignedPeaks > 0 && vowelInsideShare >= NucleusCountGrid.vowelInsideFloor }
    }

    public static func metrics(point: Point, clips: [Clip], outcomes: [ClipOutcome]) -> Metrics {
        var words = 0, matched = 0, peaks = 0, inside = 0, short = 0, nonContext = 0
        var ious: [Double] = []
        for (clip, outcome) in zip(clips, outcomes) {
            words += outcome.words.count
            matched += outcome.words.count(where: \.countMatch)
            short += outcome.words.count(where: \.short)
            nonContext += outcome.words.count(where: \.nonContextCount)
            for nucleus in outcome.nuclei {
                peaks += 1
                if clip.vowels.contains(where: {
                    nucleus.peak >= $0.lowerBound - vowelToleranceS && nucleus.peak <= $0.upperBound + vowelToleranceS
                }) { inside += 1 }
                ious.append(clip.vowels.map { iou(nucleus.region, $0) }.max() ?? 0)
            }
        }
        ious.sort()
        return Metrics(point: point, words: words, countMatched: matched, assignedPeaks: peaks,
                       peaksInsideVowel: inside, medianIoU: ious.isEmpty ? 0 : Statistics.quantile(ious, 0.5),
                       short: short, nonContextCounts: nonContext)
    }

    static func iou(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>) -> Double {
        let overlap = max(0, min(a.upperBound, b.upperBound) - max(a.lowerBound, b.lowerBound))
        let union = max(a.upperBound, b.upperBound) - min(a.lowerBound, b.lowerBound)
        return union > 0 ? overlap / union : 0
    }

    // MARK: Choice

    /// The choice: among feasible points (vowel-inside ≥ the floor), the highest count-match rate; ties by the higher
    /// vowel-inside share, then the higher median IoU, then the fewest grid steps from spec 25's initial values. Nil
    /// when no point is feasible. Rates compare as exact fractions.
    public static func choose(_ all: [Metrics], voicedWithinMs: [Double]) -> Metrics? {
        all.filter(\.feasible).min { a, b in
            // Count-match: words is the same at every point; compare cross-multiplied anyway.
            let matchA = a.countMatched * b.words, matchB = b.countMatched * a.words
            if matchA != matchB { return matchA > matchB }
            let insideA = a.peaksInsideVowel * b.assignedPeaks, insideB = b.peaksInsideVowel * a.assignedPeaks
            if insideA != insideB { return insideA > insideB }
            if a.medianIoU != b.medianIoU { return a.medianIoU > b.medianIoU }
            return stepsFromInitial(a.point, voicedWithinMs: voicedWithinMs)
                < stepsFromInitial(b.point, voicedWithinMs: voicedWithinMs)
        }
    }

    /// The points closest to feasibility (highest vowel-inside share first), for the no-feasible-point report.
    public static func closest(_ all: [Metrics], count: Int = 5) -> [Metrics] {
        Array(all.sorted { a, b in
            let insideA = a.peaksInsideVowel * b.assignedPeaks, insideB = b.peaksInsideVowel * a.assignedPeaks
            return insideA != insideB ? insideA > insideB : a.countMatched > b.countMatched
        }.prefix(count))
    }
}
