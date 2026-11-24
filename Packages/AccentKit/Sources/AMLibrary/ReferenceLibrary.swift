// The bundled reference library (spec 15, plan §9.2): the starter phrases' native recordings and their precomputed
// L0/L1 analyses, read from the app bundle. The bundle is read-only. When a bundled analysis was computed for another
// identity than the running code's (a `featureVersion` or `algorithmVersion` bump, say), the library rebuilds it from
// the bundled audio and word timings into `Caches/` through a rebuilder `AMPipeline` injects, and uses that. A corrupt
// cache is rebuilt once; a second failure is `referenceCacheCorrupt` (`loadNatives`).

import AMCore
import Foundation

/// What a rebuild reads: one recording's bundled files and its phrase.
public struct StarterRecordingSource: Sendable, Hashable {
    public let phrase: StarterManifest.Phrase
    public let recording: StarterManifest.Recording
    /// The bundled trimmed audio (FLAC, source rate).
    public let audio: URL
    /// The bundled word timings for that audio.
    public let timings: URL
    /// The recogniser the timings were recorded with.
    public let asrModelID: String

    public init(
        phrase: StarterManifest.Phrase, recording: StarterManifest.Recording, audio: URL, timings: URL,
        asrModelID: String
    ) {
        self.phrase = phrase
        self.recording = recording
        self.audio = audio
        self.timings = timings
        self.asrModelID = asrModelID
    }
}

/// How the running code analyses a native recording, injected by `AMPipeline` (`AMLibrary` never imports it).
public struct ReferenceRebuilder: Sendable {
    /// The key the running code gives `source`'s analysis. A stored record with another key is stale.
    public let expectedKey: @Sendable (StarterRecordingSource) -> String
    /// Analyses `source` from its bundled audio and timings.
    public let rebuild: @Sendable (StarterRecordingSource) async throws -> DerivedRecord

    public init(
        expectedKey: @escaping @Sendable (StarterRecordingSource) -> String,
        rebuild: @escaping @Sendable (StarterRecordingSource) async throws -> DerivedRecord
    ) {
        self.expectedKey = expectedKey
        self.rebuild = rebuild
    }
}

public actor ReferenceLibrary: ReferenceSet {
    public nonisolated let manifest: StarterManifest
    /// The bundled `Starter` folder. Never written.
    public nonisolated let bundle: URL
    /// Where rebuilt analyses go: under the app's `Caches/`, never `Application Support/`.
    public nonisolated let caches: URL
    private let rebuilder: ReferenceRebuilder
    /// Rebuilds run so far, by recording (tests).
    public private(set) var rebuilds: [RecordingID: Int] = [:]

    /// `manifest` defaults to the bundle's, validated with its files.
    public init(bundle: URL, caches: URL, rebuilder: ReferenceRebuilder, manifest: StarterManifest? = nil) throws {
        self.manifest = try manifest ?? StarterManifest.load(from: bundle)
        self.bundle = bundle
        self.caches = caches
        self.rebuilder = rebuilder
    }

    // MARK: ReferenceSet

    public nonisolated func identity(phrase: PhraseID, voice: RecordingID) -> ReferenceIdentity {
        manifest.phrase(phrase)?.identity(voice: voice)
            ?? ReferenceIdentity(
                phraseID: phrase, recordingID: voice, recordingSHA256: "", transcriptRevision: 0,
                pronunciationOverridesHash: "", targetsHash: "", nativeSetHash: "")
    }

    /// Every recording of `phrase` with its analysis: a current cache file, else the bundled record, else (stale) a
    /// rebuild into the cache. An unreadable cache file, or a stale record whose rebuild fails, is `cacheCorrupt`.
    public func natives(phrase id: PhraseID) async throws(ReferenceSetError) -> [NativeRecording] {
        guard let phrase = manifest.phrase(id) else { return [] }
        var natives: [NativeRecording] = []
        for recording in phrase.recordings {
            let source = self.source(phrase, recording)
            let expected = rebuilder.expectedKey(source)
            let record: DerivedRecord
            if let cached = try cachedRecord(recording.id, phrase: id), cached.key == expected {
                record = cached
            } else if recording.analysisKey == expected {
                guard let bytes = try? Data(contentsOf: bundle.appending(path: recording.analysis)) else {
                    throw .cacheCorrupt(recording.id)
                }
                record = DerivedRecord(level: .l1, key: recording.analysisKey, bytes: bytes)
            } else {
                record = try await rebuildRecord(source)
            }
            natives.append(NativeRecording(
                id: recording.id, voice: recording.speaker, audioSHA256: recording.audioSHA256, analysis: record))
        }
        return natives
    }

    public func rebuild(_ recording: RecordingID, phrase id: PhraseID) async throws(ReferenceSetError) {
        guard let phrase = manifest.phrase(id), let entry = phrase.recording(recording) else {
            throw .notFound(recording)
        }
        _ = try await rebuildRecord(source(phrase, entry))
    }

    // MARK: Files

    /// The cache file of `recording`: `Caches/…/<phraseID>/<recordingID>.json`.
    public nonisolated func cacheURL(_ recording: RecordingID, phrase: PhraseID) -> URL {
        caches.appending(path: phrase.rawValue).appending(path: recording.rawValue + ".json")
    }

    private nonisolated func source(_ phrase: StarterManifest.Phrase, _ recording: StarterManifest.Recording)
        -> StarterRecordingSource
    {
        StarterRecordingSource(
            phrase: phrase, recording: recording, audio: bundle.appending(path: recording.audio),
            timings: bundle.appending(path: recording.timings), asrModelID: manifest.asrModelID)
    }

    /// The cached record, nil when there's none, `cacheCorrupt` when the file can't be read as a record.
    private func cachedRecord(_ recording: RecordingID, phrase: PhraseID) throws(ReferenceSetError) -> DerivedRecord? {
        let url = cacheURL(recording, phrase: phrase)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(DerivedRecord.self, from: data)
        else { throw .cacheCorrupt(recording) }
        return record
    }

    private func rebuildRecord(_ source: StarterRecordingSource) async throws(ReferenceSetError) -> DerivedRecord {
        let id = source.recording.id
        rebuilds[id, default: 0] += 1
        do {
            let record = try await rebuilder.rebuild(source)
            let url = cacheURL(id, phrase: source.phrase.id)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
            return record
        } catch {
            throw .cacheCorrupt(id)
        }
    }
}

/// Why a phrase's natives couldn't be loaded (`loadNatives`).
public enum ReferenceLoadError: Error, Sendable, Hashable {
    /// A recording still failed after its one rebuild.
    case referenceCacheCorrupt(RecordingID)
    /// The set has no such recording.
    case notFound(RecordingID)

    public var operational: OperationalError {
        switch self {
        case .referenceCacheCorrupt(let id): .referenceCacheCorrupt(id)
        case .notFound: .inferenceFailed(stage: .mapTime)
        }
    }
}

extension ReferenceSet {
    /// The phrase's natives, each read by `decode` (nil means corrupt or built for something else). A failing
    /// recording is rebuilt once, silently; a second failure throws `referenceCacheCorrupt`. Throws
    /// `CancellationError` when cancelled.
    public func loadNatives<T: Sendable>(
        phrase: PhraseID, decode: (NativeRecording) -> T?
    ) async throws -> [T] {
        var rebuilt: Set<RecordingID> = []
        while true {
            try Task.checkCancellation()
            var corrupt: RecordingID?
            var loaded: [T] = []
            do {
                for recording in try await natives(phrase: phrase) {
                    guard let value = decode(recording) else {
                        corrupt = recording.id
                        break
                    }
                    loaded.append(value)
                }
            } catch .cacheCorrupt(let recording) {
                corrupt = recording
            } catch .notFound(let recording) {
                throw ReferenceLoadError.notFound(recording)
            }
            guard let corrupt else { return loaded }
            guard rebuilt.insert(corrupt).inserted else { throw ReferenceLoadError.referenceCacheCorrupt(corrupt) }
            do {
                try await rebuild(corrupt, phrase: phrase)
            } catch {
                throw ReferenceLoadError.referenceCacheCorrupt(corrupt)
            }
        }
    }
}
