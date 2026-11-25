import AMAlignment
import AMCore
import Foundation
import Testing

private struct MockHyphenator: Hyphenator {
    let entries: [String: [String]]

    func hyphenate(_ foldedWord: String) -> [String]? {
        entries[foldedWord]
    }
}

@Suite("Display syllables table and resolution (v3.4 Y1–Y3)")
struct DisplaySyllablesTests {
    private static func hasPhoneToken(_ s: String) -> Bool { s.firstMatch(of: /\b[A-Za-z]+[012]\b/) != nil }

    @Test("Every entry in starter-syllables.json matches CMUdict count, folds cleanly, and has no phone tokens")
    func tableCountsMatchCMUdictAndConcatenateToFoldedWord() throws {
        let table = try DisplaySyllableTable.bundled()
        let dictionary = try PronouncingDictionary.bundled()

        #expect(table.phrases.count == 14)
        #expect(table.fixtures.contains { $0.id == "photography" })

        for (_, entry) in table.lexicon {
            let pron = try Pronunciation(arpabet: entry.arpabet)
            #expect(pron.syllables.count == entry.syllableCount, "\(entry.word): CMUdict vowel count")
            #expect(entry.syllables.count == entry.syllableCount, "\(entry.word): piece count matches CMUdict")
            #expect(entry.syllables.joined() == entry.word, "\(entry.word): concatenates to folded word")
            #expect(entry.syllables.allSatisfy { $0 == $0.lowercased() && !$0.isEmpty && !$0.contains("-") })
            for piece in entry.syllables {
                #expect(!Self.hasPhoneToken(piece), "\(entry.word): phone token in \(piece)")
            }
            // Verify CMUdict contains the entry's pronunciation when sourced from cmudict or override.
            let cmu = dictionary.pronunciations(of: entry.word)
            #expect(!cmu.isEmpty, "\(entry.word) missing from CMUdict")
            if entry.source == "cmudict" {
                #expect(cmu.first?.arpabet == entry.arpabet, "\(entry.word): cmudict first variant")
            }
        }

        // All 14 phrases and photography fixture match the lexicon and concatenate per word.
        for phrase in table.phrases + table.fixtures {
            for word in phrase.words {
                let pron = try Pronunciation(arpabet: word.arpabet)
                #expect(word.syllables.count == pron.syllables.count, "\(phrase.id)/\(word.folded)")
                #expect(word.syllables.joined() == word.folded, "\(phrase.id)/\(word.folded)")
                #expect(table.syllables(forFolded: word.folded) == word.syllables, "\(phrase.id)/\(word.folded)")
            }
        }
    }

    @Test("Photography fixture and Y4 table calls win over any hyphenator")
    func tableRowAlwaysWins() throws {
        let table = try DisplaySyllableTable.bundled()
        // Even if a hyphenator wanted pho/tog/rap/hy or a/ri/sto/tle, the table row wins.
        let hyphenator = MockHyphenator(entries: [
            "photography": ["pho", "tog", "rap", "hy"],
            "harder": ["hard", "er"],
            "aristotle": ["a", "ri", "sto", "tle"],
        ])
        let resolver = DisplaySyllableResolver(table: table, hyphenator: hyphenator)

        #expect(resolver.resolve(word: "Photography", syllableCount: 4) == ["pho", "tog", "ra", "phy"])
        #expect(resolver.resolve(word: "harder", syllableCount: 2) == ["har", "der"])
        #expect(resolver.resolve(word: "Aristotle", syllableCount: 4) == ["ar", "is", "tot", "le"])
        #expect(resolver.resolve(word: "physically", syllableCount: 4) == ["phy", "si", "cal", "ly"])
        #expect(resolver.resolve(word: "prism", syllableCount: 2) == ["pri", "sm"])
        #expect(resolver.resolve(word: "sun's", syllableCount: 1) == ["sun's"])
    }

    @Test("Chocolate mismatch (CMUdict 2 vs TeX 3) and skipped hyphenation fall back to nil, never spellingSyllables")
    func chocolateMismatchAndNoSpellingFallback() throws {
        let dictionary = try PronouncingDictionary.bundled()
        let chocoPron = try #require(dictionary.pronunciations(of: "chocolate").first)
        #expect(chocoPron.syllables.count == 2)
        // Spelling syllabifier splits "chocolate" into 3 ("cho/co/late") — must NEVER be used.
        #expect(Syllabifier.spellingSyllables(of: "chocolate").count == 3)

        // With TeX-style choc-o-late (3 pieces != CMUdict 2), resolver returns nil -> merged-word fallback.
        let texMock = MockHyphenator(entries: [
            "chocolate": ["choc", "o", "late"],
            "wonderful": ["won", "der", "ful"],
        ])
        let withMock = try DisplaySyllableResolver.bundled(hyphenator: texMock)
        #expect(withMock.resolve(word: "chocolate", syllableCount: chocoPron.syllables.count) == nil)
        // When count matches CMUdict (wonderful = 3), pinned hyphenator pieces are used.
        let wonderfulPron = try #require(dictionary.pronunciations(of: "wonderful").first)
        #expect(withMock.resolve(word: "wonderful", syllableCount: wonderfulPron.syllables.count) == ["won", "der", "ful"])

        // Default bundled resolver skips hyphenation (license verdict), so non-table words fall back to nil.
        let bundled = try DisplaySyllableResolver.bundled()
        #expect(bundled.hyphenator == nil)
        #expect(bundled.resolve(word: "chocolate", syllableCount: 2) == nil)
        #expect(bundled.resolve(word: "wonderful", syllableCount: 3) == nil)
    }
}
