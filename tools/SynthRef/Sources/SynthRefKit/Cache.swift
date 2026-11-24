// The TTS cache (spec 22, Audio handling): renderings keyed by digest = SHA-256 of (text, engine, voice ID, model ID,
// settings), stored only in git-ignored `eval-cache/tts/` (locally) or the private Actions cache (CI). A hit never
// calls the engine. Only the digest manifest is committed; audio never is.

import AMCore
import Foundation

/// What a rendering's digest covers.
public struct RenderKey: Sendable, Hashable, Codable {
    /// The exact text sent to the engine, SSML included.
    public let text: String
    public let engine: EngineKind
    public let voiceID: String
    public let modelID: String
    public let settings: [String: String]

    public init(text: String, identity: EngineIdentity) {
        self.text = text
        engine = identity.kind
        voiceID = identity.voiceID
        modelID = identity.modelID
        settings = identity.settings
    }

    /// SHA-256 of the key's canonical JSON (sorted keys, no whitespace), lowercase hex.
    public var digest: String {
        get throws { try CanonicalJSON.sha256(self) }
    }
}

public struct TTSCache: Sendable {
    /// `eval-cache/tts/renders` under the repository root by default.
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static func `default`(repositoryRoot: URL) -> TTSCache {
        TTSCache(directory: repositoryRoot.appendingPathComponent("eval-cache/tts/renders"))
    }

    struct Meta: Codable {
        let key: RenderKey
        let sampleCount: Int
        let sampleRate: Double
        let words: [WordSpan]
    }

    func paths(_ digest: String) -> (audio: URL, meta: URL) {
        (directory.appendingPathComponent("\(digest).f32"), directory.appendingPathComponent("\(digest).json"))
    }

    public func lookup(digest: String) -> SynthesizedAudio? {
        let (audioURL, metaURL) = paths(digest)
        guard let metaData = try? Data(contentsOf: metaURL),
            let meta = try? JSONDecoder().decode(Meta.self, from: metaData),
            let audio = try? Data(contentsOf: audioURL), audio.count == meta.sampleCount * MemoryLayout<Float>.size
        else { return nil }
        let samples = audio.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return SynthesizedAudio(samples: samples, words: meta.words)
    }

    func store(_ audio: SynthesizedAudio, key: RenderKey, digest: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (audioURL, metaURL) = paths(digest)
        try audio.samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: audioURL, options: .atomic)
        let meta = Meta(key: key, sampleCount: audio.samples.count, sampleRate: SynthesizedAudio.sampleRate,
                        words: audio.words)
        try JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
    }

    /// One rendering, from the cache when it has the digest (the engine is not called), otherwise rendered and stored.
    public func render(_ request: SynthesisRequest, with engine: any SpeechEngine) async throws -> CachedRendering {
        let key = RenderKey(text: try engine.engineText(for: request), identity: engine.identity)
        let digest = try key.digest
        if let audio = lookup(digest: digest) {
            return CachedRendering(key: key, digest: digest, audio: audio, cacheHit: true)
        }
        let audio = try await engine.synthesize(request)
        try store(audio, key: key, digest: digest)
        return CachedRendering(key: key, digest: digest, audio: audio, cacheHit: false)
    }
}

public struct CachedRendering: Sendable {
    public let key: RenderKey
    public let digest: String
    public let audio: SynthesizedAudio
    public let cacheHit: Bool
}

/// The committed manifest (`fixtures/tts/digests.json`): which renderings a run used, by digest, never their audio.
/// Carries no key, no host and no path.
public struct DigestManifest: Sendable, Hashable, Codable {
    public struct Entry: Sendable, Hashable, Codable, Comparable {
        public let digest: String
        public let engine: EngineKind
        public let voiceID: String
        public let modelID: String
        /// Characters billed (ElevenLabs counts the text sent).
        public let characters: Int

        public init(_ key: RenderKey, digest: String) {
            self.digest = digest
            engine = key.engine
            voiceID = key.voiceID
            modelID = key.modelID
            characters = key.text.count
        }

        public static func < (a: Entry, b: Entry) -> Bool { a.digest < b.digest }
    }

    public var formatVersion = 1
    /// `syntheticReference` of the run that wrote it.
    public let syntheticReference: String
    /// The verification items' ids, so the manifest says what was (or would be) generated.
    public let items: [String]
    public let entries: [Entry]

    public init(syntheticReference: String, items: [String], entries: [Entry]) {
        self.syntheticReference = syntheticReference
        self.items = items
        self.entries = Array(Set(entries)).sorted()
    }

    public var totalCharacters: Int { entries.reduce(0) { $0 + $1.characters } }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (encoder.encode(self) + Data("\n".utf8)).write(to: url, options: .atomic)
    }
}
