import Foundation

/// One clip's recorded word timings, as `am-timestamps record` writes them (spec 03 `agreement-record`).
public struct RecordedTimestamps: Codable, Sendable, Equatable {
    public var formatVersion: Int
    public var clipID: String
    /// SHA-256 of the source audio file the words were recognised from.
    public var audioSHA256: String
    public var asrModelID: String
    /// The full recognised text.
    public var text: String
    public var words: [WordTimestamp]

    public init(clipID: String, audioSHA256: String, asrModelID: String, text: String, words: [WordTimestamp]) {
        self.formatVersion = 1
        self.clipID = clipID
        self.audioSHA256 = audioSHA256
        self.asrModelID = asrModelID
        self.text = text
        self.words = words
    }
}

/// The index of a folder of recordings (`manifest.json`). `recordingsSHA256` is `Digest.listing` over the files.
public struct ReplayManifest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var clipID: String
        public var file: String
        public var sha256: String

        public init(clipID: String, file: String, sha256: String) {
            self.clipID = clipID
            self.file = file
            self.sha256 = sha256
        }
    }

    public var formatVersion: Int
    public var asrModelID: String
    public var recordingsSHA256: String
    /// Where the source audio came from and its licence (VCTK 0.92 is CC BY 4.0).
    public var attribution: String
    public var clips: [Entry]

    public init(asrModelID: String, attribution: String, clips: [Entry]) {
        self.formatVersion = 1
        self.asrModelID = asrModelID
        self.recordingsSHA256 = Digest.listing(clips.map { ($0.file, $0.sha256) })
        self.attribution = attribution
        self.clips = clips
    }

    public static let fileName = "manifest.json"
}

/// Replays recorded word timings. Reads only local files: no ASR, no network.
public struct FixtureTimestamper: WordTimestamper {
    public let asrModelID: String
    private let recordings: [String: RecordedTimestamps]

    /// Loads every recording listed in `directory/manifest.json`, checking each file's SHA-256, the manifest's
    /// `recordingsSHA256`, and that every recording names the manifest's model.
    public init(directory: URL) throws {
        let manifest = try JSONDecoder().decode(
            ReplayManifest.self, from: Data(contentsOf: directory.appending(path: ReplayManifest.fileName)))
        let listed = Digest.listing(manifest.clips.map { ($0.file, $0.sha256) })
        guard listed == manifest.recordingsSHA256 else {
            throw ModelVerificationError.manifestInconsistent(computed: listed, recorded: manifest.recordingsSHA256)
        }
        var recordings: [String: RecordedTimestamps] = [:]
        for entry in manifest.clips {
            let data = try Data(contentsOf: directory.appending(path: entry.file))
            let actual = Digest.sha256(data)
            guard actual == entry.sha256 else {
                throw ModelVerificationError.mismatch(path: entry.file, expected: entry.sha256, actual: actual)
            }
            let recording = try JSONDecoder().decode(RecordedTimestamps.self, from: data)
            guard recording.asrModelID == manifest.asrModelID else {
                throw TimestamperError.modelMismatch(expected: manifest.asrModelID, found: recording.asrModelID)
            }
            recordings[entry.clipID] = recording
        }
        self.asrModelID = manifest.asrModelID
        self.recordings = recordings
    }

    public var clipIDs: [String] { recordings.keys.sorted() }

    public func recording(for clipID: String) -> RecordedTimestamps? { recordings[clipID] }

    public func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] {
        try Task.checkCancellation()
        guard let recording = recordings[request.clipID] else {
            throw TimestamperError.notRecorded(clipID: request.clipID)
        }
        return recording.words
    }
}
