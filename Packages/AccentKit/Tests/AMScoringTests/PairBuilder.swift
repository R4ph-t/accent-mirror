import AMAlignment
import AMCore
import AMProsody
import AMWarp
import Foundation
@testable import AMScoring

/// Replayed L1 data for one pair: per syllable a duration, an energy, a confidence level and a pitch ramp, laid end
/// to end from 0.1 s on each speaker's own timeline. Builds the alignment, time map and `ScoringInput`.
struct PairBuilder {
    struct Word {
        let text: String
        let arpabet: String
        var isTarget = false
        var isContent = true
        var ambiguous = false
    }

    struct Syllable {
        var duration: Double
        var energy: Double
        /// Semitones at the syllable's first and last frame; nil = unvoiced.
        var pitch: (Double, Double)?
        var level: Confidence = .high

        init(_ duration: Double, _ energy: Double, _ pitch: (Double, Double)?, level: Confidence = .high) {
            self.duration = duration
            self.energy = energy
            self.pitch = pitch
            self.level = level
        }
    }

    enum Fate { case present, substituted, missing }

    struct Side {
        /// One list per phrase word (empty for a missing word on your side).
        var syllables: [[Syllable]]
        var fates: [Fate]? = nil
        var timing: TimingLevel = .good
    }

    let words: [Word]
    var model: Side
    var you: Side
    var modelVoice = "p225"
    var hop = 0.01

    static func range(_ a: Double, _ b: Double) -> TimeRange { try! TimeRange(start: a, end: b) }

    /// One side laid out: per phrase word its range and syllable ranges, the comparable syllables and the pitch.
    struct Laid {
        var wordRanges: [Int: TimeRange] = [:]
        var syllableRanges: [Int: [TimeRange]] = [:]
        var syllables: [ComparableSyllable] = []
        var frames: [PitchFrame] = []
        var start = 0.1
    }

    func lay(_ side: Side) -> Laid {
        var laid = Laid()
        var t = laid.start
        let fates = side.fates ?? Array(repeating: .present, count: words.count)
        let lastPresent = fates.lastIndex { $0 != .missing }
        var lastSemitones = 0.0
        for (w, syllables) in side.syllables.enumerated() where fates[w] != .missing {
            let wordStart = t
            var ranges: [TimeRange] = []
            for (i, s) in syllables.enumerated() {
                let n = Int((s.duration / hop).rounded())
                var peak: Double?
                var voicedFrames = 0
                for j in 0..<n {
                    if let (a, b) = s.pitch {
                        let v = n > 1 ? a + (b - a) * Double(j) / Double(n - 1) : a
                        laid.frames.append(PitchFrame(semitones: v, voiced: true))
                        peak = max(peak ?? v, v)
                        voicedFrames += 1
                        lastSemitones = v
                    } else {
                        laid.frames.append(PitchFrame(semitones: lastSemitones, voiced: false))
                    }
                }
                let r = Self.range(t, t + Double(n) * hop)
                ranges.append(r)
                if fates[w] == .present {
                    let exposed = w == lastPresent && i == syllables.count - 1
                    laid.syllables.append(ComparableSyllable(
                        word: WordIndex(w), indexInWord: i,
                        features: ProminenceFeatures(
                            duration: r.end - r.start, energyDBFS: s.energy, peakSemitones: voicedFrames >= 3 ? peak : nil,
                            lengtheningExposed: exposed),
                        level: s.level))
                }
                t = r.end
            }
            laid.wordRanges[w] = Self.range(wordStart, t)
            laid.syllableRanges[w] = ranges
        }
        return laid
    }

    var accepted: [ScoringWord] {
        words.enumerated().map { i, word in
            let pronunciation = try! Pronunciation(arpabet: word.arpabet)
            let expected = ExpectedWord(
                index: WordIndex(i), text: word.text, pronunciation: pronunciation, source: .override,
                expectedAmbiguous: word.ambiguous, isContent: word.isContent, isTarget: word.isTarget)
            return ScoringWord(
                index: WordIndex(i), syllableCount: expected.syllableCount, isTarget: word.isTarget,
                isContent: word.isContent, expectedPattern: expected.expectedPattern,
                accepted: WordAcceptedSet(expected: expected, natives: []))
        }
    }

    struct Built {
        let input: ScoringInput
        let model: Laid
        let you: Laid
    }

    func build(takeProblems: [TakeProblem] = []) throws -> Built {
        let m = lay(model)
        let y = lay(you)
        let fates = you.fates ?? Array(repeating: .present, count: words.count)
        var pairs: [AlignedWordPair] = []
        var yourWords: [WordIndex: TimedWord] = [:]
        for w in words.indices {
            switch fates[w] {
            case .present:
                pairs.append(.present(phrase: WordIndex(w), you: y.wordRanges[w]!))
                yourWords[WordIndex(w)] = TimedWord(range: y.wordRanges[w]!, syllables: y.syllableRanges[w]!, timing: you.timing)
            case .substituted:
                pairs.append(.substituted(phrase: WordIndex(w), heard: "uh", you: y.wordRanges[w]!))
                yourWords[WordIndex(w)] = TimedWord(range: y.wordRanges[w]!, timing: you.timing)
            case .missing:
                pairs.append(.missing(phrase: WordIndex(w)))
            }
        }
        let alignment = try WordAlignment(pairs: pairs)
        let modelWords = words.indices.map {
            TimedWord(range: m.wordRanges[$0]!, syllables: m.syllableRanges[$0]!, timing: model.timing)
        }
        let warp = try TimeWarp(alignment: alignment, model: modelWords, you: yourWords, timing: you.timing)
        let content = words.indices.filter { words[$0].isContent }
        let matched = content.filter { fates[$0] == .present }.count
        let incomplete = words.indices.filter { fates[$0] != .present }
        let targets: [WordIndex] = incomplete.filter { words[$0].isTarget }.map { WordIndex($0) }
        let others: [WordIndex] = incomplete.filter { !words[$0].isTarget }.map { WordIndex($0) }
        let share: Double = content.isEmpty ? 1 : Double(matched) / Double(content.count)
        let summary = AlignmentSummary(
            matchShare: share, incompleteTargetWords: targets, incompleteNonTargetWords: others)
        func take(_ laid: Laid, isModel: Bool) -> ScoringTake {
            ScoringTake(
                syllables: laid.syllables, pitch: [PitchSegment(start: laid.start, frames: laid.frames)],
                words: Dictionary(uniqueKeysWithValues: laid.wordRanges.compactMap { w, r in
                    (isModel || fates[w] == .present) ? (WordIndex(w), r) : nil
                }))
        }
        let input = ScoringInput(
            words: accepted, modelVoice: modelVoice, model: take(m, isModel: true), you: take(y, isModel: false), alignment: alignment,
            alignmentSummary: summary, warp: warp, takeProblems: takeProblems, hopSeconds: hop)
        return Built(input: input, model: m, you: y)
    }

    func score(thresholds: Thresholds = .current) throws -> Scoring {
        try Scorer.score(build().input, thresholds: thresholds)
    }
}

// MARK: - The worked examples (spec 08's appendix) as replayed L1 data

enum Pairs {
    typealias S = PairBuilder.Syllable

    static let photographyWord = PairBuilder.Word(text: "photography", arpabet: "F AH0 T AA1 G R AH0 F IY0", isTarget: true)

    /// Peaks become a one-semitone ramp up to the peak.
    static func syllables(_ d: [Double], _ e: [Double], _ p: [Double?], level: Confidence = .high) -> [S] {
        d.indices.map { S(d[$0], e[$0], p[$0].map { ($0 - 1, $0) }, level: level) }
    }

    /// A: model "photography", TOG.
    static let a = syllables([0.10, 0.20, 0.08, 0.12], [-24, -18, -27, -26], [1, 6, -1, -2])
    /// B: stress on PHO.
    static let b = syllables([0.20, 0.14, 0.10, 0.12], [-19, -22, -25, -25], [5, 2, 0, -1])
    /// D: flat.
    static let d = syllables([0.15, 0.15, 0.15, 0.15], [-22, -22, -22, -22], [0, 0.2, 0, -0.2])
    /// Over-stressed TOG: much longer and louder than A's.
    static let over = syllables([0.06, 0.30, 0.05, 0.07], [-30, -14, -32, -31], [1, 7, -1, -2])

    static func photography(you: [S]) -> PairBuilder {
        PairBuilder(words: [photographyWord], model: .init(syllables: [a]), you: .init(syllables: [you]))
    }

    /// "I love photography.": I and love at `lead` level (low makes S∪U confidence low: 4 of 6 at medium or above).
    static func iLovePhotography(you: [S], lead: Confidence, timing: TimingLevel) -> PairBuilder {
        let words = [
            PairBuilder.Word(text: "I", arpabet: "AY1", isContent: false),
            PairBuilder.Word(text: "love", arpabet: "L AH1 V"),
            photographyWord,
        ]
        let modelLead: [[S]] = [[S(0.10, -22, (2, 2.5))], [S(0.16, -20, (3, 4))]]
        let yourLead: [[S]] = [[S(0.10, -22, (2, 2.5), level: lead)], [S(0.16, -20, (3, 4), level: lead)]]
        return PairBuilder(
            words: words, model: .init(syllables: modelLead + [a]), you: .init(syllables: yourLead + [you], timing: timing))
    }

    /// "record" (noun, REC-ord), two syllables: placement only.
    static func record(you: [S]) -> PairBuilder {
        PairBuilder(
            words: [PairBuilder.Word(text: "record", arpabet: "R EH1 K ER0 D", isTarget: true)],
            model: .init(syllables: [[S(0.24, -18, (4, 1)), S(0.28, -26, (1, -3))]]),
            you: .init(syllables: [you]))
    }

    static let recordYouClose: [S] = [S(0.26, -17, (4.5, 1)), S(0.30, -25, (1, -3.5))]

    /// "Who did you give it to?": the model falls over "it to" at about −8 st/s.
    static func whoDidYouGiveItTo(final you: [[S]], fates: [PairBuilder.Fate]? = nil) -> PairBuilder {
        let words = [
            PairBuilder.Word(text: "who", arpabet: "HH UW1"),
            PairBuilder.Word(text: "did", arpabet: "D IH1 D", isContent: false),
            PairBuilder.Word(text: "you", arpabet: "Y UW0", isContent: false),
            PairBuilder.Word(text: "give", arpabet: "G IH1 V", isTarget: true),
            PairBuilder.Word(text: "it", arpabet: "IH0 T", isContent: false),
            PairBuilder.Word(text: "to", arpabet: "T AH0", isContent: false),
        ]
        let lead: [[S]] = [
            [S(0.16, -19, (3, 4))], [S(0.12, -21, (4, 4.5))], [S(0.10, -25, (2, 2))], [S(0.20, -18, (5, 6))],
        ]
        // −8 st/s over "it to" (0.12 s + 0.18 s): 2.4 st over 0.30 s.
        let modelFinal: [[S]] = [[S(0.12, -26, (1.6, 0.68))], [S(0.18, -27, (0.6, -0.76))]]
        return PairBuilder(
            words: words, model: .init(syllables: lead + modelFinal),
            you: .init(syllables: lead + you, fates: fates))
    }

    /// You rise on "to" at about +7 st/s.
    static let risingFinal: [[S]] = [[S(0.12, -26, (0, 0.77))], [S(0.18, -27, (0.84, 2.03))]]
    /// You fall like the model.
    static let fallingFinal: [[S]] = [[S(0.12, -26, (1.6, 0.68))], [S(0.18, -27, (0.6, -0.76))]]
}
