import Foundation

/// Spec 03's token rule: a phrase token is a whitespace-separated word of the transcript after stripping punctuation
/// and collapsing whitespace, compared case-insensitively. Nothing richer (no number spelling, no lexicon): that is
/// spec 06.
public enum Tokens {
    /// Lower-cased, punctuation removed, whitespace collapsed and trimmed. `"  Stella's,"` → `"stellas"`.
    public static func normalize(_ word: String) -> String {
        let kept = word.lowercased().unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) }
        return String(String.UnicodeScalarView(kept))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The transcript's phrase tokens, in order; words that are only punctuation are dropped.
    public static func phraseTokens(of transcript: String) -> [String] {
        transcript.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }.filter { !$0.isEmpty }
    }

    /// For each phrase token, the index of the word (in `words`) that produced a span for it, or `nil` if none did.
    ///
    /// A word "produces a span for a token" when the two are equal after `normalize` and the pairing keeps both
    /// sequences in order: the longest common subsequence of `tokens` and the normalised words. Words that
    /// normalise to nothing are ignored.
    public static func match(tokens: [String], words: [String]) -> [Int?] {
        let candidates = words.enumerated().compactMap { index, word -> (index: Int, text: String)? in
            let text = normalize(word)
            return text.isEmpty ? nil : (index, text)
        }
        let n = tokens.count, m = candidates.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = tokens[i] == candidates[j].text
                    ? lcs[i + 1][j + 1] + 1
                    : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var result = [Int?](repeating: nil, count: n)
        var i = 0, j = 0
        while i < n, j < m {
            if tokens[i] == candidates[j].text {
                result[i] = candidates[j].index
                i += 1
                j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }
}
