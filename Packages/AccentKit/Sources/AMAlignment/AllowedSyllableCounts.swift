// Spec 26 §2: the allowed nucleus counts N_w of a word, as a set. N_w holds the syllable counts of every CMUdict
// pronunciation of the word (spec 06's bundled dictionary) plus the counts of the committed reduced forms
// (`Resources/ReducedForms/reduced-forms.json`, after Mermelstein 1975's alternative fluent-form syllabifications).
// Each count carries an index mapping: the take's syllable k (k-th assigned nucleus) → the context pronunciation's
// syllable, so A(w), `placementDecision` and S/U keep working on context indices.

import AMCore
import Foundation

/// One entry of `reduced-forms.json`.
public struct ReducedForm: Sendable, Hashable, Codable {
    public let word: String
    public let fullCount: Int
    public let reducedCount: Int
    /// Index of the syllable the shorter form lacks, counted in the longer form (see the file's
    /// `droppedSyllableMeaning`).
    public let droppedSyllable: Int
    /// CMUdict stress digit of that syllable.
    public let stress: Int
    public let source: String
}

/// The committed reduced-forms list (frozen once spec 26's grid started).
public struct ReducedForms: Sendable, Hashable {
    public static let resourcePath = "ReducedForms/reduced-forms.json"

    public let entries: [ReducedForm]
    /// Words of the spec's initial list whose reduced count CMUdict already lists (so no entry).
    public let alreadyInCMUdict: [String]
    /// SHA-256 of the file's bytes, recorded in the tuning log.
    public let sha256: String

    public init(data: Data) throws(ResourceError) {
        struct File: Decodable {
            let entries: [ReducedForm]
            let alreadyInCMUdict: [String]
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { throw .malformed(Self.resourcePath) }
        entries = file.entries
        alreadyInCMUdict = file.alreadyInCMUdict
        sha256 = SHA256Digest.hex(of: data)
    }

    public static func bundled() throws(ResourceError) -> ReducedForms { try cache.get() }

    private static let cache = Result<ReducedForms, ResourceError> { () throws(ResourceError) in
        try ReducedForms(data: BundledResource.data(resourcePath))
    }

    /// The entries for a word (folded).
    public func entries(for word: String) -> [ReducedForm] {
        let folded = WordText.fold(word)
        return entries.filter { WordText.fold($0.word) == folded }
    }
}

/// N_w for one word: every allowed count, each with its take-syllable → context-syllable mapping.
public struct AllowedSyllableCounts: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        /// The context pronunciation's own count.
        case context
        /// Another CMUdict pronunciation of the word with a different count.
        case cmudictAlternate
        /// A committed reduced form.
        case reducedForm
    }

    public struct Form: Sendable, Hashable, Codable {
        public let count: Int
        /// Per take syllable k (0..<count), the context syllable it is, or nil (an extra syllable with no context
        /// counterpart).
        public let contextIndex: [Int?]
        public let source: Source

        public init(count: Int, contextIndex: [Int?], source: Source) {
            self.count = count
            self.contextIndex = contextIndex
            self.source = source
        }
    }

    /// The context pronunciation's count.
    public let context: Int
    /// One form per allowed count, sorted by count. The context count is always present (identity mapping).
    public let forms: [Form]

    public init(context: Int, forms: [Form]) {
        self.context = context
        var byCount: [Int: Form] = [context: Form(count: context, contextIndex: Array(0..<context), source: .context)]
        for form in forms where byCount[form.count] == nil && form.count > 0 { byCount[form.count] = form }
        self.forms = byCount.values.sorted { $0.count < $1.count }
    }

    /// Only the context count (spec 25's N_w).
    public static func contextOnly(_ count: Int) -> AllowedSyllableCounts {
        AllowedSyllableCounts(context: count, forms: [])
    }

    public var counts: [Int] { forms.map(\.count) }

    public func form(for count: Int) -> Form? { forms.first { $0.count == count } }

    /// The allowed count closest to `p` (ties: the context count, then the smaller): N in s_w = 0.9 − 0.3·|P − N|.
    public func closest(to p: Int) -> Int {
        counts.min { a, b in
            let da = abs(a - p), db = abs(b - p)
            if da != db { return da < db }
            if (a == context) != (b == context) { return a == context }
            return a < b
        } ?? context
    }

    /// N_w for `word` with context pronunciation `context`: every CMUdict pronunciation's count (mapped through the
    /// syllabifier by aligning syllables) plus the reduced forms' counts.
    public static func of(
        word: String, context: Pronunciation, dictionary: PronouncingDictionary, reducedForms: ReducedForms
    ) -> AllowedSyllableCounts {
        let n = context.syllables.count
        var forms: [Form] = []
        for alternate in dictionary.pronunciations(of: word) where alternate.syllables.count != n {
            forms.append(Form(count: alternate.syllables.count,
                              contextIndex: align(alternate.syllables, to: context.syllables),
                              source: .cmudictAlternate))
        }
        for entry in reducedForms.entries(for: word) {
            // The entry pairs the context count with the other one; it only applies when its full count is the
            // context's (a reduction) or its reduced count is (a split, read the other way round).
            let other: Int
            if entry.fullCount == n { other = entry.reducedCount } else if entry.reducedCount == n { other = entry.fullCount } else { continue }
            guard other != n, other > 0 else { continue }
            let mapping: [Int?]
            if other < n {
                // The take lacks context syllable `droppedSyllable`.
                mapping = (0..<n).filter { $0 != entry.droppedSyllable }.map { Optional($0) }
            } else {
                // The take has an extra syllable at `droppedSyllable`.
                var index = 0
                mapping = (0..<other).map { k in
                    if k == entry.droppedSyllable { return nil }
                    defer { index += 1 }
                    return index
                }
            }
            guard mapping.count == other else { continue }
            forms.append(Form(count: other, contextIndex: mapping, source: .reducedForm))
        }
        return AllowedSyllableCounts(context: n, forms: forms)
    }

    /// Maps each syllable of `other` to a syllable of `context` by a monotonic alignment (Needleman–Wunsch, gaps
    /// free): same vowel scores 2, same stress 1. Unmatched syllables map to nil.
    static func align(_ other: [Syllable], to context: [Syllable]) -> [Int?] {
        func vowel(_ s: Syllable) -> String {
            (s.phones.first { $0.last?.isNumber == true }).map { String($0.dropLast()) } ?? ""
        }
        func score(_ a: Syllable, _ b: Syllable) -> Int {
            (vowel(a) == vowel(b) ? 2 : 0) + (a.stress == b.stress ? 1 : 0)
        }
        let m = other.count, n = context.count
        var best = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                best[i][j] = max(score(other[i], context[j]) + best[i + 1][j + 1], best[i + 1][j], best[i][j + 1])
            }
        }
        var mapping = [Int?](repeating: nil, count: m)
        var i = 0, j = 0
        while i < m && j < n {
            if best[i][j] == score(other[i], context[j]) + best[i + 1][j + 1] {
                mapping[i] = j
                i += 1
                j += 1
            } else if best[i][j] == best[i][j + 1] {
                j += 1
            } else {
                i += 1
            }
        }
        return mapping
    }
}
