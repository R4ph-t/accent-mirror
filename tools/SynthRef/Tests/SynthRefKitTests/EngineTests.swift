// Engines, key handling, the ElevenLabs request (stub transport only: no test opens a connection), the cache and the
// digest manifest. Nothing here synthesizes speech.

import AMAlignment
import AMEvaluation
import Foundation
import Synchronization
import Testing
@testable import SynthRefKit

enum Repo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // SynthRefKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SynthRef
        .deletingLastPathComponent()  // tools
        .deletingLastPathComponent()  // repo root
    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }
}

/// Records requests and answers with a canned response. Never touches the network.
final class StubTransport: HTTPTransport, Sendable {
    let requests = Mutex<[URLRequest]>([])
    let status: Int
    let body: Data

    init(status: Int = 200, body: Data) {
        self.status = status
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.withLock { $0.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

/// A fake engine that counts its renderings.
final class CountingEngine: SpeechEngine, Sendable {
    let calls = Mutex(0)
    let identity: EngineIdentity

    init(voice: String = "v1") { identity = EngineIdentity(kind: .macPremium, voiceID: voice, modelID: "test") }

    func engineText(for request: SynthesisRequest) throws -> String { SSML.elevenLabs(request.words) }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesizedAudio {
        calls.withLock { $0 += 1 }
        return SynthesizedAudio(
            samples: (0..<1600).map { Float(sin(Double($0) * 0.1)) * 0.1 },
            words: request.words.map { _ in WordSpan(start: 0, end: 0.1) })
    }
}

let fakeKey = "sk_test_DO_NOT_LEAK_0123456789"

@Suite("Engine choice and the key") struct EngineChoiceTests {
    @Test("no key, a blank key, a key, and offline")
    func choice() {
        #expect(EngineChoice.choose(environment: [:]).headerLine == "syntheticReference: mac-premium-fallback (no key)")
        #expect(EngineChoice.choose(environment: ["ELEVENLABS_API_KEY": "  "]).headerLine
            == "syntheticReference: mac-premium-fallback (no key)")
        #expect(EngineChoice.choose(environment: ["ELEVENLABS_API_KEY": fakeKey]).headerLine
            == "syntheticReference: elevenlabs")
        #expect(EngineChoice.choose(environment: ["ELEVENLABS_API_KEY": fakeKey], offline: true).headerLine
            == "syntheticReference: mac-premium-fallback (offline)")
    }

    @Test("the key never shows in a description, a dump or a mirror")
    func keyRedacted() throws {
        let key = try #require(APIKey.fromEnvironment(["ELEVENLABS_API_KEY": fakeKey]))
        var dumped = ""
        dump(key, to: &dumped)
        let choice = EngineChoice.elevenLabs(key)
        for text in [String(describing: key), String(reflecting: key), dumped, "\(choice)", String(reflecting: choice)] {
            #expect(!text.contains(fakeKey))
        }
    }
}

@Suite("ElevenLabs client, stub transport") struct ElevenLabsTests {
    static func response(characters: [String], pcm: [Int16]) throws -> Data {
        let bytes = pcm.flatMap { v in withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        let starts = characters.indices.map { Double($0) * 0.01 }
        let object: [String: Any] = [
            "audio_base64": Data(bytes).base64EncodedString(),
            "alignment": [
                "characters": characters, "character_start_times_seconds": starts,
                "character_end_times_seconds": starts.map { $0 + 0.01 },
            ],
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test("request: POST with-timestamps, eleven_flash_v2, cmu-arpabet SSML, key only in xi-api-key")
    func requestShape() async throws {
        let key = try #require(APIKey.fromEnvironment(["ELEVENLABS_API_KEY": fakeKey]))
        let transport = StubTransport(body: try Self.response(characters: Array("photograph").map(String.init), pcm: [0, 16_384, -16_384]))
        let engine = ElevenLabsEngine(key: key, voiceID: "voice123", transport: transport)
        let audio = try await engine.synthesize(
            SynthesisRequest(words: [SpokenWord(text: "photograph", arpabet: "F OW1 T AH0 G R AE2 F")]))

        let request = try #require(transport.requests.withLock { $0.first })
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "api.elevenlabs.io")
        #expect(request.url?.path == "/v1/text-to-speech/voice123/with-timestamps")
        #expect(request.url?.query == "output_format=pcm_16000")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == fakeKey)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model_id"] as? String == "eleven_flash_v2")
        #expect(json["text"] as? String
            == #"<phoneme alphabet="cmu-arpabet" ph="F OW1 T AH0 G R AE2 F">photograph</phoneme>"#)
        #expect(!String(decoding: body, as: UTF8.self).contains(fakeKey), "the key is never in the body")
        #expect(request.url?.absoluteString.contains(fakeKey) == false, "the key is never in the URL")

        #expect(audio.samples == [0, 0.5, -0.5])
        #expect(audio.words.count == 1)
        #expect(engine.identity.modelID == "eleven_flash_v2")
    }

    @Test("word spans from character timings, markup dropped; a mismatch throws")
    func wordSpans() async throws {
        let key = try #require(APIKey.fromEnvironment(["ELEVENLABS_API_KEY": fakeKey]))
        let characters = Array("<b>call</b> stella").map(String.init)
        let engine = ElevenLabsEngine(
            key: key, voiceID: "v", transport: StubTransport(body: try Self.response(characters: characters, pcm: [0])))
        let audio = try await engine.synthesize(SynthesisRequest(words: [SpokenWord(text: "call"), SpokenWord(text: "stella")]))
        #expect(audio.words.count == 2)
        #expect(abs(audio.words[0].start - 0.03) < 1e-9 && abs(audio.words[1].start - 0.12) < 1e-9)

        await #expect(throws: ElevenLabsEngine.Failure.alignmentMismatch(expectedWords: 3, alignedWords: 2)) {
            _ = try await engine.synthesize(SynthesisRequest(words: ["a", "b", "c"].map { SpokenWord(text: $0) }))
        }
    }

    @Test("an HTTP error keeps the status only and never the key")
    func httpError() async throws {
        let key = try #require(APIKey.fromEnvironment(["ELEVENLABS_API_KEY": fakeKey]))
        let engine = ElevenLabsEngine(
            key: key, voiceID: "v", transport: StubTransport(status: 401, body: Data("bad key \(fakeKey)".utf8)))
        do {
            _ = try await engine.synthesize(SynthesisRequest(words: [SpokenWord(text: "hi")]))
            Issue.record("expected a failure")
        } catch {
            #expect(error as? ElevenLabsEngine.Failure == .http(status: 401))
            #expect(!"\(error)".contains(fakeKey))
        }
    }
}

@Suite("TTS cache and digest manifest") struct CacheTests {
    @Test("a second identical request is a cache hit and never calls the engine")
    func cacheHit() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = TTSCache(directory: dir)
        let engine = CountingEngine()
        let request = SynthesisRequest(words: [SpokenWord(text: "rainbow", arpabet: "R EY1 N B OW2")])
        let first = try await cache.render(request, with: engine)
        let second = try await cache.render(request, with: engine)
        #expect(!first.cacheHit && second.cacheHit)
        #expect(engine.calls.withLock { $0 } == 1)
        #expect(second.audio == first.audio)
        #expect(first.digest == second.digest)
    }

    @Test("the digest covers text, engine, voice, model and settings")
    func digestCoverage() throws {
        let base = EngineIdentity(kind: .elevenlabs, voiceID: "a", modelID: "m", settings: ["s": "1"])
        let digests = try [
            RenderKey(text: "x", identity: base),
            RenderKey(text: "y", identity: base),
            RenderKey(text: "x", identity: EngineIdentity(kind: .macPremium, voiceID: "a", modelID: "m", settings: ["s": "1"])),
            RenderKey(text: "x", identity: EngineIdentity(kind: .elevenlabs, voiceID: "b", modelID: "m", settings: ["s": "1"])),
            RenderKey(text: "x", identity: EngineIdentity(kind: .elevenlabs, voiceID: "a", modelID: "n", settings: ["s": "1"])),
            RenderKey(text: "x", identity: EngineIdentity(kind: .elevenlabs, voiceID: "a", modelID: "m", settings: ["s": "2"])),
        ].map { try $0.digest }
        #expect(Set(digests).count == digests.count)
        #expect(try RenderKey(text: "x", identity: base).digest == digests[0], "stable")
    }

    @Test("the manifest carries digests and items, never audio, a key or a host")
    func manifest() throws {
        let key = RenderKey(text: "rainbow", identity: EngineIdentity(kind: .elevenlabs, voiceID: "v", modelID: "m"))
        let manifest = DigestManifest(
            syntheticReference: "elevenlabs", items: ["rainbow/correct"],
            entries: [DigestManifest.Entry(key, digest: try key.digest), DigestManifest.Entry(key, digest: try key.digest)])
        #expect(manifest.entries.count == 1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try manifest.write(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        for forbidden in ["elevenlabs.io", "xi-api-key", "ELEVENLABS_API_KEY", "/Users/", "samples"] {
            #expect(!text.contains(forbidden))
        }
    }
}
