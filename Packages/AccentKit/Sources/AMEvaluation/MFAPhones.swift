// Spec 26: MFA phone tiers (spec 07's pinned MFA, english_mfa IPA phone set) read from an MFA JSON output
// (`mfa align --output_format json`: `{"tiers": {"words": {"entries": [[s, e, w]]}, "phones": {...}}}`). Used by the
// §1a timestamp check (vowel onsets) and the §1 count grid (vowel-inside floor, region–vowel IoU). Evaluation only.

import Foundation

public struct MFATiers: Sendable, Hashable {
    public struct Interval: Sendable, Hashable {
        public let start: Double
        public let end: Double
        public let label: String

        public init(start: Double, end: Double, label: String) {
            self.start = start
            self.end = end
            self.label = label
        }
    }

    public let words: [Interval]
    public let phones: [Interval]

    public init(words: [Interval], phones: [Interval]) {
        self.words = words
        self.phones = phones
    }

    /// Reads one MFA JSON output file.
    public init(contentsOf url: URL) throws {
        struct File: Decodable {
            struct Tier: Decodable { let entries: [Entry] }
            struct Entry: Decodable {
                let start: Double, end: Double, label: String
                init(from decoder: any Decoder) throws {
                    var c = try decoder.unkeyedContainer()
                    start = try c.decode(Double.self)
                    end = try c.decode(Double.self)
                    label = try c.decode(String.self)
                }
            }
            let tiers: [String: Tier]
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        func tier(_ name: String) -> [Interval] {
            (file.tiers[name]?.entries ?? []).map { Interval(start: $0.start, end: $0.end, label: $0.label) }
        }
        self.init(words: tier("words"), phones: tier("phones"))
    }

    /// The vowel intervals (syllable nuclei) of the phone tier, in time order.
    public var vowels: [Interval] { phones.filter { MFAPhoneClass.isVowel($0.label) } }
}

/// english_mfa's IPA phones, classed for the timestamp check and the count grid.
public enum MFAPhoneClass {
    /// Vowel symbols. A phone is a vowel when its first scalar is one of these (diphthongs such as `aj`, `əw`, `ɔj`
    /// and long vowels such as `iː` included). Syllabic consonants (`m̩`, `n̩`, `l̩`: U+0329) also count as nuclei.
    static let vowelScalars: Set<Character> = ["a", "e", "i", "o", "u", "æ", "ɐ", "ɑ", "ɒ", "ɔ", "ə", "ɚ", "ɛ", "ɜ", "ɝ",
                                               "ɪ", "ʉ", "ʊ", "ʌ", "ɘ", "ɵ", "ɨ", "ø", "œ", "y", "ɤ", "ɯ"]
    static let syllabicMark: Unicode.Scalar = "\u{0329}"

    public static func isVowel(_ phone: String) -> Bool {
        guard let first = phone.first else { return false }
        if phone.unicodeScalars.contains(syllabicMark) { return true }
        return vowelScalars.contains(first)
    }

    /// Voiceless obstruents (stops, affricates, fricatives, with english_mfa's aspiration, palatalisation and dental
    /// variants). A vowel right after one of these (or after silence) starts voicing: that's a voicing onset.
    public static func isVoiceless(_ phone: String) -> Bool {
        let base = phone.unicodeScalars.filter { !["ʰ", "ʲ", "\u{032A}", "ʷ"].contains($0) }
        let text = String(String.UnicodeScalarView(base))
        return ["p", "t", "k", "c", "ʈ", "q", "f", "θ", "s", "ʃ", "ç", "x", "h", "tʃ", "ts"].contains(text)
    }

    /// What precedes a vowel, for the onset-type breakdown.
    public enum OnsetType: String, Sendable, CaseIterable, Codable {
        case silence, voicelessStop, voicelessFricative
    }

    public static func onsetType(previous: MFATiers.Interval?, vowel: MFATiers.Interval) -> OnsetType? {
        // Silence is a gap in the phone tier (MFA writes no silence label) of at least 50 ms, or the clip's start.
        guard let previous, vowel.start - previous.end < 0.05 else { return .silence }
        guard isVoiceless(previous.label) else { return nil }
        let base = previous.label.unicodeScalars.first.map(Character.init) ?? " "
        return ["p", "t", "k", "c", "ʈ", "q"].contains(base) && previous.label != "tʃ" && previous.label != "ts"
            ? .voicelessStop : .voicelessFricative
    }
}
