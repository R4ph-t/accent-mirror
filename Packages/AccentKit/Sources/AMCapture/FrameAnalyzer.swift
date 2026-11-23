// Per-frame measurements for endpointing, voicing and take quality (spec 05, plan §10): frame RMS in dBFS, the
// normalised autocorrelation peak over a causal 40 ms window, and whether the frame holds a clip run.

import Accelerate
import AMCore
import Foundation

/// What one 10 ms frame measures.
public struct FrameFeatures: Sendable, Hashable {
    /// RMS of the frame's own samples, as 20·log10(rms) (a full-scale square wave is 0 dBFS). Silence reads −120.
    public let rmsDBFS: Double
    /// Highest local maximum of the normalised autocorrelation in the pitch lag range, over the window that ends
    /// with this frame. 0 until a full window has been heard.
    public let acfPeak: Double
    /// The frame completes or continues a run of `clipRunSamples` samples at or above `clipLevel`.
    public let clipped: Bool
}

/// Streams samples one hop at a time and measures each frame. A value type: copy it to fork the stream.
struct FrameAnalyzer: Sendable {
    let hop: Int
    let window: Int
    private let minLag: Int
    private let maxLag: Int
    private let clipLevel: Float
    private let clipRun: Int
    /// The last `window` samples heard, oldest first.
    private var history: [Float]
    private var heard = 0
    private var clipRunLength = 0

    init(sampleRate: Double, thresholds: Thresholds) {
        let perMs = sampleRate / 1000
        hop = max(1, Int((thresholds.voicing.hopMs * perMs).rounded()))
        window = max(hop, Int((thresholds.voicing.windowMs * perMs).rounded()))
        minLag = max(1, Int((thresholds.voicing.minLagMs * perMs).rounded()))
        // One lag of headroom on each side so the ends of the range can be tested as local maxima.
        maxLag = min(window - 2, Int((thresholds.voicing.maxLagMs * perMs).rounded()))
        clipLevel = Float(thresholds.capture.clipLevel)
        clipRun = max(1, Int(thresholds.capture.clipRunSamples))
        history = [Float](repeating: 0, count: window)
    }

    /// Measures the next frame. `frame` must hold exactly `hop` samples.
    mutating func analyse(_ frame: [Float]) -> FrameFeatures {
        precondition(frame.count == hop, "FrameAnalyzer takes one \(hop)-sample frame at a time")
        history.removeFirst(hop)
        history.append(contentsOf: frame)
        heard += hop

        let rms = Double(vDSP.rootMeanSquare(frame))
        let rmsDBFS = 20 * log10(max(rms, 1e-6))

        var clipped = false
        for sample in frame {
            clipRunLength = abs(sample) >= clipLevel ? clipRunLength + 1 : 0
            if clipRunLength >= clipRun { clipped = true }
        }

        let peak = heard >= window ? Self.acfPeak(history, minLag: minLag, maxLag: maxLag) : 0
        return FrameFeatures(rmsDBFS: rmsDBFS, acfPeak: peak, clipped: clipped)
    }

    /// The highest local maximum of r(τ) for τ in `minLag...maxLag`, where r is the normalised cross-correlation of
    /// the mean-removed window with itself shifted by τ (1 for a perfectly periodic window). A monotonic decay, as
    /// pink or low-passed noise gives, has no local maximum in range and scores 0.
    static func acfPeak(_ samples: [Float], minLag: Int, maxLag: Int) -> Double {
        let count = samples.count
        guard minLag >= 1, maxLag + 1 < count, minLag <= maxLag else { return 0 }
        let centred = vDSP.add(-vDSP.mean(samples), samples)
        // energy[k] = sum of squares of centred[0..<k].
        var energy = [Double](repeating: 0, count: count + 1)
        for index in 0..<count { energy[index + 1] = energy[index] + Double(centred[index] * centred[index]) }

        return centred.withUnsafeBufferPointer { buffer -> Double in
            let base = buffer.baseAddress!
            func r(_ lag: Int) -> Double {
                let length = count - lag
                var dot: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &dot, vDSP_Length(length))
                let head = energy[length] - energy[0]
                let tail = energy[count] - energy[lag]
                let denominator = (head * tail).squareRoot()
                return denominator > 0 ? Double(dot) / denominator : 0
            }
            var best = 0.0
            var previous = r(minLag - 1)
            var current = r(minLag)
            for lag in minLag...maxLag {
                let next = r(lag + 1)
                if current >= previous, current >= next { best = max(best, current) }
                previous = current
                current = next
            }
            return best
        }
    }
}

/// The p-th percentile (0–100) of `values`, linearly interpolated between order statistics. `values` is non-empty.
func percentile(_ p: Double, of values: [Double]) -> Double {
    precondition(!values.isEmpty)
    let sorted = values.sorted()
    let position = min(max(p, 0), 100) / 100 * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = min(lower + 1, sorted.count - 1)
    let fraction = position - Double(lower)
    return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
}
