// Synthetic test signals for spec 05: speech-like voiced bursts (a harmonic complex with syllable-rate amplitude
// modulation) over controlled noise. Deterministic: every generator takes a seed.

import Foundation

enum Synth {
    static let sampleRate = 16_000.0

    static func samples(_ seconds: Double) -> Int { Int((seconds * sampleRate).rounded()) }

    static func amplitude(dBFS: Double) -> Double { pow(10, dBFS / 20) }

    /// SplitMix64, so the noise is the same on every run and every machine.
    struct Random {
        var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }

        /// Standard normal, by Box–Muller.
        mutating func gaussian() -> Double {
            let u = max(uniform(), 1e-12)
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * uniform())
        }
    }

    /// White Gaussian noise with RMS at `dBFS`.
    static func whiteNoise(seconds: Double, dBFS: Double, seed: UInt64) -> [Float] {
        var random = Random(seed: seed)
        let scale = amplitude(dBFS: dBFS)
        return (0..<samples(seconds)).map { _ in Float(random.gaussian() * scale) }
    }

    /// Pink noise (Paul Kellet's filter on white noise), scaled so its overall RMS is at `dBFS`.
    static func pinkNoise(seconds: Double, dBFS: Double, seed: UInt64) -> [Float] {
        var random = Random(seed: seed)
        var b = [Double](repeating: 0, count: 7)
        var raw: [Double] = []
        raw.reserveCapacity(samples(seconds))
        for _ in 0..<samples(seconds) {
            let white = random.gaussian()
            b[0] = 0.99886 * b[0] + white * 0.0555179
            b[1] = 0.99332 * b[1] + white * 0.0750759
            b[2] = 0.96900 * b[2] + white * 0.1538520
            b[3] = 0.86650 * b[3] + white * 0.3104856
            b[4] = 0.55000 * b[4] + white * 0.5329522
            b[5] = -0.7616 * b[5] - white * 0.0168980
            raw.append(b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + white * 0.5362)
            b[6] = white * 0.115926
        }
        let rms = (raw.reduce(0) { $0 + $1 * $1 } / Double(raw.count)).squareRoot()
        let scale = amplitude(dBFS: dBFS) / rms
        return raw.map { Float($0 * scale) }
    }

    /// A speech-like voiced burst: harmonics of `f0` (gliding slightly) up to 4 kHz at 1/k, under a syllable-rate
    /// envelope that swings `depthDB` below `peakDBFS` (the frame RMS at the envelope's peak). The envelope starts
    /// and ends at its peak, with 5 ms raised-cosine edges, so detected start and end sit on the true ones.
    static func speech(
        seconds: Double, peakDBFS: Double, depthDB: Double = 12, syllableRateHz: Double = 4, f0: Double = 140
    ) -> [Float] {
        let count = samples(seconds)
        let harmonics = Array(1...max(1, Int(4000 / (f0 * 1.1))))
        let complexRMS = (harmonics.reduce(0.0) { $0 + 1 / Double($1 * $1) } / 2).squareRoot()
        let scale = amplitude(dBFS: peakDBFS) / complexRMS
        let edge = samples(0.005)
        var phase = 0.0
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            let frequency = f0 * (1 + 0.05 * sin(2 * .pi * 0.7 * t))
            phase += 2 * .pi * frequency / sampleRate
            let carrier = harmonics.reduce(0.0) { $0 + sin(Double($1) * phase) / Double($1) }
            let envelopeDB = -depthDB * (1 - cos(2 * .pi * syllableRateHz * t)) / 2
            var gain = amplitude(dBFS: envelopeDB)
            let fromEdge = min(index, count - 1 - index)
            if fromEdge < edge { gain *= 0.5 - 0.5 * cos(.pi * Double(fromEdge) / Double(edge)) }
            return Float(scale * gain * carrier)
        }
    }

    /// A steady mains-style hum: 120 Hz with harmonics at 1, 1/2 and 1/4, RMS at `dBFS`.
    static func hum(seconds: Double, dBFS: Double) -> [Float] {
        let weights = [1.0, 0.5, 0.25]
        let rms = (weights.reduce(0) { $0 + $1 * $1 } / 2).squareRoot()
        let scale = amplitude(dBFS: dBFS) / rms
        return (0..<samples(seconds)).map { index in
            let t = Double(index) / sampleRate
            let value = weights.enumerated().reduce(0.0) {
                $0 + $1.element * sin(2 * .pi * 120 * Double($1.offset + 1) * t)
            }
            return Float(scale * value)
        }
    }

    /// `base` with `overlay` added from `start` seconds on (extending `base` with silence if needed).
    static func mix(_ base: [Float], _ overlay: [Float], at start: Double) -> [Float] {
        let offset = samples(start)
        var result = base
        if result.count < offset + overlay.count {
            result += [Float](repeating: 0, count: offset + overlay.count - result.count)
        }
        for (index, sample) in overlay.enumerated() { result[offset + index] += sample }
        return result
    }

    /// Hard clipping at ±1 after a gain, as an overdriven input would.
    static func clip(_ signal: [Float], gainDB: Double) -> [Float] {
        let gain = Float(amplitude(dBFS: gainDB))
        return signal.map { min(max($0 * gain, -1), 1) }
    }
}
