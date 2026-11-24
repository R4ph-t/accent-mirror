// The take store's files (spec 16, plan §9.2): the manifest, the audio file, and the few file-system primitives the
// store's atomicity rests on: fsync, an exclusive rename, an atomic replace, and the mapping of failures onto
// `StorageError`.

import AMCore
@preconcurrency import AVFAudio
import CryptoKit
import Darwin
import Foundation

/// `manifest.json`: written last into the staging folder, so a take folder without one was never committed.
struct TakeManifest: Codable, Sendable, Equatable {
    static let currentFormat = 1

    /// One stored comparison (L2): the voice and its file.
    struct Comparison: Codable, Sendable, Equatable {
        var voice: RecordingID
        var file: String
    }

    var format: Int
    var phraseID: PhraseID
    var takeID: TakeID
    /// "Take n": counts up per phrase and is never reused, pruned takes included.
    var number: Int
    var recordedAt: Date
    /// SHA-256 of the samples as little-endian Float32 (the take's identity in every cache key).
    var audioSHA256: String
    /// SHA-256 of each file's bytes, by file name.
    var files: [String: String]
    /// The analysis the take was saved with.
    var identity: AnalysisIdentity?
    /// The stored comparisons, most recently used first; at most `TakeStore.comparisonsKept`.
    var comparisons: [Comparison]
    /// Set by spec 17's transcript re-run; unalignable takes still count toward the 10.
    var unalignableReason: String?
}

enum TakeFiles {
    static let audio = "audio.caf"
    static let features = "features.json"
    static let manifest = "manifest.json"
    static let staging = ".staging"
    static let trash = ".trash"
    static let quarantine = ".quarantine"
    static let counter = "take-counter.json"
    static let temporarySuffix = ".tmp"

    static func comparison(_ voice: RecordingID) -> String { "comparison-\(component(voice.rawValue)).json" }

    /// An ID as one safe path component: letters, digits, `-` and `_` kept, everything else percent-encoded (so
    /// `.`, `..` and `/` can't escape the folder, and distinct IDs stay distinct).
    static func component(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
        return encoded.isEmpty ? "%00" : encoded
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    static func sha256(of url: URL) throws -> String { sha256(try Data(contentsOf: url)) }

    /// CryptoKit's SHA-256 (AMCore's plain-Swift one is too slow for audio files).
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Audio

    /// Writes 16 kHz mono Float32 CAF.
    static func writeAudio(_ samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
        else { throw CocoaError(.fileWriteUnknown) }
        let file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        defer { file.close() }
        guard !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else { throw CocoaError(.fileWriteUnknown) }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try file.write(from: buffer)
    }

    static func readAudio(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        defer { file.close() }
        let count = AVAudioFrameCount(file.length)
        guard count > 0 else { return [] }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // One `read(into:)` stops at a 4096-frame boundary, so read until the whole file is in.
        var samples: [Float] = []
        samples.reserveCapacity(Int(count))
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(file.length - file.framePosition))
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            samples += UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        }
        guard samples.count == Int(count) else { throw CocoaError(.fileReadCorruptFile) }
        return samples
    }

    // MARK: Durability

    /// fsync(2) on a file or a folder.
    static func sync(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Writes `data` to `url` and fsyncs it (inside a staging folder, where nothing reads it yet).
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        try sync(url)
    }

    /// One rename(2) that fails if `destination` exists: the commit of a staged take, and a move into the trash.
    static func renameExclusive(_ source: URL, to destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Replaces `url` with `data` atomically: a synced temporary file renamed over it, then the folder synced.
    static func replace(_ url: URL, with data: Data) throws {
        let temporary = url.appendingPathExtension(String(temporarySuffix.dropFirst()))
        try write(data, to: temporary)
        guard rename(temporary.path, url.path) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        try sync(url.deletingLastPathComponent())
    }

    /// A file-system failure as the store reports it.
    static func storageError(_ error: any Error) -> StorageError {
        if let error = error as? StorageError { return error }
        func posix(_ code: Int32) -> StorageError {
            switch code {
            case ENOSPC, EDQUOT: .diskFull
            case EACCES, EPERM, EROFS: .permissionDenied
            default: .ioFailure
            }
        }
        if let error = error as? POSIXError { return posix(error.code.rawValue) }
        let ns = error as NSError
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return posix(Int32(underlying.code))
        }
        if ns.domain == NSPOSIXErrorDomain { return posix(Int32(ns.code)) }
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileWriteOutOfSpaceError: return .diskFull
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError, NSFileWriteVolumeReadOnlyError:
                return .permissionDenied
            default: return .ioFailure
            }
        }
        return .ioFailure
    }
}
