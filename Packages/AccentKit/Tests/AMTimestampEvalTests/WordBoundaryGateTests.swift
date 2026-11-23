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

@Suite("Reference sanity check (CTO review)")
struct ReferenceCheckTests {
    @Test("per side: MFA minus the marker gives the median, the share within 80 ms and the mean signed error")
    func perSideFigures() throws {
        let markers = [BaselineWord(word: "Please", start: 0.10, end: 0.40),
                       BaselineWord(word: "call", start: 0.40, end: 0.60),
                       BaselineWord(word: "Stella.", start: 0.60, end: 1.00)]
        // Starts off by −20, +30, −100 ms; ends by −40, +10, −200 ms.
        let aligned = [BaselineWord(word: "please", start: 0.08, end: 0.36),
                       BaselineWord(word: "call", start: 0.43, end: 0.61),
                       BaselineWord(word: "stella", start: 0.50, end: 0.80)]
        let check = ReferenceCheck.compare(
            [.init(clipID: "tts_001", transcript: "Please call Stella.", markers: markers, aligned: aligned)],
            voice: "v", aligner: "MFA", markerResolutionMs: 11.6)
        #expect(check.phraseTokens == 3 && check.starts.n == 3 && check.ends.n == 3)
        #expect(check.starts.medianAbsErrorMs == 30)
        #expect(try #require(check.starts.shareWithinTolerance) == 2.0 / 3)
        #expect(abs(try #require(check.starts.meanSignedErrorMs) - (-30)) < 1e-9)
        #expect(check.ends.medianAbsErrorMs == 40)
        #expect(abs(try #require(check.ends.meanSignedErrorMs) - (-230.0 / 3)) < 1e-9)
        // "Stella." ends with punctuation, so the no-punctuation ends are the first two.
        #expect(check.endsWithoutPunctuation.n == 2)
        #expect(check.endsWithoutPunctuation.shareWithinTolerance == 1)
        #expect(check.line.contains("not a gate") && check.line.contains("11.6 ms"))
    }

    @Test("a word MFA did not align is left out of both sides") func unalignedWord() {
        let markers = [BaselineWord(word: "a", start: 0, end: 0.2), BaselineWord(word: "b", start: 0.2, end: 0.4)]
        let check = ReferenceCheck.compare(
            [.init(clipID: "tts_001", transcript: "a b", markers: markers, aligned: [BaselineWord(word: "a", start: 0, end: 0.2)])],
            voice: "v", aligner: "MFA", markerResolutionMs: 11.6)
        #expect(check.starts.n == 1 && check.ends.n == 1 && check.phraseTokens == 2)
    }
}
