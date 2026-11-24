// The text each engine receives. ElevenLabs: inline SSML `<phoneme alphabet="cmu-arpabet">` (Flash v2 and Turbo v2,
// English only). Mac voices: `<speak>` SSML with `<phoneme alphabet="ipa">` and a bookmark before every word, so
// word starts come from the synthesizer itself (as spec 07's TTS marker gate does).

import AMAlignment
import Foundation

/// One word to speak: its text and, when the stress must be controlled, its pronunciation.
public struct SpokenWord: Sendable, Hashable, Codable {
    public let text: String
    /// ARPAbet with stress digits; nil lets the engine choose.
    public let arpabet: String?

    public init(text: String, arpabet: String? = nil) {
        self.text = text
        self.arpabet = arpabet
    }
}

public enum SSML {
    /// ElevenLabs' text: words separated by spaces, a controlled word as
    /// `<phoneme alphabet="cmu-arpabet" ph="F OW1 T AH0 G R AE2 F">photograph</phoneme>`.
    public static func elevenLabs(_ words: [SpokenWord]) -> String {
        words.map { word in
            guard let arpabet = word.arpabet else { return escape(word.text) }
            return #"<phoneme alphabet="cmu-arpabet" ph="\#(escape(arpabet))">\#(escape(word.text))</phoneme>"#
        }.joined(separator: " ")
    }

    /// The Mac voices' SSML: `<speak>`, a bookmark `w<N>` before word N, a controlled word as an IPA phoneme.
    public static func apple(_ words: [SpokenWord]) throws -> String {
        let body = try words.enumerated().map { index, word in
            let mark = #"<mark name="w\#(index)"/>"#
            guard let arpabet = word.arpabet else { return mark + escape(word.text) }
            let ipa = ARPAbetIPA.ipa(try Pronunciation(arpabet: arpabet))
            return mark + #"<phoneme alphabet="ipa" ph="\#(escape(ipa))">\#(escape(word.text))</phoneme>"#
        }.joined(separator: " ")
        return "<speak>" + body + "</speak>"
    }

    public static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// ARPAbet to IPA for Apple's `<phoneme alphabet="ipa">`, with a primary (ˈ) or secondary (ˌ) mark before each
/// stressed syllable. AH0 and ER0 become their reduced forms (ə, ɚ).
public enum ARPAbetIPA {
    static let table: [String: String] = [
        "AA": "ɑ", "AE": "æ", "AH": "ʌ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ", "B": "b", "CH": "tʃ", "D": "d",
        "DH": "ð", "EH": "ɛ", "ER": "ɝ", "EY": "eɪ", "F": "f", "G": "ɡ", "HH": "h", "IH": "ɪ", "IY": "i",
        "JH": "dʒ", "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ", "OW": "oʊ", "OY": "ɔɪ", "P": "p",
        "R": "ɹ", "S": "s", "SH": "ʃ", "T": "t", "TH": "θ", "UH": "ʊ", "UW": "u", "V": "v", "W": "w",
        "Y": "j", "Z": "z", "ZH": "ʒ",
    ]

    public static func ipa(_ pronunciation: Pronunciation) -> String {
        pronunciation.syllables.map { syllable in
            let mark = switch syllable.stress {
            case .primary: "ˈ"
            case .secondary: "ˌ"
            case .unstressed: ""
            }
            return mark + syllable.phones.map(symbol).joined()
        }.joined()
    }

    static func symbol(_ phone: String) -> String {
        let digit = phone.last.flatMap { $0.isNumber ? $0 : nil }
        let base = digit == nil ? phone : String(phone.dropLast())
        if digit == "0" && base == "AH" { return "ə" }
        if digit == "0" && base == "ER" { return "ɚ" }
        return table[base] ?? base.lowercased()
    }
}
