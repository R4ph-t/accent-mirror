// speechocean762 labels and the §6.3 gate sets.
//
// Definitions (each checked against the plan's counts by `SpeechOceanSetsTests`):
// - syllables: the phones of the corpus `ref-phones` that carry a stress digit (0, 1, 2). A few ref strings have a
//   vowel with no digit ("HERE" is `HH IH AH0`); that vowel is not counted.
// - stress-wrong: at least 3 of the 5 raters scored the word's stress 5 (the merged `scores.json` label agrees on
//   all 287 such words); unanimous stress-correct: all 5 scored 10; dissent: 1 or 2 raters scored 5.
// - a rater scored every phone 0 when every phone of their transcription, ignoring inserted `[…]` phones, is in
//   `(…)`; a word is unintelligible when at least 3 of 5 raters did.

import Foundation
import AMCore

public enum CorpusHalf: String, Sendable, Hashable, Codable, CaseIterable {
    case train
    case test
}

public enum AgeGroup: String, Sendable, Hashable, Codable {
    /// Ages 6–15 in speechocean762.
    case child
    /// Ages 19–43 in speechocean762.
    case adult
}

public struct SpeechOceanSpeaker: Sendable, Hashable, Codable {
    public let id: String
    public let half: CorpusHalf
    public let age: Int

    public init(id: String, half: CorpusHalf, age: Int) {
        self.id = id
        self.half = half
        self.age = age
    }

    /// Children are 15 and under; the corpus has no speaker aged 16–18.
    public var ageGroup: AgeGroup { age <= 15 ? .child : .adult }
}

/// One word token with the label facts the sets need. No audio.
public struct SpeechOceanWord: Sendable, Hashable, Codable {
    /// `<utterance>#<index>`, for example `000010011#3`.
    public let id: String
    public let utterance: String
    public let index: Int
    public let speaker: String
    public let text: String
    /// The corpus `ref-phones`, for example `B EH0 R`.
    public let refPhones: String
    /// Raters (of 5) who scored stress 5.
    public let stressWrongVotes: Int
    /// Raters (of 5) who scored every phone 0.
    public let allPhonesZeroVotes: Int

    public init(
        utterance: String, index: Int, speaker: String, text: String, refPhones: String, stressWrongVotes: Int,
        allPhonesZeroVotes: Int
    ) {
        self.id = "\(utterance)#\(index)"
        self.utterance = utterance
        self.index = index
        self.speaker = speaker
        self.text = text
        self.refPhones = refPhones
        self.stressWrongVotes = stressWrongVotes
        self.allPhonesZeroVotes = allPhonesZeroVotes
    }

    public var phones: [String] { refPhones.split(separator: " ").map(String.init) }
    /// Stress digits of the syllabic phones, in order.
    public var stressDigits: [Int] { phones.compactMap { $0.last.flatMap { Int(String($0)) } } }
    public var syllableCount: Int { stressDigits.count }
    public var isPolysyllabic: Bool { syllableCount >= 2 }
    /// The syllable the corpus ref-phones mark primary (digit 1), or nil when none is marked.
    public var refPrimary: Int? { stressDigits.firstIndex(of: 1) }
    public var isStressWrong: Bool { stressWrongVotes >= 3 }
    public var isUnanimousCorrect: Bool { stressWrongVotes == 0 }
    public var isDissent: Bool { (1...2).contains(stressWrongVotes) }
    public var isUnintelligible: Bool { allPhonesZeroVotes >= 3 }
}

/// Why a monosyllabic stress-wrong token is excluded (reported, never scored).
public enum MonosyllableCategory: String, Sendable, Hashable, Codable, CaseIterable {
    /// Unintelligible: ≥ 3 raters scored every phone 0.
    case wholeWordFailure
    /// One syllable in the ref-phones and in speech.
    case trueMonosyllable
    /// A syllabic L, M or N right after a consonant (`L IH1 T L`): two syllables in the spelling, one stress digit.
    case syllabicConsonantSpelling
    /// The ref-phones have no phones at all.
    case emptyPhoneString
    /// A vowel with no stress digit in the ref-phones (`HH IH AH0`).
    case unmarkedVowel

    static let vowels: Set<String> = [
        "AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW",
    ]

    public static func of(_ word: SpeechOceanWord) -> MonosyllableCategory {
        if word.isUnintelligible { return .wholeWordFailure }
        let phones = word.phones
        if phones.isEmpty { return .emptyPhoneString }
        let base = phones.map { $0.trimmingCharacters(in: .decimalDigits) }
        if zip(phones, base).contains(where: { $0 == $1 && vowels.contains($1) }) { return .unmarkedVowel }
        for i in 1..<max(1, base.count) where ["L", "M", "N"].contains(base[i]) {
            let previous = base[i - 1]
            let nextIsVowel = i + 1 < base.count && vowels.contains(base[i + 1])
            if !vowels.contains(previous) && !nextIsVowel { return .syllabicConsonantSpelling }
        }
        return .trueMonosyllable
    }
}

/// The label-only view of speechocean762: speakers (half and age) and word tokens.
public struct SpeechOceanLabels: Sendable, Hashable {
    public let speakers: [String: SpeechOceanSpeaker]
    public let words: [SpeechOceanWord]
    /// SHA-256 of the `scores-detail.json` the labels came from (the report's label hash).
    public let sourceSHA256: String

    public init(speakers: [String: SpeechOceanSpeaker], words: [SpeechOceanWord], sourceSHA256: String) {
        self.speakers = speakers
        self.words = words
        self.sourceSHA256 = sourceSHA256
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case malformed(line: Int, reason: String)
        case unknownSpeaker(String)

        public var description: String {
            switch self {
            case .malformed(let line, let reason): "labels line \(line): \(reason)"
            case .unknownSpeaker(let id): "unknown speaker \(id)"
            }
        }
    }

    public func speaker(of word: SpeechOceanWord) -> SpeechOceanSpeaker { speakers[word.speaker]! }
    public func half(of word: SpeechOceanWord) -> CorpusHalf { speaker(of: word).half }

    // MARK: Building from the corpus

    /// Counts the five raters' votes from one `scores-detail.json` word entry.
    static func votes(stress: [Double], phones: [String]) -> (wrong: Int, zero: Int) {
        let wrong = stress.filter { $0 < 10 }.count
        let zero = phones.filter { transcription in
            let tokens = transcription.split(separator: " ").filter { !$0.hasPrefix("[") }
            return tokens.allSatisfy { $0.hasPrefix("(") }
        }.count
        return (wrong, zero)
    }

    /// Reads `resource/scores-detail.json` plus the per-half `utt2spk` and `spk2age` files of the corpus.
    public static func fromCorpus(
        scoresDetail: Data, utt2spk: [CorpusHalf: String], spk2age: [CorpusHalf: String]
    ) throws -> SpeechOceanLabels {
        var speakers: [String: SpeechOceanSpeaker] = [:]
        var utteranceSpeaker: [String: String] = [:]
        for half in CorpusHalf.allCases {
            for line in (spk2age[half] ?? "").split(whereSeparator: \.isNewline) {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count == 2, let age = Int(fields[1]) else { continue }
                // spk2age uses bare numbers; utt2spk uses the same numbers.
                speakers[String(fields[0])] = SpeechOceanSpeaker(id: String(fields[0]), half: half, age: age)
            }
            for line in (utt2spk[half] ?? "").split(whereSeparator: \.isNewline) {
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count == 2 else { continue }
                utteranceSpeaker[String(fields[0])] = String(fields[1])
            }
        }
        guard let root = try JSONSerialization.jsonObject(with: scoresDetail) as? [String: Any] else {
            throw Failure.malformed(line: 0, reason: "scores-detail.json is not an object")
        }
        var words: [SpeechOceanWord] = []
        for utterance in root.keys.sorted() {
            guard let speaker = utteranceSpeaker[utterance] else { throw Failure.unknownSpeaker(utterance) }
            guard speakers[speaker] != nil else { throw Failure.unknownSpeaker(speaker) }
            let entry = root[utterance] as? [String: Any]
            for (index, raw) in ((entry?["words"] as? [[String: Any]]) ?? []).enumerated() {
                let stress = (raw["stress"] as? [NSNumber])?.map(\.doubleValue) ?? []
                let phones = raw["phones"] as? [String] ?? []
                let (wrong, zero) = votes(stress: stress, phones: phones)
                words.append(
                    SpeechOceanWord(
                        utterance: utterance, index: index, speaker: speaker, text: raw["text"] as? String ?? "",
                        refPhones: raw["ref-phones"] as? String ?? "", stressWrongVotes: wrong,
                        allPhonesZeroVotes: zero))
            }
        }
        return SpeechOceanLabels(
            speakers: speakers, words: words, sourceSHA256: SHA256Digest.hex(of: scoresDetail))
    }

    // MARK: The committed label-only fixture

    /// Words that can be in any §6.3 set: polysyllabic or stress-wrong. Everything else is dropped from the fixture.
    public var relevantWords: [SpeechOceanWord] { words.filter { $0.isPolysyllabic || $0.isStressWrong } }

    /// The fixture's text form: a header, one `S` line per speaker and one `W` line per relevant word.
    public func fixtureText(sourceDescription: String) -> String {
        var out = "# speechocean762 label-only fixture (spec 02). Derived from \(sourceDescription).\n"
        out += "# speechocean762 is CC BY 4.0 (fixtures/smoke/ATTRIBUTION.md). Only polysyllabic or stress-wrong words.\n"
        out += "# S speaker half age | W utterance index speaker text ref-phones stress-wrong-votes all-zero-votes\n"
        out += "source-sha256\t\(sourceSHA256)\n"
        for speaker in speakers.values.sorted(by: { $0.id < $1.id }) {
            out += "S\t\(speaker.id)\t\(speaker.half.rawValue)\t\(speaker.age)\n"
        }
        for word in relevantWords {
            out += "W\t\(word.utterance)\t\(word.index)\t\(word.speaker)\t\(word.text)\t\(word.refPhones)\t"
            out += "\(word.stressWrongVotes)\t\(word.allPhonesZeroVotes)\n"
        }
        return out
    }

    /// Parses `fixtureText`.
    public static func parseFixture(_ text: String) throws -> SpeechOceanLabels {
        var speakers: [String: SpeechOceanSpeaker] = [:]
        var words: [SpeechOceanWord] = []
        var source = ""
        for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch fields[0] {
            case "source-sha256" where fields.count == 2:
                source = fields[1]
            case "S" where fields.count == 4:
                guard let half = CorpusHalf(rawValue: fields[2]), let age = Int(fields[3]) else {
                    throw Failure.malformed(line: number + 1, reason: "bad speaker")
                }
                speakers[fields[1]] = SpeechOceanSpeaker(id: fields[1], half: half, age: age)
            case "W" where fields.count == 8:
                guard let index = Int(fields[2]), let wrong = Int(fields[6]), let zero = Int(fields[7]) else {
                    throw Failure.malformed(line: number + 1, reason: "bad word")
                }
                guard speakers[fields[3]] != nil else { throw Failure.unknownSpeaker(fields[3]) }
                words.append(
                    SpeechOceanWord(
                        utterance: fields[1], index: index, speaker: fields[3], text: fields[4], refPhones: fields[5],
                        stressWrongVotes: wrong, allPhonesZeroVotes: zero))
            default:
                throw Failure.malformed(line: number + 1, reason: "unexpected record")
            }
        }
        return SpeechOceanLabels(speakers: speakers, words: words, sourceSHA256: source)
    }
}

/// Every set in the §6.3 table, built from the labels.
public struct SpeechOceanSets: Sendable, Hashable {
    /// Polysyllabic stress-wrong words (both halves): 180.
    public let stressWrongPool: [SpeechOceanWord]
    /// The recall set: intelligible polysyllabic stress-wrong words: 134 / 72.
    public let recall: [SpeechOceanWord]
    /// Recall words with ≥ 4 of 5 raters agreeing: the diagnostic subset, 42.
    public let recallDiagnostic: [SpeechOceanWord]
    /// Test-half unanimous, intelligible, polysyllabic stress-correct words: supplementary FP set, 1,868 / 124.
    public let supplementaryFalsePositive: [SpeechOceanWord]
    /// The primary FP gate: the supplementary set minus every speaker with any token in tuning: 1,400 / 90.
    public let cleanFalsePositive: [SpeechOceanWord]
    /// Train-half unanimous, intelligible, polysyllabic stress-correct words: the tuning FP constraint, 1,705 / 120.
    public let tuningCorrect: [SpeechOceanWord]
    /// Intelligible polysyllabic words with 1–2 raters dissenting: reported (train 550, test 449).
    public let dissent: [SpeechOceanWord]
    /// Unintelligible words that are polysyllabic or stress-wrong: "must never be flagged", 157.
    public let unintelligible: [SpeechOceanWord]
    /// Monosyllabic stress-wrong tokens, excluded and listed with their category: 107.
    public let monosyllabicStressWrong: [(word: SpeechOceanWord, category: MonosyllableCategory)]

    public let labels: SpeechOceanLabels

    public init(labels: SpeechOceanLabels) {
        self.labels = labels
        let words = labels.words
        stressWrongPool = words.filter { $0.isStressWrong && $0.isPolysyllabic }
        recall = stressWrongPool.filter { !$0.isUnintelligible }
        recallDiagnostic = recall.filter { $0.stressWrongVotes >= 4 }
        let correct = words.filter { $0.isUnanimousCorrect && $0.isPolysyllabic && !$0.isUnintelligible }
        supplementaryFalsePositive = correct.filter { labels.half(of: $0) == .test }
        tuningCorrect = correct.filter { labels.half(of: $0) == .train }
        let tuningSpeakers = Set(recall.map(\.speaker)).union(tuningCorrect.map(\.speaker))
        cleanFalsePositive = supplementaryFalsePositive.filter { !tuningSpeakers.contains($0.speaker) }
        dissent = words.filter { $0.isDissent && $0.isPolysyllabic && !$0.isUnintelligible }
        unintelligible = words.filter { $0.isUnintelligible && ($0.isPolysyllabic || $0.isStressWrong) }
        monosyllabicStressWrong = words.filter { $0.isStressWrong && !$0.isPolysyllabic }
            .map { ($0, MonosyllableCategory.of($0)) }
    }

    public static func == (a: SpeechOceanSets, b: SpeechOceanSets) -> Bool { a.labels == b.labels }
    public func hash(into hasher: inout Hasher) { hasher.combine(labels) }

    /// Speakers of `words`.
    public static func speakers(_ words: [SpeechOceanWord]) -> Set<String> { Set(words.map(\.speaker)) }

    public func filter(_ words: [SpeechOceanWord], half: CorpusHalf) -> [SpeechOceanWord] {
        words.filter { labels.half(of: $0) == half }
    }

    public func filter(_ words: [SpeechOceanWord], age: AgeGroup) -> [SpeechOceanWord] {
        words.filter { labels.speaker(of: $0).ageGroup == age }
    }

    /// One recount against the plan's §6.3 table.
    public struct CountCheck: Sendable, Hashable {
        public let name: String
        public let actual: Int
        public let plan: Int
        /// The plan's monosyllable category split, which the plan does not define a rule for (see the spec's notes).
        public let isCategorySplit: Bool

        public var matches: Bool { actual == plan }
        public var line: String {
            "\(matches ? "match  " : "DIFFERS") \(name): \(actual)" + (matches ? "" : " (plan \(plan))")
        }
    }

    /// Every count the plan states (§6.3 table and rev 4), recounted. If one differs, the test fails and the
    /// difference goes to CTO; nobody edits these expected values to pass.
    public var countChecks: [CountCheck] {
        func speakers(_ words: [SpeechOceanWord]) -> Int { Self.speakers(words).count }
        let recallSpeakers = Self.speakers(recall)
        let dropped = tuningCorrect.filter { recallSpeakers.contains($0.speaker) }
        let usable = tuningCorrect.filter { !recallSpeakers.contains($0.speaker) }
        let cleanAdults = filter(cleanFalsePositive, age: .adult)
        let cleanChildren = filter(cleanFalsePositive, age: .child)
        let tenPlus = Dictionary(grouping: cleanFalsePositive, by: \.speaker).values.filter { $0.count >= 10 }.count
        let categories = Dictionary(grouping: monosyllabicStressWrong, by: \.category).mapValues(\.count)
        var rows: [(String, Int, Int, Bool)] = [
            ("stress-wrong polysyllabic pool", stressWrongPool.count, 180, false),
            ("pool, train words", filter(stressWrongPool, half: .train).count, 105, false),
            ("pool, train speakers", speakers(filter(stressWrongPool, half: .train)), 40, false),
            ("pool, test words", filter(stressWrongPool, half: .test).count, 75, false),
            ("pool, test speakers", speakers(filter(stressWrongPool, half: .test)), 36, false),
            ("recall set, words", recall.count, 134, false),
            ("recall set, speakers", recallSpeakers.count, 72, false),
            ("recall set, adult words", filter(recall, age: .adult).count, 108, false),
            ("recall set, adult speakers", speakers(filter(recall, age: .adult)), 48, false),
            ("recall set, child words", filter(recall, age: .child).count, 26, false),
            ("recall set, child speakers", speakers(filter(recall, age: .child)), 24, false),
            ("recall diagnostic (≥ 4 of 5)", recallDiagnostic.count, 42, false),
            ("recall diagnostic, train", filter(recallDiagnostic, half: .train).count, 26, false),
            ("recall diagnostic, test", filter(recallDiagnostic, half: .test).count, 16, false),
            ("primary FP gate (clean), words", cleanFalsePositive.count, 1400, false),
            ("primary FP gate (clean), speakers", speakers(cleanFalsePositive), 90, false),
            ("clean, adult words", cleanAdults.count, 693, false),
            ("clean, adult speakers", speakers(cleanAdults), 41, false),
            ("clean, child words", cleanChildren.count, 707, false),
            ("clean, child speakers", speakers(cleanChildren), 49, false),
            ("clean, speakers with ≥ 10 words", tenPlus, 74, false),
            ("supplementary FP set, words", supplementaryFalsePositive.count, 1868, false),
            ("supplementary FP set, speakers", speakers(supplementaryFalsePositive), 124, false),
            ("tuning FP constraint (train half), words", tuningCorrect.count, 1705, false),
            ("tuning FP constraint, speakers", speakers(tuningCorrect), 120, false),
            ("dropped when their speaker is in the outer fold, words", dropped.count, 406, false),
            ("dropped, speakers", speakers(dropped), 34, false),
            ("always usable, words", usable.count, 1299, false),
            ("always usable, speakers", speakers(usable), 86, false),
            ("dissent (1–2 raters), train", filter(dissent, half: .train).count, 550, false),
            ("dissent (1–2 raters), test", filter(dissent, half: .test).count, 449, false),
            ("unintelligible", unintelligible.count, 157, false),
            ("unintelligible, stress-wrong polysyllabic", unintelligible.filter { $0.isStressWrong && $0.isPolysyllabic }.count, 46, false),
            ("unintelligible, monosyllabic", unintelligible.filter { !$0.isPolysyllabic }.count, 73, false),
            ("unintelligible, stress-correct", unintelligible.filter { !$0.isStressWrong }.count, 38, false),
            ("monosyllabic stress-wrong", monosyllabicStressWrong.count, 107, false),
            ("monosyllabic, intelligible (reported only)", monosyllabicStressWrong.filter { !$0.word.isUnintelligible }.count, 34, false),
            ("monosyllabic, whole-word failures", categories[.wholeWordFailure] ?? 0, 73, false),
        ]
        rows += [
            ("monosyllabic, true monosyllables", categories[.trueMonosyllable] ?? 0, 25, true),
            ("monosyllabic, syllabic-consonant spellings", categories[.syllabicConsonantSpelling] ?? 0, 8, true),
            ("monosyllabic, empty phone string", categories[.emptyPhoneString] ?? 0, 1, true),
            ("monosyllabic, unmarked vowel (no plan category)", categories[.unmarkedVowel] ?? 0, 0, true),
        ]
        return rows.map { CountCheck(name: $0.0, actual: $0.1, plan: $0.2, isCategorySplit: $0.3) }
    }
}
