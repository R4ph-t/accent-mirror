import Foundation
import Testing
import AMCore
@testable import AMAlignment

@Suite("Pronunciation selection (plan §3.1)")
struct PronunciationSelectionTests {
    func selector(_ tagger: any LexicalClassTagger) throws -> PronunciationSelector {
        try PronunciationSelector.bundled(tagger: tagger)
    }

    func word(_ phrase: ExpectedPhrase, _ text: String) throws -> ExpectedWord {
        try #require(phrase.words.first { $0.folded == text })
    }

    @Test("\"record\" as a noun and as a verb chooses different variants through the real tagger")
    func recordNounVersusVerb() throws {
        let selector = try selector(NaturalLanguageTagger())
        let noun = try word(
            selector.expectedPhrase(for: PhraseText(text: "They set a new record.", origin: .imported(persisted: [:]))),
            "record")
        let verb = try word(
            selector.expectedPhrase(for: PhraseText(text: "She will record the song.", origin: .imported(persisted: [:]))),
            "record")
        #expect(noun.source == .tagger && verb.source == .tagger)
        #expect(!noun.expectedAmbiguous && !verb.expectedAmbiguous)
        #expect(noun.pronunciation?.arpabet == "R EH1 K ER0 D")
        #expect(verb.pronunciation?.arpabet == "R AH0 K AO1 R D")
        #expect(noun.expectedPattern == [.primary, .unstressed])
        #expect(verb.expectedPattern == [.unstressed, .primary])
    }

    @Test("An override beats the tagger, and the tagger isn't asked")
    func overrideBeatsTagger() throws {
        let spy = SpyTagger(always: .noun)
        let verbForm = try Pronunciation(arpabet: "R IH0 K AO1 R D")
        let phrase = try selector(spy).expectedPhrase(
            for: PhraseText(
                text: "A new world record.", origin: .imported(persisted: [:]), overrides: [WordIndex(3): verbForm]))
        let record = try word(phrase, "record")
        #expect(record.source == .override)
        #expect(record.pronunciation == verbForm)
        #expect(!record.expectedAmbiguous)
        #expect(spy.callCount == 0)
    }

    @Test("A persisted import pronunciation is used without calling the tagger")
    func persistedImportSkipsTagger() throws {
        let spy = SpyTagger(always: .noun)
        let saved = PersistedPronunciation(
            word: WordIndex(1), text: "record", pronunciation: try Pronunciation(arpabet: "R AH0 K AO1 R D"),
            expectedAmbiguous: false, chosenBy: .tagger)
        let phrase = try selector(spy).expectedPhrase(
            for: PhraseText(text: "Please record the meeting.", origin: .imported(persisted: [WordIndex(1): saved])))
        let record = try word(phrase, "record")
        #expect(record.source == .persistedImport)
        #expect(record.pronunciation?.primarySyllable == 1)
        #expect(spy.callCount == 0)
    }

    @Test("A persisted ambiguous choice stays ambiguous without re-tagging")
    func persistedAmbiguousStays() throws {
        let spy = SpyTagger(always: .noun)
        let first = try selector(spy).expectedPhrase(
            for: PhraseText(text: "Record it.", origin: .imported(persisted: [:])))
        let persisted = Dictionary(uniqueKeysWithValues: first.persistable.map { ($0.word, $0) })
        let again = try selector(spy).expectedPhrase(
            for: PhraseText(text: "Record it.", origin: .imported(persisted: persisted)))
        #expect(try word(again, "record").expectedAmbiguous)
        #expect(try word(again, "record").source == .persistedImport)
        #expect(spy.callCount == 0)
    }

    @Test("The persisted value round-trips through JSON as ARPAbet")
    func persistedRoundTrips() throws {
        let value = PersistedPronunciation(
            word: WordIndex(2), text: "Record", pronunciation: try Pronunciation(arpabet: "R EH1 K ER0 D"),
            expectedAmbiguous: false, chosenBy: .tagger)
        let json = try JSONEncoder().encode(value)
        #expect(String(decoding: json, as: UTF8.self).contains("\"R EH1 K ER0 D\""))
        #expect(try JSONDecoder().decode(PersistedPronunciation.self, from: json) == value)
    }

    @Test("A two-token import with \"record\" is expectedAmbiguous, and the tagger isn't asked")
    func twoTokenImportIsAmbiguous() throws {
        let spy = SpyTagger(always: .noun)
        let phrase = try selector(spy).expectedPhrase(for: PhraseText(text: "Record it.", origin: .imported(persisted: [:])))
        let record = try word(phrase, "record")
        #expect(record.expectedAmbiguous)
        #expect(record.expectedPattern == nil)
        #expect(record.syllableCount == 2)
        #expect(spy.callCount == 0)
    }

    @Test("A tag other than noun, verb or adjective is expectedAmbiguous")
    func otherTagIsAmbiguous() throws {
        let phrase = try selector(SpyTagger(always: .other)).expectedPhrase(
            for: PhraseText(text: "We present it today.", origin: .imported(persisted: [:])))
        #expect(try word(phrase, "present").expectedAmbiguous)
        #expect(try word(phrase, "present").source == .tagger)
    }

    @Test("A POS the curated table leaves out is expectedAmbiguous (\"desert\")")
    func uncuratedPOSIsAmbiguous() throws {
        let phrase = try selector(SpyTagger(always: .noun)).expectedPhrase(
            for: PhraseText(text: "The hot desert sun.", origin: .imported(persisted: [:])))
        #expect(try word(phrase, "desert").expectedAmbiguous)
    }

    @Test("A word with one primary pattern takes the first CMUdict variant; starters never tag")
    func dictionaryFirstVariant() throws {
        let spy = SpyTagger(always: .verb)
        let phrase = try selector(spy).expectedPhrase(
            for: PhraseText(text: "Some people love photography.", origin: .starter))
        let photography = try word(phrase, "photography")
        #expect(photography.source == .dictionary)
        #expect(!photography.expectedAmbiguous)
        #expect(photography.expectedPattern == [.unstressed, .primary, .unstressed, .unstressed])
        // A stress-shift word in a starter phrase with no override has no single pattern to expect.
        let record = try word(
            try selector(spy).expectedPhrase(for: PhraseText(text: "A new world record.", origin: .starter)), "record")
        #expect(record.source == .dictionary && record.expectedAmbiguous)
        #expect(spy.callCount == 0)
    }

    @Test("An unknown word syllabifies from its spelling and is expectedAmbiguous")
    func unknownWord() throws {
        let phrase = try selector(SpyTagger()).expectedPhrase(
            for: PhraseText(text: "The zorblat sings.", origin: .imported(persisted: [:])))
        let unknown = try word(phrase, "zorblat")
        #expect(unknown.source == .unknown)
        #expect(unknown.pronunciation == nil)
        #expect(unknown.expectedAmbiguous)
        #expect(unknown.syllableCount == 2)
    }

    @Test("Content words are everything off the function-word list; contractions follow their expansion")
    func contentWords() throws {
        let phrase = try starterPhrase("I don't think the rainbow was there, let's go.")
        let content = phrase.words.filter(\.isContent).map(\.folded)
        #expect(content == ["think", "rainbow", "let's", "go"])
    }

    @Test("Import targets default to content words with at least two syllables; starters use the phrase JSON")
    func targets() throws {
        let imported = try selector(SpyTagger()).expectedPhrase(
            for: PhraseText(text: "The rainbow is a beautiful bridge.", origin: .imported(persisted: [:])))
        #expect(imported.words.filter(\.isTarget).map(\.folded) == ["rainbow", "beautiful"])
        let starter = try starterPhrase("The rainbow is a beautiful bridge.", targets: [5])
        #expect(starter.words.filter(\.isTarget).map(\.folded) == ["bridge"])
    }

    @Test("Bare punctuation takes no word index (CPO's \"There is , according\")")
    func barePunctuationSkipped() {
        let tokens = phraseTokens("There is , according to legend.")
        #expect(tokens.map(\.folded) == ["there", "is", "according", "to", "legend"])
        #expect(tokens[2].index == WordIndex(2))
    }
}

@Suite("NLTagger regression fixture")
struct TaggerRegressionTests {
    struct Document: Decodable {
        struct Row: Decodable {
            let sentence: String
            let word: String
            let pos: String
            let tagger: String
            let expectedPrimarySyllable: Int?
        }

        let sentences: [Row]
    }

    @Test("Stress-shift words in noun and verb contexts choose the recorded variant")
    func fixture() throws {
        let document = try JSONDecoder().decode(Document.self, from: Fixture.data("tagger-stress-shift.json"))
        #expect(document.sentences.count >= 50)
        let selector = try PronunciationSelector.bundled(tagger: NaturalLanguageTagger())
        let tagger = NaturalLanguageTagger()
        var correctTags = 0
        for row in document.sentences {
            let tokens = phraseTokens(row.sentence)
            let index = try #require(tokens.firstIndex { $0.folded == row.word }, "\(row.sentence)")
            let tag = tagger.lexicalClasses(in: row.sentence, words: tokens.map(\.range))[index]
            #expect(tag.rawValue == row.tagger, "\(row.sentence): tagger said \(tag)")
            if tag.rawValue == row.pos { correctTags += 1 }

            let word = selector.expectedPhrase(for: PhraseText(text: row.sentence, origin: .imported(persisted: [:])))
                .words[index]
            #expect(word.source == .tagger, "\(row.sentence)")
            if let expected = row.expectedPrimarySyllable {
                #expect(!word.expectedAmbiguous, "\(row.sentence)")
                #expect(word.pronunciation?.primarySyllable == expected - 1, "\(row.sentence)")
            } else {
                #expect(word.expectedAmbiguous, "\(row.sentence)")
            }
        }
        // The known misses are in the fixture (rows where tagger != pos); this only catches a broad regression.
        #expect(correctTags == document.sentences.filter { $0.tagger == $0.pos }.count)
    }
}

@Suite("Starter-phrase validator")
struct StarterPhraseValidatorTests {
    func load(_ name: String) throws -> PhrasePronunciationFile {
        try JSONDecoder().decode(PhrasePronunciationFile.self, from: Fixture.data(name))
    }

    @Test("Rejects a target with CMUdict stress variants and no override")
    func rejectsMissingOverride() throws {
        let problems = StarterPhraseValidator.problems(
            in: try load("phrase-missing-override.json"), dictionary: try .bundled())
        #expect(problems == [.targetNeedsOverride(word: WordIndex(5), text: "record.")])
    }

    @Test("Accepts a phrase whose variant targets all have overrides")
    func acceptsOverride() throws {
        let file = try load("phrase-with-override.json")
        #expect(StarterPhraseValidator.problems(in: file, dictionary: try .bundled()).isEmpty)
        let phrase = try PronunciationSelector.bundled(tagger: SpyTagger()).expectedPhrase(for: try file.phraseText())
        #expect(phrase.words[1].source == .override)
        #expect(phrase.words[1].pronunciation?.arpabet == "K AH0 N")
        #expect(phrase.words.filter(\.isTarget).map(\.folded) == ["can", "train"])
    }

    @Test("Flags out-of-range indices and invalid ARPAbet")
    func flagsBadInput() throws {
        let file = PhrasePronunciationFile(text: "A new record.", targets: [2, 7], pronunciations: [2: "R EH9 K"])
        let problems = StarterPhraseValidator.problems(in: file, dictionary: try .bundled())
        #expect(problems == [.invalidOverride(word: WordIndex(2), arpabet: "R EH9 K"), .wordIndexOutOfRange(WordIndex(7))])
    }
}
