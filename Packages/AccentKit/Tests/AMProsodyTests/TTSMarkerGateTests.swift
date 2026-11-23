// The synthetic gate (spec 07 Defaults): pinned phrases spoken by a pinned on-device English voice through
// `AVSpeechSynthesizer.write`, its word markers injected as `WordSpan`s with probability 1. Every reported word
// boundary must stay within 10 ms of its marker, and every word gets its dictionary syllable count. Audio is
// generated at test time and never written to disk; nothing is fetched. Without the voice (normal in CI) it skips.

import AMAlignment
import AMCore
import AMProsody
@preconcurrency import AVFoundation
import Foundation
import Synchronization
import Testing

extension SyllableSegmenterTests {
    @Suite("TTS marker gate") struct TTSMarkerGate {
        /// The pinned voice. Compact Samantha ships with macOS; CI runners usually have no voices at all.
        static let voiceIdentifier = "com.apple.voice.compact.en-US.Samantha"
        static var voiceInstalled: Bool { AVSpeechSynthesisVoice(identifier: voiceIdentifier) != nil }

        /// Pinned phrases and the pronunciations injected for them, one per word.
        static let phrases: [(text: String, arpabet: [String])] = [
            ("Record the photography lesson today.",
             ["R EH1 K ER0 D", "DH AH0", "F AH0 T AA1 G R AH0 F IY0", "L EH1 S AH0 N", "T AH0 D EY1"]),
            ("Please call Stella.", ["P L IY1 Z", "K AO1 L", "S T EH1 L AH0"]),
            ("The banana is yellow.", ["DH AH0", "B AH0 N AE1 N AH0", "IH1 Z", "Y EH1 L OW0"]),
        ]

        @Test("reported word boundaries stay within 10 ms of the injected TTS markers",
              .enabled(if: voiceInstalled, "no English voice: \(voiceIdentifier) is not installed"),
              arguments: phrases.indices)
        func markerGate(phrase: Int) async throws {
            let (text, arpabet) = Self.phrases[phrase]
            let speech = try await Self.speak(text)
            try #require(speech.wordStarts.count == arpabet.count, "\(text): one word marker per word")

            let duration = Double(speech.samples.count) / 16_000
            let edges = speech.wordStarts + [duration]
            var spans: [WordIndex: SyllableSegmenter.WordSpan] = [:]
            var pronunciations: [WordIndex: Pronunciation] = [:]
            var pairs: [AlignedWordPair] = []
            for index in arpabet.indices {
                let word = WordIndex(index)
                spans[word] = try SyllableSegmenter.WordSpan(start: edges[index], end: edges[index + 1], probability: 1)
                pronunciations[word] = try Pronunciation(arpabet: arpabet[index])
                pairs.append(.present(phrase: word, you: try TimeRange(start: edges[index], end: edges[index + 1])))
            }
            let input = SyllableSegmenter.Input(
                samples: speech.samples, sampleRate: 16_000, alignment: try WordAlignment(pairs: pairs),
                pronunciations: pronunciations, spans: spans, l0Key: "tts", transcriptRevision: 1)
            let result = try SyllableSegmenter(voicing: EnergyVoicing(thresholdDBFS: -45)).segment(input)

            #expect(result.words.count == arpabet.count)
            let worst = zip(result.words, zip(edges, edges.dropFirst())).map { word, span in
                max(abs(word.range.start - span.0), abs(word.range.end - span.1))
            }.max() ?? .infinity
            print("TTS marker gate [\(Self.voiceIdentifier)] \"\(text)\": \(result.words.count) words, "
                + "syllables \(result.words.map(\.syllables.count)), worst boundary deviation \(worst * 1000) ms")
            for (index, word) in result.words.enumerated() {
                #expect(abs(word.range.start - edges[index]) <= 0.010, "\(text) word \(index) start")
                #expect(abs(word.range.end - edges[index + 1]) <= 0.010, "\(text) word \(index) end")
                #expect(word.syllables.count == pronunciations[word.phraseWord]?.syllables.count, "\(text) word \(index)")
                #expect(word.syllables.first?.range.start == word.range.start)
                #expect(word.syllables.last?.range.end == word.range.end)
            }
        }

        // MARK: Synthesis

        struct Speech {
            /// 16 kHz mono.
            let samples: [Float]
            /// Word marker times in seconds.
            let wordStarts: [Double]
        }

        /// Collects buffers and word markers. Markers arrive through the delegate (the `toMarkerCallback` of
        /// `write` stays silent on macOS 26 voices); both may arrive on any queue, hence the mutex.
        final class Collector: NSObject, AVSpeechSynthesizerDelegate, Sendable {
            struct State {
                var samples: [Float] = []
                var sampleRate = 0.0
                var bytesPerFrame = 4.0
                var markerBytes: [Int] = []
                var finished: CheckedContinuation<Void, Never>?
                var done = false
            }

            let state = Mutex(State())

            func append(_ buffer: AVAudioBuffer) {
                guard let pcm = buffer as? AVAudioPCMBuffer, let channel = pcm.floatChannelData else { return }
                let frames = Array(UnsafeBufferPointer(start: channel[0], count: Int(pcm.frameLength)))
                state.withLock {
                    $0.sampleRate = pcm.format.sampleRate
                    $0.bytesPerFrame = Double(pcm.format.streamDescription.pointee.mBytesPerFrame)
                    $0.samples += frames
                }
            }

            func finish() {
                let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
                    state.done = true
                    defer { state.finished = nil }
                    return state.finished
                }
                continuation?.resume()
            }

            func wait() async {
                await withCheckedContinuation { continuation in
                    let resumeNow = state.withLock { state -> Bool in
                        if state.done { return true }
                        state.finished = continuation
                        return false
                    }
                    if resumeNow { continuation.resume() }
                }
            }

            func speechSynthesizer(
                _ synthesizer: AVSpeechSynthesizer, willSpeak marker: AVSpeechSynthesisMarker,
                utterance: AVSpeechUtterance
            ) {
                guard marker.mark == .word else { return }
                state.withLock { $0.markerBytes.append(marker.byteSampleOffset) }
            }

            func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
                finish()
            }

            func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
                finish()
            }
        }

        @MainActor static func speak(_ text: String) async throws -> Speech {
            let voice = try #require(AVSpeechSynthesisVoice(identifier: voiceIdentifier))
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            let synthesizer = AVSpeechSynthesizer()
            let collector = Collector()
            synthesizer.delegate = collector
            synthesizer.write(utterance, toBufferCallback: { collector.append($0) }, toMarkerCallback: { _ in })
            let timeout = Task {
                try? await Task.sleep(for: .seconds(20))
                collector.finish()
            }
            await collector.wait()
            timeout.cancel()
            withExtendedLifetime(synthesizer) {}

            let state = collector.state.withLock { $0 }
            try #require(state.sampleRate > 0 && !state.samples.isEmpty, "the voice produced no audio")
            let wordStarts = state.markerBytes.map { Double($0) / state.bytesPerFrame / state.sampleRate }
            return Speech(samples: resample(state.samples, from: state.sampleRate, to: 16_000), wordStarts: wordStarts)
        }

        /// Linear resampling; timing is what matters here, not fidelity.
        static func resample(_ samples: [Float], from source: Double, to target: Double) -> [Float] {
            let count = Int((Double(samples.count) * target / source).rounded(.down))
            return (0..<count).map { index in
                let position = Double(index) * source / target
                let lower = min(samples.count - 1, Int(position)), upper = min(samples.count - 1, lower + 1)
                let fraction = Float(position - Double(lower))
                return samples[lower] * (1 - fraction) + samples[upper] * fraction
            }
        }
    }
}
