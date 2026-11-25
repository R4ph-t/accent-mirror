// Display syllable labels for the strip (Designer addendum v3.4 Y1–Y2).
//
// Precedence:
//   1. Bundled display-syllable table (`Resources/starter-syllables.json`, covering the 14 starter phrases plus the
//      `photography` fixture as pho/tog/ra/phy). A table row always wins when its piece count matches the pronunciation.
//   2. A single pinned en-US hyphenator, used only when its piece count equals the CMUdict syllable count of the
//      pronunciation actually used. Currently nil (hyphenation skipped): the candidate Liang/TeX en-US pattern sets
//      (`hyph-en-us.tex` / `ushyphmax.tex` and LibreOffice `hyph_en_US.dic`) embed Donald Knuth's `hyphen.tex` patterns
//      whose filename-rename restriction (`Knuth-CTAN` / `PlainTeX`) is not clearly GPL-3.0 compatible.
//   3. Otherwise nil -> the UI shows the whole folded word once, lowercase, Geist 12 regular, text.tertiary, centred
//      across the word's syllable bars, with no caps (`ShellPresenter` / `StripCard`).
//
// Never falls back to `Syllabifier.spellingSyllables` or joined ARPAbet phone tokens.

import AMCore
import Foundation

/// A single pinned source of orthographic hyphenation breaks for a folded lowercase word.
public protocol Hyphenator: Sendable {
    /// Returns lowercase orthographic pieces (no hyphens) that concatenate to `foldedWord`, or nil if unknown.
    func hyphenate(_ foldedWord: String) -> [String]?
}

/// Bundled `starter-syllables.json`: the 14 starter phrases, the `photography` fixture, and their unique lexicon.
public struct DisplaySyllableTable: Sendable, Hashable, Decodable {
    public struct PhraseEntry: Sendable, Hashable, Decodable {
        public struct WordEntry: Sendable, Hashable, Decodable {
            public let index: Int
            public let text: String
            public let folded: String
            public let arpabet: String
            public let source: String
            public let syllables: [String]
        }

        public let id: String
        public let text: String
        public let words: [WordEntry]
    }

    public struct LexiconEntry: Sendable, Hashable, Decodable {
        public let word: String
        public let arpabet: String
        public let source: String
        public let syllableCount: Int
        public let variantCounts: [Int]
        public let syllables: [String]
    }

    public let version: String
    public let date: String
    public let phrases: [PhraseEntry]
    public let fixtures: [PhraseEntry]
    public let lexicon: [String: LexiconEntry]

    public init(json: Data) throws(ResourceError) {
        do {
            self = try JSONDecoder().decode(DisplaySyllableTable.self, from: json)
        } catch {
            throw .malformed("starter-syllables.json")
        }
    }

    public static func bundled() throws(ResourceError) -> DisplaySyllableTable { try cache.get() }

    private static let cache = Result<DisplaySyllableTable, ResourceError> { () throws(ResourceError) in
        try DisplaySyllableTable(json: BundledResource.data("starter-syllables.json"))
    }

    /// Lowercase orthographic pieces for `folded` if the table has a row.
    public func syllables(forFolded word: String) -> [String]? {
        lexicon[word]?.syllables
    }

    /// Full lexicon entry for `folded`, if present.
    public func entry(forFolded word: String) -> LexiconEntry? {
        lexicon[word]
    }
}

/// Resolves readable orthographic syllable pieces for a word given the syllable count of the pronunciation used.
public struct DisplaySyllableResolver: Sendable {
    public let table: DisplaySyllableTable
    /// Currently nil by default because no clearly GPL-3.0-compatible Liang/TeX en-US pattern set is bundled.
    public let hyphenator: (any Hyphenator)?

    public init(table: DisplaySyllableTable, hyphenator: (any Hyphenator)? = nil) {
        self.table = table
        self.hyphenator = hyphenator
    }

    public static func bundled(hyphenator: (any Hyphenator)? = nil) throws(ResourceError) -> DisplaySyllableResolver {
        DisplaySyllableResolver(table: try .bundled(), hyphenator: hyphenator)
    }

    /// Returns one lowercase piece per syllable when a table row or matching hyphenation applies; otherwise nil
    /// (caller renders the merged-word fallback). Never returns joined phones or `spellingSyllables`.
    public func resolve(word: String, syllableCount: Int) -> [String]? {
        let folded = WordText.fold(word)
        guard !folded.isEmpty, syllableCount > 0 else { return nil }

        // 1. Table row always wins when it matches the pronunciation's syllable count.
        if let row = table.syllables(forFolded: folded), Self.isValid(pieces: row, forFolded: folded, count: syllableCount) {
            return row
        }

        // 2. Otherwise, pinned hyphenator pieces only when count equals the pronunciation's syllable count.
        if let hyphenator, let pieces = hyphenator.hyphenate(folded),
           Self.isValid(pieces: pieces, forFolded: folded, count: syllableCount)
        {
            return pieces
        }

        // 3. Mismatch, no hyphenation, or OOV: merged-word fallback.
        return nil
    }

    private static func isValid(pieces: [String], forFolded folded: String, count: Int) -> Bool {
        pieces.count == count
            && pieces.allSatisfy { !$0.isEmpty && $0 == $0.lowercased() && !$0.contains("-") }
            && pieces.joined() == folded
    }
}
