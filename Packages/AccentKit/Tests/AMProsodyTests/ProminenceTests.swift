import AMCore
import AMProsody
import Foundation
import Testing

/// The worked examples of `tools/worked_examples.py` (plan §2), reproduced to 2 decimals.
@Suite("ProminenceTests") struct ProminenceTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let syllables: [ComparableSyllable]
        /// The word "photography" is phrase word `word`, its last four syllables.
        let word: WordIndex
        let p16: [Double]
        let primary16: Int
        let margin16: Double
        let confidence16: Confidence
        let p10: [Double]
        let primary10: Int
        let margin10: Double
        let confidence10: Confidence
        /// C and W (as a percentage) with S = {tog}, U = {pho, ra, phy}.
        let contrast: Double
        let weakLength: Double
        var testDescription: String { name }
    }

    static let pho = 0, tog = 1, phy = 3

    /// One word, last syllable exposed (the script's `word()`), every syllable at high confidence.
    static func word(
        _ durations: [Double], _ energies: [Double], _ pitches: [Double?], index: Int = 0, final: Bool = true
    ) -> [ComparableSyllable] {
        durations.indices.map { i in
            ComparableSyllable(
                word: WordIndex(index), indexInWord: i,
                features: ProminenceFeatures(
                    duration: durations[i], energyDBFS: energies[i], peakSemitones: pitches[i],
                    lengtheningExposed: final && i == durations.count - 1),
                level: .high)
        }
    }

    static let cases: [Case] = [
        Case(
            name: "A model 'photography'", syllables: word([0.10, 0.20, 0.08, 0.12], [-24, -18, -27, -26], [1, 6, -1, -2]),
            word: WordIndex(0),
            p16: [-0.07, 1.65, -0.75, -0.83], primary16: tog, margin16: 1.72, confidence16: .high,
            p10: [-0.21, 1.61, -0.93, -0.46], primary10: tog, margin10: 1.82, confidence10: .high,
            contrast: 4.19, weakLength: 50.0),
        Case(
            name: "B you, PHO", syllables: word([0.20, 0.14, 0.10, 0.12], [-19, -22, -25, -25], [5, 2, 0, -1]),
            word: WordIndex(0),
            p16: [1.46, 0.32, -0.67, -1.11], primary16: pho, margin16: 1.14, confidence16: .high,
            p10: [1.52, 0.21, -0.94, -0.79], primary10: pho, margin10: 1.31, confidence10: .high,
            contrast: 1.65, weakLength: 85.7),
        Case(
            name: "C as B, 'ra' unvoiced", syllables: word([0.20, 0.14, 0.10, 0.12], [-19, -22, -25, -25], [5, 2, nil, -1]),
            word: WordIndex(0),
            p16: [1.37, 0.26, -0.68, -1.15], primary16: pho, margin16: 1.12, confidence16: .high,
            p10: [1.43, 0.14, -1.07, -0.83], primary10: pho, margin10: 1.29, confidence10: .high,
            contrast: 1.65, weakLength: 85.7),
        Case(
            name: "D flat", syllables: word([0.15, 0.15, 0.15, 0.15], [-22, -22, -22, -22], [0, 0.2, 0, -0.2]),
            word: WordIndex(0),
            p16: [0.23, 0.29, 0.23, -0.75], primary16: tog, margin16: 0.06, confidence16: .low,
            p10: [0.00, 0.06, 0.00, -0.06], primary10: tog, margin10: 0.06, confidence10: .low,
            contrast: 1.0, weakLength: 100.0),
        Case(
            name: "E native 'I love photography.'",
            syllables: word([0.09], [-22], [1], index: 0, final: false) + word([0.20], [-18], [3], index: 1, final: false)
                + word([0.10, 0.18, 0.08, 0.28], [-24, -21, -27, -20], [0, 2, -1, 1], index: 2),
            word: WordIndex(2),
            p16: [-0.71, 0.70, -1.50, 0.54], primary16: tog, margin16: 0.16, confidence16: .low,
            p10: [-0.72, 0.56, -1.46, 0.81], primary10: phy, margin10: 0.25, confidence10: .medium,
            contrast: 2.54, weakLength: 55.6),
    ]

    static func near(_ value: Double?, _ expected: Double, places: Double = 2) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.5 * pow(10, -places) + 1e-9
    }

    @Test("A–E at λ = 1.6 reproduce the worked examples", arguments: cases)
    func discounted(_ example: Case) throws {
        let take = try #require(TakeProminence(example.syllables, lambda: 1.6))
        let p = take.scores(of: example.word)
        for (i, expected) in example.p16.enumerated() {
            #expect(Self.near(p[i], expected), "P[\(i)] = \(p[i] ?? .nan), expected \(expected)")
        }
        let stress = try #require(take.observedStress(of: example.word))
        #expect(stress.primary == example.primary16)
        #expect(Self.near(stress.margin, example.margin16), "margin \(stress.margin)")
        #expect(stress.confidence == example.confidence16)
        // The §3.3 rule: flaggable only at high stress confidence (the script's `flaggable`).
        let decision = try #require(
            placementDecision(observed: stress, accepted: [99], confidence: .high, exposure: stress.exposed))
        #expect(decision.flagged == (example.confidence16 == .high))
    }

    @Test("A–E at λ = 1.0 (the undiscounted path)", arguments: cases)
    func undiscounted(_ example: Case) throws {
        let take = try #require(TakeProminence(example.syllables, lambda: 1.0))
        let p = take.scores(of: example.word)
        for (i, expected) in example.p10.enumerated() {
            #expect(Self.near(p[i], expected), "P[\(i)] = \(p[i] ?? .nan), expected \(expected)")
        }
        let stress = try #require(take.observedStress(of: example.word))
        #expect(stress.primary == example.primary10)
        #expect(Self.near(stress.margin, example.margin10), "margin \(stress.margin)")
        #expect(stress.confidence == example.confidence10)
        let decision = try #require(
            placementDecision(observed: stress, accepted: [99], confidence: .high, exposure: stress.exposed))
        #expect(decision.flagged == (example.confidence10 == .high), "E at λ = 1.0 is medium: not flaggable")
    }

    @Test("C and W use raw durations, the same at both λ", arguments: cases)
    func contrastAndWeakLength(_ example: Case) throws {
        let features = example.syllables.suffix(4).map(\.features)
        let contrast = try #require(Contrast.contrast(features, stressed: [1], unstressed: [0, 2, 3]))
        let weak = try #require(Contrast.weakLength(features, stressed: [1], unstressed: [0, 2, 3]))
        #expect(Self.near(contrast, example.contrast), "C = \(contrast)")
        #expect(Self.near(weak * 100, example.weakLength, places: 1), "W = \(weak * 100)%")
    }

    @Test("the current thresholds use λ = 1.6") func currentLambda() throws {
        let a = Self.cases[0]
        #expect(TakeProminence(a.syllables)?.scores == TakeProminence(a.syllables, lambda: 1.6)?.scores)
    }

    // MARK: Degenerate cases

    struct Degenerate: Sendable, CustomTestStringConvertible {
        let name: String
        let features: [ProminenceFeatures]
        /// nil: prominence unavailable.
        let expected: [Double]?
        var testDescription: String { name }
    }

    static func f(_ d: Double, _ e: Double, _ p: Double?, exposed: Bool = false) -> ProminenceFeatures {
        ProminenceFeatures(duration: d, energyDBFS: e, peakSemitones: p, lengtheningExposed: exposed)
    }

    static let degenerate: [Degenerate] = [
        Degenerate(name: "no syllables", features: [], expected: nil),
        Degenerate(name: "n = 1: unavailable", features: [f(0.2, -20, 3)], expected: nil),
        // d: ln 0.1, ln 0.2 → z ∓1 (sd 0.347 > floor); e: z ∓1 (sd 2 dB); p missing: weights 0.4 + 0.3.
        Degenerate(
            name: "all pitch missing: pitch drops out", features: [f(0.1, -22, nil), f(0.2, -18, nil)],
            expected: [-1, 1]),
        // One voiced syllable: fewer than 2 pitch values, so pitch drops out for both.
        Degenerate(
            name: "one pitch value: pitch drops out", features: [f(0.1, -22, 5), f(0.2, -18, nil)], expected: [-1, 1]),
        Degenerate(
            name: "zero variance: the sd floors give 0, never NaN",
            features: [f(0.15, -22, 1), f(0.15, -22, 1), f(0.15, -22, 1)], expected: [0, 0, 0]),
        // Energy below −60 dBFS is floored: −80 and −60 are the same value.
        Degenerate(
            name: "energy floored at −60 dBFS", features: [f(0.15, -80, nil), f(0.15, -60, nil)], expected: [0, 0]),
        Degenerate(
            name: "a zero-length syllable stays finite", features: [f(0, -30, nil), f(0.2, -20, nil)], expected: [-1, 1]),
    ]

    @Test("degenerate inputs", arguments: degenerate)
    func degenerateCases(_ example: Degenerate) {
        let scores = Prominence.scores(example.features)
        guard let expected = example.expected else {
            #expect(scores == nil)
            return
        }
        #expect(scores?.count == expected.count)
        for (got, want) in zip(scores ?? [], expected) {
            #expect(got.isFinite)
            #expect(abs(got - want) < 1e-9, "\(got) vs \(want)")
        }
    }

    @Test("a feature at zero variance is floored, not divided by zero") func floorOnZeroVariance() throws {
        // Energy and pitch are flat; only duration varies: P is the duration z scaled by 0.4 / 1.0.
        let scores = try #require(Prominence.scores([Self.f(0.1, -20, 2), Self.f(0.2, -20, 2)]))
        #expect(abs(scores[0] + 0.4) < 1e-9 && abs(scores[1] - 0.4) < 1e-9)
    }

    @Test("fewer than 2 comparable syllables: no take prominence") func unavailableTake() {
        #expect(TakeProminence([]) == nil)
        #expect(TakeProminence(Self.word([0.2], [-20], [1])) == nil)
    }

    // MARK: Observed stress

    @Test("a monosyllable has no observed stress") func monosyllable() throws {
        let take = try #require(TakeProminence(Self.cases[4].syllables))
        #expect(take.observedStress(of: WordIndex(0)) == nil)
        #expect(take.observedStress(of: WordIndex(9)) == nil, "a word not in the set")
    }

    @Test("stress confidence is capped by the syllable confidence") func cappedBySyllable() throws {
        let medium = Self.cases[0].syllables.map {
            ComparableSyllable(word: $0.word, indexInWord: $0.indexInWord, features: $0.features, level: .medium)
        }
        let stress = try #require(TakeProminence(medium)?.observedStress(of: WordIndex(0)))
        #expect(stress.marginConfidence == .high)
        #expect(stress.syllableConfidence == .medium)
        #expect(stress.confidence == .medium)
    }

    @Test("margins come from the bucket of n comparable syllables", arguments: [(4, Confidence.high), (6, .medium), (9, .low)])
    func marginBuckets(n: Int, expected: Confidence) throws {
        var thresholds = Thresholds.current.prominence
        thresholds.tauMedium = .init(syllables2to4: 0.1, syllables5to8: 0.1, syllables9Plus: 5)
        thresholds.tauHigh = .init(syllables2to4: 0.2, syllables5to8: 5, syllables9Plus: 6)
        // A two-syllable target word with a clear peak, padded with flat filler words to n syllables.
        let target = Self.word([0.25, 0.1], [-18, -24], [4, 0], index: 0, final: false)
        let filler = (0..<(n - 2)).flatMap { Self.word([0.15], [-22], [1], index: $0 + 1, final: false) }
        let stress = try #require(TakeProminence(target + filler, thresholds: thresholds)?.observedStress(of: WordIndex(0)))
        #expect(stress.primary == 0)
        #expect(stress.marginConfidence == expected)
    }

    @Test("secondary: a non-adjacent peak at ≥ 0.75 of the primary's display prominence") func secondary() throws {
        // A five-syllable word: peaks on 0 and 3, the rest weak.
        let strong = Self.word([0.22, 0.08, 0.08, 0.2, 0.08], [-18, -26, -26, -18.5, -26], [3, -1, -1, 2.8, -1], final: false)
        let stress = try #require(TakeProminence(strong)?.observedStress(of: WordIndex(0)))
        #expect(stress.primary == 0)
        #expect(stress.secondary == 3)
        // Same, but the second peak is next to the primary: no secondary.
        let adjacent = Self.word([0.22, 0.2, 0.08, 0.08, 0.08], [-18, -18.5, -26, -26, -26], [3, 2.8, -1, -1, -1], final: false)
        let none = try #require(TakeProminence(adjacent)?.observedStress(of: WordIndex(0)))
        #expect(none.primary == 0)
        #expect(none.secondary == nil)
        // The second peak is too weak.
        let weak = Self.word([0.22, 0.08, 0.08, 0.11, 0.08], [-18, -26, -26, -24, -26], [3, -1, -1, 0, -1], final: false)
        #expect(try #require(TakeProminence(weak)?.observedStress(of: WordIndex(0))).secondary == nil)
    }

    @Test("display prominence is 0–1 within the take, 0 everywhere when flat") func display() {
        #expect(Prominence.display([-1, 0, 1]) == [0, 0.5, 1])
        #expect(Prominence.display([0.3, 0.3]) == [0, 0])
    }

    @Test("ties go to the earlier syllable, with margin 0 and low confidence") func ties() throws {
        let flat = Self.word([0.15, 0.15], [-22, -22], [1, 1], final: false)
        let stress = try #require(TakeProminence(flat)?.observedStress(of: WordIndex(0)))
        #expect(stress.primary == 0)
        #expect(stress.margin == 0)
        #expect(stress.confidence == .low)
    }
}
