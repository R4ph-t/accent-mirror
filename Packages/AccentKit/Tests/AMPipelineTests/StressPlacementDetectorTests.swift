import AMAlignment
import AMCore
import AMPipeline
import AMProsody
import Foundation
import Testing

/// The shared-detector stages end to end on a synthetic voiced take of "a new record" (no ASR: word timings given).
@Suite("StressPlacementDetectorTests") struct StressPlacementDetectorTests {
    struct Syllable {
        let start: Double
        let end: Double
        let amplitude: Float
        let f0: Double
    }

    /// A harmonic tone per syllable with raised-cosine edges and short silences between syllables.
    static func render(_ syllables: [Syllable], duration: Double, rate: Double = 16_000) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(duration * rate))
        for s in syllables {
            let first = Int(s.start * rate), last = min(samples.count, Int(s.end * rate))
            var phase = 0.0
            for i in first..<last {
                let t = Double(i - first) / rate, length = s.end - s.start
                let edge = min(1, t / 0.02, (length - t) / 0.02)
                phase += 2 * .pi * s.f0 / rate
                let tone = sin(phase) + 0.5 * sin(2 * phase) + 0.25 * sin(3 * phase)
                samples[i] = s.amplitude * Float(max(0, edge) * tone / 1.75)
            }
        }
        return samples
    }

    static let noun = try! Pronunciation(arpabet: "R EH1 K ER0 D")

    /// "a new record" with "record" stressed on its second syllable (verb stress), words heard as given.
    static func take(heardProbability: Double = 0.95, dropRecord: Bool = false) -> PlacementTake {
        let syllables = [
            Syllable(start: 0.20, end: 0.30, amplitude: 0.10, f0: 140),  // a
            Syllable(start: 0.36, end: 0.56, amplitude: 0.20, f0: 150),  // new
            Syllable(start: 0.66, end: 0.76, amplitude: 0.06, f0: 130),  // re
            Syllable(start: 0.80, end: 1.10, amplitude: 0.30, f0: 190),  // CORD
        ]
        let heard = [
            WordTimestamp(word: " a", start: 0.20, end: 0.30, probability: heardProbability),
            WordTimestamp(word: " new", start: 0.36, end: 0.56, probability: heardProbability),
        ] + (dropRecord ? [] : [WordTimestamp(word: " record.", start: 0.66, end: 1.10, probability: heardProbability)])
        let words = [
            PlacementTake.Word(index: WordIndex(0), text: "a", pronunciation: try! Pronunciation(arpabet: "AH0"), accepted: nil),
            PlacementTake.Word(index: WordIndex(1), text: "new", pronunciation: try! Pronunciation(arpabet: "N UW1"), accepted: nil),
            PlacementTake.Word(index: WordIndex(2), text: "record", pronunciation: noun, accepted: [0]),
        ]
        return PlacementTake(
            samples: render(syllables, duration: 1.4), words: words, heard: heard, l0Key: "synthetic")
    }

    @Test("verb stress on the noun 'record' is flagged before and after suppression") func flagged() async throws {
        let analysis = try await StressPlacementDetector.bundled().analyse(Self.take())
        #expect(analysis.segmentation.syllables.count == 4)
        let record = try #require(analysis.words.first)
        #expect(analysis.words.count == 1, "only words with an A(w) are decided")
        #expect(record.present)
        #expect(record.observed?.primary == 1)
        #expect(record.flaggedBeforeSuppression)
        #expect(record.flaggedAfterSuppression, "suppressed by \(String(describing: record.suppression))")
    }

    @Test("the same take accepted as verb stress is not flagged") func accepted() async throws {
        var take = Self.take()
        take.words[2] = PlacementTake.Word(index: WordIndex(2), text: "record", pronunciation: Self.noun, accepted: [0, 1])
        let record = try #require(try await StressPlacementDetector.bundled().analyse(take).words.first)
        #expect(!record.flaggedBeforeSuppression && !record.flaggedAfterSuppression)
    }

    @Test("low ASR confidence: counted before, suppressed after") func lowConfidence() async throws {
        let analysis = try await StressPlacementDetector.bundled().analyse(Self.take(heardProbability: 0.2))
        let record = try #require(analysis.words.first)
        #expect(analysis.segmentation.timing == .poor)
        #expect(record.flaggedBeforeSuppression)
        #expect(!record.flaggedAfterSuppression)
        #expect(record.suppression == .poorTiming)
    }

    @Test("a word the recogniser did not hear is not present and never flagged") func missingWord() async throws {
        let record = try #require(try await StressPlacementDetector.bundled().analyse(Self.take(dropRecord: true)).words.first)
        #expect(!record.present)
        #expect(record.decision == nil)
        #expect(!record.flaggedAfterSuppression)
    }
}
