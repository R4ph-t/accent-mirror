import AMTimestampEval
import Testing

@Suite("Spec 23 gate diagnostics")
struct VerdictDiagnosticsTests {
    static func verdict(_ syllables: Int, longest: Int = 0, loudest: Int = 0, inconclusive: Bool = false) -> WordVerdict {
        WordVerdict(inconclusive: inconclusive, syllableCount: syllables, longestSyllable: longest, loudestSyllable: loudest)
    }

    /// Five words: one unchanged, one duration flip, one intensity+duration flip, one turned inconclusive by the
    /// confidence gate only, one turned inconclusive with or without the gate.
    static let words: [DiagnosticWord] = [
        DiagnosticWord(clipID: "a", word: "cat", oracle: verdict(1), candidate: verdict(1), boundaryErrorMs: 10),
        DiagnosticWord(clipID: "a", word: "table", oracle: verdict(2), candidate: verdict(2, longest: 1),
                       boundaryErrorMs: 20),
        DiagnosticWord(clipID: "a", word: "banana", oracle: verdict(3), candidate: verdict(3, longest: 1, loudest: 1),
                       boundaryErrorMs: 30),
        DiagnosticWord(clipID: "b", word: "telephone", oracle: verdict(3), candidate: verdict(3, inconclusive: true),
                       candidateUngated: verdict(3), boundaryErrorMs: 100, gatedByConfidence: true),
        DiagnosticWord(clipID: "b", word: "university", oracle: verdict(5), candidate: verdict(5, inconclusive: true),
                       boundaryErrorMs: 400),
    ]

    @Test("The diff counts flipped words and each differing part, as the gate does")
    func diff() {
        let d = VerdictDiagnostics.diff(Self.words)
        #expect(d.words == 5)
        #expect(d.differing == 4)
        #expect(d.parts == ["longestSyllable": 2, "loudestSyllable": 1, "inconclusive": 2])
        #expect(d.oracleInconclusive == 0 && d.candidateInconclusive == 2)
        #expect(d.risePoints == 40)
        let pairs = Self.words.map { (oracle: $0.oracle, candidate: $0.candidate) }
        let gate = DownstreamGate.compare(pairs, set: "s", oracle: "o")
        #expect(gate.differing == d.differing && gate.differingParts == d.parts)
    }

    @Test("Cues count every differing part and the sole one; pitch is not a part")
    func cues() {
        let c = VerdictDiagnostics.cues(Self.words)
        #expect(c.flipped == 4)
        #expect(c.sole == ["longestSyllable": 1, "inconclusive": 2])
        #expect(c.pitch == "pitch: not a verdict part in spec 07")
    }

    @Test("Bins by syllable count, transition and boundary error")
    func bins() {
        #expect(VerdictDiagnostics.bySyllableCount(Self.words).map { [$0.words, $0.flipped] }
                == [[1, 0], [1, 1], [2, 2], [1, 1]])
        let transitions = VerdictDiagnostics.byTransition(Self.words)
        #expect(transitions.map(\.flipped) == [2, 2])
        #expect(transitions.allSatisfy { $0.words == 4 })
        // Upper edges inclusive: 10 and 20 in the first bin, 30 in the second, 100 in (80, 160], 400 over 160.
        #expect(VerdictDiagnostics.byBoundaryError(Self.words).map { [$0.words, $0.flipped] }
                == [[2, 1], [1, 1], [0, 0], [1, 1], [1, 1]])
    }

    @Test("The inconclusive rise splits into the confidence gate's share and the margins'")
    func inconclusiveSplit() {
        let s = VerdictDiagnostics.inconclusiveSplit(Self.words)
        #expect(s.fullRiseWords == 2 && s.fromGateWords == 1 && s.fromMarginsWords == 1)
        #expect(s.fullRisePoints == 40 && s.fromGatePoints == 20 && s.fromMarginsPoints == 20)
        #expect(s.gatedWords == 1)
    }

    @Test("Unmatched phrase words are substituted when an unmatched recogniser word fills the gap, else deleted")
    func unmatched() {
        // Phrase "a b c d"; recogniser "a x c" (b substituted by x, d deleted).
        let matches = Tokens.match(tokens: ["a", "b", "c", "d"], words: ["a", "x", "c"])
        let counts = VerdictDiagnostics.unmatched(matches: matches, eligible: [true, true, true, true], recognised: 3)
        #expect(counts.substituted == 1 && counts.deleted == 1)
        // Not eligible (no oracle span or pronunciation): not counted.
        let none = VerdictDiagnostics.unmatched(matches: matches, eligible: [true, false, true, false], recognised: 3)
        #expect(none.substituted == 0 && none.deleted == 0)
    }
}
