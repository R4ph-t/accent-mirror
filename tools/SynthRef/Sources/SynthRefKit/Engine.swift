// Engines and the choice between them (spec 22, Engines). ElevenLabs is the default when `ELEVENLABS_API_KEY` is in
// the environment; otherwise every run is the labelled Mac Premium fallback. The key is read only from the process
// environment, never logged, never written to disk or a report.

import AMEvaluation
import Foundation

public enum EngineKind: String, Sendable, Hashable, Codable {
    case elevenlabs
    case macPremium = "mac-premium"
}

/// Everything that identifies a rendering besides its text. Part of the cache digest.
public struct EngineIdentity: Sendable, Hashable, Codable {
    public let kind: EngineKind
    public let voiceID: String
    public let modelID: String
    /// Settings that change the audio (voice settings, output format).
    public let settings: [String: String]

    public init(kind: EngineKind, voiceID: String, modelID: String, settings: [String: String] = [:]) {
        self.kind = kind
        self.voiceID = voiceID
        self.modelID = modelID
        self.settings = settings
    }

    /// `<kind>:<voice>` for report lines and native-reader names.
    public var label: String { "\(kind.rawValue):\(voiceID)" }
}

/// One rendering request.
public struct SynthesisRequest: Sendable, Hashable, Codable {
    public let words: [SpokenWord]

    public init(words: [SpokenWord]) { self.words = words }

    public var plainText: String { words.map(\.text).joined(separator: " ") }
}

/// A word's span in a rendering, in seconds.
public struct WordSpan: Sendable, Hashable, Codable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// 16 kHz mono audio and one span per requested word.
public struct SynthesizedAudio: Sendable, Hashable {
    public static let sampleRate = 16_000.0
    public let samples: [Float]
    public let words: [WordSpan]

    public init(samples: [Float], words: [WordSpan]) {
        self.samples = samples
        self.words = words
    }

    public var duration: Double { Double(samples.count) / Self.sampleRate }
}

public protocol SpeechEngine: Sendable {
    var identity: EngineIdentity { get }
    /// The exact text sent to the engine for `request` (SSML included). Part of the cache digest.
    func engineText(for request: SynthesisRequest) throws -> String
    func synthesize(_ request: SynthesisRequest) async throws -> SynthesizedAudio
}

/// The ElevenLabs key. Its value never appears in a description, a mirror, a log or an encoded form.
public struct APIKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let environmentVariable = "ELEVENLABS_API_KEY"

    let value: String

    init(value: String) { self.value = value }

    /// The key from the process environment; nil when unset or blank. The only way to get one.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> APIKey? {
        guard let raw = environment[environmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }
        return APIKey(value: raw)
    }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
    public var customMirror: Mirror { Mirror(self, children: []) }
}

/// Which engine a run uses, and the `syntheticReference` its report header carries.
public enum EngineChoice: Sendable, CustomStringConvertible {
    case elevenLabs(APIKey)
    /// No key, offline, or a fork PR (which never gets the secret, so it reads as no key).
    case macFallback(reason: String)

    /// ElevenLabs with a key unless `offline`; otherwise the Mac fallback, with the reason.
    public static func choose(
        environment: [String: String] = ProcessInfo.processInfo.environment, offline: Bool = false
    ) -> EngineChoice {
        if offline { return .macFallback(reason: "offline") }
        guard let key = APIKey.fromEnvironment(environment) else { return .macFallback(reason: "no key") }
        return .elevenLabs(key)
    }

    public var syntheticReference: SyntheticReference {
        switch self {
        case .elevenLabs: .elevenlabs
        case .macFallback(let reason): .macPremiumFallback(reason: reason)
        }
    }

    /// The report header line: `syntheticReference: elevenlabs | mac-premium-fallback (<reason>)`.
    public var headerLine: String { "syntheticReference: \(syntheticReference)" }

    public var description: String { headerLine }
}
