// The voice-verification items (plan §6.4): every target word in CPO's set plus the stress-trap list, each once with
// correct stress and once with stress moved to another syllable. Built from committed data only: CPO's 20 VCTK
// prompts (CC BY 4.0 text), spec 06's bundled CMUdict and stress-shift pairs. Never from speechocean762 or a
// held-out VCTK speaker.

import AMAlignment
import AMEvaluation
import Foundation

/// CPO's starter set: the 20 VCTK 0.92 shared-text prompts (`VCTK.starterPhrases`), as the corpus transcripts read
/// (p225's, p226's for 015). VCTK 0.92, CSTR, University of Edinburgh, CC BY 4.0.
public enum CPOSet {
    public static let phrases: [String: String] = [
        "002": "Ask her to bring these things with her from the store.",
        "003": "Six spoons of fresh snow peas, five thick slabs of blue cheese, and maybe a snack for her brother Bob.",
        "004": "We also need a small plastic snake and a big toy frog for the kids.",
        "005": "She can scoop these things into three red bags, and we will go meet her Wednesday at the train station.",
        "006": "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow.",
        "007": "The rainbow is a division of white light into many beautiful colors.",
        "008": "These take the shape of a long round arch, with its path high above, and its two ends apparently beyond the horizon.",
        "009": "There is, according to legend, a boiling pot of gold at one end.",
        "010": "People look, but no one ever finds it.",
        "011": "When a man looks for something beyond his reach, his friends say he is looking for the pot of gold at the end of the rainbow.",
        "012": "Throughout the centuries people have explained the rainbow in various ways.",
        "013": "Some have accepted it as a miracle without physical explanation.",
        "014": "To the Hebrews it was a token that there would be no more universal floods.",
        "015": "The Greeks used to imagine that it was a sign from the gods to foretell war or heavy rain.",
        "016": "The Norsemen considered the rainbow as a bridge over which the gods passed from earth to their home in the sky.",
        "017": "Others have tried to explain the phenomenon physically.",
        "018": "Aristotle thought that the rainbow was caused by reflection of the sun's rays by the rain.",
        "019": "Since then physicists have found that it is not reflection, but refraction by the raindrops which causes the rainbows.",
        "020": "Many complicated ideas about the rainbow have been formed.",
        "024": "This is a very common type of bow, one showing mainly red and yellow, with little or no green or blue.",
    ]

    /// The stress traps the spec adds to the stress-shift words found in CPO's set (Defaults).
    public static let extraTraps = ["photography", "photograph", "photographic"]
}

/// Correct stress, or stress moved to another syllable.
public enum StressVariant: String, Sendable, Hashable, Codable, CaseIterable {
    case correct
    case moved
}

/// One word to synthesize with a known primary.
public struct VerificationItem: Sendable, Hashable, Codable {
    /// `<word>/<variant>`, for example `photograph/moved`.
    public let id: String
    public let word: String
    public let variant: StressVariant
    /// The pronunciation to render, stress digits included.
    public let arpabet: String
    /// The syllable the rendering marks primary (index in word).
    public let markedSyllable: Int
    /// From the stress-trap list (stress-shift words in CPO's set, plus the extra traps).
    public let isTrap: Bool

    public init(word: String, variant: StressVariant, arpabet: String, markedSyllable: Int, isTrap: Bool) {
        self.id = "\(word)/\(variant.rawValue)"
        self.word = word
        self.variant = variant
        self.arpabet = arpabet
        self.markedSyllable = markedSyllable
        self.isTrap = isTrap
    }

    public func pronunciation() throws -> Pronunciation { try Pronunciation(arpabet: arpabet) }
}

public struct VerificationSet: Sendable, Hashable {
    /// CPO's target words: every word of CPO's 20 prompts with two or more syllables in its CMUdict pronunciation.
    public let targets: [String]
    /// The stress traps: stress-shift words in CPO's set, plus `CPOSet.extraTraps`.
    public let traps: [String]
    /// Two items per word (correct, moved), targets and traps merged, sorted by word.
    public let items: [VerificationItem]

    public enum Failure: Error, Equatable {
        case notInDictionary(String)
    }

    /// The words of CPO's prompts, folded, in first-seen order over the prompts sorted by id.
    public static func cpoWords() -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for id in CPOSet.phrases.keys.sorted() {
            for token in phraseTokens(CPOSet.phrases[id]!) where seen.insert(token.folded).inserted {
                out.append(token.folded)
            }
        }
        return out
    }

    public static func build(dictionary: PronouncingDictionary, stressShifts: StressShiftPairs) throws -> VerificationSet {
        func pronunciation(_ word: String) -> Pronunciation? { dictionary.pronunciations(of: word).first }
        let words = cpoWords()
        let targets = words.filter { (pronunciation($0)?.syllables.count ?? 0) >= 2 }
        let traps = Array(Set(words.filter { stressShifts.entry(for: $0) != nil } + CPOSet.extraTraps)).sorted()
        var items: [VerificationItem] = []
        for word in Set(targets + traps).sorted() {
            guard let correct = pronunciation(word), let primary = correct.primarySyllable,
                correct.syllables.count >= 2
            else { throw Failure.notInDictionary(word) }
            let isTrap = traps.contains(word)
            let marked = movedSyllable(from: primary, count: correct.syllables.count)
            items.append(VerificationItem(
                word: word, variant: .correct, arpabet: correct.arpabet, markedSyllable: primary, isTrap: isTrap))
            items.append(VerificationItem(
                word: word, variant: .moved, arpabet: try moving(correct, to: marked).arpabet, markedSyllable: marked,
                isTrap: isTrap))
        }
        return VerificationSet(targets: targets, traps: traps, items: items)
    }

    /// Where moved stress goes: the next syllable, or the previous one when the primary is last.
    public static func movedSyllable(from primary: Int, count: Int) -> Int {
        primary + 1 < count ? primary + 1 : primary - 1
    }

    /// `pronunciation` with its primary on `syllable`: the old primary becomes unstressed, every other digit stays.
    public static func moving(_ pronunciation: Pronunciation, to syllable: Int) throws -> Pronunciation {
        let phones = pronunciation.syllables.enumerated().flatMap { index, part in
            part.phones.map { phone -> String in
                guard let digit = phone.last, digit.isNumber else { return phone }
                let base = String(phone.dropLast())
                if index == syllable { return base + "1" }
                if digit == "1" { return base + "0" }
                return phone
            }
        }
        return try Pronunciation(arpabet: phones.joined(separator: " "))
    }
}
