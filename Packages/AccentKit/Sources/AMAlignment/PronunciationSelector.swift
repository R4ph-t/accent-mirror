// Pronunciation selection (plan §3.1), content words and targets (plan §4.2).

import Foundation
import AMCore

/// Where a word's expected pronunciation came from. Spec 08 builds the context-compatible accepted pattern (§3.3)
/// from `override`, or from the POS-selected and persisted variant (`persistedImport`, `tagger`).
public enum PronunciationSource: String, Sendable, Hashable, Codable, CaseIterable {
    /// The phrase JSON's `pronunciations` override.
    case override
    /// An import's pronunciation, chosen and saved at import time.
    case persistedImport
    /// An import's stress-shift word, chosen by part of speech now.
    case tagger
    /// The first CMUdict variant.
    case dictionary
    /// Out of vocabulary: syllables from the spelling.
    case unknown
}

/// An import's chosen pronunciation for one word, persisted into `phrase.json` at import time so re-analysis never
/// re-tags. Specs 16–17 store it; this spec only defines it.
public struct PersistedPronunciation: Sendable, Hashable, Codable {
    public let word: WordIndex
    /// The folded word it was chosen for. A persisted value for a different word is ignored.
    public let text: String
    /// nil when the word was out of vocabulary.
    public let pronunciation: Pronunciation?
    public let expectedAmbiguous: Bool
    /// Where the choice came from when it was made (`tagger`, `dictionary`, `unknown`, or `override`).
    public let chosenBy: PronunciationSource

    public init(
        word: WordIndex, text: String, pronunciation: Pronunciation?, expectedAmbiguous: Bool,
        chosenBy: PronunciationSource
    ) {
        self.word = word
        self.text = WordText.fold(text)
        self.pronunciation = pronunciation
        self.expectedAmbiguous = expectedAmbiguous
        self.chosenBy = chosenBy
    }
}

/// What the selector needs to know about a phrase.
public struct PhraseText: Sendable, Hashable {
    public enum Origin: Sendable, Hashable {
        /// A bundled starter phrase: overrides only, the tagger is never used.
        case starter
        /// A clip you imported, with whatever was persisted at import time (empty on the first analysis).
        case imported(persisted: [WordIndex: PersistedPronunciation])
    }

    public let text: String
    public let origin: Origin
    /// The phrase JSON's `pronunciations`, by word index.
    public let overrides: [WordIndex: Pronunciation]
    /// The phrase JSON's `targets`; nil means the import default (every content word with ≥ 2 syllables).
    public let targets: Set<WordIndex>?

    public init(
        text: String, origin: Origin, overrides: [WordIndex: Pronunciation] = [:], targets: Set<WordIndex>? = nil
    ) {
        self.text = text
        self.origin = origin
        self.overrides = overrides
        self.targets = targets
    }
}

/// One phrase word with its expected pronunciation.
public struct ExpectedWord: Sendable, Hashable {
    public let index: WordIndex
    /// As written in the phrase text.
    public let text: String
    public let folded: String
    /// The selected pronunciation; nil when the word is out of vocabulary.
    public let pronunciation: Pronunciation?
    /// Out-of-vocabulary words only: syllables from the spelling.
    public let spellingSyllables: [String]
    public let source: PronunciationSource
    /// No placement diff, and excluded from S and U (plan §3.1).
    public let expectedAmbiguous: Bool
    /// Not on the closed function-word list (plan §4.2).
    public let isContent: Bool
    public let isTarget: Bool

    public init(
        index: WordIndex, text: String, pronunciation: Pronunciation?, spellingSyllables: [String] = [],
        source: PronunciationSource, expectedAmbiguous: Bool, isContent: Bool, isTarget: Bool
    ) {
        self.index = index
        self.text = text
        self.folded = WordText.fold(text)
        self.pronunciation = pronunciation
        self.spellingSyllables = spellingSyllables
        self.source = source
        self.expectedAmbiguous = expectedAmbiguous
        self.isContent = isContent
        self.isTarget = isTarget
    }

    public var syllableCount: Int { pronunciation?.syllables.count ?? max(spellingSyllables.count, 1) }

    /// The expected stress pattern, one entry per syllable; nil when the word is `expectedAmbiguous`.
    public var expectedPattern: [SyllableStress]? { expectedAmbiguous ? nil : pronunciation?.stressPattern }
}

public struct ExpectedPhrase: Sendable, Hashable {
    public let words: [ExpectedWord]

    public init(words: [ExpectedWord]) { self.words = words }

    /// What an import saves into `phrase.json` so the next analysis reuses it without the tagger.
    public var persistable: [PersistedPronunciation] {
        words.map { word in
            PersistedPronunciation(
                word: word.index, text: word.folded, pronunciation: word.pronunciation,
                expectedAmbiguous: word.expectedAmbiguous, chosenBy: word.source)
        }
    }
}

/// Plan §3.1, per word, first match wins: override; (imports) persisted value, else NLTagger through the
/// stress-shift pairs; the first CMUdict variant when the word has one primary-stress pattern; unknown.
public struct PronunciationSelector: Sendable {
    public let dictionary: PronouncingDictionary
    public let stressShifts: StressShiftPairs
    public let functionWords: FunctionWords
    public let tagger: any LexicalClassTagger
    /// Fewer phrase tokens than this: a stress-shift word is ambiguous (the tagger has too little context).
    public static let minimumTokensForTagger = 3

    public init(
        dictionary: PronouncingDictionary, stressShifts: StressShiftPairs, functionWords: FunctionWords,
        tagger: any LexicalClassTagger = NaturalLanguageTagger()
    ) {
        self.dictionary = dictionary
        self.stressShifts = stressShifts
        self.functionWords = functionWords
        self.tagger = tagger
    }

    /// The selector over the bundled resources.
    public static func bundled(tagger: any LexicalClassTagger = NaturalLanguageTagger()) throws(ResourceError)
        -> PronunciationSelector
    {
        PronunciationSelector(
            dictionary: try .bundled(), stressShifts: try .bundled(), functionWords: try .bundled(), tagger: tagger)
    }

    public func expectedPhrase(for phrase: PhraseText) -> ExpectedPhrase {
        let tokens = phraseTokens(phrase.text)
        // The tagger runs at most once per phrase, and only when a word needs it.
        var classes: [LexicalClass]?
        func lexicalClass(of index: Int) -> LexicalClass {
            if classes == nil { classes = tagger.lexicalClasses(in: phrase.text, words: tokens.map(\.range)) }
            return classes?[index] ?? .other
        }

        let selected = tokens.enumerated().map { offset, token -> Selection in
            if let override = phrase.overrides[token.index] {
                return Selection(pronunciation: override, source: .override, ambiguous: false)
            }
            if case .imported(let persisted) = phrase.origin {
                if let saved = persisted[token.index], saved.text == token.folded {
                    return Selection(
                        pronunciation: saved.pronunciation, source: .persistedImport, ambiguous: saved.expectedAmbiguous)
                }
                if let entry = stressShifts.entry(for: token.folded) {
                    let first = try? Pronunciation(arpabet: entry.variants[0].arpabet)
                    guard tokens.count >= Self.minimumTokensForTagger,
                        let chosen = entry.pronunciation(for: lexicalClass(of: offset))
                    else { return Selection(pronunciation: first, source: .tagger, ambiguous: true) }
                    return Selection(pronunciation: chosen, source: .tagger, ambiguous: false)
                }
            }
            let variants = dictionary.pronunciations(of: token.folded)
            if let first = variants.first {
                // A stress-shift word with no override (starter phrases) has no single pattern to expect.
                let ambiguous = stressShifts.entry(for: token.folded) != nil
                return Selection(pronunciation: first, source: .dictionary, ambiguous: ambiguous)
            }
            return Selection(pronunciation: nil, source: .unknown, ambiguous: true)
        }

        let words = zip(tokens, selected).map { token, selection in
            let isContent = !functionWords.contains(token.folded)
            let spelling = selection.pronunciation == nil ? Syllabifier.spellingSyllables(of: token.folded) : []
            let syllables = selection.pronunciation?.syllables.count ?? max(spelling.count, 1)
            let isTarget = phrase.targets?.contains(token.index) ?? (isContent && syllables >= 2)
            return ExpectedWord(
                index: token.index, text: token.text, pronunciation: selection.pronunciation,
                spellingSyllables: spelling, source: selection.source, expectedAmbiguous: selection.ambiguous,
                isContent: isContent, isTarget: isTarget)
        }
        return ExpectedPhrase(words: words)
    }

    private struct Selection {
        let pronunciation: Pronunciation?
        let source: PronunciationSource
        let ambiguous: Bool
    }
}
