// The Mac fallback (spec 22): installed English Premium voices through `AVSpeechSynthesizer.write`, which renders to
// buffers. Nothing is played, nothing is recorded, and no voice is ever downloaded: if no Premium English voice is
// installed, the fallback is NOT EVALUATED. Word starts come from SSML bookmarks, as in spec 07's TTS marker gate.

@preconcurrency import AVFoundation
import AMEvaluation
import Foundation
import Synchronization

public enum VoiceQuality: String, Sendable, Hashable, Codable, Comparable {
    case standard, enhanced, premium

    public static func < (a: VoiceQuality, b: VoiceQuality) -> Bool {
        [.standard, .enhanced, .premium].firstIndex(of: a)! < [.standard, .enhanced, .premium].firstIndex(of: b)!
    }
}

public struct InstalledVoice: Sendable, Hashable, Codable {
    public let identifier: String
    public let name: String
    public let language: String
    public let quality: VoiceQuality

    public init(identifier: String, name: String, language: String, quality: VoiceQuality) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.quality = quality
    }

    public var line: String { "\(quality.rawValue) \(language) \(name) (\(identifier))" }
}

public enum InstalledVoices {
    /// Every installed English voice, novelty and personal voices left out. Lists only; downloads nothing.
    public static func english() -> [InstalledVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix("en")
                && !voice.voiceTraits.contains(.isNoveltyVoice) && !voice.voiceTraits.contains(.isPersonalVoice)
        }.map { voice in
            let quality: VoiceQuality = switch voice.quality {
            case .premium: .premium
            case .enhanced: .enhanced
            default: .standard
            }
            return InstalledVoice(
                identifier: voice.identifier, name: voice.name, language: voice.language, quality: quality)
        }.sorted { ($0.language, $0.name, $0.identifier) < ($1.language, $1.name, $1.identifier) }
    }

    /// The fallback's candidates: Premium only (the spec names Premium; Enhanced is not a fallback voice).
    public static func fallbackCandidates(_ voices: [InstalledVoice]) -> [InstalledVoice] {
        voices.filter { $0.quality == .premium }
    }
}

public struct MacPremiumEngine: SpeechEngine {
    public static let modelID = "avspeechsynthesizer"
    public let voice: InstalledVoice
    /// Longest a rendering may take before it is abandoned.
    public var timeout: Duration = .seconds(30)

    public init(voice: InstalledVoice) { self.voice = voice }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case voiceNotInstalled(String)
        case invalidSSML
        case timedOut
        case noAudio
        case bookmarks(expected: Int, got: Int)

        public var description: String {
            switch self {
            case .voiceNotInstalled(let id): "voice \(id) is not installed"
            case .invalidSSML: "the voice rejected the SSML"
            case .timedOut: "synthesis did not finish in time"
            case .noAudio: "the voice produced no audio"
            case .bookmarks(let expected, let got): "\(got) word bookmarks for \(expected) words"
            }
        }
    }

    public var identity: EngineIdentity {
        EngineIdentity(
            kind: .macPremium, voiceID: voice.identifier, modelID: Self.modelID,
            settings: ["os": ProcessInfo.processInfo.operatingSystemVersionString, "quality": voice.quality.rawValue])
    }

    public func engineText(for request: SynthesisRequest) throws -> String { try SSML.apple(request.words) }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesizedAudio {
        try await Self.render(ssml: try engineText(for: request), voice: voice.identifier, words: request.words.count,
                              timeout: timeout)
    }

    @MainActor static func render(ssml: String, voice identifier: String, words: Int, timeout: Duration) async throws
        -> SynthesizedAudio
    {
        guard let voice = AVSpeechSynthesisVoice(identifier: identifier) else {
            throw Failure.voiceNotInstalled(identifier)
        }
        guard let utterance = AVSpeechUtterance(ssmlRepresentation: ssml) else { throw Failure.invalidSSML }
        utterance.voice = voice
        let synthesizer = AVSpeechSynthesizer()
        let collector = Collector()
        synthesizer.delegate = collector
        synthesizer.write(
            utterance, toBufferCallback: { collector.append($0) }, toMarkerCallback: { collector.record($0) })
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            collector.timeOut()
        }
        await collector.wait()
        watchdog.cancel()
        withExtendedLifetime(synthesizer) {}

        let state = collector.state.withLock { $0 }
        if state.timedOut { throw Failure.timedOut }
        guard state.sampleRate > 0, !state.samples.isEmpty else { throw Failure.noAudio }
        let names = (0..<words).map { "w\($0)" }
        guard names.allSatisfy({ state.bookmarks[$0] != nil }) else {
            throw Failure.bookmarks(expected: words, got: state.bookmarks.count)
        }
        let samples = try AudioFiles.resample(state.samples, from: state.sampleRate, to: SynthesizedAudio.sampleRate)
        let duration = Double(samples.count) / SynthesizedAudio.sampleRate
        let starts = names.map { min(duration, Double(state.bookmarks[$0]!) / state.bytesPerFrame / state.sampleRate) }
        let ends = Array(starts.dropFirst()) + [Energy.lastVoicedEnd(samples) ?? duration]
        return SynthesizedAudio(
            samples: samples, words: zip(starts, ends).map { WordSpan(start: $0, end: max($0, $1)) })
    }

    /// Buffers and bookmarks from both the `write` callbacks and the delegate (macOS 26 voices deliver bookmarks
    /// through the delegate). Done at the zero-length final buffer plus the delegate's `didFinish`.
    final class Collector: NSObject, AVSpeechSynthesizerDelegate, Sendable {
        struct State {
            var samples: [Float] = []
            var sampleRate = 0.0
            var bytesPerFrame = 4.0
            var bookmarks: [String: Int] = [:]
            var endedBuffers = false
            var finishedDelegate = false
            var timedOut = false
            var waiter: CheckedContinuation<Void, Never>?
            var done: Bool { timedOut || (endedBuffers && finishedDelegate) }
        }

        let state = Mutex(State())

        private func update(_ change: (inout State) -> Void) {
            let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
                change(&state)
                guard state.done else { return nil }
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume()
        }

        func append(_ buffer: AVAudioBuffer) {
            guard let pcm = buffer as? AVAudioPCMBuffer, let channel = pcm.floatChannelData else { return }
            let frames = Array(UnsafeBufferPointer(start: channel[0], count: Int(pcm.frameLength)))
            let rate = pcm.format.sampleRate
            let bytesPerFrame = Double(pcm.format.streamDescription.pointee.mBytesPerFrame)
            update {
                $0.sampleRate = rate
                $0.bytesPerFrame = bytesPerFrame
                if frames.isEmpty { $0.endedBuffers = true } else { $0.samples += frames }
            }
        }

        func record(_ markers: [AVSpeechSynthesisMarker]) {
            let bookmarks = markers.filter { $0.mark == .bookmark && !$0.bookmarkName.isEmpty }
                .map { ($0.bookmarkName, $0.byteSampleOffset) }
            update { state in
                for (name, offset) in bookmarks where state.bookmarks[name] == nil { state.bookmarks[name] = offset }
            }
        }

        func timeOut() { update { $0.timedOut = true } }

        func wait() async {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { state -> Bool in
                    if state.done { return true }
                    state.waiter = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }

        func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer, willSpeak marker: AVSpeechSynthesisMarker, utterance: AVSpeechUtterance
        ) {
            record([marker])
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            update { $0.finishedDelegate = true }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            update { $0.finishedDelegate = true }
        }
    }
}

/// Frame energy helpers for word ends and trimming.
public enum Energy {
    /// The end of the last 10 ms frame within 40 dB of the loudest frame; nil for silence.
    public static func lastVoicedEnd(_ samples: [Float], sampleRate: Double = SynthesizedAudio.sampleRate) -> Double? {
        let frame = Int(sampleRate * 0.010)
        guard frame > 0, samples.count >= frame else { return nil }
        let energies = stride(from: 0, to: samples.count - frame + 1, by: frame).map { start in
            samples[start..<start + frame].reduce(0) { $0 + $1 * $1 } / Float(frame)
        }
        guard let peak = energies.max(), peak > 0 else { return nil }
        let floor = peak * 1e-4
        guard let last = energies.lastIndex(where: { $0 >= floor }) else { return nil }
        return Double((last + 1) * frame) / sampleRate
    }
}
