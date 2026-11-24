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

    func gate(_ outcome: Outcome, _ set: String) -> DownstreamGate {
        switch outcome {
        case .pass: .compare([(WordVerdict(syllables: []), WordVerdict(syllables: []))], set: set, oracle: "o")
        case .fail:
            .compare([(WordVerdict(inconclusive: false, syllableCount: 2, longestSyllable: 0, loudestSyllable: 0),
                       WordVerdict(inconclusive: false, syllableCount: 1, longestSyllable: 0, loudestSyllable: 0))],
                     set: set, oracle: "o")
        case .notEvaluated: .notEvaluated(set: set, oracle: "o", reason: "waiting")
        }
    }

    @Test("decision (CTO 14:05): b2 is the aligner, whisper stays shipped, ship READY only with the gate and every prerequisite")
    func decision() {
        let met = [ShipDecision.Prerequisite("licence", "ok", met: true)]
        let missing = met + [.init("macos-26 latency", "NOT RUN", met: false)]
        func decide(_ a: Outcome, _ b: Outcome, _ prerequisites: [ShipDecision.Prerequisite]) -> ShipDecision.Result {
            ShipDecision.decide(gates: [gate(a, "Synthetic"), gate(b, "VCTK")], prerequisites: prerequisites,
                                candidate: "ctc-w2v2b960-1", shipped: "whisper")
        }
        for result in [decide(.pass, .pass, met), decide(.pass, .pass, missing), decide(.fail, .pass, met),
                       decide(.pass, .notEvaluated, met)] {
            #expect(result.shippedAligner == "whisper" && result.alignerOfRecord == "ctc-w2v2b960-1")
        }
        #expect(decide(.pass, .pass, met).ship == "READY")
        #expect(decide(.pass, .pass, missing).ship == "PENDING")
        #expect(decide(.pass, .fail, met).ship == "FAIL" && decide(.pass, .fail, met).gate == .fail)
        #expect(decide(.pass, .notEvaluated, met).ship == "PENDING" && decide(.pass, .notEvaluated, met).gate == .notEvaluated)
    }

    @Test("downstream gate: ≤ 2% of words differ and the inconclusive rate rises ≤ 2 points") func downstream() {
        let base = WordVerdict(inconclusive: false, syllableCount: 2, longestSyllable: 1, loudestSyllable: 0)
        var longer = base; longer.longestSyllable = 0
        var loud = base; loud.loudestSyllable = 1
        var low = base; low.inconclusive = true
        // 100 words: 2 differ (one by the longest syllable, one by inconclusive): exactly 2%, a 1-point rise. PASS.
        var pairs = Array(repeating: (oracle: base, candidate: base), count: 98)
        pairs += [(base, longer), (base, low)]
        let pass = DownstreamGate.compare(pairs, set: "VCTK", oracle: "MFA")
        #expect(pass.words == 100 && pass.differing == 2 && pass.diffShare == 0.02)
        #expect(pass.differingParts == ["longestSyllable": 1, "inconclusive": 1])
        #expect(pass.riseInconclusivePoints == 0.01 && pass.outcome == .pass)
        // A third differing word: 3% FAIL on verdicts.
        let more = DownstreamGate.compare(pairs.dropLast(3) + [(base, longer), (base, loud), (base, low)] + [(base, base)],
                                          set: "VCTK", oracle: "MFA")
        #expect(more.differing == 3 && more.diffOutcome == .fail && more.outcome == .fail)
        // Inconclusive rising 3 points with the verdict share at 3% fails both lines; a fall never fails the rise.
        let rise = DownstreamGate.compare(Array(repeating: (base, base), count: 97) + Array(repeating: (base, low), count: 3),
                                          set: "S", oracle: "TTS")
        #expect(rise.riseOutcome == .fail && rise.riseInconclusivePoints == 0.03)
        let fall = DownstreamGate.compare(Array(repeating: (base, base), count: 99) + [(low, base)], set: "S", oracle: "TTS")
        #expect(fall.riseOutcome == .pass && fall.diffOutcome == .pass)
        #expect(DownstreamGate.compare([], set: "S", oracle: "TTS").outcome == .notEvaluated)
    }

    @Test("a word verdict takes the first longest and first loudest syllable; any low syllable makes it inconclusive")
    func wordVerdict() {
        let v = WordVerdict(syllables: [(0.1, -20, false), (0.3, -10, false), (0.3, -10, true)])
        #expect(v == WordVerdict(inconclusive: true, syllableCount: 3, longestSyllable: 1, loudestSyllable: 1))
        #expect(WordVerdict(syllables: []) == WordVerdict(inconclusive: false, syllableCount: 0, longestSyllable: nil, loudestSyllable: nil))
    }

    @Test("quadrature estimate: sqrt(max(0, obs² − ref²)), never negative") func quadrature() {
        #expect(ReferenceErrors.quadrature(obs: 50, ref: 30) == 40)
        #expect(ReferenceErrors.quadrature(obs: 20, ref: 30) == 0)
        #expect(ReferenceErrors.quadrature(obs: nil, ref: 30) == nil)
        let side = ReferenceCheck.Side(signedErrorsMs: [-50, 50, 10], toleranceMs: 80)
        let errors = ReferenceErrors(
            mfaOnTTS: .init(label: "MFA", starts: .init(signedErrorsMs: [30], toleranceMs: 80), ends: .init(signedErrorsMs: [-30], toleranceMs: 80)),
            b2OnTTS: nil, b2VsMFAOnVCTK: .init(label: "b2", starts: side, ends: side), voice: nil, markerResolutionMs: nil, notes: [])
        #expect(errors.quadratureStartsMs == 40 && errors.quadratureEndsMs == 40)
        #expect(errors.markdown(toleranceMs: 80).joined().contains("estimate"))
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
