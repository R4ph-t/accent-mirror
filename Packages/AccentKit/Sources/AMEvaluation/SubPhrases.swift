// VCTK sub-phrases (spec 24): shared prompts 021 and 023 run 7–13 s, so the 2–6 s trim rejects every clip. Each is
// split, once and from its text, into sub-phrases (`fixtures/vctk/sub-phrases.json`). Every speaker's clip is cut at
// the MFA boundaries of the same words (`fixtures/vctk/sub-phrase-cuts.json`, built locally by
// scripts/vctk-sub-phrase-cuts.sh), then trimmed by spec 02's rule unchanged.

import Foundation

/// The text normalisation spec 02's transcript check uses (tools/pick_vctk_eval_speakers.py `normalised`): lowercase,
/// apostrophes and hyphens dropped, anything else outside a–z a space, whitespace collapsed.
public enum VCTKText {
    public static func normalised(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "-", with: "")
        let letters = String(lowered.unicodeScalars.map { ("a"..."z").contains($0) || $0 == " " ? Character($0) : " " })
        return letters.split(separator: " ").joined(separator: " ")
    }

    public static func words(_ text: String) -> [String] {
        normalised(text).split(separator: " ").map(String.init)
    }
}

/// One sub-phrase: a contiguous word range of a shared prompt, defined once for every speaker.
public struct VCTKSubPhrase: Sendable, Hashable, Codable {
    /// `<prompt>-<letter>`, for example `021-a`.
    public let id: String
    /// The source prompt, for example `021`.
    public let prompt: String
    /// Index of the first and last word (inclusive) in the prompt's normalised words.
    public let firstWord: Int
    public let lastWord: Int
    /// The normalised text of those words.
    public let text: String
    /// Why the range ends where it does: `sentence` or `clause`.
    public let boundary: String

    public init(id: String, prompt: String, firstWord: Int, lastWord: Int, text: String, boundary: String) {
        self.id = id
        self.prompt = prompt
        self.firstWord = firstWord
        self.lastWord = lastWord
        self.text = text
        self.boundary = boundary
    }
}

/// `fixtures/vctk/sub-phrases.json`.
public struct VCTKSubPhraseTable: Sendable, Hashable, Codable {
    /// How the cuts were chosen (spec 24, Open question 1).
    public let rule: String
    /// Prompt id → its shared text with punctuation (the punctuation marks the boundaries).
    public let prompts: [String: String]
    public let subPhrases: [VCTKSubPhrase]

    public init(rule: String, prompts: [String: String], subPhrases: [VCTKSubPhrase]) {
        self.rule = rule
        self.prompts = prompts
        self.subPhrases = subPhrases
    }

    public static func load(_ url: URL) throws -> VCTKSubPhraseTable {
        try JSONDecoder().decode(VCTKSubPhraseTable.self, from: Data(contentsOf: url))
    }

    /// The prompts that are split: they leave the positive set and their sub-phrases replace them.
    public var splitPrompts: Set<String> { Set(subPhrases.map(\.prompt)) }

    /// The positive set's phrases: every shared prompt that isn't split, plus every sub-phrase.
    public var evaluationPhrases: [String] {
        (VCTK.phrases.filter { !splitPrompts.contains($0) } + subPhrases.map(\.id)).sorted()
    }

    /// Words that start a clause, so a range may end just before one (spec 24: "a conjunction that starts a clause").
    static let clauseConjunctions: Set<String> = [
        "and", "but", "or", "so", "yet", "since", "because", "although", "though", "while", "whereas", "if", "when",
    ]

    /// Everything wrong with the table, given spec 02's shared text (`phraseText` in eval-speakers.json). Empty when
    /// every sub-phrase is a contiguous word range of its prompt that starts at the prompt's start or a boundary and
    /// ends at a sentence end or a clause boundary.
    public func problems(phraseText: [String: String]) -> [String] {
        var out: [String] = []
        for (prompt, text) in prompts.sorted(by: { $0.key < $1.key }) {
            if VCTKText.normalised(text) != phraseText[prompt] {
                out.append("\(prompt): text is not spec 02's shared text")
            }
        }
        var letters: [String: Int] = [:]
        for sub in subPhrases {
            guard let text = prompts[sub.prompt] else {
                out.append("\(sub.id): no prompt \(sub.prompt)")
                continue
            }
            let index = letters[sub.prompt, default: 0]
            letters[sub.prompt] = index + 1
            let letter = String(UnicodeScalar(UInt8(ascii: "a") + UInt8(index)))
            if sub.id != "\(sub.prompt)-\(letter)" { out.append("\(sub.id): expected id \(sub.prompt)-\(letter)") }
            // Punctuated tokens, aligned one to one with the normalised words.
            let tokens = text.split(separator: " ").map(String.init).filter { !VCTKText.normalised($0).isEmpty }
            let words = tokens.map(VCTKText.normalised)
            guard sub.firstWord >= 0, sub.firstWord <= sub.lastWord, sub.lastWord < words.count else {
                out.append("\(sub.id): word range \(sub.firstWord)...\(sub.lastWord) is not inside the prompt")
                continue
            }
            if words[sub.firstWord...sub.lastWord].joined(separator: " ") != sub.text {
                out.append("\(sub.id): text is not words \(sub.firstWord)...\(sub.lastWord) of \(sub.prompt)")
            }
            func endsAt(_ i: Int) -> String? {
                if i == words.count - 1 || tokens[i].last.map({ ".?!".contains($0) }) == true { return "sentence" }
                if tokens[i].last.map({ ",;:".contains($0) }) == true || Self.clauseConjunctions.contains(words[i + 1]) {
                    return "clause"
                }
                return nil
            }
            if sub.firstWord > 0 && endsAt(sub.firstWord - 1) == nil {
                out.append("\(sub.id): does not start at a sentence or clause boundary")
            }
            if let boundary = endsAt(sub.lastWord) {
                if boundary != sub.boundary { out.append("\(sub.id): ends at a \(boundary) boundary, not \(sub.boundary)") }
            } else {
                out.append("\(sub.id): does not end at a sentence or clause boundary")
            }
        }
        return out
    }
}

/// One word of an MFA alignment (the `WordBaseline` clip format scripts/mfa-align.sh writes).
public struct VCTKTimedWord: Sendable, Hashable, Codable {
    public let word: String
    public let start: Double
    public let end: Double

    public init(word: String, start: Double, end: Double) {
        self.word = word
        self.start = start
        self.end = end
    }
}

/// Where one speaker's clip of a sub-phrase is cut, or why it isn't.
public enum VCTKSubPhraseCut: Sendable, Hashable, Codable {
    /// The cut, in seconds into the official `_mic1.flac`: the MFA span of the sub-phrase's words (`wordStart` to
    /// `wordEnd`) extended outward into the neighbouring silence (`extend`). `words` are the MFA words in the range,
    /// for audit. With no word after it, `end` may pass the clip's end; the audio is clamped at the clip edge.
    case cut(start: Double, end: Double, wordStart: Double, wordEnd: Double, words: [String])
    /// The transcript doesn't contain the sub-phrase text: the clip is not listed.
    case transcriptMismatch
    /// The MFA alignment doesn't contain the sub-phrase's words exactly once: rejected and counted, never guessed.
    case mfaMismatch(words: [String])
    /// No MFA alignment for the clip.
    case noAlignment

    /// The cut for `subPhrase` in a clip with this transcript and MFA alignment. The same rule for every speaker: the
    /// sub-phrase's words must appear exactly once, contiguously, in the alignment.
    public static func make(_ subPhrase: VCTKSubPhrase, transcript: String, alignment: [VCTKTimedWord]?) -> Self {
        guard " \(VCTKText.normalised(transcript)) ".contains(" \(subPhrase.text) ") else { return .transcriptMismatch }
        guard let alignment else { return .noAlignment }
        let target = subPhrase.text.split(separator: " ").map(String.init)
        // Each MFA word normalised; one that normalises to nothing (or to several words) never matches.
        let words = alignment.map { VCTKText.normalised($0.word) }
        let starts = words.count >= target.count
            ? (0...(words.count - target.count)).filter { Array(words[$0..<($0 + target.count)]) == target } : []
        guard starts.count == 1, let first = starts.first else { return .mfaMismatch(words: words) }
        let last = first + target.count - 1
        let (start, end) = extend(
            wordStart: alignment[first].start, wordEnd: alignment[last].end,
            previousEnd: first > 0 ? alignment[first - 1].end : nil,
            nextStart: last + 1 < alignment.count ? alignment[last + 1].start : nil)
        return .cut(
            start: start, end: end, wordStart: alignment[first].start, wordEnd: alignment[last].end,
            words: Array(words[first...last]))
    }

    /// Room for spec 02's trim rule at a cut: its pre-roll before the first word and its tail after the last.
    public static let preRoll = TrimRule().capture.preRollMs / 1000
    public static let tail = TrimRule().tailMs / 1000

    /// Extends a word span outward so the trim's pre-roll and tail can apply unchanged: up to `preRoll` before the
    /// first word and `tail` after the last, each stopping at the midpoint of the gap to the neighbouring word's MFA
    /// span, so a cut never takes the neighbour's speech. With no neighbour the bound is the clip edge (0 at the
    /// start; the end is clamped to the audio when it's read). Rounded to the millisecond so the cut list is stable.
    public static func extend(
        wordStart: Double, wordEnd: Double, previousEnd: Double?, nextStart: Double?
    ) -> (start: Double, end: Double) {
        func ms(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
        let startBound = previousEnd.map { min(wordStart, ($0 + wordStart) / 2) } ?? 0
        let endBound = nextStart.map { max(wordEnd, (wordEnd + $0) / 2) } ?? .infinity
        return (ms(max(wordStart - preRoll, startBound)), ms(min(wordEnd + tail, endBound)))
    }
}

/// `fixtures/vctk/sub-phrase-cuts.json`: every listed clip's cut, replayed by CI and by `am-eval vctk-trim`.
public struct VCTKSubPhraseCutList: Sendable, Hashable, Codable {
    public struct Entry: Sendable, Hashable, Codable {
        public let speaker: String
        public let subPhrase: String
        public let outcome: VCTKSubPhraseCut

        public init(speaker: String, subPhrase: String, outcome: VCTKSubPhraseCut) {
            self.speaker = speaker
            self.subPhrase = subPhrase
            self.outcome = outcome
        }
    }

    /// SHA-256 of the sub-phrase table the cuts were made from (a stale cut list fails the tests).
    public let subPhrasesSHA256: String
    /// SHA-256 of the MFA alignments file the cuts came from (git-ignored cache; recorded for audit).
    public let alignmentsSHA256: String
    /// The aligner as scripts/mfa-align.sh recorded it (MFA 3.4.4, english_mfa v3.1.0 and their digests).
    public let aligner: [String: String]
    public let entries: [Entry]

    public init(subPhrasesSHA256: String, alignmentsSHA256: String, aligner: [String: String], entries: [Entry]) {
        self.subPhrasesSHA256 = subPhrasesSHA256
        self.alignmentsSHA256 = alignmentsSHA256
        self.aligner = aligner
        self.entries = entries
    }

    public static func load(_ url: URL) throws -> VCTKSubPhraseCutList {
        try JSONDecoder().decode(VCTKSubPhraseCutList.self, from: Data(contentsOf: url))
    }

    /// The cut list for every clip spec 02's manifest lists for a split prompt, from one table: the same word range
    /// for every speaker. `transcripts` and `alignments` are keyed by `<speaker>_<prompt>`.
    public static func make(
        table: VCTKSubPhraseTable, manifest: VCTKEvalSpeakersManifest, transcripts: [String: String],
        alignments: [String: [VCTKTimedWord]], subPhrasesSHA256: String, alignmentsSHA256: String,
        aligner: [String: String]
    ) -> VCTKSubPhraseCutList {
        var entries: [Entry] = []
        for sub in table.subPhrases {
            for entry in (manifest.bundled + manifest.speakers).sorted(by: { $0.speaker < $1.speaker })
            where entry.files[sub.prompt] != nil {
                let clip = "\(entry.speaker)_\(sub.prompt)"
                let cut = VCTKSubPhraseCut.make(sub, transcript: transcripts[clip] ?? "", alignment: alignments[clip])
                entries.append(Entry(speaker: entry.speaker, subPhrase: sub.id, outcome: cut))
            }
        }
        return VCTKSubPhraseCutList(
            subPhrasesSHA256: subPhrasesSHA256, alignmentsSHA256: alignmentsSHA256, aligner: aligner, entries: entries)
    }
}
