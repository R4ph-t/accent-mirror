@preconcurrency import AVFoundation
import AMAlignment
import AMTimestampEval
import Foundation
import Synchronization

// The reference sanity check (CTO review of spec 23). `tts-reference` synthesises each eval phrase once with a pinned
// on-device voice, with an SSML <mark> before and after every word, and writes an MFA input corpus (WAV + .lab) and
// the marker spans. `reference-compare` compares MFA's alignment of that audio with the markers. Local tooling: no
// network, no audio in git. AVFoundation is imported @preconcurrency because AVSpeechSynthesizer and its buffers are
// not Sendable; they never leave the main actor here.

/// The marker spans of one synthesised phrase.
struct MarkedPhrase: Codable {
    var clipID: String
    var transcript: String
    var words: [BaselineWord]
    var wordsWithoutMarkers: Int
}

/// What `tts-reference` writes next to the corpus.
struct MarkerFile: Codable {
    var voice: String
    var sampleRate: Double
    var bufferFrames: Int
    var phrases: [MarkedPhrase]
}

/// Collects the synthesiser's buffers and bookmark offsets. Its state is behind a Mutex, so it is Sendable.
final class SpeechRecorder: NSObject, AVSpeechSynthesizerDelegate, Sendable {
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

extension AMTimestamps {
    static func ssmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Synthesises `words` with a bookmark `s<i>` before and `e<i>` after each word (after its trailing punctuation).
    @MainActor
    static func synthesize(_ words: [String], voice: AVSpeechSynthesisVoice) async throws -> SpeechRecorder.State {
        let ssml = "<speak>" + words.enumerated().map { index, word in
            "<mark name=\"s\(index)\"/>\(ssmlEscaped(word))<mark name=\"e\(index)\"/>"
        }.joined(separator: " ") + "</speak>"
        guard let utterance = AVSpeechUtterance(ssmlRepresentation: ssml) else {
            throw ToolError.failed("the synthesiser rejected the SSML: \(ssml)")
        }
        utterance.voice = voice
        let recorder = SpeechRecorder()
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

    // MARK: - tts-reference

    static func ttsReference(_ options: Options) async throws -> Int32 {
        let voiceID = try options.string("voice")
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceID) else {
            print("tts-reference: SKIPPED, voice \(voiceID) is not installed on this Mac")
            return 3
        }
        let out = try options.url("out")
        let corpus = out.appending(path: "corpus/tts")
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)

        // One phrase per text ID, its transcript from the first speaker that has it.
        var seen: Set<String> = []
        var phrases: [MarkedPhrase] = []
        var bufferFrames: [Int: Int] = [:]
        var rate = 0.0
        var ids: [String] = []
        for clip in try clips(options).present {
            let textID = String(clip.id.split(separator: "_")[1])
            guard seen.insert(textID).inserted else { continue }
            let transcript = try clip.text()
            let words = transcript.split(separator: " ").map(String.init)
            let state = try await synthesize(words, voice: voice)
            rate = state.sampleRate
            bufferFrames.merge(state.bufferFrames, uniquingKeysWith: +)
            var spans: [BaselineWord] = [], missing = 0
            for (index, word) in words.enumerated() {
                guard let start = state.bookmarks["s\(index)"], let end = state.bookmarks["e\(index)"] else {
                    missing += 1
                    continue
                }
                spans.append(BaselineWord(word: word, start: Double(start) / rate, end: Double(end) / rate))
            }
            let clipID = "tts_\(textID)"
            ids.append(clipID)
            phrases.append(MarkedPhrase(clipID: clipID, transcript: transcript, words: spans, wordsWithoutMarkers: missing))
            let format = try require(AVAudioFormat(standardFormatWithSampleRate: state.sampleRate, channels: 1), "an audio format")
            let buffer = try require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(state.samples.count)), "a buffer")
            buffer.frameLength = AVAudioFrameCount(state.samples.count)
            state.samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
            let file = try AVAudioFile(forWriting: corpus.appending(path: "\(clipID).wav"), settings: format.settings)
            try file.write(from: buffer)
            try Data((transcript + "\n").utf8).write(to: corpus.appending(path: "\(clipID).lab"))
        }
        let common = bufferFrames.max { $0.value < $1.value }?.key ?? 0
        try writeJSON(MarkerFile(voice: voiceID, sampleRate: rate, bufferFrames: common, phrases: phrases),
                      to: out.appending(path: "markers.json"))
        try Data((ids.joined(separator: "\n") + "\n").utf8).write(to: out.appending(path: "clips.txt"))
        print("tts-reference: \(phrases.count) phrases by \(voiceID) at \(Int(rate)) Hz, \(phrases.map(\.wordsWithoutMarkers).reduce(0, +)) words without markers → \(out.path)")
        return 0
    }

    // MARK: - reference-compare

    static func referenceCompare(_ options: Options) throws -> Int32 {
        let markers = try JSONDecoder().decode(MarkerFile.self, from: Data(contentsOf: try options.url("markers")))
        let baseline = try JSONDecoder().decode(WordBaseline.self, from: Data(contentsOf: try options.url("baseline")))
        let aligned = Dictionary(uniqueKeysWithValues: baseline.clips.map { ($0.clipID, $0.words) })
        let check = ReferenceCheck.compare(
            markers.phrases.map {
                ReferenceCheck.Clip(clipID: $0.clipID, transcript: $0.transcript, markers: $0.words,
                                    aligned: aligned[$0.clipID] ?? [])
            },
            voice: markers.voice,
            aligner: "\(baseline.aligner.name) \(baseline.aligner.version) (\(baseline.aligner.acousticModel))",
            markerResolutionMs: markers.sampleRate > 0 ? Double(markers.bufferFrames) / markers.sampleRate * 1000 : 0,
            wordsWithoutMarkers: markers.phrases.map(\.wordsWithoutMarkers).reduce(0, +))
        try writeJSON(check, to: try options.url("out"))
        print("reference-compare: \(check.line)")
        return 0
    }
}

/// Unwraps or fails the tool.
func require<T>(_ value: T?, _ what: String = "a value") throws -> T {
    guard let value else { throw ToolError.failed("missing \(what)") }
    return value
}
