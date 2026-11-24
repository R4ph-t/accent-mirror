// Spec 27 §1 front end: spec 25's nucleus detector at spec 26's frozen values (Thresholds.current: 1.5 dB, 50 ms,
// 9 dB, ±60 ms voicing; report nucleus-count-69675122), and the raw per-nucleus measures the classifier's features
// are made from. Reads the samples and spec 04's pitch track only; no word boundary, speaker id or reference.

import Accelerate
import AMCore
import AMPitch
import AMProsody
import Foundation

/// One nucleus of a take with its raw measures. Every feature is made relative within a word later (`Features`).
public struct MeasuredNucleus: Sendable, Hashable, Codable {
    public let peakTime: Double
    public let regionStart: Double
    public let regionEnd: Double
    /// dB above the higher separating minimum (spec 25 §1): arm B's "most prominent".
    public let prominenceDB: Double
    public let peakDB: Double
    /// d: the nucleus region's length (s).
    public let duration: Double
    /// e: full-band RMS (dBFS) over ±`nucleus.windowMs` around the peak, clamped to the region, floored.
    public let energyDB: Double
    /// Mean F0 (st re the take's median) over the region's voiced frames; nil with none.
    public let f0Semitones: Double?
    /// Lit amendment 2: `f0Semitones` minus the phrase-level fit (a least-squares line over the take's voiced
    /// frames) averaged over the same frames; nil with no voiced frame.
    public let f0Residual: Double?
    /// Lit amendment 2: spectral balance, band energy 100–1,000 Hz minus 1,000–4,000 Hz (dB), Hann window over the
    /// same ± window as e. The same measure for every variant.
    public let tiltDB: Double
}

/// One take through the front end: its nuclei and the voiced frames the phrase metrics read.
public struct MeasuredAudio: Sendable, Hashable, Codable {
    public let duration: Double
    public let nuclei: [MeasuredNucleus]
    /// Centres (s) and semitones (re the take's median) of every voiced pYIN frame, in time order.
    public let voicedTimes: [Double]
    public let voicedSemitones: [Double]
    public let hopSeconds: Double
}

public enum FrontEnd {
    public static let sampleRate = 16_000.0
    /// Lit amendment 2's spectral balance bands (Hz). Fixed before any data.
    public static let tiltLowBand: ClosedRange<Double> = 100...1_000
    public static let tiltHighBand: ClosedRange<Double> = 1_000...4_000

    /// Measures one 16 kHz mono take at the head's (spec 26 frozen) thresholds.
    public static func measure(_ samples: [Float], thresholds: Thresholds = .current) async throws -> MeasuredAudio {
        let track = try await PYINTracker(thresholds: thresholds.pitch).track(samples, sampleRate: sampleRate)
        return measure(samples, track: track, thresholds: thresholds)
    }

    public static func measure(_ samples: [Float], track: PitchTrack, thresholds: Thresholds = .current) -> MeasuredAudio {
        let envelope = NucleusDetector.envelope(samples: samples, sampleRate: sampleRate)
        let voiced = NucleusDetector.voicedCells(track, count: envelope.count)
        let nuclei = NucleusDetector(thresholds: thresholds).detect(envelope: envelope, voiced: voiced)

        var times: [Double] = []
        var semitones: [Double] = []
        for segment in track.segments {
            for (k, frame) in segment.frames.enumerated() where frame.voiced {
                times.append(segment.start + (Double(k) + 0.5) * track.hopSeconds)
                semitones.append(frame.semitones)
            }
        }
        let fit = linearFit(times, semitones)
        let reach = thresholds.nucleus.windowMs / 1000
        let floor = thresholds.prominence.energyMinimumDBFS
        let measured = nuclei.map { nucleus -> MeasuredNucleus in
            let lower = max(nucleus.peakTime - reach, nucleus.region.start)
            let upper = min(nucleus.peakTime + reach, nucleus.region.end)
            let window = sampleRange(lower, upper, count: samples.count)
            var f0: [Double] = []
            var residual: [Double] = []
            for (t, st) in zip(times, semitones) where t >= nucleus.region.start && t <= nucleus.region.end {
                f0.append(st)
                if let fit { residual.append(st - (fit.intercept + fit.slope * t)) }
            }
            return MeasuredNucleus(
                peakTime: nucleus.peakTime, regionStart: nucleus.region.start, regionEnd: nucleus.region.end,
                prominenceDB: nucleus.prominenceDB, peakDB: nucleus.peakDB, duration: nucleus.region.duration,
                energyDB: max(rmsDB(samples, window), floor),
                f0Semitones: f0.isEmpty ? nil : f0.reduce(0, +) / Double(f0.count),
                f0Residual: residual.isEmpty ? nil : residual.reduce(0, +) / Double(residual.count),
                tiltDB: tilt(samples, window))
        }
        return MeasuredAudio(duration: Double(samples.count) / sampleRate, nuclei: measured, voicedTimes: times,
                             voicedSemitones: semitones, hopSeconds: track.hopSeconds)
    }

    static func sampleRange(_ start: Double, _ end: Double, count: Int) -> Range<Int> {
        let a = max(0, min(count, Int((start * sampleRate).rounded())))
        let b = max(a, min(count, Int((end * sampleRate).rounded())))
        return a..<b
    }

    static func rmsDB(_ samples: [Float], _ range: Range<Int>) -> Double {
        guard !range.isEmpty else { return -120 }
        var sum = 0.0
        for i in range { sum += Double(samples[i]) * Double(samples[i]) }
        let ms = sum / Double(range.count)
        return ms > 0 ? max(10 * log10(ms), -120) : -120
    }

    /// Least-squares line of semitones on seconds; nil with fewer than 2 distinct times.
    static func linearFit(_ t: [Double], _ y: [Double]) -> (intercept: Double, slope: Double)? {
        guard t.count >= 2 else { return nil }
        let n = Double(t.count)
        let mt = t.reduce(0, +) / n, my = y.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for (a, b) in zip(t, y) { sxx += (a - mt) * (a - mt); sxy += (a - mt) * (b - my) }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        return (my - slope * mt, slope)
    }

    /// Low band minus high band energy (dB) of the Hann-windowed segment.
    static func tilt(_ samples: [Float], _ range: Range<Int>) -> Double {
        let count = range.count
        guard count >= 16 else { return 0 }
        var log2n = 4
        while (1 << log2n) < max(count, 512) { log2n += 1 }
        let size = 1 << log2n, half = size / 2
        guard let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else { return 0 }
        defer { vDSP_destroy_fftsetup(setup) }
        var frame = [Float](repeating: 0, count: size)
        for k in 0..<count {
            let w = 0.5 - 0.5 * cos(2 * Float.pi * Float(k) / Float(count - 1))
            frame[k] = samples[range.lowerBound + k] * w
        }
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var low = 0.0, high = 0.0
        real.withUnsafeMutableBufferPointer { r in
            imaginary.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2n), FFTDirection(FFT_FORWARD))
                for bin in 1..<half {
                    let f = Double(bin) * sampleRate / Double(size)
                    let p = Double(r[bin]) * Double(r[bin]) + Double(i[bin]) * Double(i[bin])
                    if tiltLowBand.contains(f) { low += p } else if f > tiltHighBand.lowerBound && f <= tiltHighBand.upperBound { high += p }
                }
            }
        }
        return 10 * log10(max(low, 1e-20)) - 10 * log10(max(high, 1e-20))
    }
}
