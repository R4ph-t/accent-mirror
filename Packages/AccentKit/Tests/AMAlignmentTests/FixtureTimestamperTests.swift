import AMAlignment
import Darwin
import Foundation
import Synchronization
import Testing

/// The committed replay set written by `scripts/agreement-record.sh`.
let committedReplay = repoRoot.appending(path: "fixtures/timestamps/openai_whisper-base.en")

/// Writes recordings and their manifest into a fresh folder.
func writeReplay(_ recordings: [RecordedTimestamps], asrModelID: String) throws -> URL {
    let folder = try temporaryFolder()
    let encoder = JSONEncoder()
    var entries: [ReplayManifest.Entry] = []
    for recording in recordings {
        let data = try encoder.encode(recording)
        try data.write(to: folder.appending(path: "\(recording.clipID).json"))
        entries.append(.init(clipID: recording.clipID, file: "\(recording.clipID).json", sha256: Digest.sha256(data)))
    }
    let manifest = ReplayManifest(asrModelID: asrModelID, attribution: "test", clips: entries)
    try encoder.encode(manifest).write(to: folder.appending(path: ReplayManifest.fileName))
    return folder
}

let sampleWords = [
    WordTimestamp(word: " Please", start: 0.24, end: 0.5, probability: 0.97),
    WordTimestamp(word: " call", start: 0.5, end: 0.74, probability: 0.88),
]

@Suite("Fixture replay")
struct FixtureTimestamperTests {
    @Test("Replays the recorded words for a clip, with the recording's model ID")
    func replaysRecordedWords() async throws {
        let folder = try writeReplay(
            [RecordedTimestamps(clipID: "p225_001", audioSHA256: "a", asrModelID: "m@c#12345678", text: "Please call",
                                words: sampleWords)],
            asrModelID: "m@c#12345678")
        defer { try? FileManager.default.removeItem(at: folder) }
        let timestamper = try FixtureTimestamper(directory: folder)
        #expect(timestamper.asrModelID == "m@c#12345678")
        #expect(try await timestamper.wordTimestamps(for: TimestampRequest(clipID: "p225_001", samples: [])) == sampleWords)
    }

    @Test("A clip that was never recorded throws notRecorded")
    func unknownClipThrows() async throws {
        let folder = try writeReplay([], asrModelID: "m@c#12345678")
        defer { try? FileManager.default.removeItem(at: folder) }
        let timestamper = try FixtureTimestamper(directory: folder)
        await #expect(throws: TimestamperError.notRecorded(clipID: "p999_001")) {
            try await timestamper.wordTimestamps(for: TimestampRequest(clipID: "p999_001", samples: []))
        }
    }

    @Test("An edited recording fails its manifest hash")
    func editedRecordingFails() throws {
        let folder = try writeReplay(
            [RecordedTimestamps(clipID: "p225_001", audioSHA256: "a", asrModelID: "m@c#1", text: "", words: sampleWords)],
            asrModelID: "m@c#1")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "p225_001.json")
        let edited = String(decoding: try Data(contentsOf: file), as: UTF8.self).replacingOccurrences(of: "0.24", with: "0.30")
        try Data(edited.utf8).write(to: file)
        #expect(throws: ModelVerificationError.self) { try FixtureTimestamper(directory: folder) }
    }

    @Test("A recording from another model is rejected")
    func otherModelRejected() throws {
        let folder = try writeReplay(
            [RecordedTimestamps(clipID: "p225_001", audioSHA256: "a", asrModelID: "other@c#1", text: "", words: [])],
            asrModelID: "m@c#1")
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(throws: TimestamperError.modelMismatch(expected: "m@c#1", found: "other@c#1")) {
            try FixtureTimestamper(directory: folder)
        }
    }

    @Test("A cancelled request throws CancellationError")
    func cancelledRequestThrows() async throws {
        let folder = try writeReplay(
            [RecordedTimestamps(clipID: "p225_001", audioSHA256: "a", asrModelID: "m@c#1", text: "", words: sampleWords)],
            asrModelID: "m@c#1")
        defer { try? FileManager.default.removeItem(at: folder) }
        let timestamper = try FixtureTimestamper(directory: folder)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await timestamper.wordTimestamps(for: TimestampRequest(clipID: "p225_001", samples: []))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("The committed WhisperKit recordings replay without ASR, matching the pinned model")
    func committedRecordingReplays() async throws {
        let timestamper = try FixtureTimestamper(directory: committedReplay)
        let manifest = try ModelManifest(contentsOf: baseEnManifestURL)
        #expect(timestamper.asrModelID == manifest.asrModelID)
        // One recording per clip the pinned VCTK fetch holds (some specified clips are not in VCTK 0.92).
        let pinnedClips = try String(contentsOf: repoRoot.appending(path: "fixtures/vctk/vctk-0.92-clips.sha256"),
                                     encoding: .utf8).split(separator: "\n").filter { $0.hasSuffix("_mic1.flac") }
        #expect(timestamper.clipIDs.count == pinnedClips.count)
        let words = try await timestamper.wordTimestamps(for: TimestampRequest(clipID: "p225_002", samples: []))
        #expect(!words.isEmpty)
        #expect(words.allSatisfy { $0.start <= $0.end && (0...1).contains($0.probability) })
        #expect(zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start })
    }

    @Test("Replay works with networking denied and opens no socket")
    func replayOpensNoSocket() async throws {
        URLProtocol.registerClass(DenyNetwork.self)
        defer { URLProtocol.unregisterClass(DenyNetwork.self) }
        let before = openSockets()
        let timestamper = try FixtureTimestamper(directory: committedReplay)
        for clipID in timestamper.clipIDs {
            _ = try await timestamper.wordTimestamps(for: TimestampRequest(clipID: clipID, samples: []))
        }
        #expect(DenyNetwork.attempts.withLock { $0 } == 0)
        #expect(openSockets() == before)
    }
}

/// Fails every URL request and counts the attempts.
final class DenyNetwork: URLProtocol {
    static let attempts = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool {
        attempts.withLock { $0 += 1 }
        return true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

/// File descriptors of this process that are sockets.
func openSockets() -> Set<Int32> {
    var sockets: Set<Int32> = []
    for fd in 0..<getdtablesize() {
        var info = stat()
        if fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK { sockets.insert(fd) }
    }
    return sockets
}
