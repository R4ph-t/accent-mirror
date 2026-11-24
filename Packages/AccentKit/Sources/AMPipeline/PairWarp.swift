// The shipped half of pair scoring (spec 09 and spec 28): your take on the model's timeline and the alignment summary
// the take-problem gate reads. `AMVerdicts` extends `PairScoring` with `input` and `score` (spec 10's verdict path).

import AMAlignment
import AMCore
import AMProsody
import AMWarp
import Foundation

public enum PairScoring {
    public enum Failure: Error, Equatable {
        /// The model take is missing or substituted a phrase word, so it can't serve as the reference.
        case modelIncomplete([WordIndex])
    }

    /// The alignment summary of your take against `words`: what decision steps 1–2 (the take-problem gate) read.
    /// Targets are the words with an A(w) seed.
    public static func alignmentSummary(words: [PlacementTake.Word], you: TakeProsody) -> AlignmentSummary {
        let present = Set(you.alignment.pairs.compactMap { if case .present(let w, _) = $0 { w } else { nil } })
        let targets = words.filter { $0.accepted != nil }.map(\.index)
        return AlignmentSummary(
            matchShare: words.isEmpty ? 0 : Double(present.count) / Double(words.count),
            nonFillerInsertions: you.alignment.pairs.compactMap {
                if case .inserted(let heard, _, _) = $0 { heard } else { nil }
            },
            incompleteTargetWords: targets.filter { !present.contains($0) },
            incompleteNonTargetWords: words.map(\.index).filter { !present.contains($0) && !targets.contains($0) })
    }

    /// `you` on `model`'s timeline (spec 09), both analysed from `words`. Throws `modelIncomplete` when the model
    /// misses or substitutes a phrase word. The analyzer also warps each other native reader onto the selected voice
    /// with it, for the band and the native description.
    public static func warp(
        you: TakeProsody, model: TakeProsody, words: [PlacementTake.Word], thresholds: Thresholds = .current
    ) throws -> TimeWarp {
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
        return try TimeWarp(
            alignment: you.alignment, model: words.map { timed(modelWords[$0.index]!) }, you: yourWords,
            timing: you.segmentation.timing)
    }
}
