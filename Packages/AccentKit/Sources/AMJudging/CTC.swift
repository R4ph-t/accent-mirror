// CTC in log space over one take's posteriors: the full likelihood of a label sequence, the shared forward/backward
// passes the segmentation-free GOP reuses, and Viterbi forced alignment. Double accumulation; posteriors stay Float.

import Foundation

@inline(__always) func logAdd(_ a: Double, _ b: Double) -> Double {
    if a == -.infinity { return b }
    if b == -.infinity { return a }
    return a > b ? a + log1p(exp(b - a)) : b + log1p(exp(a - b))
}

/// Log-sum-exp of a list (−∞ when empty).
func logSumExp(_ xs: [Double]) -> Double {
    guard let m = xs.max(), m > -.infinity else { return -.infinity }
    var s = 0.0
    for x in xs { s += exp(x - m) }
    return m + log(s)
}

/// Read access to the posteriors: `lp(t, id)`.
struct Emissions {
    let frames: Int
    let vocabularySize: Int
    let values: [Float]
    let blank: Int

    init(_ posteriors: LogPosteriors, blank: Int) {
        frames = posteriors.frames
        vocabularySize = posteriors.vocabularySize
        values = posteriors.values
        self.blank = blank
    }

    @inline(__always) func lp(_ t: Int, _ id: Int) -> Double { Double(values[t * vocabularySize + id]) }

    /// One token's column over all frames.
    func column(_ id: Int) -> [Double] { (0..<frames).map { lp($0, id) } }
}

/// The forward and backward passes over one label sequence's extended states (blank, l1, blank, l2, …, blank).
/// State 2k is a blank, state 2k+1 is label k. `alpha[t * states + s]`, `beta[t * states + s]`.
struct CTCLattice {
    let labels: [Int]
    let frames: Int
    let states: Int
    let alpha: [Double]
    let beta: [Double]
    /// log P(labels | posteriors).
    let logLikelihood: Double

    init(labels: [Int], emissions e: Emissions, blankColumn: [Double]) {
        self.labels = labels
        let T = e.frames
        let S = 2 * labels.count + 1
        frames = T
        states = S
        let z: [Int] = (0..<S).map { (s: Int) -> Int in s % 2 == 0 ? e.blank : labels[s / 2] }
        let emit: [[Double]] = labels.map { e.column($0) }
        @inline(__always) func y(_ t: Int, _ s: Int) -> Double { s % 2 == 0 ? blankColumn[t] : emit[s / 2][t] }
        let skip: [Bool] = (0..<S).map { (s: Int) -> Bool in s % 2 == 1 && s >= 2 && z[s] != z[s - 2] }

        var a = [Double](repeating: -.infinity, count: max(1, T * S))
        if T > 0 {
            a[0] = y(0, 0)
            if S > 1 { a[1] = y(0, 1) }
            for t in 1..<max(1, T) {
                let r = t * S, p = (t - 1) * S
                for s in 0..<S {
                    var v = a[p + s]
                    if s >= 1 { v = logAdd(v, a[p + s - 1]) }
                    if skip[s] { v = logAdd(v, a[p + s - 2]) }
                    a[r + s] = v == -.infinity ? v : v + y(t, s)
                }
            }
        }
        var b = [Double](repeating: -.infinity, count: max(1, T * S))
        if T > 0 {
            let r = (T - 1) * S
            b[r + S - 1] = y(T - 1, S - 1)
            if S > 1 { b[r + S - 2] = y(T - 1, S - 2) }
            var t = T - 2
            while t >= 0 {
                let r = t * S, n = (t + 1) * S
                for s in 0..<S {
                    var v = b[n + s]
                    if s + 1 < S { v = logAdd(v, b[n + s + 1]) }
                    if s + 2 < S, skip[s + 2] { v = logAdd(v, b[n + s + 2]) }
                    b[r + s] = v == -.infinity ? v : v + y(t, s)
                }
                t -= 1
            }
        }
        alpha = a
        beta = b
        if T == 0 {
            logLikelihood = -.infinity
        } else {
            let r = (T - 1) * S
            logLikelihood = S > 1 ? logAdd(a[r + S - 1], a[r + S - 2]) : a[r + S - 1]
        }
    }

    @inline(__always) func alphaAt(_ t: Int, _ s: Int) -> Double { alpha[t * states + s] }
    @inline(__always) func betaAt(_ t: Int, _ s: Int) -> Double { beta[t * states + s] }
}

enum CTC {
    /// log P(labels | posteriors), the full forward pass (`-ctc_loss` in the spike).
    static func logLikelihood(_ labels: [Int], emissions e: Emissions, blankColumn: [Double]) -> Double {
        let T = e.frames
        guard T > 0 else { return -.infinity }
        let S = 2 * labels.count + 1
        let z: [Int] = (0..<S).map { (s: Int) -> Int in s % 2 == 0 ? e.blank : labels[s / 2] }
        var prev = [Double](repeating: -.infinity, count: S)
        var cur = prev
        prev[0] = blankColumn[0]
        if S > 1 { prev[1] = e.lp(0, z[1]) }
        for t in 1..<max(1, T) where T > 1 {
            for s in 0..<S {
                var v = prev[s]
                if s >= 1 { v = logAdd(v, prev[s - 1]) }
                if s % 2 == 1, s >= 2, z[s] != z[s - 2] { v = logAdd(v, prev[s - 2]) }
                cur[s] = v == -.infinity ? v : v + (s % 2 == 0 ? blankColumn[t] : e.lp(t, z[s]))
            }
            swap(&prev, &cur)
        }
        return S > 1 ? logAdd(prev[S - 1], prev[S - 2]) : prev[0]
    }

    /// Viterbi forced alignment of `labels` with blanks (as torchaudio's `forced_align`): for each label, its first
    /// and last frame (inclusive). Nil when the take has too few frames for the sequence.
    static func align(_ labels: [Int], emissions e: Emissions, blankColumn: [Double]) -> [ClosedRange<Int>]? {
        let T = e.frames
        let S = 2 * labels.count + 1
        guard T > 0, !labels.isEmpty else { return labels.isEmpty ? [] : nil }
        let z: [Int] = (0..<S).map { (s: Int) -> Int in s % 2 == 0 ? e.blank : labels[s / 2] }
        @inline(__always) func y(_ t: Int, _ s: Int) -> Double { s % 2 == 0 ? blankColumn[t] : e.lp(t, z[s]) }
        var score = [Double](repeating: -.infinity, count: S)
        var next = score
        var back = [UInt8](repeating: 0, count: T * S)
        score[0] = y(0, 0)
        score[1] = y(0, 1)
        for t in 1..<max(1, T) where T > 1 {
            for s in 0..<S {
                let x0 = score[s]
                let x1 = s >= 1 ? score[s - 1] : -.infinity
                let x2 = s % 2 == 1 && s >= 2 && z[s] != z[s - 2] ? score[s - 2] : -.infinity
                var best = x0, ptr: UInt8 = 0
                if x2 > x1 && x2 > x0 {
                    best = x2; ptr = 2
                } else if x1 > x0 && x1 > x2 {
                    best = x1; ptr = 1
                }
                next[s] = best == -.infinity ? best : best + y(t, s)
                back[t * S + s] = ptr
            }
            swap(&score, &next)
        }
        var s = score[S - 1] > score[S - 2] ? S - 1 : S - 2
        guard score[s] > -.infinity else { return nil }
        var path = [Int](repeating: 0, count: T)
        var t = T - 1
        while t >= 0 {
            path[t] = s
            if t > 0 { s -= Int(back[t * S + s]) }
            t -= 1
        }
        var ranges = [ClosedRange<Int>?](repeating: nil, count: labels.count)
        for (t, s) in path.enumerated() where s % 2 == 1 {
            let k = s / 2
            ranges[k] = ranges[k].map { $0.lowerBound...t } ?? t...t
        }
        let all = ranges.compactMap { $0 }
        return all.count == labels.count ? all : nil
    }
}
