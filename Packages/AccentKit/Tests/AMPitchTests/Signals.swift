// Synthetic test signals (spec 04 Defaults): generated here, no audio file is committed.

import Foundation
import AMCore
import AMPitch

enum Signals {
    static let sampleRate = 16_000.0

    /// A signal whose instantaneous F0 is `f0(t)`, as a sum of harmonics with amplitudes `harmonics[h-1]`.
    /// `harmonicGain(t, h)` can mute harmonics over time (octave trap).
    static func tone(
        duration: Double, amplitude: Float = 0.5, harmonics: [Double] = [1],
        harmonicGain: (Double, Int) -> Double = { _, _ in 1 }, f0: (Double) -> Double
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        var phase = 0.0
        let norm = harmonics.reduce(0, +)
        return (0..<count).map { n in
            let t = Double(n) / sampleRate
            var value = 0.0
            for (index, gain) in harmonics.enumerated() {
                value += gain * harmonicGain(t, index + 1) * sin(Double(index + 1) * phase)
            }
            phase += 2 * Double.pi * f0(t) / sampleRate
            return Float(value / norm) * amplitude
        }
    }

    static func sine(_ hz: Double, duration: Double) -> [Float] {
        tone(duration: duration) { _ in hz }
    }

    /// A speech-like harmonic complex: 8 harmonics falling off as 1/h.
    static let speechHarmonics: [Double] = (1...8).map { 1 / Double($0) }

    static func complex(_ hz: Double, duration: Double) -> [Float] {
        tone(duration: duration, harmonics: speechHarmonics) { _ in hz }
    }

    /// Exponential glide from `from` to `to` Hz over `duration`.
    static func glideF0(from: Double, to: Double, duration: Double) -> (Double) -> Double {
        { t in from * pow(to / from, min(max(t / duration, 0), 1)) }
    }

    /// Vibrato: `depth` st peak around `centre`, at `rate` Hz.
    static func vibratoF0(centre: Double, depth: Double, rate: Double) -> (Double) -> Double {
        { t in centre * pow(2, depth * sin(2 * Double.pi * rate * t) / 12) }
    }

    static func silence(duration: Double) -> [Float] {
        Array(repeating: 0, count: Int(duration * sampleRate))
    }

    /// Uniform white noise from a fixed seed (SplitMix64), so runs are repeatable.
    static func noise(duration: Double, amplitude: Float = 0.3, seed: UInt64 = 0x5EED) -> [Float] {
        var state = seed
        return (0..<Int(duration * sampleRate)).map { _ in
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return (Float(z >> 40) / Float(1 << 24) * 2 - 1) * amplitude
        }
    }
}

/// A voiced frame read back in Hz, at its cell centre in seconds.
struct VoicedReading {
    let time: Double
    let f0Hz: Double
}

extension PitchTrack {
    /// Every voiced frame, in Hz (medianF0Hz × 2^(st/12)).
    var voicedReadings: [VoicedReading] {
        guard let median = medianF0Hz else { return [] }
        return segments.flatMap { segment in
            segment.frames.enumerated().compactMap { k, frame in
                frame.voiced
                    ? VoicedReading(
                        time: segment.start + (Double(k) + 0.5) * hopSeconds,
                        f0Hz: median * pow(2, frame.semitones / 12))
                    : nil
            }
        }
    }

    var allFrames: [PitchFrame] { segments.flatMap(\.frames) }
}

/// Signed error in semitones.
func semitoneError(_ measured: Double, _ truth: Double) -> Double { 12 * log2(measured / truth) }
