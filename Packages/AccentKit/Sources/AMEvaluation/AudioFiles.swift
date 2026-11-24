// Reading and writing corpus audio for the harness (tool side only: the app never links AMEvaluation).

import Accelerate
import AVFoundation
import Foundation

public enum AudioFiles {
    public enum Failure: Error, CustomStringConvertible {
        case unreadable(URL)
        case conversion(String)

        public var description: String {
            switch self {
            case .unreadable(let url): "cannot read audio \(url.lastPathComponent)"
            case .conversion(let reason): "audio conversion failed: \(reason)"
            }
        }
    }

    /// Mono float samples (channel 0) and the file's sample rate.
    public static func readMono(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw Failure.unreadable(url)
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw Failure.unreadable(url) }
        return (Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), format.sampleRate)
    }

    /// Downsamples mono `samples` by an integer factor (48 kHz VCTK to 16 kHz) with a Blackman-windowed sinc
    /// low-pass at 0.45 × the target rate, through vDSP. Other ratios are refused rather than approximated.
    public static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) throws -> [Float] {
        if sourceRate == targetRate { return samples }
        let ratio = sourceRate / targetRate
        guard ratio > 1, ratio == ratio.rounded() else { throw Failure.conversion("ratio \(sourceRate)/\(targetRate)") }
        let factor = Int(ratio)
        let taps = 32 * factor + 1
        let cutoff = 0.45 / ratio  // cycles per input sample
        let centre = Double(taps - 1) / 2
        var filter = (0..<taps).map { i -> Float in
            let x = Double(i) - centre
            let sinc = x == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * x) / (.pi * x)
            let window = 0.42 - 0.5 * cos(2 * .pi * Double(i) / Double(taps - 1))
                + 0.08 * cos(4 * .pi * Double(i) / Double(taps - 1))
            return Float(sinc * window)
        }
        let gain = filter.reduce(0, +)
        filter = filter.map { $0 / gain }
        // Pad so the filter is centred on each output sample and the length is preserved.
        let pad = [Float](repeating: 0, count: taps / 2)
        let padded = pad + samples + pad + [Float](repeating: 0, count: factor)
        let outputCount = samples.count / factor
        var output = [Float](repeating: 0, count: outputCount)
        vDSP_desamp(padded, vDSP_Stride(factor), filter, &output, vDSP_Length(outputCount), vDSP_Length(taps))
        return output
    }

    /// Writes mono 16-bit FLAC at `sampleRate`.
    public static func writeFLAC(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
        ]
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { throw Failure.conversion("FLAC buffer") }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }
}
