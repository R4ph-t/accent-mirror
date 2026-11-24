// Decoding an imported file (spec 17): m4a, mp3, wav, aiff, caf, mov or mp4, through AVFoundation, to the 16 kHz mono
// Float32 every take uses. Only the first audio track is read (Open question 1); a video track is ignored. The file
// itself is only read, never modified or copied.

@preconcurrency import AVFoundation
import AMCore
import Foundation

/// The audio of an imported file.
public struct DecodedClip: Sendable, Hashable {
    public static let sampleRate = 16_000.0

    /// 16 kHz mono Float32 (AVFoundation's downmix of the first audio track's channels).
    public let samples: [Float]

    public init(samples: [Float]) { self.samples = samples }

    public var duration: Double { Double(samples.count) / Self.sampleRate }
}

public enum ClipDecoder {
    /// The file extensions the importer accepts (Designer v1 §8).
    public static let fileExtensions: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "mov", "mp4"]

    /// Decodes `url`'s first audio track. A missing file, one with no audio track and one AVFoundation can't read are
    /// one case to the user (Designer v1 §8.2), so they all throw `ClipDecodeError`.
    public static func decode(_ url: URL) async throws(ClipDecodeError) -> DecodedClip {
        let asset = AVURLAsset(url: url)
        let track: AVAssetTrack
        do {
            guard let first = try await asset.loadTracks(withMediaType: .audio).first else { throw ClipDecodeError() }
            track = first
        } catch {
            throw ClipDecodeError()
        }
        do {
            return DecodedClip(samples: try read(asset: asset, track: track))
        } catch {
            throw ClipDecodeError()
        }
    }

    private static func read(asset: AVURLAsset, track: AVAssetTrack) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: DecodedClip.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ClipDecodeError() }
        reader.add(output)
        guard reader.startReading() else { throw ClipDecodeError() }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = chunk.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw ClipDecodeError() }
            samples += chunk
        }
        guard reader.status == .completed, !samples.isEmpty, samples.allSatisfy(\.isFinite) else {
            throw ClipDecodeError()
        }
        return samples
    }
}

/// The file can't be read as audio: `OperationalError.audioUnreadable`.
public struct ClipDecodeError: Error, Sendable, Hashable {
    public init() {}
    public var operational: OperationalError { .audioUnreadable }
}
