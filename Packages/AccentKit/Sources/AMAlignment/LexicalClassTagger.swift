// Part of speech for imported phrases (plan §3.1 rule 2): NLTagger, language set explicitly to English.

import Foundation
import NaturalLanguage

/// The parts of speech the stress-shift mapping knows. Anything else is `other` (ambiguous).
public enum LexicalClass: String, Sendable, Hashable, Codable {
    case noun, verb, adjective, other
}

/// Tags the words of a phrase. A seam so tests can prove when the tagger is (not) called.
public protocol LexicalClassTagger: Sendable {
    /// One class per word range, in order.
    func lexicalClasses(in text: String, words: [Range<String.Index>]) -> [LexicalClass]
}

/// `NLTagger` with `.lexicalClass` and the language set to `.english` (never guessed). On device, no assets fetched.
public struct NaturalLanguageTagger: LexicalClassTagger {
    public init() {}

    public func lexicalClasses(in text: String, words: [Range<String.Index>]) -> [LexicalClass] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let whole = text.startIndex..<text.endIndex
        tagger.setLanguage(.english, range: whole)

        var tagged: [(range: Range<String.Index>, tag: NLTag?)] = []
        tagger.enumerateTags(
            in: whole, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            tagged.append((range, tag))
            return true
        }
        return words.map { word in
            // The first tagger token inside our whitespace token ("don't" → "do" + "n't" takes "do").
            guard let hit = tagged.first(where: { $0.range.overlaps(word) }) else { return .other }
            switch hit.tag {
            case .noun?: return .noun
            case .verb?: return .verb
            case .adjective?: return .adjective
            default: return .other
            }
        }
    }
}
