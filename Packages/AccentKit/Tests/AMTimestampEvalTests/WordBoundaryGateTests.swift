import AMAlignment
import AMCore
import AMTimestampEval
import Foundation
import Testing

@Suite("Spec 23 gate")
struct WordBoundaryGateTests {
    @Test("Pearson's r on known points") func pearson() throws {
        #expect(try #require(CorrelationGate.pearson([(1, 2), (2, 4), (3, 6)])) == 1)
        #expect(try #require(CorrelationGate.pearson([(1, 3), (2, 2), (3, 1)])) == -1)
        #expect(CorrelationGate.pearson([(1, 1), (2, 1), (3, 1)]) == nil)
        #expect(CorrelationGate.pearson([(1, 1), (2, 2)]) == nil)
    }

    /// Syllables of `clips` clips; `snapCoupling` makes the snapped duration follow intensity.
    func syllables(clips: Int, snapCoupling: Double, seed: UInt64) -> [CorrelationGate.Syllable] {
        var rng = SeededGenerator(seed: seed)
        return (0..<clips).flatMap { clip in
            (0..<8).map { _ in
                let duration = Double.random(in: 0.08...0.3, using: &rng)
                let intensity = Double.random(in: -40 ... -10, using: &rng)
                let snapped = duration + snapCoupling * (intensity + 25) / 100
                return CorrelationGate.Syllable(clipID: "c\(clip)", whisper: (duration, intensity),
                                                snapped: (snapped, intensity))
            }
        }
    }

    @Test("Δr gate: no extra coupling passes, coupling added by snapping fails, and the seed reproduces it")
    func correlationGate() {
        let same = CorrelationGate.evaluate(syllables(clips: 30, snapCoupling: 0, seed: 1), resamples: 500, seed: 7)
        #expect(same.outcome == .pass)
        #expect(same.deltaR == 0)
        let coupled = CorrelationGate.evaluate(syllables(clips: 30, snapCoupling: 0.5, seed: 1), resamples: 500, seed: 7)
        #expect(coupled.outcome == .fail)
        #expect((coupled.ciLower ?? 0) > 0)
        let again = CorrelationGate.evaluate(syllables(clips: 30, snapCoupling: 0.5, seed: 1), resamples: 500, seed: 7)
        #expect(again == coupled)
        #expect(CorrelationGate.evaluate([], seed: 7).outcome == .notEvaluated)
    }

    @Test("decision: the simplest aligner that passes ships; NOT EVALUATED is not a pass") func decision() {
        func decide(_ b1Bar: Outcome, _ b1Corr: Outcome, _ b2: Outcome?) -> BoundaryDecision.Result {
            BoundaryDecision.decide(b1Bar: b1Bar, b1Correlation: b1Corr, b2Bar: b2, b1ID: "dsp-snap-1",
                                    b2ID: "ctc-w2v2b960-1", fallbackID: "whisper")
        }
        #expect(decide(.pass, .pass, .pass).shippedAligner == "dsp-snap-1")
        #expect(decide(.pass, .notEvaluated, .pass).shippedAligner == "ctc-w2v2b960-1")
        #expect(decide(.pass, .notEvaluated, nil).shippedAligner == "whisper")
        #expect(decide(.fail, .pass, .pass).shippedAligner == "ctc-w2v2b960-1")
        let none = decide(.fail, .notEvaluated, .fail)
        #expect(none.shippedAligner == "whisper" && none.outcome == .fail)
    }

    @Test("the bar fails when any speaker misses a side, even if the pooled sides pass") func perSpeakerBar() throws {
        func clip(_ id: String, offset: Double) -> ClipInput {
            let base = (0..<10).map { BaselineWord(word: "w\($0)", start: Double($0), end: Double($0) + 0.5) }
            let asr = base.map { WordTimestamp(word: $0.word, start: $0.start + offset, end: $0.end + offset, probability: 0.9) }
            return ClipInput(clipID: id, transcript: base.map(\.word).joined(separator: " "), asrWords: asr, baselineWords: base)
        }
        // Eight speakers within 10 ms, one 200 ms off: pooled sides pass, p9 fails.
        let clips = (1...8).map { clip("p\($0)_001", offset: 0.01) } + [clip("p9_001", offset: 0.2)]
        let bar = BoundaryBar(Evaluation.evaluate(clips))
        #expect(bar.starts == .pass && bar.ends == .pass)
        #expect(bar.failingSpeakers == ["p9"])
        #expect(bar.outcome == .fail)
    }
}
