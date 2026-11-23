// Word alignment model (plan §4.3). Only `present` words contribute syllables to measures.

import Foundation

public enum AlignedWordPair: Sendable, Hashable, Codable {
    case present(phrase: WordIndex, you: TimeRange)
    /// Kept for display and the inspector; never measured.
    case substituted(phrase: WordIndex, heard: String, you: TimeRange)
    case missing(phrase: WordIndex)
    /// Fillers are removed before alignment, so these are real insertions.
    case inserted(heard: String, you: TimeRange, afterPhrase: WordIndex?)

    /// The phrase word this pair stands for; nil for an insertion.
    public var phraseWord: WordIndex? {
        switch self {
        case .present(let phrase, _), .substituted(let phrase, _, _), .missing(let phrase): phrase
        case .inserted: nil
        }
    }

    /// Where the pair sits on your timeline; nil for a missing word.
    public var yourRange: TimeRange? {
        switch self {
        case .present(_, let you), .substituted(_, _, let you), .inserted(_, let you, _): you
        case .missing: nil
        }
    }
}

/// The alignment of your take to the phrase: pairs in your-time order, phrase order preserved
/// (Needleman–Wunsch +2 / −1 / −1, spec 06).
public struct WordAlignment: Sendable, Hashable, Codable {
    public let pairs: [AlignedWordPair]

    public enum Invalid: Error, Equatable {
        /// Phrase words must appear once each, in increasing order.
        case phraseOrderBroken(WordIndex)
        /// Timed pairs must not go back in your time.
        case yourTimeOrderBroken(index: Int)
    }

    public init(pairs: [AlignedWordPair]) throws {
        var lastPhrase: WordIndex?
        var lastStart = -Double.infinity
        for (index, pair) in pairs.enumerated() {
            if let phrase = pair.phraseWord {
                if let last = lastPhrase, phrase <= last { throw Invalid.phraseOrderBroken(phrase) }
                lastPhrase = phrase
            }
            if let range = pair.yourRange {
                if range.start < lastStart { throw Invalid.yourTimeOrderBroken(index: index) }
                lastStart = range.start
            }
        }
        self.pairs = pairs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pairs = try container.decode([AlignedWordPair].self, forKey: .pairs)
        do {
            try self.init(pairs: pairs)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .pairs, in: container, debugDescription: "Invalid WordAlignment: \(error)")
        }
    }
}
