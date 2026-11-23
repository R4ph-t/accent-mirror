// Normalisation (plan §4.1): the only equivalences allowed between phrase words and heard words. Case and
// punctuation are folded (`WordText.fold`), fillers are dropped and immediate repeats collapsed (`WordAligner`).
// Everything else is one row of `EquivalenceTable`; anything not in it is compared literally.

import Foundation

/// One equivalence: every form in it matches every other. A form is a sequence of folded words.
public struct EquivalenceRow: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// `contractions.txt`: "don't" ↔ "do not".
        case contraction
        /// `compounds.txt`: "train station" ↔ "train-station" ↔ "trainstation".
        case compound
        /// `us-uk.txt`: "color" ↔ "colour".
        case spelling
        /// Cardinals 0–9999, years as pairs, ordinals 1st–31st: "1990" ↔ "nineteen ninety".
        case number
    }

    public let kind: Kind
    public let forms: [[String]]
}

public struct EquivalenceTable: Sendable {
    public static let fillers: Set<String> = ["um", "uh", "er", "erm"]

    public let rows: [EquivalenceRow]
    /// A form, its words joined by a space → the rows it belongs to ("it's" is in two).
    private let rowsByForm: [String: [Int]]
    private let longestForm: Int

    public init(rows: [EquivalenceRow]) {
        var rowsByForm: [String: [Int]] = [:]
        var longest = 1
        for (id, row) in rows.enumerated() {
            for form in row.forms {
                let key = form.joined(separator: " ")
                if rowsByForm[key]?.contains(id) != true { rowsByForm[key, default: []].append(id) }
                longest = max(longest, form.count)
            }
        }
        self.rows = rows
        self.rowsByForm = rowsByForm
        self.longestForm = longest
    }

    /// The bundled lists plus the number rows, built once.
    public static func bundled() throws(ResourceError) -> EquivalenceTable { try cache.get() }

    private static let cache = Result<EquivalenceTable, ResourceError> { () throws(ResourceError) in
        var rows: [EquivalenceRow] = []
        for line in try BundledResource.listLines("contractions.txt") {
            rows.append(EquivalenceRow(kind: .contraction, forms: barSeparatedForms(line)))
        }
        for line in try BundledResource.listLines("us-uk.txt") {
            rows.append(EquivalenceRow(kind: .spelling, forms: barSeparatedForms(line)))
        }
        for line in try BundledResource.listLines("compounds.txt") {
            let parts = line.split(separator: " ").map { WordText.fold($0) }
            rows.append(
                EquivalenceRow(
                    kind: .compound, forms: [parts, [parts.joined(separator: "-")], [parts.joined()]]))
        }
        rows += NumberSpelling.rows()
        return EquivalenceTable(rows: rows)
    }

    private static func barSeparatedForms(_ line: String) -> [[String]] {
        line.split(separator: "|").map { form in form.split(separator: " ").map { WordText.fold($0) } }
    }

    /// True when two texts match word for word under this table, e.g. "it's" and "it has", "1990" and "nineteen
    /// ninety". Both directions give the same answer.
    public func areEquivalent(_ a: String, _ b: String) -> Bool {
        let left = canonicalTokens(a.split(whereSeparator: \.isWhitespace).map { WordText.fold($0) })
        let right = canonicalTokens(b.split(whereSeparator: \.isWhitespace).map { WordText.fold($0) })
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { $0.matches($1) }
    }

    /// Greedy longest match from left to right: each run of words that is a form in the table becomes one token
    /// keyed by its rows; any other word is a literal token.
    func canonicalTokens(_ words: [String]) -> [CanonicalToken] {
        var tokens: [CanonicalToken] = []
        var start = 0
        while start < words.count {
            var matched = false
            for length in stride(from: min(longestForm, words.count - start), through: 1, by: -1) {
                let key = words[start..<(start + length)].joined(separator: " ")
                if let ids = rowsByForm[key] {
                    tokens.append(CanonicalToken(keys: Set(ids.map { .row($0) }), words: start..<(start + length)))
                    start += length
                    matched = true
                    break
                }
            }
            if !matched {
                tokens.append(CanonicalToken(keys: [.literal(words[start])], words: start..<(start + 1)))
                start += 1
            }
        }
        return tokens
    }

    /// One word on its own (no multi-word forms).
    func canonicalToken(_ word: String, at index: Int) -> CanonicalToken {
        if let ids = rowsByForm[word] {
            return CanonicalToken(keys: Set(ids.map { .row($0) }), words: index..<(index + 1))
        }
        return CanonicalToken(keys: [.literal(word)], words: index..<(index + 1))
    }

    /// The expansions of a single-word contraction ("don't" → [["do", "not"]]); empty for anything else.
    func expansions(ofContraction word: String) -> [[String]] {
        guard let ids = rowsByForm[word] else { return [] }
        return ids.flatMap { id in
            rows[id].kind == .contraction ? rows[id].forms.filter { $0 != [word] } : []
        }
    }
}

/// A run of words that compares as one unit. Two tokens match when they share a key.
struct CanonicalToken: Sendable, Hashable {
    enum Key: Sendable, Hashable {
        case row(Int)
        case literal(String)
    }

    let keys: Set<Key>
    /// The words it covers, as indices into the word list it was built from.
    let words: Range<Int>

    func matches(_ other: CanonicalToken) -> Bool { !keys.isDisjoint(with: other.keys) }
}

/// The closed list of function words (`function-words.txt`, plan §4.2). A contraction is a function word when every
/// word of one of its expansions is ("don't" yes, "let's" no).
public struct FunctionWords: Sendable {
    private let words: Set<String>
    private let table: EquivalenceTable

    public init(words: Set<String>, table: EquivalenceTable) {
        self.words = words
        self.table = table
    }

    public static func bundled() throws(ResourceError) -> FunctionWords {
        FunctionWords(words: Set(try BundledResource.listLines("function-words.txt")), table: try .bundled())
    }

    public func contains(_ word: String) -> Bool {
        let folded = WordText.fold(word)
        if words.contains(folded) { return true }
        return table.expansions(ofContraction: folded).contains { $0.allSatisfy(words.contains) }
    }
}

/// Number ↔ spoken form rows (spec 06 Defaults): cardinals 0–9999 ("twenty-one", "one hundred and five"), years read
/// as pairs ("nineteen ninety", "nineteen oh five", "nineteen hundred"), ordinals 1st–31st ("21st", "twenty-first").
/// Anything else is compared literally.
enum NumberSpelling {
    static let units = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    static let ordinalUnits = [
        "zeroth", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
        "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth",
        "nineteenth",
    ]
    static let ordinalTens = ["", "", "twentieth", "thirtieth"]

    static func rows() -> [EquivalenceRow] {
        var rows: [EquivalenceRow] = []
        for n in 0...9999 {
            var forms = [[String(n)]] + cardinal(n)
            if n >= 1000 { forms += yearPair(n) }
            rows.append(EquivalenceRow(kind: .number, forms: unique(forms)))
        }
        for n in 1...31 {
            rows.append(EquivalenceRow(kind: .number, forms: unique([[String(n) + suffix(n)]] + ordinal(n))))
        }
        return rows
    }

    /// 0–99: "twenty one" and "twenty-one".
    static func belowHundred(_ n: Int) -> [[String]] {
        if n < 20 { return [[units[n]]] }
        let ten = tens[n / 10]
        let unit = n % 10
        return unit == 0 ? [[ten]] : [[ten, units[unit]], ["\(ten)-\(units[unit])"]]
    }

    /// 0–9999, with and without "and" before a final part under 100.
    static func cardinal(_ n: Int) -> [[String]] {
        if n < 100 { return belowHundred(n) }
        var heads: [[String]] = []
        var rest = n
        if n >= 1000 {
            heads.append([units[n / 1000], "thousand"])
            rest = n % 1000
        }
        if rest >= 100 {
            heads.append([units[rest / 100], "hundred"])
            rest %= 100
        }
        let head = heads.flatMap { $0 }
        guard rest > 0 else { return [head] }
        return belowHundred(rest).flatMap { tail in [head + tail, head + ["and"] + tail] }
    }

    /// 1000–9999 as two pairs: "nineteen ninety", "nineteen oh five", "nineteen hundred", "twenty twenty".
    static func yearPair(_ n: Int) -> [[String]] {
        let high = belowHundred(n / 100)
        let low = n % 100
        let lows: [[String]] =
            switch low {
            case 0: [["hundred"]]
            case 1..<10: [["oh", units[low]]]
            default: belowHundred(low)
            }
        return high.flatMap { h in lows.map { h + $0 } }
    }

    static func ordinal(_ n: Int) -> [[String]] {
        if n < 20 { return [[ordinalUnits[n]]] }
        let unit = n % 10
        if unit == 0 { return [[ordinalTens[n / 10]]] }
        let ten = tens[n / 10]
        return [[ten, ordinalUnits[unit]], ["\(ten)-\(ordinalUnits[unit])"]]
    }

    static func suffix(_ n: Int) -> String {
        if (11...13).contains(n % 100) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    private static func unique(_ forms: [[String]]) -> [[String]] {
        var seen = Set<[String]>()
        return forms.filter { seen.insert($0).inserted }
    }
}
