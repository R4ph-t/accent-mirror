// An imported phrase as the pipeline reads it (spec 17): its words through spec 06's selector with the pronunciations
// persisted in phrase.json, and the clip's own analysis as the phrase's one native reference.
//
// Pronunciation (Designer v1 §8.3, Addendum A5): each word's context variant is chosen once (the tagger for
// stress-shift words) and persisted; a persisted value is used only while its folded text still matches the word. A
// content word of two or more syllables that isn't in CMUdict stays ambiguous (spec 28: its stress used to be measured
// from the clip, but observed stress is verdict-only now and out of the shipped graph). With scoring on, A(w) is the
// persisted context primary plus the clip's own high-confidence observed primary (`VerdictScorer`).

import AMAlignment
import AMCore
import AMLibrary
import AMProsody
import Foundation

public struct ImportedPhrases: Sendable {
    public let store: MyPhraseStore
    public let selector: PronunciationSelector
    public let analyzer: Analyzer

    public init(store: MyPhraseStore, selector: PronunciationSelector, analyzer: Analyzer) {
        self.store = store
        self.selector = selector
        self.analyzer = analyzer
    }

    /// The stored phrase as the analyzer reads it (the take store's recompute asks for this); nil when unknown.
    public func input(_ id: PhraseID) -> PhraseInput? { store.phrase(id).map(input) }

    /// `phrase`'s words from its text and persisted pronunciations. Never runs the tagger for a persisted word.
    public func input(_ phrase: MyPhrase) -> PhraseInput {
        let persisted = Self.persisted(phrase.pronunciations)
        return PhraseInput(
            id: phrase.id, words: Self.words(expected(phrase.text, persisted: persisted), measuring: false),
            transcriptRevision: phrase.transcriptRevision)
    }

    /// What `MyPhraseStore` injects: the key the running code gives a clip's analysis, and its rebuild from clip.caf.
    public var rebuilder: MyPhraseRebuilder {
        let phrases = self
        return MyPhraseRebuilder(
            expectedKey: { phrase in
                let input = phrases.input(phrase)
                return phrases.analyzer.l1Key(
                    l0: phrases.analyzer.l0Key(takeAudioSHA256: phrase.clipSHA256), phrase: input
                ).text
            },
            rebuild: { phrase, samples in
                let clip = TakeAudio(samples: samples, sha256: phrase.clipSHA256, recordedAt: phrase.createdAt)
                return try await phrases.analyzer.analyseNative(take: clip, phrase: phrases.input(phrase))
            })
    }

    /// The clip analysed as `text`'s reference: the pronunciations to persist and the analysis built with them.
    /// `persisted` is what phrase.json held before (empty at import). Throws what the analyzer's stages throw.
    func analyseClip(
        _ clip: TakeAudio, id: PhraseID, text: String, revision: Int, persisted stored: [StoredPronunciation]
    ) async throws -> (reference: DerivedRecord, pronunciations: [StoredPronunciation]) {
        let previous = Self.persisted(stored)
        let first = expected(text, persisted: previous)
        // Spec 28: an out-of-vocabulary word's stress is no longer measured from the clip (observed stress is
        // verdict-only and out of the shipped graph); it stays ambiguous, so no syllable of it is marked.
        let chosen = Self.stored(first, previous: stored)
        let final = expected(text, persisted: Self.persisted(chosen.ordered))
        let input = PhraseInput(id: id, words: Self.words(final, measuring: false), transcriptRevision: revision)
        return (try await analyzer.analyseNative(take: clip, phrase: input), chosen.ordered)
    }

    // MARK: - Words

    func expected(_ text: String, persisted: [WordIndex: PersistedPronunciation]) -> ExpectedPhrase {
        selector.expectedPhrase(for: PhraseText(text: text, origin: .imported(persisted: persisted)))
    }

    /// An out-of-vocabulary target: its stress is measured from the clip.
    static func needsMeasuring(_ word: ExpectedWord) -> Bool {
        word.pronunciation == nil && word.isContent && word.syllableCount >= 2
    }

    /// The analyzer's words. Targets are every content word of two or more syllables (plan §4.2), with A(w) seeded by
    /// the context primary; `measuring` accepts every syllable of an out-of-vocabulary target so its observed stress
    /// is recorded.
    static func words(_ phrase: ExpectedPhrase, measuring: Bool) -> [PlacementTake.Word] {
        phrase.words.map { word in
            let count = word.syllableCount
            let pronunciation = word.pronunciation ?? schwas(count)
            let accepted: Set<Int>? =
                if measuring && needsMeasuring(word) {
                    Set(0..<count)
                } else if word.isTarget, let pattern = word.expectedPattern, pattern.count >= 2,
                    let primary = pattern.firstIndex(of: .primary)
                {
                    [primary]
                } else {
                    nil
                }
            return PlacementTake.Word(
                index: word.index, text: word.text, pronunciation: pronunciation, accepted: accepted,
                expectedStress: word.expectedPattern)
        }
    }

    /// One unstressed schwa per spelling syllable: an out-of-vocabulary word still needs a syllable count.
    static func schwas(_ count: Int) -> Pronunciation {
        // Repeated "AH0" is always valid ARPAbet, so this never fails for a count of one or more.
        try! Pronunciation(arpabet: Array(repeating: "AH0", count: max(count, 1)).joined(separator: " "))
    }

    // MARK: - Persistence

    static func persisted(_ stored: [StoredPronunciation]) -> [WordIndex: PersistedPronunciation] {
        var out: [WordIndex: PersistedPronunciation] = [:]
        for value in stored {
            let pronunciation = value.arpabet.flatMap { try? Pronunciation(arpabet: $0) }
            if value.arpabet != nil && pronunciation == nil { continue }
            out[WordIndex(value.word)] = PersistedPronunciation(
                word: WordIndex(value.word), text: value.text, pronunciation: pronunciation,
                expectedAmbiguous: value.expectedAmbiguous,
                chosenBy: PronunciationSource(rawValue: value.chosenBy) ?? .persistedImport)
        }
        return out
    }

    /// What to persist for `phrase`: a stored value that was used (its folded text still matches) is kept as it was,
    /// so it records what first chose it; every other word records the selector's choice now. Keyed by word index.
    static func stored(_ phrase: ExpectedPhrase, previous: [StoredPronunciation]) -> [Int: StoredPronunciation] {
        let kept = Dictionary(previous.map { ($0.word, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Int: StoredPronunciation] = [:]
        for word in phrase.words {
            let index = word.index.rawValue
            if word.source == .persistedImport, let value = kept[index], value.text == word.folded {
                out[index] = value
            } else {
                out[index] = StoredPronunciation(
                    word: index, text: word.folded, arpabet: word.pronunciation?.arpabet,
                    expectedAmbiguous: word.expectedAmbiguous, chosenBy: word.source.rawValue)
            }
        }
        return out
    }
}

extension Dictionary where Key == Int, Value == StoredPronunciation {
    /// In word order, as phrase.json lists them.
    var ordered: [StoredPronunciation] { keys.sorted().compactMap { self[$0] } }
}
