// ARPAbet -> judging units, a port of the judging spike's `gop.py` `units()` (espeak kind). Each unit is one expected
// phone (or a vowel+R / AH0+L composite) with the espeak token sequences that count as saying it right: lenient
// allophone classes, weak-form deletions and the optional word-final T/D. The tables are copied verbatim from the
// spike; changing one changes flags, so it needs a new `SoundScorer.judgeID`.

import Foundation

/// The espeak IPA tokens of the lv-60 model's vocabulary that the judge uses, with their ids.
public struct TokenVocabulary: Sendable, Hashable {
    /// Token -> id, for the tokens the judge can expect or report.
    public let ids: [String: Int]
    /// The CTC blank's id (`<pad>`, 0 for lv-60).
    public let blank: Int

    /// Builds the table from the model's full vocabulary in id order (the manifest's `vocabulary`). Nil when the
    /// blank or any English token the judge needs is missing.
    public init?(tokens: [String], blank: String) {
        var all: [String: Int] = [:]
        for (id, token) in tokens.enumerated() where all[token] == nil { all[token] = id }
        guard let blankID = all[blank] else { return nil }
        var ids: [String: Int] = [:]
        for token in Lexicon.englishTokens {
            guard let id = all[token] else { return nil }
            ids[token] = id
        }
        self.ids = ids
        self.blank = blankID
    }

    init(ids: [String: Int], blank: Int) {
        self.ids = ids
        self.blank = blank
    }

    /// The ids of `facebook/wav2vec2-lv-60-espeak-cv-ft`'s `vocab.json` for the English tokens (blank `<pad>` = 0).
    /// `SoundJudge` builds its table from the installed manifest instead; the parity fixtures check this one.
    public static let lv60Espeak = TokenVocabulary(ids: [
        "a": 9, "aɪ": 37, "aɪɚ": 131, "aʊ": 53, "b": 26, "d": 12, "dʒ": 60, "e": 16, "eɪ": 44, "f": 23, "h": 39,
        "i": 10, "iə": 81, "iː": 30, "j": 24, "k": 11, "l": 8, "m": 13, "n": 4, "o": 19, "oʊ": 49, "oː": 55,
        "oːɹ": 77, "p": 18, "s": 5, "t": 6, "tʃ": 66, "u": 34, "uː": 46, "v": 25, "w": 32, "z": 21, "æ": 36, "ð": 22,
        "ŋ": 42, "ɐ": 20, "ɑ": 59, "ɑː": 41, "ɑːɹ": 68, "ɔ": 40, "ɔɪ": 100, "ɔː": 67, "ɔːɹ": 71, "ə": 7, "əl": 61,
        "ɚ": 43, "ɛ": 14, "ɛɹ": 94, "ɜː": 63, "ɡ": 35, "ɪ": 17, "ɪɹ": 97, "ɹ": 27, "ɾ": 15, "ʃ": 38, "ʊ": 29,
        "ʊɹ": 104, "ʌ": 33, "ʒ": 65, "ʔ": 80, "θ": 52, "ᵻ": 50,
    ], blank: 0)

    /// Every English token's id, ascending: the substitutions the GOP denominator tries.
    var englishIDs: [Int] { Array(Set(ids.values)).sorted() }

    /// Id -> token, for `heardInstead`.
    var tokensByID: [Int: String] { Dictionary(ids.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a }) }
}

/// The spike's lenient classes and composites (`gop.py`, espeak kind), verbatim.
enum Lexicon {
    /// ARPAbet (stress stripped, or with a `0` suffix for the reduced forms) -> acceptable tokens, canonical first.
    static let classes: [String: [String]] = [
        "AA": ["ɑː", "ɑ"], "AE": ["æ", "a"], "AH": ["ʌ", "ə", "ɐ"], "AH0": ["ə", "ɐ", "ᵻ", "ɪ", "ʌ"],
        "AO": ["ɔː", "ɔ", "ɑː", "ɑ"], "AW": ["aʊ"], "AY": ["aɪ"], "EH": ["ɛ", "e"], "ER": ["ɜː", "ɚ"],
        "ER0": ["ɚ", "ə"], "EY": ["eɪ", "e"], "IH": ["ɪ", "ᵻ"], "IH0": ["ɪ", "ᵻ", "ə", "i", "iː"], "IY": ["iː", "i"],
        "IY0": ["i", "iː", "ɪ"], "OW": ["oʊ", "o", "oː"], "OY": ["ɔɪ"], "UH": ["ʊ"], "UW": ["uː", "u"],
        "UW0": ["uː", "u", "ʊ", "ə"],
        "B": ["b"], "CH": ["tʃ"], "D": ["d", "ɾ"], "DH": ["ð"], "F": ["f"], "G": ["ɡ"], "HH": ["h"], "JH": ["dʒ"],
        "K": ["k"], "L": ["l"], "M": ["m"], "N": ["n"], "NG": ["ŋ"], "P": ["p"], "R": ["ɹ"], "S": ["s"], "SH": ["ʃ"],
        "T": ["t", "ɾ", "ʔ"], "TH": ["θ"], "V": ["v"], "W": ["w"], "Y": ["j"], "Z": ["z"], "ZH": ["ʒ"],
    ]

    struct Pair: Hashable {
        let first: String
        let second: String
    }

    /// Vowel+R composites the espeak-trained model emits as one token.
    static let composites: [Pair: [String]] = [
        Pair(first: "AA", second: "R"): ["ɑːɹ"], Pair(first: "AO", second: "R"): ["ɔːɹ", "oːɹ"],
        Pair(first: "OW", second: "R"): ["oːɹ", "ɔːɹ"], Pair(first: "EH", second: "R"): ["ɛɹ"],
        Pair(first: "IH", second: "R"): ["ɪɹ"], Pair(first: "IY", second: "R"): ["ɪɹ", "iə"],
        Pair(first: "UH", second: "R"): ["ʊɹ"], Pair(first: "UW", second: "R"): ["ʊɹ"],
        Pair(first: "AY", second: "ER0"): ["aɪɚ"],
    ]

    /// Weak-form deletions: (word, phone) pairs whose phone may be dropped.
    static let functionDeletions: Set<Pair> = [
        Pair(first: "have", second: "HH"), Pair(first: "has", second: "HH"), Pair(first: "had", second: "HH"),
        Pair(first: "he", second: "HH"), Pair(first: "her", second: "HH"), Pair(first: "him", second: "HH"),
        Pair(first: "his", second: "HH"), Pair(first: "of", second: "V"), Pair(first: "and", second: "D"),
        Pair(first: "and", second: "N"),
    ]

    static let vowels: Set<String> = ["AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY",
                                      "UH", "UW"]

    /// `ENG` in the spike: every token a class or composite accepts, plus `ɑːɹ`, `əl` and `ʔ`.
    static let englishTokens: Set<String> = Set(classes.values.joined()).union(composites.values.joined())
        .union(["ɑːɹ", "əl", "ʔ"])

    static func stripStress(_ phone: String) -> String { phone.filter { !$0.isNumber } }

    /// `base()` in the spike: stress stripped, keeping a `0` suffix when a reduced class exists for it.
    static func classKey(_ phone: String) -> String {
        let stripped = stripStress(phone)
        return phone.hasSuffix("0") && classes[stripped + "0"] != nil ? stripped + "0" : stripped
    }

    static func isVowel(_ phone: String) -> Bool { vowels.contains(stripStress(phone)) }
}

/// One judging unit: the expected phones it covers (one, or two for a composite) and its acceptable token-id
/// sequences, canonical first. `[]` among them means the sound may be dropped.
struct JudgingUnit: Sendable, Hashable {
    /// Position of each member in the word's chosen ARPAbet variant.
    let members: [Int]
    let acceptable: [[Int]]
    var canonical: [Int] { acceptable[0] }
}

enum UnitBuilder {
    /// Units for one word, or nil when a phone has no class or a token isn't in the vocabulary (word unjudged).
    /// Units never span words, so building word by word equals the spike's whole-utterance pass.
    static func units(word: String, phones: [String], vocabulary: TokenVocabulary) -> [JudgingUnit]? {
        let text = normalised(word)
        var out: [JudgingUnit] = []
        var i = 0

        func ids(_ alternatives: [[String]]) -> [[Int]]? {
            var result: [[Int]] = []
            for alternative in alternatives {
                var seq: [Int] = []
                for token in alternative {
                    guard let id = vocabulary.ids[token] else { return nil }
                    seq.append(id)
                }
                if !result.contains(seq) { result.append(seq) }
            }
            return result
        }

        while i < phones.count {
            let p = phones[i]
            let b = Lexicon.stripStress(p)
            guard let cls = Lexicon.classes[Lexicon.classKey(p)] else { return nil }
            let next: String? = i + 1 < phones.count ? phones[i + 1] : nil
            let afterNext: String? = i + 2 < phones.count ? phones[i + 2] : nil
            if let nb = next {
                let key = Lexicon.Pair(first: b, second: nb == "ER0" ? "ER0" : Lexicon.stripStress(nb))
                let intervocalic = afterNext.map(Lexicon.isVowel) ?? false
                if let comp = Lexicon.composites[key], !intervocalic {  // no merge for intervocalic R
                    guard let nextCls = Lexicon.classes[Lexicon.classKey(nb)] else { return nil }
                    var alts = comp.map { [$0] }
                    for c in cls.prefix(2) { for n in nextCls.prefix(1) { alts.append([c, n]) } }
                    guard let acc = ids(alts) else { return nil }
                    out.append(JudgingUnit(members: [i, i + 1], acceptable: acc))
                    i += 2
                    continue
                }
                if p == "AH0", nb == "L", !intervocalic {
                    guard let acc = ids([["əl"], ["ə", "l"], ["l"], ["ɪ", "l"]]) else { return nil }
                    out.append(JudgingUnit(members: [i, i + 1], acceptable: acc))
                    i += 2
                    continue
                }
            }
            var alts = cls.map { [$0] }
            if p.hasSuffix("2"), Lexicon.vowels.contains(b) { alts += [["ə"], ["ɪ"]] }
            let last = next == nil
            if Lexicon.functionDeletions.contains(Lexicon.Pair(first: text, second: b))
                || ((b == "T" || b == "D") && last && i > 0) {
                alts.append([])
            }
            guard let acc = ids(alts), !acc.isEmpty, !acc[0].isEmpty else { return nil }
            out.append(JudgingUnit(members: [i], acceptable: acc))
            i += 1
        }
        return out
    }

    /// The spike's word form: lowercased, letters and apostrophes only (`re.findall(r"[a-z']+")`).
    static func normalised(_ word: String) -> String {
        String(word.lowercased().replacingOccurrences(of: "’", with: "'").filter {
            ("a"..."z").contains($0) || $0 == "'"
        })
    }
}
