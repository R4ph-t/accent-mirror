// DTW inside a mapped segment whose anchors are Poor (plan §4.4, §8.2). Features are 13 MFCCs plus log-energy on
// 25 ms windows every 10 ms, through Accelerate. DTW maps time for the pitch overlay and the playhead only: it never
// changes syllable boundaries, durations, stress or any confidence, and it caps the take's timing at Rough.

import Accelerate
import Foundation
import AMCore

/// Per-frame acoustic features of one take: frame `i` is the window starting at `i × hopSeconds`.
public struct FrameFeatures: Sendable, Hashable {
    public static let coefficientCount = 13
    public static let windowSeconds = 0.025
    public static let hopSeconds = 0.010
    static let melFilterCount = 26
    static let preEmphasis: Float = 0.97

    /// 13 MFCCs then log-energy per frame, each dimension mean-normalised over the take.
    public let frames: [[Float]]
    public let hopSeconds: Double
    public let windowSeconds: Double

    /// The centre of frame `i` in seconds.
    public func time(ofFrame i: Int) -> Double { Double(i) * hopSeconds + windowSeconds / 2 }

    /// Features of mono `samples` at `sampleRate` Hz.
    public init(samples: [Float], sampleRate: Double) {
        hopSeconds = Self.hopSeconds
        windowSeconds = Self.windowSeconds
        let length = Int((Self.windowSeconds * sampleRate).rounded())
        let hop = Int((Self.hopSeconds * sampleRate).rounded())
        guard sampleRate > 0, length > 1, hop > 0, samples.count >= length else {
            frames = []
            return
        }
        let fftSize = 1 << Int(ceil(log2(Double(length))))
        let bins = fftSize / 2 + 1
        let mels = Self.melFilterCount
        let coefficients = Self.coefficientCount
        guard let dft = try? vDSP.DiscreteFourierTransform(
            previous: nil, count: fftSize, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        else {
            frames = []
            return
        }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hamming, count: length, isHalfWindow: false)
        // Filters as a bins × mels matrix and the DCT as a mels × coefficients matrix, row-major.
        let filters = Self.melFilters(bins: bins, fftSize: fftSize, sampleRate: sampleRate)
        let filtersT = (0..<bins).flatMap { b in (0..<mels).map { filters[$0][b] } }
        let dct = Self.dctMatrix(rows: coefficients, columns: mels)
        let dctT = (0..<mels).flatMap { n in (0..<coefficients).map { dct[$0][n] } }
        let emphasised = vDSP.add(multiplication: ([0] + samples.dropLast(), -Self.preEmphasis), samples)
        let zeros = [Float](repeating: 0, count: fftSize)

        let count = 1 + (samples.count - length) / hop
        var power = [Float](repeating: 0, count: count * bins)
        var energy = [Float](repeating: 0, count: count)
        var buffer = [Float](repeating: 0, count: fftSize)
        var re = [Float](repeating: 0, count: fftSize)
        var im = [Float](repeating: 0, count: fftSize)
        for f in 0..<count {
            let start = f * hop
            energy[f] = log(max(vDSP.sumOfSquares(samples[start..<(start + length)]), 1e-10))
            buffer.withUnsafeMutableBufferPointer { out in
                vDSP.multiply(emphasised[start..<(start + length)], window, result: &out[0..<length])
            }
            dft.transform(inputReal: buffer, inputImaginary: zeros, outputReal: &re, outputImaginary: &im)
            power.withUnsafeMutableBufferPointer { out in
                var row = out[(f * bins)..<((f + 1) * bins)]
                vDSP.multiply(re[0..<bins], re[0..<bins], result: &row)
                vDSP.add(multiplication: (im[0..<bins], im[0..<bins]), row, result: &row)
            }
        }
        var mel = [Float](repeating: 0, count: count * mels)
        vDSP_mmul(power, 1, filtersT, 1, &mel, 1, vDSP_Length(count), vDSP_Length(mels), vDSP_Length(bins))
        mel = vForce.log(vDSP.threshold(mel, to: 1e-10, with: .clampToThreshold))
        var cepstra = [Float](repeating: 0, count: count * coefficients)
        vDSP_mmul(mel, 1, dctT, 1, &cepstra, 1, vDSP_Length(count), vDSP_Length(coefficients), vDSP_Length(mels))

        var out = (0..<count).map { f in Array(cepstra[(f * coefficients)..<((f + 1) * coefficients)]) + [energy[f]] }
        // Mean normalisation per dimension, so two takes recorded differently still compare.
        for d in 0...coefficients {
            let mean = out.reduce(Float(0)) { $0 + $1[d] } / Float(count)
            for i in out.indices { out[i][d] -= mean }
        }
        frames = out
    }

    /// Triangular HTK mel filters over the power-spectrum bins, 0 Hz to Nyquist.
    static func melFilters(bins: Int, fftSize: Int, sampleRate: Double) -> [[Float]] {
        func mel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
        func hz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }
        let top = mel(sampleRate / 2)
        let edges = (0...(melFilterCount + 1)).map { hz(top * Double($0) / Double(melFilterCount + 1)) }
        let binHz = sampleRate / Double(fftSize)
        return (1...melFilterCount).map { m in
            (0..<bins).map { b in
                let f = Double(b) * binHz
                let (lo, mid, hi) = (edges[m - 1], edges[m], edges[m + 1])
                if f <= lo || f >= hi { return 0 }
                return Float(f <= mid ? (f - lo) / (mid - lo) : (hi - f) / (hi - mid))
            }
        }
    }

    /// DCT-II rows (orthonormal scaling).
    static func dctMatrix(rows: Int, columns: Int) -> [[Float]] {
        (0..<rows).map { k in
            let scale = sqrt((k == 0 ? 1.0 : 2.0) / Double(columns))
            return (0..<columns).map { n in
                Float(scale * cos(Double.pi * Double(k) * (Double(n) + 0.5) / Double(columns)))
            }
        }
    }
}

/// Dynamic time warping between two feature sequences, start to start and end to end.
public enum DTW {
    /// `Task.isCancelled` is checked every this many rows (§8.2).
    public static let cancellationCheckRows = 100

    /// The optimal path as (row in `a`, column in `b`) pairs from (0, 0) to the last cell, with unit steps
    /// (diagonal, down, right) and Euclidean frame distance. Throws `CancellationError` when the task is cancelled;
    /// returns no partial path.
    public static func path(_ a: [[Float]], _ b: [[Float]]) throws -> [(Int, Int)] {
        let n = a.count
        let m = b.count
        guard n > 0, m > 0 else { return [] }
        let dims = a[0].count
        // Squared distances as |a|² + |b|² − 2 a·b, from one matrix product.
        let flatA = a.flatMap { $0 }
        let flatB = b.flatMap { $0 }
        var bT = [Float](repeating: 0, count: m * dims)
        vDSP_mtrans(flatB, 1, &bT, 1, vDSP_Length(dims), vDSP_Length(m))
        var dot = [Float](repeating: 0, count: n * m)
        vDSP_mmul(flatA, 1, bT, 1, &dot, 1, vDSP_Length(n), vDSP_Length(m), vDSP_Length(dims))
        let normA = a.map { vDSP.sumOfSquares($0) }
        let normB = b.map { vDSP.sumOfSquares($0) }

        let width = m + 1
        var cost = [Float](repeating: .infinity, count: (n + 1) * width)
        cost[0] = 0
        try cost.withUnsafeMutableBufferPointer { c in
            try dot.withUnsafeBufferPointer { g in
                for i in 1...n {
                    if (i - 1) % cancellationCheckRows == 0 { try Task.checkCancellation() }
                    let na = normA[i - 1]
                    for j in 1...m {
                        let d = max(na + normB[j - 1] - 2 * g[(i - 1) * m + j - 1], 0).squareRoot()
                        c[i * width + j] = d + min(c[(i - 1) * width + j - 1], c[(i - 1) * width + j], c[i * width + j - 1])
                    }
                }
            }
        }
        var path: [(Int, Int)] = [(n - 1, m - 1)]
        var i = n
        var j = m
        while i > 1 || j > 1 {
            let diagonal = i > 1 && j > 1 ? cost[(i - 1) * width + j - 1] : .infinity
            let up = i > 1 ? cost[(i - 1) * width + j] : .infinity
            let left = j > 1 ? cost[i * width + j - 1] : .infinity
            if diagonal <= up && diagonal <= left {
                i -= 1
                j -= 1
            } else if up <= left {
                i -= 1
            } else {
                j -= 1
            }
            path.append((i - 1, j - 1))
        }
        return path.reversed()
    }
}

extension TimeWarp {
    /// DTW inside every mapped segment whose anchors are Poor, from the two takes' features. Only the time lookups
    /// change: the map, its anchors, the comparable coverage and every confidence are kept, and the take timing is
    /// capped at Rough when any segment was refined. Throws `CancellationError` when the task is cancelled.
    public func refined(model: FrameFeatures, you: FrameFeatures) throws -> TimeWarp {
        var refinements = self.refinements
        for (i, segment) in map.segments.enumerated() {
            guard anchorTiming[i] == .poor, case .mapped(let modelRange, let yourRange, _, _) = segment else { continue }
            let mi = Self.frames(of: model, inside: modelRange)
            let yi = Self.frames(of: you, inside: yourRange)
            guard mi.count >= 2, yi.count >= 2 else { continue }
            let path = try DTW.path(mi.map { model.frames[$0] }, yi.map { you.frames[$0] })
            var knots: [PartialTimeMap.Anchor] = []
            for (r, c) in path {
                let knot = PartialTimeMap.Anchor(model: model.time(ofFrame: mi[r]), you: you.time(ofFrame: yi[c]))
                if let last = knots.last, !(knot.model > last.model && knot.you > last.you) { continue }
                knots.append(knot)
            }
            refinements[i] = knots
        }
        let refinedAny = refinements.count > self.refinements.count
        return TimeWarp(
            map: map, modelWords: modelWords, comparableCoverage: comparableCoverage, anchorTiming: anchorTiming,
            refinements: refinements, timing: refinedAny && timing == .good ? .rough : timing)
    }

    /// Indices of the frames whose centre lies in `range`.
    static func frames(of features: FrameFeatures, inside range: TimeRange) -> [Int] {
        features.frames.indices.filter { range.contains(features.time(ofFrame: $0)) }
    }
}
