import AVFoundation
import CoreMedia
import CoreVideo

/// Test-only encoder: turns synthetic PCM into real compressed clips, so import tests go through
/// AVFoundation's AAC decode path instead of a WAV shortcut.
enum ClipEncoding {
    enum Container { case m4a, mp4WithVideo }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Encodes 16 kHz mono Float32 samples as 44.1 kHz mono AAC (~128 kbps) into `url`.
    /// `.m4a` is audio only. `.mp4WithVideo` puts a tiny H.264 track first and the AAC track second,
    /// so a decoder has to pick the audio track rather than track 0.
    static func write(
        _ samples: [Float], sampleRate: Double = 16_000, to url: URL, as container: Container
    ) async throws {
        // AVAssetWriter refuses to overwrite an existing file.
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: container == .m4a ? .m4a : .mp4)

        // Added before audio so it becomes the first track.
        var video: (input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor)?
        if container == .mp4WithVideo {
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoSide,
                AVVideoHeightKey: videoSide,
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: videoSide,
                kCVPixelBufferHeightKey as String: videoSide,
            ])
            guard writer.canAdd(input) else { throw Failure(description: "cannot add video input") }
            writer.add(input)
            video = (input, adaptor)
        }

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ])
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else { throw Failure(description: "cannot add audio input") }
        writer.add(audioInput)

        guard writer.startWriting() else { throw failure("startWriting failed", writer) }
        writer.startSession(atSourceTime: .zero)

        let format = try pcmFormat(sampleRate: sampleRate)
        let timescale = CMTimeScale(sampleRate.rounded())
        let duration = CMTime(value: CMTimeValue(samples.count), timescale: timescale)
        let frameTimes = videoFrameTimes(spanning: duration)

        // One loop feeds both inputs: the writer interleaves tracks, so draining one input
        // before the other can stall it.
        var audioOffset = 0
        var frameIndex = 0
        var audioDone = false
        var videoDone = video == nil
        while !(audioDone && videoDone) {
            var progressed = false
            if !audioDone, audioInput.isReadyForMoreMediaData {
                if audioOffset < samples.count {
                    let count = min(chunkFrames, samples.count - audioOffset)
                    let buffer = try pcmBuffer(
                        samples[audioOffset..<(audioOffset + count)], at: audioOffset, timescale: timescale,
                        format: format)
                    guard audioInput.append(buffer) else { throw failure("audio append failed", writer) }
                    audioOffset += count
                } else {
                    audioInput.markAsFinished()
                    audioDone = true
                }
                progressed = true
            }
            if let video, !videoDone, video.input.isReadyForMoreMediaData {
                if frameIndex < frameTimes.count {
                    let frame = try solidFrame(from: video.adaptor, shade: UInt8(truncatingIfNeeded: 40 + frameIndex * 20))
                    guard video.adaptor.append(frame, withPresentationTime: frameTimes[frameIndex]) else {
                        throw failure("video append failed", writer)
                    }
                    frameIndex += 1
                } else {
                    video.input.markAsFinished()
                    videoDone = true
                }
                progressed = true
            }
            if writer.status == .failed { throw failure("writer failed", writer) }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }

        // Pins the file's duration to the audio, not to the last video frame.
        if samples.count > 0 { writer.endSession(atSourceTime: duration) }
        await writer.finishWriting()
        guard writer.status == .completed else { throw failure("finishWriting did not complete", writer) }
    }

    private static let videoSide = 64
    private static let chunkFrames = 4_096
    private static let framesPerSecond: Int32 = 5

    private static func failure(_ what: String, _ writer: AVAssetWriter) -> Failure {
        Failure(description: "\(what) (status \(writer.status.rawValue)): \(String(describing: writer.error))")
    }

    private static func pcmFormat(sampleRate: Double) throws -> CMAudioFormatDescription {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1,
            mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
            magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard status == noErr, let format else { throw Failure(description: "PCM format: OSStatus \(status)") }
        return format
    }

    private static func pcmBuffer(
        _ chunk: ArraySlice<Float>, at start: Int, timescale: CMTimeScale, format: CMAudioFormatDescription
    ) throws -> CMSampleBuffer {
        let byteCount = chunk.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard status == noErr, let block else { throw Failure(description: "block buffer: OSStatus \(status)") }
        status = chunk.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard status == noErr else { throw Failure(description: "copy PCM: OSStatus \(status)") }
        var buffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: chunk.count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: timescale),
            packetDescriptions: nil, sampleBufferOut: &buffer)
        guard status == noErr, let buffer else { throw Failure(description: "sample buffer: OSStatus \(status)") }
        return buffer
    }

    /// A few frames at 5 fps from zero up to (not past) the audio's end; always at least one.
    private static func videoFrameTimes(spanning duration: CMTime) -> [CMTime] {
        let count = max(1, Int((duration.seconds * Double(framesPerSecond)).rounded(.up)))
        return (0..<count).map { CMTime(value: CMTimeValue($0), timescale: framesPerSecond) }
    }

    private static func solidFrame(from adaptor: AVAssetWriterInputPixelBufferAdaptor, shade: UInt8) throws
        -> CVPixelBuffer
    {
        // The pool exists only after startWriting, which has run by now.
        guard let pool = adaptor.pixelBufferPool else { throw Failure(description: "no pixel buffer pool") }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw Failure(description: "pixel buffer: CVReturn \(status)")
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            // Same byte in B, G, R and A: an opaque-enough grey, which is all the test needs.
            memset(base, Int32(shade), CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer))
        }
        return pixelBuffer
    }
}
