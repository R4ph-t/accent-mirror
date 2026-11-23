// Synthetic takes for the segmenter tests, generated in test code: syllable envelopes over voiced harmonic carriers,
// with the word spans and syllable boundaries they were built from as truth.

import AMAlignment
import AMCore
import AMProsody
import Foundation

/// Voicing by frame energy: a frame is voiced when its RMS is above `thresholdDBFS`. Good enough for carriers that
/// are voiced wherever they are loud.
struct EnergyVoicing: VoicingSource {
    var thresholdDBFS = -35.0
    var id: String { "test-energy" }

    func voicedFrames(samples: [Float], sampleRate: Double) -> [Bool] {
        let hop = Int((sampleRate * voicingFrameDuration).rounded())
        return stride(from: 0, to: samples.count, by: hop).map { start in
            let frame = samples[start..<min(samples.count, start + hop)]
            let power = frame.reduce(0) { $0 + Double($1) * Double($1) } / Double(frame.count)
            return 10 * log10(max(power, 1e-12)) > thresholdDBFS
        }
    }
}

/// One synthetic word: its pronunciation and its syllables' edges in seconds.
struct SyntheticWord {
    let text: String
    let arpabet: String
    /// Syllable edges: `edges[0]` is the word start, `edges.last` its end.
    let edges: [Double]
    var probability = 1.0
    /// Amplitude multiplier over the word, given the time and the syllable index; nil uses one raised-cosine bump
    /// per syllable.
    var shape: (@Sendable (_ time: Double, _ syllable: Int, _ edges: [Double]) -> Double)? = nil

    var start: Double { edges.first! }
    var end: Double { edges.last! }
    var pronunciation: Pronunciation { try! Pronunciation(arpabet: arpabet) }
}

struct SyntheticTake {
    static let sampleRate = 16_000.0
    let words: [SyntheticWord]
    let duration: Double
    /// Phrase words heard as something else: kept as `substituted` in the alignment.
    var substituted: Set<Int> = []

    /// Harmonic carrier at 120 Hz (five harmonics) under each syllable's envelope; silence elsewhere.
    var samples: [Float] {
        let count = Int(duration * Self.sampleRate)
        var samples = [Float](repeating: 0, count: count)
        for word in words {
            let first = max(0, Int(word.start * Self.sampleRate)), last = min(count, Int(word.end * Self.sampleRate))
            for index in first..<last {
                let time = Double(index) / Self.sampleRate
                let syllable = max(0, (word.edges.lastIndex { $0 <= time } ?? 0)).clamped(to: 0...(word.edges.count - 2))
                let amplitude = word.shape?(time, syllable, word.edges) ?? Self.bump(time, syllable, word.edges)
                let carrier = (1...5).reduce(0.0) { sum, harmonic in
                    sum + sin(2 * .pi * 120 * Double(harmonic) * time) / Double(harmonic)
                }
                samples[index] = Float(0.25 * amplitude * carrier)
            }
        }
        return samples
    }

    /// A raised-cosine bump over the syllable: zero at its edges, one at its middle.
    static func bump(_ time: Double, _ syllable: Int, _ edges: [Double]) -> Double {
        let start = edges[syllable], end = edges[syllable + 1]
        let phase = (time - start) / (end - start)
        return 0.5 - 0.5 * cos(2 * .pi * phase)
    }

    var alignment: WordAlignment {
        try! WordAlignment(pairs: words.indices.map { index in
            let range = try! TimeRange(start: words[index].start, end: words[index].end)
            return substituted.contains(index)
                ? .substituted(phrase: WordIndex(index), heard: "uh", you: range)
                : .present(phrase: WordIndex(index), you: range)
        })
    }

    var input: SyllableSegmenter.Input {
        SyllableSegmenter.Input(
            samples: samples, sampleRate: Self.sampleRate, alignment: alignment,
            pronunciations: Dictionary(uniqueKeysWithValues: words.indices.filter { !substituted.contains($0) }.map {
                (WordIndex($0), words[$0].pronunciation)
            }),
            spans: Dictionary(uniqueKeysWithValues: words.indices.map {
                (WordIndex($0), try! SyllableSegmenter.WordSpan(
                    start: words[$0].start, end: words[$0].end, probability: words[$0].probability))
            }),
            l0Key: "test-l0", transcriptRevision: 1)
    }

    func segment(thresholds: Thresholds = .current) throws -> SyllableSegmentation {
        try SyllableSegmenter(voicing: EnergyVoicing(), thresholds: thresholds).segment(input)
    }

    /// The 3 s pulse train: "record the photography | lesson | today", with a 200 ms pause after "photography" and a
    /// 100 ms pause after "lesson".
    static let pulseTrain = SyntheticTake(words: [
        SyntheticWord(text: "record", arpabet: "R EH1 K ER0 D", edges: [0.10, 0.30, 0.55]),
        SyntheticWord(text: "the", arpabet: "DH AH0", edges: [0.55, 0.70]),
        SyntheticWord(text: "photography", arpabet: "F AH0 T AA1 G R AH0 F IY0", edges: [0.70, 0.88, 1.10, 1.25, 1.45]),
        SyntheticWord(text: "lesson", arpabet: "L EH1 S AH0 N", edges: [1.65, 1.85, 2.05]),
        SyntheticWord(text: "today", arpabet: "T AH0 D EY1", edges: [2.15, 2.35, 2.70]),
    ], duration: 3.0)
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
