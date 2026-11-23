// ARPAbet pronunciations and the syllabifier (spec 06).

import Foundation
import AMCore

/// One ARPAbet pronunciation, vowels carrying their CMUdict stress digit (1 primary, 2 secondary, 0 none).
/// Encodes as its ARPAbet string, e.g. "R EH1 K ER0 D".
public struct Pronunciation: Sendable, Hashable, Codable, CustomStringConvertible {
    public let phones: [String]
    public let syllables: [Syllable]

    public enum Invalid: Error, Equatable {
        case empty
        case unknownPhone(String)
        case vowelWithoutStress(String)
    }

    public init(arpabet: String) throws(Invalid) {
        let phones = arpabet.split(whereSeparator: \.isWhitespace).map { String($0).uppercased() }
        guard !phones.isEmpty else { throw .empty }
        for phone in phones {
            if let digit = phone.last, digit.isNumber {
                guard "012".contains(digit), ARPAbet.vowels.contains(String(phone.dropLast())) else {
                    throw .unknownPhone(phone)
                }
            } else if ARPAbet.vowels.contains(phone) {
                throw .vowelWithoutStress(phone)
            } else if !ARPAbet.consonants.contains(phone) {
                throw .unknownPhone(phone)
            }
        }
        self.phones = phones
        self.syllables = Syllabifier.syllables(of: phones)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let arpabet = try container.decode(String.self)
        do {
            try self.init(arpabet: arpabet)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ARPAbet \(arpabet): \(error)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(arpabet)
    }

    public var arpabet: String { phones.joined(separator: " ") }
    public var description: String { arpabet }
    public var stressPattern: [SyllableStress] { syllables.map(\.stress) }
    /// The first syllable with primary stress, if any.
    public var primarySyllable: Int? { syllables.firstIndex { $0.stress == .primary } }
}

/// One syllable of a dictionary pronunciation, with its dictionary stress.
public struct Syllable: Sendable, Hashable {
    public let phones: [String]
    public let stress: SyllableStress
}

enum ARPAbet {
    static let vowels: Set<String> = [
        "AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW",
    ]
    static let consonants: Set<String> = [
        "B", "CH", "D", "DH", "F", "G", "HH", "JH", "K", "L", "M", "N", "NG", "P", "R", "S", "SH", "T", "TH", "V", "W",
        "Y", "Z", "ZH",
    ]

    static func isVowel(_ phone: String) -> Bool { phone.last?.isNumber == true }

    static func stress(of vowel: String) -> SyllableStress {
        switch vowel.last {
        case "1": .primary
        case "2": .secondary
        default: .unstressed
        }
    }
}

public enum Syllabifier {
    /// Legal English onsets, the consonant clusters that may start a syllable. Every consonant but NG on its own,
    /// plus the usual two- and three-consonant clusters. L Y, N Y, T Y and D Y are left out (they split in US
    /// English: "val·ue", "on·ion").
    static let legalOnsets: Set<[String]> = {
        var onsets = Set(ARPAbet.consonants.subtracting(["NG"]).map { [$0] })
        let clusters = [
            "P R", "P L", "P Y", "B R", "B L", "B Y", "T R", "T W", "D R", "D W", "K R", "K L", "K W", "K Y", "G R", "G L",
            "G W", "G Y", "F R", "F L", "F Y", "V Y", "TH R", "TH W", "SH R", "S P", "S T", "S K", "S M", "S N", "S L",
            "S W", "S F", "M Y", "HH Y", "S P R", "S P L", "S P Y", "S T R", "S K R", "S K W", "S K Y", "S K L",
        ]
        for cluster in clusters { onsets.insert(cluster.split(separator: " ").map(String.init)) }
        return onsets
    }()

    /// ARPAbet → syllables by maximum onset: between two vowels, the longest run of consonants that is a legal onset
    /// starts the next syllable; the rest close the previous one. Each syllable carries its vowel's dictionary stress.
    /// A pronunciation without a vowel ("hmm", HH M) is one unstressed syllable.
    public static func syllables(of phones: [String]) -> [Syllable] {
        let vowelPositions = phones.indices.filter { ARPAbet.isVowel(phones[$0]) }
        guard !vowelPositions.isEmpty else { return [Syllable(phones: phones, stress: .unstressed)] }

        var starts = [0]
        for (previous, next) in zip(vowelPositions, vowelPositions.dropFirst()) {
            let cluster = Array(phones[(previous + 1)..<next].map(stripStress))
            var onsetLength = 0
            for length in stride(from: cluster.count, through: 1, by: -1)
            where legalOnsets.contains(Array(cluster.suffix(length))) {
                onsetLength = length
                break
            }
            starts.append(next - onsetLength)
        }
        return starts.indices.map { i in
            let end = i + 1 < starts.count ? starts[i + 1] : phones.count
            let slice = Array(phones[starts[i]..<end])
            return Syllable(phones: slice, stress: ARPAbet.stress(of: phones[vowelPositions[i]]))
        }
    }

    /// Out-of-vocabulary words: syllables from vowel groups in the spelling (a, e, i, o, u, and y after the first
    /// letter), a final silent "e" dropped, and a consonant run between groups split with one consonant going to
    /// the next syllable. Always at least one syllable. No stress is known.
    public static func spellingSyllables(of word: String) -> [String] {
        let letters = Array(WordText.fold(word))
        guard !letters.isEmpty else { return [] }
        func isVowel(_ i: Int) -> Bool {
            let c = letters[i]
            return "aeiou".contains(c) || (c == "y" && i > 0 && !isVowelLetter(letters[i - 1]))
        }
        var groups: [Range<Int>] = []
        var i = 0
        while i < letters.count {
            if isVowel(i) {
                var end = i + 1
                while end < letters.count, isVowel(end) { end += 1 }
                groups.append(i..<end)
                i = end
            } else {
                i += 1
            }
        }
        // Silent final e: "name", but not "table" (consonant + le) or "the".
        if groups.count > 1, let last = groups.last, last == (letters.count - 1)..<letters.count, letters.last == "e",
            !(letters.count >= 3 && letters[letters.count - 2] == "l" && !isVowelLetter(letters[letters.count - 3]))
        {
            groups.removeLast()
        }
        guard groups.count > 1 else { return [String(letters)] }

        var cuts: [Int] = []
        for (previous, next) in zip(groups, groups.dropFirst()) {
            let consonants = next.lowerBound - previous.upperBound
            cuts.append(consonants == 0 ? next.lowerBound : next.lowerBound - 1)
        }
        var pieces: [String] = []
        var from = 0
        for cut in cuts {
            pieces.append(String(letters[from..<cut]))
            from = cut
        }
        pieces.append(String(letters[from...]))
        return pieces
    }

    private static func isVowelLetter(_ c: Character) -> Bool { "aeiouy".contains(c) }
    private static func stripStress(_ phone: String) -> String {
        phone.last?.isNumber == true ? String(phone.dropLast()) : phone
    }
}
