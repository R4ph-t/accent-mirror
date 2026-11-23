import AMAlignment
import AMTimestampEval
import Foundation
import Testing

/// Baseline words at fixed times, and ASR words derived from them by a per-word shift of start and end.
func clip(_ id: String, _ transcript: String, shifts: [(start: Double, end: Double, p: Double)]) -> ClipInput {
    let tokens = transcript.split(separator: " ").map(String.init)
    let baseline = tokens.enumerated().map { i, word in
        BaselineWord(word: word.lowercased(), start: Double(i) * 0.5, end: Double(i) * 0.5 + 0.4)
    }
    let asr = zip(tokens, baseline).enumerated().compactMap { i, pair -> WordTimestamp? in
        guard i < shifts.count else { return nil }
        let (word, b) = pair
        return WordTimestamp(word: " \(word)", start: b.start + shifts[i].start, end: b.end + shifts[i].end,
                             probability: shifts[i].p)
    }
    return ClipInput(clipID: id, transcript: transcript, asrWords: asr, baselineWords: baseline)
}

@Suite("Tokens")
struct TokenTests {
    @Test("Phrase tokens strip punctuation, ignore case and collapse whitespace")
    func phraseTokens() {
        #expect(Tokens.phraseTokens(of: "Please call Stella.") == ["please", "call", "stella"])
        #expect(Tokens.phraseTokens(of: "Ask her  to bring  these things.") == ["ask", "her", "to", "bring", "these", "things"])
        #expect(Tokens.phraseTokens(of: "Stella's, - snow-peas!") == ["stellas", "snowpeas"])
        #expect(Tokens.normalize("  Bob.") == "bob")
    }

    @Test("Words match tokens in order; extra, missing and punctuation-only words are skipped")
    func inOrderMatch() {
        let tokens = ["please", "call", "stella", "now"]
        #expect(Tokens.match(tokens: tokens, words: [" Please,", " uh", " Stella.", "", " now"]) == [0, nil, 2, 4])
        #expect(Tokens.match(tokens: tokens, words: ["now", "please"]) == [0, nil, nil, nil]
            || Tokens.match(tokens: tokens, words: ["now", "please"]) == [nil, nil, nil, 0])
        #expect(Tokens.match(tokens: tokens, words: ["...", "-"]) == [nil, nil, nil, nil])
        #expect(Tokens.match(tokens: ["the", "cat", "the"], words: ["the", "the"]).compactMap { $0 } == [0, 1])
    }
}

@Suite("Word-boundary evaluation")
struct EvaluationTests {
    @Test("Spans 80 ms too narrow on each side pass once padded, and the raw figures are reported too")
    func paddedGatePasses() {
        let shifts = Array(repeating: (start: 0.08, end: -0.08, p: 0.9), count: 4)
        let result = Evaluation.evaluate([clip("p225_002", "a b c d", shifts: shifts)])
        #expect(result.padded.boundaries == 8)
        #expect(abs(result.padded.medianErrorMs! - 0) < 1e-6)
        #expect(result.padded.shareWithinTolerance == 1)
        #expect(abs(result.raw.medianErrorMs! - 80) < 1e-6)
        #expect(result.medianOutcome == .pass)
        #expect(result.shareOutcome == .pass)
    }

    @Test("Exact raw spans are 80 ms off once padded, so the 40 ms median bar fails")
    func exactSpansFailPaddedMedian() {
        let result = Evaluation.evaluate([clip("p225_002", "a b c d", shifts: Array(repeating: (0, 0, 0.9), count: 4))])
        #expect(abs(result.padded.medianErrorMs! - 80) < 1e-6)
        #expect(result.padded.shareWithinTolerance == 1)
        #expect(result.raw.medianErrorMs == 0)
        #expect(result.medianOutcome == .fail)
        #expect(result.outcome == .fail)
    }

    @Test("The share bar counts boundaries within 80 ms against 85%")
    func shareBar() {
        // Padded errors: 4 boundaries at 0 ms, 2 boundaries at 100 ms → 4 / 6 within.
        let shifts = [(0.08, -0.08, 0.9), (0.08, -0.08, 0.9), (0.18, 0.02, 0.9)]
        let result = Evaluation.evaluate([clip("p225_002", "a b c", shifts: shifts.map { ($0.0, $0.1, $0.2) })])
        #expect(result.padded.shareWithinTolerance == 4.0 / 6.0)
        #expect(result.shareOutcome == .fail)
    }

    @Test("Coverage counts tokens missing from either side and skips them")
    func coverage() {
        var input = clip("p225_002", "a b c d", shifts: Array(repeating: (0.08, -0.08, 0.9), count: 3))
        input.baselineWords.remove(at: 0)
        let result = Evaluation.evaluate([input])
        #expect(result.coverage.phraseTokens == 4)
        #expect(result.coverage.comparable == 2)
        #expect(result.coverage.missingFromBaselineOnly == 1)
        #expect(result.coverage.missingFromASROnly == 1)
        #expect(result.padded.boundaries == 4)
    }

    @Test("Calibration passes when low-probability words have more error than high-probability words")
    func calibrationPasses() {
        let shifts = [(0.08, -0.08, 0.99), (0.08, -0.08, 0.95), (0.2, -0.2, 0.4), (0.3, -0.3, 0.3)]
        let result = Evaluation.evaluate([clip("p225_002", "a b c d", shifts: shifts.map { ($0.0, $0.1, $0.2) })])
        #expect(result.calibration.low.words == 2)
        #expect(result.calibration.high.words == 2)
        #expect(result.calibration.outcome == .pass)
    }

    @Test("Calibration fails when high-probability words have more error")
    func calibrationFails() {
        let shifts = [(0.3, -0.3, 0.99), (0.2, -0.2, 0.95), (0.08, -0.08, 0.4), (0.08, -0.08, 0.3)]
        let result = Evaluation.evaluate([clip("p225_002", "a b c d", shifts: shifts.map { ($0.0, $0.1, $0.2) })])
        #expect(result.calibration.outcome == .fail)
        #expect(result.outcome == .fail)
    }

    @Test("Calibration with an empty bin is NOT EVALUATED, and that is not a pass")
    func calibrationEmptyBin() {
        let result = Evaluation.evaluate([clip("p225_002", "a b c d", shifts: Array(repeating: (0.08, -0.08, 0.9), count: 4))])
        #expect(result.calibration.low.words == 0)
        #expect(result.calibration.outcome == .notEvaluated)
        #expect(result.outcome == .notEvaluated)
    }

    @Test("Nothing comparable means NOT EVALUATED, never PASS")
    func nothingComparable() {
        let result = Evaluation.evaluate([clip("p225_002", "a b", shifts: [])])
        #expect(result.padded.boundaries == 0)
        #expect(result.medianOutcome == .notEvaluated)
        #expect(result.outcome == .notEvaluated)
        #expect(Outcome.combine([.pass, .notEvaluated]) == .notEvaluated)
        #expect(Outcome.combine([.notEvaluated, .fail]) == .fail)
        #expect(Outcome.combine([]) == .notEvaluated)
    }

    @Test("Per-voice and per-phrase breakdowns group by speaker and text ID")
    func breakdowns() {
        let shifts = Array(repeating: (start: 0.08, end: -0.08, p: 0.9), count: 2)
        let result = Evaluation.evaluate([
            clip("p225_002", "a b", shifts: shifts), clip("p226_002", "a b", shifts: shifts),
            clip("p226_003", "a b", shifts: shifts),
        ])
        #expect(result.perVoice.map(\.key) == ["p225", "p226"])
        #expect(result.perVoice.map(\.padded.boundaries) == [4, 8])
        #expect(result.perPhrase.map(\.key) == ["002", "003"])
    }

    @Test("Median and nearest-rank percentile")
    func statistics() {
        #expect(Statistics.median([3, 1, 2]) == 2)
        #expect(Statistics.median([4, 1, 3, 2]) == 2.5)
        #expect(Statistics.median([]) == nil)
        #expect(Statistics.percentile(Array(1...10).map(Double.init), 90) == 9)
    }
}
