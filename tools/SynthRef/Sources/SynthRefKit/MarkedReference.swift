// Spec 23's reference sanity check, the synthesis half (moved here from am-timestamps so TTS stays out of AccentKit,
// spec 22). Speaks each phrase once with a pinned on-device voice, with an SSML <mark> before and after every word,
// and writes an MFA input corpus (WAV + .lab), markers.json and clips.txt. `am-timestamps reference-phrases` writes
// the input and `am-timestamps reference-compare` reads markers.json. No network, no audio in git.
// AVFoundation is imported @preconcurrency because AVSpeechSynthesizer and its buffers are not Sendable; they never
// leave the main actor here.

@preconcurrency import AVFoundation
import Foundation
import Synchronization

public enum MarkedReference {
    /// One phrase to speak (`am-timestamps reference-phrases`).
    public struct Phrase: Codable, Sendable {
        public var clipID: String
        public var transcript: String
    }

    /// One word's marker span, in seconds (the JSON shape of AMTimestampEval's `BaselineWord`).
    public struct Span: Codable, Sendable {
        public var word: String
        public var start: Double
        public var end: Double
    }

    /// The marker spans of one synthesised phrase.
    public struct MarkedPhrase: Codable, Sendable {
        public var clipID: String
        public var transcript: String
        public var words: [Span]
        public var wordsWithoutMarkers: Int
    }

    /// markers.json, read back by `am-timestamps reference-compare`.
    public struct MarkerFile: Codable, Sendable {
        public var voice: String
        public var sampleRate: Double
        public var bufferFrames: Int
        public var phrases: [MarkedPhrase]
    }

    public enum Failure: Error, CustomStringConvertible {
        case voiceMissing(String)
        case failed(String)

        public var description: String {
            switch self {
            case .voiceMissing(let id): "voice \(id) is not installed on this Mac"
            case .failed(let message): message
            }
        }
    }

    /// Collects the synthesiser's buffers and bookmark offsets. Its state is behind a Mutex, so it is Sendable.
    final class Recorder: NSObject, AVSpeechSynthesizerDelegate, Sendable {
        struct State {
            var samples: [Float] = []
            var sampleRate = 0.0
            var bytesPerFrame = 4
            var bufferFrames: [Int: Int] = [:]
            var bookmarks: [String: Int] = [:]
        }

        let state = Mutex(State())

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeak marker: AVSpeechSynthesisMarker,
                               utterance: AVSpeechUtterance) {
            guard marker.mark == .bookmark, !marker.bookmarkName.isEmpty else { return }
            let name = marker.bookmarkName
            let offset = marker.byteSampleOffset
            state.withLock { $0.bookmarks[name] = offset / max($0.bytesPerFrame, 1) }
        }
    }

    static func ssmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Synthesises `words` with a bookmark `s<i>` before and `e<i>` after each word (after its trailing punctuation).
    @MainActor
    static func synthesize(_ words: [String], voice: AVSpeechSynthesisVoice) async throws -> Recorder.State {
        let ssml = "<speak>" + words.enumerated().map { index, word in
            "<mark name=\"s\(index)\"/>\(ssmlEscaped(word))<mark name=\"e\(index)\"/>"
        }.joined(separator: " ") + "</speak>"
        guard let utterance = AVSpeechUtterance(ssmlRepresentation: ssml) else {
            throw Failure.failed("the synthesiser rejected the SSML: \(ssml)")
        }
        utterance.voice = voice
        let recorder = Recorder()
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = recorder
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumed = Mutex(false)
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !resumed.withLock({ let was = $0; $0 = true; return was }) { continuation.resume() }
                    return
                }
                let frames = Int(pcm.frameLength)
                let channel = pcm.floatChannelData.map { Array(UnsafeBufferPointer(start: $0[0], count: frames)) } ?? []
                recorder.state.withLock { state in
                    state.sampleRate = pcm.format.sampleRate
                    state.bytesPerFrame = Int(pcm.format.streamDescription.pointee.mBytesPerFrame)
                    state.samples += channel
                    state.bufferFrames[frames, default: 0] += 1
                }
            }
        }
        withExtendedLifetime(synthesizer) {}
        return recorder.state.withLock { $0 }
    }

    /// Speaks every phrase in `phrasesFile` with the voice `voiceID` and writes corpus/tts/, markers.json and
    /// clips.txt under `out`. Throws `Failure.voiceMissing` when the voice is not installed.
    @MainActor
    public static func write(phrasesFile: URL, voiceID: String, out: URL) async throws -> String {
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceID) else { throw Failure.voiceMissing(voiceID) }
        let input = try JSONDecoder().decode([Phrase].self, from: Data(contentsOf: phrasesFile))
        let corpus = out.appending(path: "corpus/tts")
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)

        var phrases: [MarkedPhrase] = []
        var bufferFrames: [Int: Int] = [:]
        var rate = 0.0
        for phrase in input {
            let words = phrase.transcript.split(separator: " ").map(String.init)
            let state = try await synthesize(words, voice: voice)
            rate = state.sampleRate
            bufferFrames.merge(state.bufferFrames, uniquingKeysWith: +)
            var spans: [Span] = [], missing = 0
            for (index, word) in words.enumerated() {
                guard let start = state.bookmarks["s\(index)"], let end = state.bookmarks["e\(index)"] else {
                    missing += 1
                    continue
                }
                spans.append(Span(word: word, start: Double(start) / rate, end: Double(end) / rate))
            }
            phrases.append(MarkedPhrase(clipID: phrase.clipID, transcript: phrase.transcript, words: spans,
                                        wordsWithoutMarkers: missing))
            guard let format = AVAudioFormat(standardFormatWithSampleRate: state.sampleRate, channels: 1),
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(state.samples.count)),
                let channel = buffer.floatChannelData
            else { throw Failure.failed("no audio buffer for \(phrase.clipID)") }
            buffer.frameLength = AVAudioFrameCount(state.samples.count)
            state.samples.withUnsafeBufferPointer { channel[0].update(from: $0.baseAddress!, count: $0.count) }
            let file = try AVAudioFile(forWriting: corpus.appending(path: "\(phrase.clipID).wav"), settings: format.settings)
            try file.write(from: buffer)
            try Data((phrase.transcript + "\n").utf8).write(to: corpus.appending(path: "\(phrase.clipID).lab"))
        }
        let common = bufferFrames.max { $0.value < $1.value }?.key ?? 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try (encoder.encode(MarkerFile(voice: voiceID, sampleRate: rate, bufferFrames: common, phrases: phrases))
            + Data("\n".utf8)).write(to: out.appending(path: "markers.json"), options: .atomic)
        try Data((input.map(\.clipID).joined(separator: "\n") + "\n").utf8).write(to: out.appending(path: "clips.txt"))
        let missing = phrases.map(\.wordsWithoutMarkers).reduce(0, +)
        return "\(phrases.count) phrases by \(voiceID) at \(Int(rate)) Hz, \(missing) words without markers → \(out.path)"
    }
}
