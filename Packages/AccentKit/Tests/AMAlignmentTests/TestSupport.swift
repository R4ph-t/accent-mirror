import Foundation
import Synchronization
import Testing
import AMCore
@testable import AMAlignment

/// A tagger that answers from a fixed list and counts its calls.
final class SpyTagger: LexicalClassTagger {
    private let answer: LexicalClass
    private let calls = Mutex(0)

    init(always answer: LexicalClass = .noun) { self.answer = answer }

    var callCount: Int { calls.withLock { $0 } }

    func lexicalClasses(in text: String, words: [Range<String.Index>]) -> [LexicalClass] {
        calls.withLock { $0 += 1 }
        return words.map { _ in answer }
    }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

/// Heard words from a space-separated string, 0.3 s each, back to back.
func heard(_ text: String) throws -> [HeardWord] {
    try text.split(separator: " ").enumerated().map { i, word in
        HeardWord(text: String(word), range: try TimeRange(start: Double(i) * 0.3, end: Double(i) * 0.3 + 0.25))
    }
}

/// A phrase built by the bundled selector (starter origin, so the tagger is never involved).
func starterPhrase(_ text: String, targets: Set<Int>? = nil) throws -> ExpectedPhrase {
    try PronunciationSelector.bundled(tagger: SpyTagger())
        .expectedPhrase(for: PhraseText(text: text, origin: .starter, targets: targets.map { Set($0.map { WordIndex($0) }) }))
}

/// A compact, readable rendering of an alignment for table tests: "a b ~x(c) -d +e".
/// Plain = present, ~heard(phrase) = substituted, -word = missing, +word = inserted.
func render(_ alignment: WordAlignment, _ phrase: ExpectedPhrase) -> String {
    alignment.pairs.map { pair in
        switch pair {
        case .present(let p, _): phrase.words[p.rawValue].folded
        case .substituted(let p, let heard, _): "~\(WordText.fold(heard))(\(phrase.words[p.rawValue].folded))"
        case .missing(let p): "-\(phrase.words[p.rawValue].folded)"
        case .inserted(let heard, _, _): "+\(WordText.fold(heard))"
        }
    }.joined(separator: " ")
}