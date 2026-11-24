// Spec 27 §4: TD-PSOLA (Moulines & Charpentier 1990), written here from the published algorithm only (no code from
// Praat, Prosogram or any PSOLA library). Offline, negatives and the identity control only; nothing here ships.
//
// - Analysis marks: in voiced stretches one mark per pitch period from spec 04's pYIN track, each placed on the
//   largest sample within ±20% of a period of where the previous mark plus one period predicts (the first one of a
//   voiced run on the largest sample of its first period); in unvoiced stretches a mark every 10 ms.
// - Synthesis: a piecewise-linear time map (slope = the duration factor inside a modified region, 1 elsewhere)
//   carries analysis time to output time. Output marks are laid one local period apart, divided by the pitch factor
//   on voiced marks; each takes the analysis mark nearest its pre-image, a Hann-windowed two-period segment around
//   it (asymmetric: the left and right period, widened to the output spacing when pitch falls), scaled by the gain,
//   and overlap-adds it there. The sum is divided by the summed windows, so an unmodified pass with the same marks
//   gives the input back (the identity path of CTO markup 4).

import AMCore
import AMPitch
import Foundation

public enum PSOLA {
    public struct Mark: Sendable, Hashable {
        public let position: Int
        public let voiced: Bool
    }

    /// One modified stretch of analysis time.
    public struct Region: Sendable, Hashable, Codable {
        public let start: Double
        public let end: Double
        /// Output length over input length.
        public let durationFactor: Double
        public let gainDB: Double
        /// Pitch shift (st) at evenly spaced relative positions 0…1 across the region (linear in between).
        public let shiftProfile: [Double]

        public init(start: Double, end: Double, durationFactor: Double, gainDB: Double, shiftProfile: [Double]) {
            self.start = start
            self.end = end
            self.durationFactor = durationFactor
            self.gainDB = gainDB
            self.shiftProfile = shiftProfile
        }

        func shift(at t: Double) -> Double {
            guard !shiftProfile.isEmpty, end > start else { return 0 }
            let r = min(max((t - start) / (end - start), 0), 1) * Double(shiftProfile.count - 1)
            let i = min(Int(r), shiftProfile.count - 1), j = min(i + 1, shiftProfile.count - 1)
            return shiftProfile[i] + (r - Double(i)) * (shiftProfile[j] - shiftProfile[i])
        }

        /// 0 at the region's edges rising to 1 over `rampSeconds` inside it, so gain and shift never step.
        func weight(at t: Double) -> Double {
            guard t >= start && t <= end else { return 0 }
            let ramp = min(PSOLA.rampSeconds, (end - start) / 2)
            guard ramp > 0 else { return 1 }
            return min(1, (t - start) / ramp, (end - t) / ramp)
        }
    }

    /// Piecewise-linear map from analysis time to output time.
    public struct TimeMap: Sendable, Hashable, Codable {
        /// (analysis, output) knots, increasing in both.
        public let analysis: [Double]
        public let output: [Double]

        public init(regions: [Region], duration: Double) {
            var a: [Double] = [0], o: [Double] = [0]
            for region in regions.sorted(by: { $0.start < $1.start }) {
                let start = max(region.start, a.last!)
                guard region.end > start else { continue }
                o.append(o.last! + (start - a.last!)); a.append(start)
                o.append(o.last! + (region.end - start) * region.durationFactor); a.append(region.end)
            }
            if duration > a.last! { o.append(o.last! + (duration - a.last!)); a.append(duration) }
            analysis = a
            output = o
        }

        public func forward(_ t: Double) -> Double { Self.interpolate(t, analysis, output) }
        public func inverse(_ t: Double) -> Double { Self.interpolate(t, output, analysis) }

        static func interpolate(_ x: Double, _ xs: [Double], _ ys: [Double]) -> Double {
            guard xs.count >= 2 else { return x }
            if x <= xs[0] { return ys[0] + (x - xs[0]) }
            if x >= xs[xs.count - 1] { return ys[ys.count - 1] + (x - xs[xs.count - 1]) }
            var lo = 0, hi = xs.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if xs[mid] <= x { lo = mid } else { hi = mid }
            }
            let span = xs[hi] - xs[lo]
            return span > 0 ? ys[lo] + (x - xs[lo]) / span * (ys[hi] - ys[lo]) : ys[lo]
        }
    }

    public struct Output: Sendable {
        public let samples: [Float]
        public let timeMap: TimeMap
        /// Any output sample at or beyond full scale.
        public let clipped: Bool
    }

    static let rampSeconds = 0.01
    static let unvoicedSpacing = 0.01
    static let searchShare = 0.2

    /// F0 (Hz) of each 10 ms cell, nil when unvoiced.
    static func f0Cells(_ track: PitchTrack, count: Int) -> [Double?] {
        var cells = [Double?](repeating: nil, count: count)
        guard let median = track.medianF0Hz else { return cells }
        for segment in track.segments {
            let first = Int((segment.start / track.hopSeconds).rounded())
            for (k, frame) in segment.frames.enumerated() where frame.voiced {
                let cell = first + k
                if cell >= 0 && cell < count { cells[cell] = median * exp2(frame.semitones / 12) }
            }
        }
        return cells
    }

    /// Pitch-synchronous analysis marks over the whole take.
    public static func analysisMarks(_ x: [Float], track: PitchTrack, sampleRate: Double) -> [Mark] {
        let hop = track.hopSeconds
        let cellCount = Int((Double(x.count) / sampleRate / hop).rounded(.up)) + 1
        let f0 = f0Cells(track, count: cellCount)
        func f0At(_ n: Int) -> Double? {
            let cell = Int(Double(n) / sampleRate / hop)
            return cell >= 0 && cell < f0.count ? f0[cell] : nil
        }
        func argmax(_ lo: Int, _ hi: Int) -> Int {
            let a = max(0, lo), b = min(x.count - 1, hi)
            guard a <= b else { return min(max(lo, 0), x.count - 1) }
            var best = a
            for i in a...b where x[i] > x[best] { best = i }
            return best
        }
        var marks: [Mark] = []
        var n = 0
        var previousVoiced = false
        let unvoiced = max(1, Int(unvoicedSpacing * sampleRate))
        while n < x.count {
            if let f = f0At(n) {
                let period = sampleRate / f
                let position: Int
                if previousVoiced, let last = marks.last {
                    let predicted = last.position + Int(period.rounded())
                    let reach = Int((searchShare * period).rounded())
                    position = argmax(predicted - reach, predicted + reach)
                } else {
                    position = argmax(n, n + Int(period.rounded()) - 1)
                }
                let next = max(position, (marks.last?.position ?? -1) + 1)
                guard next < x.count else { break }
                marks.append(Mark(position: next, voiced: true))
                previousVoiced = true
                n = next + max(1, Int((period * (1 - searchShare)).rounded()))
            } else {
                let next = max(n, (marks.last?.position ?? -1) + 1)
                guard next < x.count else { break }
                marks.append(Mark(position: next, voiced: false))
                previousVoiced = false
                n = next + unvoiced
            }
        }
        return marks
    }

    /// Resynthesis with `regions` modified; no regions is the identity path.
    public static func process(_ x: [Float], marks: [Mark], regions: [Region], sampleRate: Double) -> Output {
        let duration = Double(x.count) / sampleRate
        let map = TimeMap(regions: regions, duration: duration)
        let outCount = Int((map.forward(duration) * sampleRate).rounded())
        guard marks.count >= 2, outCount > 0 else {
            return Output(samples: x, timeMap: map, clipped: x.contains { abs($0) >= 1 })
        }
        var out = [Double](repeating: 0, count: outCount)
        var weight = [Double](repeating: 0, count: outCount)
        func spacing(_ k: Int) -> (left: Int, right: Int) {
            let left = k > 0 ? marks[k].position - marks[k - 1].position : marks[k + 1].position - marks[k].position
            let right = k + 1 < marks.count ? marks[k + 1].position - marks[k].position : left
            return (max(left, 1), max(right, 1))
        }
        func nearest(_ n: Double) -> Int {
            var lo = 0, hi = marks.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if Double(marks[mid].position) <= n { lo = mid } else { hi = mid }
            }
            return abs(Double(marks[lo].position) - n) <= abs(Double(marks[hi].position) - n) ? lo : hi
        }
        let sorted = regions.sorted { $0.start < $1.start }
        func modifiers(_ t: Double) -> (shift: Double, gain: Double) {
            for region in sorted where t >= region.start && t <= region.end {
                let w = region.weight(at: t)
                return (w * region.shift(at: t), w * region.gainDB)
            }
            return (0, 0)
        }

        var ts = map.forward(Double(marks[0].position) / sampleRate) * sampleRate
        while ts < Double(outCount) {
            let ta = map.inverse(ts / sampleRate)
            let k = nearest(ta * sampleRate)
            let (left, right) = spacing(k)
            let mod = modifiers(ta)
            let factor = marks[k].voiced ? exp2(mod.shift / 12) : 1
            let step = max(1, Double(right) / factor)
            let gain = pow(10, mod.gain / 20)
            let halfLeft = max(left, Int(step.rounded(.up))), halfRight = max(right, Int(step.rounded(.up)))
            let centre = Int(ts.rounded())
            let source = marks[k].position
            for offset in -halfLeft...halfRight {
                let o = centre + offset, s = source + offset
                guard o >= 0, o < outCount, s >= 0, s < x.count else { continue }
                let half = offset < 0 ? Double(halfLeft) : Double(halfRight)
                let w = 0.5 + 0.5 * cos(Double.pi * Double(offset) / max(half, 1))
                out[o] += Double(x[s]) * w * gain
                weight[o] += w
            }
            ts += step
        }
        var samples = [Float](repeating: 0, count: outCount)
        var clipped = false
        for i in 0..<outCount where weight[i] > 1e-3 {
            let v = out[i] / weight[i]
            if abs(v) >= 1 { clipped = true }
            samples[i] = Float(max(-1, min(1, v)))
        }
        return Output(samples: samples, timeMap: map, clipped: clipped)
    }

    /// Share of the voiced 10 ms cells in `range` that have a voiced analysis mark within one period of their
    /// centre (the §1 quality check's pitch-mark coverage); 0 with no voiced cell.
    public static func markCoverage(_ range: ClosedRange<Double>, marks: [Mark], track: PitchTrack,
                                    sampleRate: Double) -> Double {
        let hop = track.hopSeconds
        let f0 = f0Cells(track, count: Int((range.upperBound / hop).rounded(.up)) + 2)
        let voicedMarks = marks.filter(\.voiced).map { Double($0.position) / sampleRate }
        var voiced = 0, covered = 0
        for cell in f0.indices {
            let centre = (Double(cell) + 0.5) * hop
            guard range.contains(centre), let f = f0[cell] else { continue }
            voiced += 1
            let period = 1 / f
            if voicedMarks.contains(where: { abs($0 - centre) <= period }) { covered += 1 }
        }
        return voiced == 0 ? 0 : Double(covered) / Double(voiced)
    }
}
