// Observed stress per word (spec 08, plan §2): primary = argmax P within the word, margin to the runner-up, stress
// confidence from n-bucket margins capped by the syllable confidence (spec 07), and a secondary peak on display
// prominence (Open question 1: the 0.75 rule reads the 0–1 display prominence, not the z-score P).

import AMCore
import AMPitch
import Foundation

/// One syllable of the comparable set.
public struct ComparableSyllable: Sendable, Hashable, Codable {
    public let word: WordIndex
    public let indexInWord: Int
    public let features: ProminenceFeatures
    /// The syllable confidence level, min(c_w, s_w) (spec 07).
    public let level: Confidence

    public init(word: WordIndex, indexInWord: Int, features: ProminenceFeatures, level: Confidence) {
        self.word = word
        self.indexInWord = indexInWord
        self.features = features
        self.level = level
    }

    /// Every syllable of the segmentation's `present` words, in time order: the comparable set when nothing else
    /// restricts it (the shared-detector mode, §6.3).
    public static func all(
        in segmentation: SyllableSegmentation, pitch: PitchTrack,
        thresholds: Thresholds.Prominence = Thresholds.current.prominence
    ) -> [ComparableSyllable] {
        segmentation.words.filter { $0.kind == .present }.flatMap(\.syllables).map {
            ComparableSyllable(
                word: $0.phraseWord, indexInWord: $0.indexInWord,
                features: ProminenceFeatures($0, pitch: pitch, thresholds: thresholds), level: $0.level)
        }
    }
}

/// Prominence over one take's comparable set.
public struct TakeProminence: Sendable, Hashable {
    public let syllables: [ComparableSyllable]
    /// P_i, one per syllable.
    public let scores: [Double]
    /// P min-max normalised to 0–1 within the take.
    public let display: [Double]
    public let thresholds: Thresholds.Prominence

    /// Nil when prominence is unavailable (fewer than 2 comparable syllables).
    public init?(
        _ syllables: [ComparableSyllable], lambda: Double? = nil,
        thresholds: Thresholds.Prominence = Thresholds.current.prominence
    ) {
        guard let scores = Prominence.scores(
            syllables.map(\.features), lambda: lambda ?? thresholds.lengtheningLambda, thresholds: thresholds)
        else { return nil }
        self.syllables = syllables
        self.scores = scores
        self.display = Prominence.display(scores)
        self.thresholds = thresholds
    }

    /// n: the number of comparable syllables, which picks the margin bucket.
    public var comparableCount: Int { syllables.count }

    /// P of `word`'s syllables in the set, by index in word.
    public func scores(of word: WordIndex) -> [Int: Double] {
        Dictionary(uniqueKeysWithValues: syllables.indices.filter { syllables[$0].word == word }
            .map { (syllables[$0].indexInWord, scores[$0]) })
    }

    /// Observed stress of `word`; nil when fewer than 2 of its syllables are in the set.
    public func observedStress(of word: WordIndex) -> ObservedStress? {
        let members = syllables.indices.filter { syllables[$0].word == word }
        guard members.count >= 2 else { return nil }
        // Highest P first; ties go to the earlier syllable.
        let ranked = members.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
        let top = ranked[0]
        let margin = scores[top] - scores[ranked[1]]
        let n = comparableCount
        let marginConfidence: Confidence =
            margin >= thresholds.tauHigh.margin(forSyllableCount: n) ? .high
            : margin >= thresholds.tauMedium.margin(forSyllableCount: n) ? .medium : .low
        let syllableConfidence = members.map { syllables[$0].level }.min()!
        let primary = syllables[top].indexInWord
        let secondary = ranked.dropFirst().first { abs(syllables[$0].indexInWord - primary) > 1 }.flatMap { candidate in
            display[top] > 0 && display[candidate] >= thresholds.secondaryStressShare * display[top]
                ? syllables[candidate].indexInWord : nil
        }
        return ObservedStress(
            primary: primary, secondary: secondary, margin: margin, marginConfidence: marginConfidence,
            syllableConfidence: syllableConfidence, exposed: members.contains { syllables[$0].features.lengtheningExposed })
    }
}

/// One word's observed stress.
public struct ObservedStress: Sendable, Hashable, Codable {
    /// Index in word of the most prominent syllable.
    public let primary: Int
    /// A second peak at ≥ `secondaryStressShare` of the primary's display prominence, not next to the primary.
    public let secondary: Int?
    /// m = P(top) − P(second), z units.
    public let margin: Double
    /// From the margin alone: high ≥ τ_high(n), medium ≥ τ_med(n), else low.
    public let marginConfidence: Confidence
    /// The lowest syllable confidence level of the word (spec 07).
    public let syllableConfidence: Confidence
    /// The word has a lengthening-exposed syllable.
    public let exposed: Bool

    public init(
        primary: Int, secondary: Int?, margin: Double, marginConfidence: Confidence, syllableConfidence: Confidence,
        exposed: Bool
    ) {
        self.primary = primary
        self.secondary = secondary
        self.margin = margin
        self.marginConfidence = marginConfidence
        self.syllableConfidence = syllableConfidence
        self.exposed = exposed
    }

    /// Stress confidence: the margin's level capped by the syllable confidence.
    public var confidence: Confidence { min(marginConfidence, syllableConfidence) }
}
