// Our own TD-PSOLA (time-domain pitch-synchronous overlap-add) for the synthetic edited-native negative set: shifts
// F0, stretches duration and changes level inside one region of a take, leaving the rest untouched. Pitch marks come
// from a plain autocorrelation period estimate; unvoiced frames keep a fixed 10 ms hop. Evaluation tooling only.

import AMEvaluation
import Foundation

public enum TDPSOLA {
    /// F0 search range for the period estimate.
    static let minHz = 60.0, maxHz = 400.0

    /// The period in samples around `center`, or nil when the frame is unvoiced (normalised ACF peak below 0.5).
    public static func period(_ samples: [Float], at center: Int, sampleRate: Double) -> Int? {
        let minLag = Int(sampleRate / maxHz), maxLag = Int(sampleRate / minHz)
        let half = maxLag * 2
        let start = max(0, center - half / 2), end = min(samples.count, start + half)
        guard end - start > maxLag * 2 - 1 else { return nil }
        let frame = Array(samples[start..<end])
        let energy = frame.reduce(0) { $0 + Double($1 * $1) }
        guard energy > 1e-8 else { return nil }
        var r = [Double](repeating: 0, count: maxLag + 2)
        for lag in minLag...(maxLag + 1) {
            var sum = 0.0, e1 = 0.0, e2 = 0.0
            for i in 0..<(frame.count - lag) {
                sum += Double(frame[i] * frame[i + lag])
                e1 += Double(frame[i] * frame[i])
                e2 += Double(frame[i + lag] * frame[i + lag])
            }
            r[lag] = sum / max(sqrt(e1 * e2), 1e-12)
        }
        guard let peak = r[minLag...maxLag].max(), peak >= 0.5 else { return nil }
        // The first local maximum close to the best one: avoids picking a multiple of the period (octave error).
        for lag in minLag...maxLag where r[lag] >= 0.9 * peak && r[lag] >= r[max(minLag, lag - 1)] && r[lag] >= r[lag + 1] {
            return lag
        }
        return nil
    }

    /// Median F0 (Hz) over `region`, from 10 ms frames; nil when no frame is voiced.
    public static func medianF0(_ samples: [Float], region: Range<Int>, sampleRate: Double) -> Double? {
        let hop = Int(sampleRate * 0.010)
        let f0s = stride(from: region.lowerBound, to: region.upperBound, by: hop).compactMap {
            period(samples, at: $0, sampleRate: sampleRate).map { sampleRate / Double($0) }
        }.sorted()
        return f0s.isEmpty ? nil : f0s[f0s.count / 2]
    }

    /// `samples` with `region` re-synthesised: F0 × `pitchFactor`, duration × `durationFactor`, level + `gainDB`.
    /// Factors of 1 and 0 dB reproduce the input (the null-processing control).
    public static func modify(
        _ samples: [Float], sampleRate: Double, region: Range<Int>, pitchFactor: Double, durationFactor: Double,
        gainDB: Double
    ) -> [Float] {
        let region = region.clamped(to: 0..<samples.count)
        guard !region.isEmpty, pitchFactor > 0, durationFactor > 0 else { return samples }
        let fallback = Int(sampleRate * 0.010)
        // Analysis marks: one per period through the region (10 ms apart where unvoiced).
        var marks: [(position: Int, period: Int, voiced: Bool)] = []
        var t = region.lowerBound
        while t < region.upperBound {
            let p = period(samples, at: t, sampleRate: sampleRate)
            marks.append((t, p ?? fallback, p != nil))
            t += p ?? fallback
        }
        let outLength = Int((Double(region.count) * durationFactor).rounded())
        var out = [Double](repeating: 0, count: outLength)
        var weight = [Double](repeating: 0, count: outLength)
        let gain = pow(10, gainDB / 20)
        var ts = 0.0
        while Int(ts) < outLength {
            let ta = Double(region.lowerBound) + ts / durationFactor
            let k = marks.indices.min { abs(Double(marks[$0].position) - ta) < abs(Double(marks[$1].position) - ta) }!
            let mark = marks[k]
            let p = mark.period
            for j in -p..<p {
                let source = mark.position + j, target = Int(ts) + j
                guard source >= 0, source < samples.count, target >= 0, target < outLength else { continue }
                let w = 0.5 - 0.5 * cos(Double.pi * Double(j + p) / Double(p))
                out[target] += w * Double(samples[source])
                weight[target] += w
            }
            ts += mark.voiced ? Double(p) / pitchFactor : Double(p)
        }
        var result = Array(samples[..<region.lowerBound])
        for i in 0..<outLength {
            let original = Double(samples[min(samples.count - 1, region.lowerBound + Int(Double(i) / durationFactor))])
            let value = weight[i] > 0.05 ? out[i] / weight[i] : original
            result.append(Float(value * gain))
        }
        result += samples[region.upperBound...]
        return result
    }
}

/// The Rubber Band CLI (GPL-2.0-or-later), the second DSP: run as an external offline tool if it is on PATH, never
/// linked and never installed by this tool.
public struct RubberBandCLI: Sendable {
    public let executable: URL

    /// `rubberband` on PATH, or nil (the second DSP is then NOT EVALUATED).
    public static func locate(path: String? = ProcessInfo.processInfo.environment["PATH"]) -> RubberBandCLI? {
        for dir in (path ?? "").split(separator: ":") {
            let url = URL(fileURLWithPath: String(dir)).appendingPathComponent("rubberband")
            if FileManager.default.isExecutableFile(atPath: url.path) { return RubberBandCLI(executable: url) }
        }
        return nil
    }

    public enum Failure: Error, Equatable { case exit(Int32) }

    /// The arguments for one segment: time ratio and pitch shift in semitones.
    public static func arguments(input: URL, output: URL, semitones: Double, timeRatio: Double) -> [String] {
        ["--quiet", "-t", String(format: "%.4f", timeRatio), "-p", String(format: "%.4f", semitones), input.path, output.path]
    }

    /// `samples` with `region` processed by Rubber Band (pitch, time) and gained; files go to `scratch` only.
    public func modify(
        _ samples: [Float], sampleRate: Double, region: Range<Int>, semitones: Double, timeRatio: Double,
        gainDB: Double, scratch: URL
    ) throws -> [Float] {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let input = scratch.appendingPathComponent("\(UUID().uuidString)-in.wav")
        let output = scratch.appendingPathComponent("\(UUID().uuidString)-out.wav")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        try WAV.write(Array(samples[region]), sampleRate: sampleRate, to: input)
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(input: input, output: output, semitones: semitones, timeRatio: timeRatio)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.exit(process.terminationStatus) }
        let gain = Float(pow(10, gainDB / 20))
        let edited = try WAV.read(output).map { $0 * gain }
        return Array(samples[..<region.lowerBound]) + edited + Array(samples[region.upperBound...])
    }
}

/// 16-bit mono WAV for the Rubber Band round trip.
enum WAV {
    static func write(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate))
        u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767))) }
        try data.write(to: url)
    }

    static func read(_ url: URL) throws -> [Float] {
        let (samples, _) = try AudioFiles.readMono(url)
        return samples
    }
}
