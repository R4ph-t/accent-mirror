// pyin-1: our own YIN/pYIN (Mauch & Dixon 2014, stage one) on Accelerate/vDSP. No third-party pitch code.
//
// Per 10 ms cell, a 40 ms window centred on the cell gives YIN's cumulative-mean-normalised difference d'(τ) over
// lags for 60–500 Hz. pYIN's Beta(2, 18) prior over thresholds spreads probability onto the first dip under each
// threshold; the frame's voicing probability is the total, and it is voiced at or above `voicingProbability`. Its F0
// is the most probable dip, refined by parabolic interpolation. `PitchTrack(frameF0Hz:)` then drops short runs,
// median-filters, repairs octave jumps and builds the line. pYIN's HMM stage is not used: the spec's smoothing is the
// median filter and octave repair.

import Accelerate
import Foundation
import AMCore

public struct PYINTracker: PitchTracker {
    public static let trackerID = "pyin-1"

    public var id: String { Self.trackerID }
    public let thresholds: Thresholds.Pitch

    /// Frames between cancellation checks (plan §8.2).
    static let cancellationCheckFrames = 50

    public init(thresholds: Thresholds.Pitch = Thresholds.current.pitch) {
        self.thresholds = thresholds
    }

    public func track(_ samples: [Float], sampleRate: Double) async throws -> PitchTrack {
        try await track(samples, sampleRate: sampleRate, onFrame: { _ in })
    }

    /// `onFrame` sees each frame index before it is analysed (tests count frames analysed after a cancel).
    func track(_ samples: [Float], sampleRate: Double, onFrame: (Int) -> Void) async throws -> PitchTrack {
        var analyser = try FrameAnalyser(sampleRate: sampleRate, thresholds: thresholds)
        let hop = analyser.hopSamples
        let frameCount = samples.count / hop
        var f0: [Double?] = []
        f0.reserveCapacity(frameCount)
        try samples.withUnsafeBufferPointer { audio in
            for i in 0..<frameCount {
                if i.isMultiple(of: Self.cancellationCheckFrames) { try Task.checkCancellation() }
                onFrame(i)
                let estimate = analyser.analyse(audio, centre: i * hop + hop / 2)
                f0.append(estimate.voicingProbability >= thresholds.voicingProbability ? estimate.f0Hz : nil)
            }
        }
        try Task.checkCancellation()
        return PitchTrack(frameF0Hz: f0, thresholds: thresholds)
    }
}

/// One frame's stage-one pYIN result.
struct FrameEstimate: Equatable {
    var f0Hz: Double?
    var voicingProbability: Double

    static let unvoiced = FrameEstimate(f0Hz: nil, voicingProbability: 0)
}

/// YIN/pYIN on one window. Owns its scratch buffers, so one analyser serves one call to `track`.
struct FrameAnalyser {
    /// pYIN's threshold prior: Beta(α, β) over thresholds 0.01…1.00 in steps of 0.01 (Mauch & Dixon 2014).
    static let priorAlpha = 2
    static let priorBeta = 18
    static let thresholdCount = 100
    /// Probability kept for the absolute minimum when no dip is under a threshold (pYIN's p_a).
    static let absoluteMinimumWeight = 0.01
    /// Frames with less energy than this per sample (about −120 dBFS) are unvoiced: numerical guard, not a tunable.
    static let silentEnergyPerSample = 1e-12

    let sampleRate: Double
    let hopSamples: Int
    let windowSamples: Int
    let minLag: Int
    let maxLag: Int
    /// The integration window: `windowSamples − maxLag`, so the largest lag still fits in the window.
    let integrationSamples: Int
    let thresholdWeights: [Double]

    private var frame: [Double]
    private var squares: [Double]
    private var energyPrefix: [Double]
    private var correlation: [Double]
    private var difference: [Double]
    private var normalised: [Double]

    init(sampleRate: Double, thresholds: Thresholds.Pitch) throws {
        guard sampleRate.isFinite, sampleRate > 0,
              thresholds.minF0Hz > 0, thresholds.maxF0Hz > thresholds.minF0Hz,
              Int((sampleRate / thresholds.maxF0Hz).rounded(.down)) >= 2
        else { throw PitchTrackingError.unsupportedSampleRate(sampleRate) }
        self.sampleRate = sampleRate
        hopSamples = max(Int((sampleRate * thresholds.hopMs / 1000).rounded()), 1)
        minLag = Int((sampleRate / thresholds.maxF0Hz).rounded(.down))
        maxLag = Int((sampleRate / thresholds.minF0Hz).rounded(.up))
        // The window must hold the largest lag plus an integration window at least as long as it.
        windowSamples = max(Int((sampleRate * thresholds.windowMs / 1000).rounded()), 2 * maxLag + 2)
        integrationSamples = windowSamples - maxLag - 1
        thresholdWeights = Self.betaWeights()
        frame = Array(repeating: 0, count: windowSamples)
        squares = Array(repeating: 0, count: windowSamples)
        energyPrefix = Array(repeating: 0, count: windowSamples + 1)
        correlation = Array(repeating: 0, count: maxLag + 2)
        difference = Array(repeating: 0, count: maxLag + 2)
        normalised = Array(repeating: 1, count: maxLag + 2)
    }

    /// pYIN's per-threshold weights: Beta(2, 18) mass on each 0.01-wide threshold bin.
    static func betaWeights() -> [Double] {
        // For integer α, β the Beta CDF is a binomial tail: I_x(α, β) = P(Bin(α + β − 1, x) ≥ α).
        let n = priorAlpha + priorBeta - 1
        func cdf(_ x: Double) -> Double {
            var below = 0.0
            var coefficient = 1.0
            for j in 0..<priorAlpha {
                if j > 0 { coefficient *= Double(n - j + 1) / Double(j) }
                below += coefficient * pow(x, Double(j)) * pow(1 - x, Double(n - j))
            }
            return 1 - below
        }
        return (1...thresholdCount).map { k in
            cdf(Double(k) / Double(thresholdCount)) - cdf(Double(k - 1) / Double(thresholdCount))
        }
    }

    /// Analyses the window for the cell centred on sample `centre`. The stretch a lag τ compares is
    /// `[start, start + w + τ)`; the window starts `(w + maxLag/2)/2` before the centre, so that stretch is centred on
    /// the cell for mid-range lags and within ±(maxLag/4) samples of it for any lag. The window is shifted inside the
    /// audio at its ends and zero-padded when the audio is shorter than one window.
    mutating func analyse(_ audio: UnsafeBufferPointer<Float>, centre: Int) -> FrameEstimate {
        let lead = (integrationSamples + maxLag / 2) / 2
        let start = max(0, min(centre - lead, audio.count - windowSamples))
        let available = min(windowSamples, audio.count - start)
        frame.withUnsafeMutableBufferPointer { out in
            vDSP_vspdp(audio.baseAddress! + start, 1, out.baseAddress!, 1, vDSP_Length(available))
            if available < windowSamples { out[available...].update(repeating: 0) }
        }
        return estimate()
    }

    private mutating func estimate() -> FrameEstimate {
        let w = integrationSamples
        let lags = maxLag + 1
        vDSP_vsqD(frame, 1, &squares, 1, vDSP_Length(windowSamples))
        energyPrefix[0] = 0
        for i in 0..<windowSamples { energyPrefix[i + 1] = energyPrefix[i] + squares[i] }
        let total = energyPrefix[windowSamples]
        guard total.isFinite, total > Self.silentEnergyPerSample * Double(windowSamples) else { return .unvoiced }

        // r(τ) = Σ_{j<w} x_j·x_{j+τ}, τ = 0…maxLag+1 (vDSP_convD with a positive stride correlates).
        vDSP_convD(frame, 1, frame, 1, &correlation, 1, vDSP_Length(lags + 1), vDSP_Length(w))
        // d(τ) = e(0) + e(τ) − 2r(τ), with e(τ) = Σ_{j<w} x_{j+τ}².
        let e0 = energyPrefix[w]
        var runningSum = 0.0
        normalised[0] = 1
        for tau in 0...lags {
            let eTau = energyPrefix[tau + w] - energyPrefix[tau]
            let d = max(e0 + eTau - 2 * correlation[tau], 0)
            difference[tau] = d
            guard tau > 0 else { continue }
            runningSum += d
            normalised[tau] = runningSum > 0 ? d * Double(tau) / runningSum : 1
        }

        // Dips of d' in the search range, in lag order.
        var dips: [Int] = []
        var global = minLag
        for tau in minLag...maxLag {
            let value = normalised[tau]
            if value < normalised[global] { global = tau }
            let fallsIn = tau == minLag || value < normalised[tau - 1]
            let risesOut = value <= normalised[tau + 1]
            if fallsIn, risesOut { dips.append(tau) }
        }

        // pYIN stage one: each threshold puts its prior weight on the first dip under it.
        var probability: [Int: Double] = [:]
        for (k, weight) in thresholdWeights.enumerated() {
            let threshold = Double(k + 1) / Double(Self.thresholdCount)
            if let tau = dips.first(where: { normalised[$0] < threshold }) {
                probability[tau, default: 0] += weight
            } else {
                probability[global, default: 0] += weight * Self.absoluteMinimumWeight
            }
        }
        let voicing = probability.values.reduce(0, +)
        guard let best = probability.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })
        else { return .unvoiced }
        let period = refinedLag(best.key)
        guard period > 0, period.isFinite else { return .unvoiced }
        return FrameEstimate(f0Hz: sampleRate / period, voicingProbability: min(voicing, 1))
    }

    /// Parabolic interpolation of d around an integer lag.
    private func refinedLag(_ tau: Int) -> Double {
        guard tau > 1, tau + 1 < difference.count else { return Double(tau) }
        let a = difference[tau - 1], b = difference[tau], c = difference[tau + 1]
        let curvature = a - 2 * b + c
        guard curvature > 0 else { return Double(tau) }
        let shift = 0.5 * (a - c) / curvature
        return Double(tau) + max(-1, min(1, shift))
    }
}
