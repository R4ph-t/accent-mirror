// Spec 10 wiring for evaluation and the smoke goldens: two detector analyses (yours and a native model's) of the same
// phrase → the time map (spec 09) → `AMScoring`. The coordinator (spec 12) will feed the same `ScoringInput` from
// the app's stages; this adapter only reads what `StressPlacementDetector` already produced.

import AMAlignment
import AMCore
import AMProsody
import AMScoring
import AMWarp
import Foundation

public enum PairScoring {
    public enum Failure: Error, Equatable {
        /// The model take is missing or substituted a phrase word, so it can't serve as the reference.
        case modelIncomplete([WordIndex])
    }

    /// Scores `you` against `model`, both analysed from `words` (the phrase, in order). `natives` adds native
    /// readers' observed stress to each word's A(w) (spec 08); empty by default. Spec 22's end-to-end check passes the
    /// synthetic reference's own observed primaries here.
    public static func score(
        words: [PlacementTake.Word], you: PlacementAnalysis, model: PlacementAnalysis, modelVoice: String,
        natives: [WordIndex: [NativeReading]] = [:], thresholds: Thresholds = .current
    ) throws -> Scoring {
        let modelWords = Dictionary(
            model.segmentation.words.filter { $0.kind == .present }.map { ($0.phraseWord, $0) },
            uniquingKeysWith: { a, _ in a })
        let incomplete = words.map(\.index).filter { modelWords[$0] == nil }
        guard incomplete.isEmpty else { throw Failure.modelIncomplete(incomplete) }

        let confidence = thresholds.confidence
        func timed(_ word: SegmentedWord) -> TimedWord {
            let levels = word.syllables.map(\.level)
            let timing = levels.isEmpty
                ? (SyllableSegmenter.level(of: word.confidence, thresholds: confidence) >= .medium ? .good : .poor)
                : SyllableSegmenter.timing(of: levels, thresholds: confidence).level
            return TimedWord(range: word.range, syllables: word.syllables.map(\.range), timing: timing)
        }
        let yourWords = Dictionary(you.segmentation.words.map { ($0.phraseWord, timed($0)) }, uniquingKeysWith: { a, _ in a })
        let warp = try TimeWarp(
            alignment: you.alignment, model: words.map { timed(modelWords[$0.index]!) }, you: yourWords,
            timing: you.segmentation.timing)

        let scoringWords = words.map { word -> ScoringWord in
            // A polysyllable with no A(w) is `expectedAmbiguous`; a monosyllable has nothing to decide but still
            // counts in S and U.
            let ambiguous = word.accepted == nil && word.pronunciation.syllables.count >= 2
            let expected = ExpectedWord(
                index: word.index, text: word.text, pronunciation: word.pronunciation, source: .override,
                expectedAmbiguous: ambiguous, isContent: true, isTarget: word.accepted != nil)
            return ScoringWord(
                index: word.index, syllableCount: expected.syllableCount, isTarget: expected.isTarget, isContent: true,
                expectedPattern: expected.expectedPattern,
                accepted: WordAcceptedSet(expected: expected, natives: natives[word.index] ?? []))
        }

        func take(_ analysis: PlacementAnalysis) -> ScoringTake {
            ScoringTake(
                syllables: ComparableSyllable.all(in: analysis.segmentation, pitch: analysis.pitch, thresholds: thresholds.prominence),
                pitch: analysis.pitch.segments,
                words: Dictionary(
                    analysis.segmentation.words.filter { $0.kind == .present }.map { ($0.phraseWord, $0.range) },
                    uniquingKeysWith: { a, _ in a }))
        }

        let present = Set(you.alignment.pairs.compactMap { if case .present(let w, _) = $0 { w } else { nil } })
        let targets = scoringWords.filter(\.isTarget).map(\.index)
        let summary = AlignmentSummary(
            matchShare: words.isEmpty ? 0 : Double(present.count) / Double(words.count),
            nonFillerInsertions: you.alignment.pairs.compactMap { if case .inserted(let heard, _, _) = $0 { heard } else { nil } },
            incompleteTargetWords: targets.filter { !present.contains($0) },
            incompleteNonTargetWords: words.map(\.index).filter { !present.contains($0) && !targets.contains($0) })

        return try Scorer.score(
            ScoringInput(
                words: scoringWords, modelVoice: modelVoice, model: take(model), you: take(you),
                alignment: you.alignment, alignmentSummary: summary, warp: warp,
                hopSeconds: you.pitch.hopSeconds),
            thresholds: thresholds)
    }
}
