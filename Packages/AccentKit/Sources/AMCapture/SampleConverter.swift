// Any PCM format to the 16 kHz mono Float32 that spec 05's endpointer and take quality read (spec 14). Used by the
// microphone tap and by `FileCaptureSource(contentsOf:)`. A format converter only: no capture API.

@preconcurrency import AVFAudio
import Foundation

/// Converts a stream of PCM buffers to 16 kHz mono Float32. Keeps the first channel of a multi-channel input (an
/// interface's input 1, a stereo file's left channel). Not thread-safe: feed it from one thread at a time.
final class SampleConverter {
    static let outputSampleRate = 16_000.0

    let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from inputFormat: AVAudioFormat) {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Self.outputSampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { return nil }
        converter.channelMap = [0]
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
    }

    /// The samples `buffer` yields so far (the resampler may hold a few back until the next buffer or `finish()`).
    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let input = InputOnce(buffer)
        return drain(capacity: buffer.frameLength) { _, status in
            guard let buffer = input.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return buffer
        }
    }

    /// The samples still held, at the end of the stream.
    func finish() -> [Float] {
        drain(capacity: 0) { _, status in
            status.pointee = .endOfStream
            return nil
        }
    }

    private func drain(capacity inputFrames: AVAudioFrameCount, input: @escaping AVAudioConverterInputBlock) -> [Float] {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(inputFrames) * ratio).rounded(.up)) + 256
        var samples: [Float] = []
        while let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) {
            var error: NSError?
            let status = converter.convert(to: output, error: &error, withInputFrom: input)
            if let channel = output.floatChannelData?[0], output.frameLength > 0 {
                samples += UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
            }
            // A full buffer may mean more is waiting; anything else means this input is used up.
            guard status == .haveData, output.frameLength == output.frameCapacity else { break }
        }
        return samples
    }
}

/// Hands the converter one buffer, once. The converter calls its input block synchronously, on the calling thread.
private final class InputOnce: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
