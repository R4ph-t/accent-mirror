// Word alignment (plan §4.3): Needleman–Wunsch of normalised heard words against the phrase words, and the
// summary the decision procedure reads (plan §4.2, §1.2).

import Foundation
import AMCore

/// One word the recogniser heard, on your timeline.
public struct HeardWord: Sendable, Hashable {
    public let text: String
    public let range: TimeRange

    public init(text: String, range: TimeRange) {
        self.text = text
        self.range = range
    }
}

public struct WordAlignmentResult: Sendable, Hashable {
    public let alignment: WordAlignment
    public let summary: AlignmentSummary
}

public struct WordAligner: Sendable {
    public let table: EquivalenceTable
    public let scores: Thresholds.Alignment

    public init(table: EquivalenceTable, scores: Thresholds.Alignment = Thresholds.current.alignment) {
        self.table = table
        self.scores = scores
    }

    public static func bundled(thresholds: Thresholds = .current) throws(ResourceError) -> WordAligner {
        WordAligner(table: try .bundled(), scores: thresholds.alignment)
    }

    /// Aligns heard words (in your-time order) to the phrase. Fillers are dropped and immediate repeats collapsed
    /// first; then equivalent runs (contractions, numbers, compounds, US/UK) compare as one unit.
    /// Throws `WordAlignment.Invalid` only when the heard words go back in time.
    public func align(_ phrase: ExpectedPhrase, heard: [HeardWord]) throws -> WordAlignmentResult {
        let phraseWords = phrase.words.map(\.folded)
        let heardWords = cleaned(heard, phraseWords: phraseWords)
        let heardFolded = heardWords.map { WordText.fold($0.text) }

        var phraseTokens = table.canonicalTokens(phraseWords)
        var heardTokens = table.canonicalTokens(heardFolded)
        // A multi-word unit only stands if the other side has something it can match; otherwise its words compare
        // one by one, so "train" still matches when you said "train stations" for "train station".
        phraseTokens = confirmed(phraseTokens, against: heardTokens, words: phraseWords)
        heardTokens = confirmed(heardTokens, against: phraseTokens, words: heardFolded)

        let steps = needlemanWunsch(phraseTokens, heardTokens)

        var pairs: [AlignedWordPair] = []
        var lastPhrase: WordIndex?
        for step in steps {
            switch step {
            case .pair(let p, let h):
                let phraseRun = phraseTokens[p].words.map { phrase.words[$0] }
                let heardRun = heardTokens[h].words.map { heardWords[$0] }
                let ranges = try distribute(heardRun, over: phraseRun)
                let matched = phraseTokens[p].matches(heardTokens[h])
                let heardText = heardRun.map(\.trimmedText).joined(separator: " ")
                for (word, range) in zip(phraseRun, ranges) {
                    pairs.append(
                        matched
                            ? .present(phrase: word.index, you: range)
                            : .substituted(phrase: word.index, heard: heardText, you: range))
                    lastPhrase = word.index
                }
            case .missing(let p):
                for index in phraseTokens[p].words {
                    pairs.append(.missing(phrase: phrase.words[index].index))
                    lastPhrase = phrase.words[index].index
                }
            case .inserted(let h):
                for index in heardTokens[h].words {
                    let word = heardWords[index]
                    pairs.append(.inserted(heard: word.trimmedText, you: word.range, afterPhrase: lastPhrase))
                }
            }
        }

        let alignment = try WordAlignment(pairs: pairs)
        return WordAlignmentResult(alignment: alignment, summary: summary(of: alignment, phrase: phrase))
    }

    // MARK: - Steps

    /// Drops empty words and fillers, then collapses immediate repeats ("I I want" → "I want"), keeping the last
    /// occurrence. A repeat the phrase itself has ("had had") is kept up to the phrase's own run length.
    private func cleaned(_ heard: [HeardWord], phraseWords: [String]) -> [HeardWord] {
        var allowedRun: [String: Int] = [:]
        var runStart = 0
        for i in phraseWords.indices {
            if i > 0, phraseWords[i] != phraseWords[i - 1] { runStart = i }
            allowedRun[phraseWords[i]] = max(allowedRun[phraseWords[i], default: 1], i - runStart + 1)
        }

        let spoken = heard.filter { word in
            let folded = WordText.fold(word.text)
            return !folded.isEmpty && !EquivalenceTable.fillers.contains(folded)
        }
        var kept: [HeardWord] = []
        var i = 0
        while i < spoken.count {
            let folded = WordText.fold(spoken[i].text)
            var end = i + 1
            while end < spoken.count, WordText.fold(spoken[end].text) == folded { end += 1 }
            let keep = min(end - i, allowedRun[folded, default: 1])
            kept += spoken[(end - keep)..<end]
            i = end
        }
        return kept
    }

    private func confirmed(_ tokens: [CanonicalToken], against other: [CanonicalToken], words: [String])
        -> [CanonicalToken]
    {
        let otherKeys = other.reduce(into: Set<CanonicalToken.Key>()) { $0.formUnion($1.keys) }
        return tokens.flatMap { token -> [CanonicalToken] in
            guard token.words.count > 1, token.keys.isDisjoint(with: otherKeys) else { return [token] }
            return token.words.map { table.canonicalToken(words[$0], at: $0) }
        }
    }

    private enum Step {
        case pair(Int, Int)
        case missing(Int)
        case inserted(Int)
    }

    /// Global alignment: match +2, substitution −1, insertion or omission −1 (`Thresholds.alignment`). Ties go to
    /// the diagonal, then an omission, then an insertion, so the result is deterministic.
    private func needlemanWunsch(_ phrase: [CanonicalToken], _ heard: [CanonicalToken]) -> [Step] {
        let m = phrase.count
        let n = heard.count
        var score = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { score[i][0] = Double(i) * scores.gapScore }
        for j in 0...n { score[0][j] = Double(j) * scores.gapScore }
        func pairScore(_ i: Int, _ j: Int) -> Double {
            phrase[i].matches(heard[j]) ? scores.matchScore : scores.mismatchScore
        }
        if m > 0, n > 0 {
            for i in 1...m {
                for j in 1...n {
                    score[i][j] = max(
                        score[i - 1][j - 1] + pairScore(i - 1, j - 1),
                        score[i - 1][j] + scores.gapScore,
                        score[i][j - 1] + scores.gapScore)
                }
            }
        }

        var steps: [Step] = []
        var i = m
        var j = n
        while i > 0 || j > 0 {
            if i > 0, j > 0, score[i][j] == score[i - 1][j - 1] + pairScore(i - 1, j - 1) {
                steps.append(.pair(i - 1, j - 1))
                i -= 1
                j -= 1
            } else if i > 0, score[i][j] == score[i - 1][j] + scores.gapScore {
                steps.append(.missing(i - 1))
                i -= 1
            } else {
                steps.append(.inserted(j - 1))
                j -= 1
            }
        }
        return steps.reversed()
    }

    /// Your time for each phrase word of a run. Same count: word for word. Otherwise the heard run's span is split
    /// in proportion to the phrase words' letters ("trainstation" heard for "train station").
    private func distribute(_ heard: [HeardWord], over phrase: [ExpectedWord]) throws -> [TimeRange] {
        if heard.count == phrase.count { return heard.map(\.range) }
        let start = heard.first?.range.start ?? 0
        let end = heard.last?.range.end ?? start
        let weights = phrase.map { Double(max($0.folded.count, 1)) }
        let total = weights.reduce(0, +)
        var ranges: [TimeRange] = []
        var cursor = start
        for (k, weight) in weights.enumerated() {
            let next = k == weights.count - 1 ? end : cursor + (end - start) * weight / total
            ranges.append(try TimeRange(start: cursor, end: max(next, cursor)))
            cursor = next
        }
        return ranges
    }

    /// Match % = matched content words ÷ content words; with no content words, matched words ÷ all words (§4.2).
    /// A substitution is never matched.
    private func summary(of alignment: WordAlignment, phrase: ExpectedPhrase) -> AlignmentSummary {
        var present = Set<WordIndex>()
        var incomplete: [WordIndex] = []
        var insertions: [String] = []
        for pair in alignment.pairs {
            switch pair {
            case .present(let word, _): present.insert(word)
            case .substituted(let word, _, _), .missing(let word): incomplete.append(word)
            case .inserted(let heard, _, _): insertions.append(heard)
            }
        }
        let content = phrase.words.filter(\.isContent)
        let counted = content.isEmpty ? phrase.words : content
        let matchShare =
            counted.isEmpty ? 0 : Double(counted.filter { present.contains($0.index) }.count) / Double(counted.count)
        let targets = Set(phrase.words.filter(\.isTarget).map(\.index))
        return AlignmentSummary(
            matchShare: matchShare, nonFillerInsertions: insertions,
            incompleteTargetWords: incomplete.filter(targets.contains).sorted(),
            incompleteNonTargetWords: incomplete.filter { !targets.contains($0) }.sorted())
    }
}

extension HeardWord {
    fileprivate var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
