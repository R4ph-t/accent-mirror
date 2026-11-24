// The ElevenLabs engine (spec 22 default): `eleven_flash_v2`, inline SSML `<phoneme alphabet="cmu-arpabet">`, 16 kHz
// PCM and character timings from the `with-timestamps` endpoint. Every request goes through an `HTTPTransport`, so
// tests use a stub and never open a connection; a run without a key never builds this engine at all.
//
// The response's alignment is assumed to cover the spoken characters (tags stripped below if present). That is
// unverified until the first keyed run; a mismatch throws rather than guessing word spans.

import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real transport: an ephemeral session (no cookies, no disk cache). Used only with a key.
public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ElevenLabsEngine.Failure.notHTTP }
        return (data, http)
    }
}

public struct ElevenLabsEngine: SpeechEngine {
    public static let host = "api.elevenlabs.io"
    public static let modelID = "eleven_flash_v2"
    public static let outputFormat = "pcm_16000"

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notHTTP
        /// The HTTP status only: the body may echo request details, so it is never kept.
        case http(status: Int)
        case malformedResponse
        case alignmentMismatch(expectedWords: Int, alignedWords: Int)

        public var description: String {
            switch self {
            case .notHTTP: "ElevenLabs: not an HTTP response"
            case .http(let status): "ElevenLabs: HTTP \(status)"
            case .malformedResponse: "ElevenLabs: malformed response"
            case .alignmentMismatch(let expected, let aligned):
                "ElevenLabs: \(aligned) aligned words for \(expected) requested"
            }
        }
    }

    /// Voice settings sent with every request; part of the cache digest.
    public struct VoiceSettings: Sendable, Hashable, Codable {
        public var stability = 0.5
        public var similarityBoost = 0.75

        public init() {}

        enum CodingKeys: String, CodingKey {
            case stability
            case similarityBoost = "similarity_boost"
        }
    }

    private let key: APIKey
    public let voiceID: String
    public let settings: VoiceSettings
    private let transport: any HTTPTransport

    public init(key: APIKey, voiceID: String, settings: VoiceSettings = .init(), transport: any HTTPTransport) {
        self.key = key
        self.voiceID = voiceID
        self.settings = settings
        self.transport = transport
    }

    public var identity: EngineIdentity {
        EngineIdentity(
            kind: .elevenlabs, voiceID: voiceID, modelID: Self.modelID,
            settings: [
                "stability": String(settings.stability), "similarity_boost": String(settings.similarityBoost),
                "output_format": Self.outputFormat,
            ])
    }

    public func engineText(for request: SynthesisRequest) throws -> String { SSML.elevenLabs(request.words) }

    struct Body: Encodable {
        let text: String
        let modelID: String
        let voiceSettings: VoiceSettings

        enum CodingKeys: String, CodingKey {
            case text
            case modelID = "model_id"
            case voiceSettings = "voice_settings"
        }
    }

    /// The request for `request`: POST `/v1/text-to-speech/<voice>/with-timestamps?output_format=pcm_16000`, the key in
    /// `xi-api-key` and nowhere else.
    public func urlRequest(for request: SynthesisRequest) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = "/v1/text-to-speech/\(voiceID)/with-timestamps"
        components.queryItems = [URLQueryItem(name: "output_format", value: Self.outputFormat)]
        guard let url = components.url else { throw Failure.malformedResponse }
        var http = URLRequest(url: url)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue(key.value, forHTTPHeaderField: "xi-api-key")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        http.httpBody = try encoder.encode(
            Body(text: try engineText(for: request), modelID: Self.modelID, voiceSettings: settings))
        return http
    }

    struct Response: Decodable {
        struct Alignment: Decodable {
            let characters: [String]
            let characterStartTimesSeconds: [Double]
            let characterEndTimesSeconds: [Double]

            enum CodingKeys: String, CodingKey {
                case characters
                case characterStartTimesSeconds = "character_start_times_seconds"
                case characterEndTimesSeconds = "character_end_times_seconds"
            }
        }

        let audioBase64: String
        let alignment: Alignment?

        enum CodingKeys: String, CodingKey {
            case audioBase64 = "audio_base64"
            case alignment
        }
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesizedAudio {
        let (data, response) = try await transport.send(try urlRequest(for: request))
        guard response.statusCode == 200 else { throw Failure.http(status: response.statusCode) }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
            let pcm = Data(base64Encoded: decoded.audioBase64)
        else { throw Failure.malformedResponse }
        let samples = Self.samples(pcm16LE: pcm)
        let duration = Double(samples.count) / SynthesizedAudio.sampleRate
        let spans: [WordSpan]
        if let alignment = decoded.alignment {
            spans = try Self.wordSpans(alignment, expected: request.words.count)
        } else if request.words.count == 1 {
            spans = [WordSpan(start: 0, end: duration)]
        } else {
            throw Failure.alignmentMismatch(expectedWords: request.words.count, alignedWords: 0)
        }
        return SynthesizedAudio(samples: samples, words: spans)
    }

    /// Signed 16-bit little-endian PCM to floats in [-1, 1).
    static func samples(pcm16LE data: Data) -> [Float] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - 1, by: 2).map { i in
            Float(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8)) / 32_768
        }
    }

    /// Word spans from character timings: markup between `<` and `>` dropped, words split on whitespace, each word from
    /// its first character's start to its last character's end.
    static func wordSpans(_ alignment: Response.Alignment, expected: Int) throws -> [WordSpan] {
        let count = min(
            alignment.characters.count, alignment.characterStartTimesSeconds.count,
            alignment.characterEndTimesSeconds.count)
        var spans: [WordSpan] = []
        var current: WordSpan?
        var inTag = false
        for i in 0..<count {
            let character = alignment.characters[i]
            if character == "<" { inTag = true }
            if inTag {
                if character == ">" { inTag = false }
                continue
            }
            if character.allSatisfy(\.isWhitespace) {
                if let word = current { spans.append(word) }
                current = nil
                continue
            }
            let start = alignment.characterStartTimesSeconds[i], end = alignment.characterEndTimesSeconds[i]
            current = WordSpan(start: current?.start ?? start, end: max(current?.end ?? end, end))
        }
        if let word = current { spans.append(word) }
        guard spans.count == expected else {
            throw Failure.alignmentMismatch(expectedWords: expected, alignedWords: spans.count)
        }
        return spans
    }
}
