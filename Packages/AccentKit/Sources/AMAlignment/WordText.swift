// Case and punctuation folding, and phrase tokenisation (plan §4.1).

import Foundation
import AMCore

public enum WordText {
    /// Lowercased, curly apostrophes straightened, everything but letters, digits, apostrophes and hyphens removed,
    /// and leading or trailing apostrophes and hyphens trimmed. "Stella." → "stella", "Don’t" → "don't".
    public static func fold(_ text: some StringProtocol) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            switch scalar {
            case "\u{2019}", "\u{2018}", "\u{02BC}", "'": scalars.append("'")
            case "-", "\u{2010}", "\u{2011}": scalars.append("-")
            default:
                if CharacterSet.alphanumerics.contains(scalar) { scalars.append(scalar) }
            }
        }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "'-"))
    }
}

/// One word of the phrase text: split on whitespace, punctuation stripped. A token that folds to nothing (a bare
/// comma or dash) is skipped and takes no index, which matches the starter phrases' 0-based word indices.
public struct PhraseToken: Sendable, Hashable {
    public let index: WordIndex
    /// As written, punctuation included.
    public let text: String
    public let folded: String
    /// Where the token sits in the phrase text (for the tagger).
    public let range: Range<String.Index>
}

public func phraseTokens(_ text: String) -> [PhraseToken] {
    var tokens: [PhraseToken] = []
    var start: String.Index?
    func close(at end: String.Index) {
        guard let from = start else { return }
        let piece = String(text[from..<end])
        let folded = WordText.fold(piece)
        if !folded.isEmpty {
            tokens.append(PhraseToken(index: WordIndex(tokens.count), text: piece, folded: folded, range: from..<end))
        }
        start = nil
    }
    var index = text.startIndex
    while index < text.endIndex {
        if text[index].isWhitespace {
            close(at: index)
        } else if start == nil {
            start = index
        }
        index = text.index(after: index)
    }
    close(at: text.endIndex)
    return tokens
}
