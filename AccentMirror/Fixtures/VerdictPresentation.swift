import Foundation

// Spec 28: the presenter's verdict helpers, moved out of `ShellPresenter.swift` so it reads no verdict. No view calls
// them any more; the app-hosted contract tests still do. Spec 29 deletes them.

extension ShellPresenter {
    /// §10 order, rough timing first, at most 3 rows; too much contrast only fits when there is room.
    static func orderedRows(_ rows: [DiffRow]) -> [DiffRow] {
        let order = DiffRow.Kind.allCases
        let sorted = rows.sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
        return Array(sorted.prefix(3))
    }

    /// The final-direction icon follows the direction: arrow.up.right for "End higher", arrow.down.right for
    /// "End lower" (Designer 12:19 c, round 3).
    static func diffIcon(_ row: DiffRow) -> String {
        switch row.kind {
        case .roughTiming: "waveform.path.ecg"
        case .placement: "arrow.left.arrow.right"
        case .contrast: "chart.bar"
        case .reduction: "arrow.left.and.right"
        case .range: "arrow.up.and.down"
        case .finalDirection: row.direction == "higher" ? "arrow.up.right" : "arrow.down.right"
        case .tooMuchContrast: "chart.bar.fill"
        }
    }

    /// The mistake marker goes only on the syllable named after "not" in a placement row that card 1 shows:
    /// your stress is outside the accepted set at high confidence (§8, §13 item 5). Every other verdict
    /// (close, noClearDifference, inconclusive, feedback without that row) shows no marker.
    static func flaggedSyllables(_ analysis: Analysis?) -> Set<FlaggedSyllable> {
        guard let verdict = analysis?.verdict, verdict.kind == .feedback else { return [] }
        return Set(orderedRows(verdict.rows ?? []).compactMap { row in
            guard row.kind == .placement, let word = row.word, let heard = row.heardIndex else { return nil }
            return FlaggedSyllable(word: word.lowercased(), index: heard)
        })
    }

    /// The words card 1 names, normalised: a row's word (placement) or a whole word among its targets ("than" in
    /// "ra, phy, der, than"; a syllable like HAR names no word on its own), the words an inconclusive sentence
    /// names (targetWordsMissing), plus the starter manifest's `targets` for the phrase, which add to the set and
    /// never replace it.
    static func namedTargetWords(rows: [DiffRow], sentenceWords: [String], manifestTargets: [String],
                                 phraseWords: [String]) -> Set<String> {
        let words = Set(phraseWords.map(normalizedWord))
        let fromRows = rows.flatMap { row in (row.word.map { [$0] } ?? []) + (row.targets ?? []) }
        return Set((fromRows + sentenceWords + manifestTargets).map(normalizedWord)).intersection(words)
    }
}
