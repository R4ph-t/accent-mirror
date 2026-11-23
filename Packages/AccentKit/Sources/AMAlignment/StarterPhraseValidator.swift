// The starter-phrase check (spec 06): a target word whose CMUdict variants differ in stress needs an override.
// Spec 15 runs it on the bundled phrases in CI.

import Foundation
import AMCore

/// The pronunciation fields of a phrase JSON file: `text`, 0-based word `targets` (after splitting on whitespace
/// and skipping bare punctuation) and `pronunciations` overrides keyed by word index, as ARPAbet strings. Spec 15
/// owns the full file; unknown keys are ignored here.
public struct PhrasePronunciationFile: Sendable, Hashable, Codable {
    public let text: String
    public let targets: [Int]
    public let pronunciations: [Int: String]

    public init(text: String, targets: [Int], pronunciations: [Int: String] = [:]) {
        self.text = text
        self.targets = targets
        self.pronunciations = pronunciations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        targets = try container.decodeIfPresent([Int].self, forKey: .targets) ?? []
        pronunciations = try container.decodeIfPresent([Int: String].self, forKey: .pronunciations) ?? [:]
    }

    /// The phrase as the selector reads it. Throws on an invalid ARPAbet override.
    public func phraseText() throws -> PhraseText {
        var overrides: [WordIndex: Pronunciation] = [:]
        for (index, arpabet) in pronunciations { overrides[WordIndex(index)] = try Pronunciation(arpabet: arpabet) }
        return PhraseText(
            text: text, origin: .starter, overrides: overrides, targets: Set(targets.map { WordIndex($0) }))
    }
}

public enum StarterPhraseProblem: Sendable, Hashable {
    /// The target has CMUdict stress variants and no `pronunciations` override.
    case targetNeedsOverride(word: WordIndex, text: String)
    /// A target or override index past the end of the phrase.
    case wordIndexOutOfRange(WordIndex)
    /// An override that isn't valid ARPAbet.
    case invalidOverride(word: WordIndex, arpabet: String)
}

public enum StarterPhraseValidator {
    /// Every problem in one phrase file; empty when it's fine.
    public static func problems(in file: PhrasePronunciationFile, dictionary: PronouncingDictionary)
        -> [StarterPhraseProblem]
    {
        let tokens = phraseTokens(file.text)
        var problems: [StarterPhraseProblem] = []
        for (index, arpabet) in file.pronunciations.sorted(by: { $0.key < $1.key }) {
            if !tokens.indices.contains(index) { problems.append(.wordIndexOutOfRange(WordIndex(index))) }
            if (try? Pronunciation(arpabet: arpabet)) == nil {
                problems.append(.invalidOverride(word: WordIndex(index), arpabet: arpabet))
            }
        }
        for index in file.targets.sorted() {
            guard tokens.indices.contains(index) else {
                problems.append(.wordIndexOutOfRange(WordIndex(index)))
                continue
            }
            let token = tokens[index]
            if file.pronunciations[index] == nil, dictionary.hasStressVariants(token.folded) {
                problems.append(.targetNeedsOverride(word: token.index, text: token.text))
            }
        }
        return problems
    }
}
