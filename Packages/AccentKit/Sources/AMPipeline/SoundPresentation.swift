// What the v5 result screen says about a judged take's sounds (Designer addendum v5 "Sound flags and word
// playback"): plain-English sound labels, card 1's ranking, the word popover's list and the playback windows. Pure
// and UI-free, so the rules are tested here and the app only draws them. Confidence ranks; it is never shown.

import AMCore

/// One sound in plain English, with its IPA for tooltips and VoiceOver only (v5 §5: IPA never appears inline).
public struct SoundLabel: Sendable, Hashable {
    /// "th as in think".
    public let plain: String
    /// "/θ/".
    public let ipa: String

    public init(plain: String, ipa: String) {
        self.plain = plain
        self.ipa = ipa
    }
}

public enum SoundLabels {
    /// v5 §5: the 39 CMUdict phones (stress digits stripped), plus `AH0`, the unstressed schwa (engine ruling,
    /// 2026-11-25: `AH0` stays apart from `AH`).
    public static let expected: [String: SoundLabel] = [
        // Vowels
        "AA": SoundLabel(plain: "a as in father", ipa: "/ɑ/"),
        "AE": SoundLabel(plain: "a as in cat", ipa: "/æ/"),
        "AH": SoundLabel(plain: "u as in cup", ipa: "/ʌ/"),
        "AH0": SoundLabel(plain: "a as in about", ipa: "/ə/"),
        "AO": SoundLabel(plain: "aw as in law", ipa: "/ɔ/"),
        "AW": SoundLabel(plain: "ow as in now", ipa: "/aʊ/"),
        "AY": SoundLabel(plain: "i as in time", ipa: "/aɪ/"),
        "EH": SoundLabel(plain: "e as in bed", ipa: "/ɛ/"),
        "ER": SoundLabel(plain: "ir as in bird", ipa: "/ɝ/"),
        "EY": SoundLabel(plain: "ay as in day", ipa: "/eɪ/"),
        "IH": SoundLabel(plain: "i as in sit", ipa: "/ɪ/"),
        "IY": SoundLabel(plain: "ee as in see", ipa: "/i/"),
        "OW": SoundLabel(plain: "o as in go", ipa: "/oʊ/"),
        "OY": SoundLabel(plain: "oy as in boy", ipa: "/ɔɪ/"),
        "UH": SoundLabel(plain: "oo as in book", ipa: "/ʊ/"),
        "UW": SoundLabel(plain: "oo as in food", ipa: "/u/"),
        // Consonants
        "B": SoundLabel(plain: "b as in bed", ipa: "/b/"),
        "CH": SoundLabel(plain: "ch as in chair", ipa: "/tʃ/"),
        "D": SoundLabel(plain: "d as in dog", ipa: "/d/"),
        "DH": SoundLabel(plain: "th as in this", ipa: "/ð/"),
        "F": SoundLabel(plain: "f as in fun", ipa: "/f/"),
        "G": SoundLabel(plain: "g as in go", ipa: "/ɡ/"),
        "HH": SoundLabel(plain: "h as in hat", ipa: "/h/"),
        "JH": SoundLabel(plain: "j as in jam", ipa: "/dʒ/"),
        "K": SoundLabel(plain: "k as in key", ipa: "/k/"),
        "L": SoundLabel(plain: "l as in lip", ipa: "/l/"),
        "M": SoundLabel(plain: "m as in man", ipa: "/m/"),
        "N": SoundLabel(plain: "n as in no", ipa: "/n/"),
        "NG": SoundLabel(plain: "ng as in sing", ipa: "/ŋ/"),
        "P": SoundLabel(plain: "p as in pen", ipa: "/p/"),
        "R": SoundLabel(plain: "r as in red", ipa: "/ɹ/"),
        "S": SoundLabel(plain: "s as in sit", ipa: "/s/"),
        "SH": SoundLabel(plain: "sh as in she", ipa: "/ʃ/"),
        "T": SoundLabel(plain: "t as in tin", ipa: "/t/"),
        "TH": SoundLabel(plain: "th as in think", ipa: "/θ/"),
        "V": SoundLabel(plain: "v as in van", ipa: "/v/"),
        "W": SoundLabel(plain: "w as in wet", ipa: "/w/"),
        "Y": SoundLabel(plain: "y as in yes", ipa: "/j/"),
        "Z": SoundLabel(plain: "z as in zoo", ipa: "/z/"),
        "ZH": SoundLabel(plain: "s as in vision", ipa: "/ʒ/"),
    ]

    /// The judge's competitor tokens (espeak IPA, the spike's English set) that stand for exactly one phone above.
    /// Tokens that could be several phones (`e`, `ᵻ`, the flap `ɾ`), the glottal stop `ʔ` and the vowel+R composites
    /// have no plain label: they read as "sounded unclear" rather than a guess.
    static let heardPhone: [String: String] = [
        "ɑː": "AA", "ɑ": "AA", "æ": "AE", "a": "AE", "ʌ": "AH", "ə": "AH0", "ɐ": "AH0", "ɔː": "AO", "ɔ": "AO",
        "aʊ": "AW", "aɪ": "AY", "ɛ": "EH", "ɜː": "ER", "ɚ": "ER", "eɪ": "EY", "ɪ": "IH", "iː": "IY", "i": "IY",
        "oʊ": "OW", "o": "OW", "oː": "OW", "ɔɪ": "OY", "ʊ": "UH", "uː": "UW", "u": "UW",
        "b": "B", "tʃ": "CH", "d": "D", "ð": "DH", "f": "F", "ɡ": "G", "h": "HH", "dʒ": "JH", "k": "K", "l": "L",
        "m": "M", "n": "N", "ŋ": "NG", "p": "P", "ɹ": "R", "s": "S", "ʃ": "SH", "t": "T", "θ": "TH", "v": "V",
        "w": "W", "j": "Y", "z": "Z", "ʒ": "ZH",
    ]

    /// The plain label for an expected phone; any stress digit is dropped except `AH0`'s.
    public static func expected(_ phone: String) -> SoundLabel? {
        if let label = expected[phone] { return label }
        return expected[String(phone.filter { !$0.isNumber })]
    }

    /// The plain label for a heard espeak token, nil when it doesn't stand for one English phone.
    public static func heard(_ token: String) -> SoundLabel? {
        heardPhone[token].flatMap { expected[$0] }
    }
}

/// One flagged sound as the result screen words it.
public struct SoundHint: Sendable, Hashable {
    public enum Heard: Sendable, Hashable {
        /// "sounded closer to t as in tin".
        case closer(SoundLabel)
        /// No clear other sound, the same sound, or one with no plain label (v5 rulings): "sounded unclear".
        case unclear
    }

    public let wordIndex: Int
    public let word: String
    public let expected: SoundLabel
    public let heard: Heard
    /// The sound on your take's timeline; nil when it wasn't heard.
    public let youRange: TimeRange?

    /// The plain label shown when an expected phone has none (never expected: the table covers CMUdict).
    public static let unknownSound = SoundLabel(plain: "this sound", ipa: "")

    public init(word: JudgedWord, phone: JudgedPhone) {
        wordIndex = word.index.rawValue
        self.word = word.text
        let expected = SoundLabels.expected(phone.phone) ?? Self.unknownSound
        self.expected = expected
        youRange = word.youRange == nil ? nil : phone.youRange
        if case .sound(let token) = phone.heardInstead, let label = SoundLabels.heard(token),
           label.plain != expected.plain {
            heard = .closer(label)
        } else {
            heard = .unclear
        }
    }

    /// "sounded closer to t as in tin" or "sounded unclear".
    public var heardLine: String {
        switch heard {
        case .closer(let label): "sounded closer to \(label.plain)"
        case .unclear: "sounded unclear"
        }
    }

    /// Tooltip and VoiceOver secondary line: "Expected /θ/ · sounded closer to /t/".
    public var ipaLine: String {
        let expected = expected.ipa.isEmpty ? "" : "Expected \(self.expected.ipa) \u{00B7} "
        switch heard {
        case .closer(let label): return expected + "sounded closer to \(label.ipa)"
        case .unclear: return expected + "sounded unclear"
        }
    }

    /// VoiceOver's "Expected /θ/, heard /t/" (v5 §6, card 1 rows).
    public var spokenIPA: String {
        switch heard {
        case .closer(let label): "Expected \(expected.ipa), heard \(label.ipa)"
        case .unclear: "Expected \(expected.ipa), sounded unclear"
        }
    }
}

/// Card 1's `SOUNDS TO CHECK` and the word popover's flagged sounds (v5 §1.1, §3, rulings 2026-11-25).
public enum SoundsToCheck {
    public static let rowLimit = 3

    /// A word drawn flagged: a flagged sound in a word you said. A word missing from your take stays neutral (Designer
    /// ruling, 2026-11-25), so card 1 doesn't list it either.
    public static func isFlagged(_ word: JudgedWord) -> Bool {
        word.flagged && word.youRange != nil
    }

    /// Up to `limit` flagged words, each shown by its least confident flagged sound, least confident word first; and
    /// how many more flagged words there are. Ties keep phrase order.
    public static func rows(_ judgement: SoundJudgement, limit: Int = rowLimit) -> (rows: [SoundHint], more: Int) {
        let ranked = judgement.words.enumerated().compactMap { offset, word -> (Int, JudgedWord, JudgedPhone)? in
            guard isFlagged(word),
                  let lowest = word.phones.filter(\.flagged).min(by: { $0.confidence < $1.confidence })
            else { return nil }
            return (offset, word, lowest)
        }
        .sorted { a, b in a.2.confidence != b.2.confidence ? a.2.confidence < b.2.confidence : a.0 < b.0 }
        let shown = ranked.prefix(limit).map { SoundHint(word: $0.1, phone: $0.2) }
        return (Array(shown), max(0, ranked.count - shown.count))
    }

    /// Every flagged sound in a word, in word order (the popover's list).
    public static func hints(_ word: JudgedWord) -> [SoundHint] {
        guard isFlagged(word) else { return [] }
        return word.phones.filter(\.flagged).map { SoundHint(word: word, phone: $0) }
    }
}

/// The stretch of a recording a word or sound button plays (v5 ruling: 30 ms each side of your phone or word, a
/// 10 ms fade in and out, never reaching into the neighbouring words).
public enum SegmentWindow {
    public static let padding = 0.03
    public static let fade = 0.01

    /// `range` widened by `padding` each side, but not before `previousEnd` or after `nextStart` (the neighbouring
    /// words on the same timeline) unless the range itself already reaches there, and never before 0.
    public static func padded(_ range: TimeRange, padding: Double = padding, previousEnd: Double?,
                              nextStart: Double?) -> (start: Double, end: Double) {
        var start = range.start - padding
        var end = range.end + padding
        if let previousEnd { start = max(start, min(previousEnd, range.start)) }
        if let nextStart { end = min(end, max(nextStart, range.end)) }
        return (max(0, start), max(max(0, start), end))
    }

    /// Your take's window for word `index` of `judgement`, padded and clamped to the words either side; nil when the
    /// word wasn't heard.
    public static func you(word index: Int, in judgement: SoundJudgement) -> (start: Double, end: Double)? {
        guard let position = judgement.words.firstIndex(where: { $0.index.rawValue == index }),
              let range = judgement.words[position].youRange
        else { return nil }
        let (previous, next) = neighbours(position, in: judgement)
        return padded(range, previousEnd: previous, nextStart: next)
    }

    /// Your take's window for one sound of word `index`, padded and clamped to the words either side.
    public static func you(sound range: TimeRange, word index: Int,
                           in judgement: SoundJudgement) -> (start: Double, end: Double) {
        guard let position = judgement.words.firstIndex(where: { $0.index.rawValue == index }) else {
            return padded(range, previousEnd: nil, nextStart: nil)
        }
        let (previous, next) = neighbours(position, in: judgement)
        return padded(range, previousEnd: previous, nextStart: next)
    }

    /// The nearest heard words before and after `position` on your timeline.
    private static func neighbours(_ position: Int, in judgement: SoundJudgement) -> (Double?, Double?) {
        let words = judgement.words
        let previous = words[..<position].last(where: { $0.youRange != nil })?.youRange?.end
        let next = words[(position + 1)...].first(where: { $0.youRange != nil })?.youRange?.start
        return (previous, next)
    }
}
