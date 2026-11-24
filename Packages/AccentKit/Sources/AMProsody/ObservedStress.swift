// The comparable syllable set and prominence over it (spec 08, plan §2): shipped, for the prominence display. Observed
// stress (the per-word primary and its confidence) is verdict-only and lives in `AMPlacement` (spec 28).

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
}
