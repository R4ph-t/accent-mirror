import Testing
import AMCore
@testable import AMAlignment

@Suite("Syllabifier")
struct SyllabifierTests {
    @Test("\"photography\" is pho·TOG·ra·phy: four syllables, primary on the second")
    func photography() throws {
        let pronunciation = try #require(try PronouncingDictionary.bundled().pronunciations(of: "photography").first)
        #expect(pronunciation.syllables.count == 4)
        #expect(pronunciation.stressPattern == [.unstressed, .primary, .unstressed, .unstressed])
        #expect(pronunciation.primarySyllable == 1)
        // Maximum onset: G R is a legal onset, so it opens the third syllable.
        #expect(pronunciation.syllables.map { $0.phones.joined(separator: " ") } == [
            "F AH0", "T AA1", "G R AH0", "F IY0",
        ])
    }

    @Test(
        "Maximum onset with the legal onset list",
        arguments: [
            ("EH2 K S P L AH0 N EY1 SH AH0 N", ["EH2 K", "S P L AH0", "N EY1", "SH AH0 N"]),  // explanation
            ("AE1 T L AE2 S", ["AE1 T", "L AE2 S"]),  // atlas: T L isn't an onset
            ("IH0 K S T R AH0", ["IH0 K", "S T R AH0"]),  // extra
            ("S IH1 NG ER0", ["S IH1 NG", "ER0"]),  // singer: NG never starts a syllable
            ("HH M", ["HH M"]),  // hmm: no vowel, one syllable
        ])
    func maximumOnset(arpabet: String, expected: [String]) throws {
        let syllables = try Pronunciation(arpabet: arpabet).syllables
        #expect(syllables.map { $0.phones.joined(separator: " ") } == expected)
    }

    @Test("Dictionary stress 1 / 2 / 0 is primary / secondary / unstressed")
    func stressLevels() throws {
        let pronunciation = try Pronunciation(arpabet: "EH2 K S P L AH0 N EY1 SH AH0 N")
        #expect(pronunciation.stressPattern == [.secondary, .unstressed, .primary, .unstressed])
    }

    @Test("Rejects invalid ARPAbet")
    func rejectsInvalid() {
        #expect(throws: Pronunciation.Invalid.empty) { try Pronunciation(arpabet: "  ") }
        #expect(throws: Pronunciation.Invalid.unknownPhone("QQ")) { try Pronunciation(arpabet: "QQ AH0") }
        #expect(throws: Pronunciation.Invalid.vowelWithoutStress("AH")) { try Pronunciation(arpabet: "K AH N") }
        #expect(throws: Pronunciation.Invalid.unknownPhone("AH3")) { try Pronunciation(arpabet: "K AH3 N") }
    }

    @Test(
        "Out-of-vocabulary words syllabify by vowel groups",
        arguments: [
            ("zorblat", ["zorb", "lat"]),
            ("flimbate", ["flim", "bate"]),  // silent final e
            ("snargle", ["snarg", "le"]),  // consonant + le keeps its syllable
            ("brr", ["brr"]),  // no vowel: still one syllable
            ("quoxy", ["quo", "xy"]),
        ])
    func spellingSyllables(word: String, expected: [String]) {
        #expect(Syllabifier.spellingSyllables(of: word) == expected)
    }
}
