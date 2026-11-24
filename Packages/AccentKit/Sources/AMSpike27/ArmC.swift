// Spec 27 §3a (lit amendment 5): arm C, report-only. Vowel positions come from b2's character CTC under the known
// prompt text: a CTC forced alignment of the prompt's letters (word separators between words) over the whole take,
// then each word's vowel-letter groups. A word whose group count isn't its syllable count N abstains; otherwise each
// group takes the detected nucleus nearest its centre (within `reachSeconds`), and two groups on one nucleus abstain.

import Foundation

public enum ArmC {
    public static let reachSeconds = 0.06

    /// One letter's frames in the forced alignment.
    public struct LetterSpan: Sendable, Hashable, Codable {
        public let word: Int
        public let letter: Character
        public let first: Int
        public let last: Int

        enum CodingKeys: String, CodingKey { case word, letter, first, last }
        public init(word: Int, letter: Character, first: Int, last: Int) {
            self.word = word
            self.letter = letter
            self.first = first
            self.last = last
        }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            word = try c.decode(Int.self, forKey: .word)
            letter = Character(try c.decode(String.self, forKey: .letter))
            first = try c.decode(Int.self, forKey: .first)
            last = try c.decode(Int.self, forKey: .last)
        }
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(word, forKey: .word)
            try c.encode(String(letter), forKey: .letter)
            try c.encode(first, forKey: .first)
            try c.encode(last, forKey: .last)
        }
    }

    /// CTC forced alignment (Viterbi over blank-interleaved labels) of `words` (each a list of label indices; a
    /// separator label between words). Returns every letter's first and last frame, or nil when no path fits.
    public static func align(logProbs: [Float], frames: Int, classes: Int, words: [[Int]], letters: [[Character]],
                             blank: Int, separator: Int) -> [LetterSpan]? {
        var labels: [Int] = [], owner: [(word: Int, letter: Int)?] = []
        for (w, word) in words.enumerated() {
            if w > 0 { labels.append(separator); owner.append(nil) }
            for (k, label) in word.enumerated() { labels.append(label); owner.append((w, k)) }
        }
        let states = 2 * labels.count + 1
        guard !labels.isEmpty, frames >= labels.count else { return nil }
        func label(_ s: Int) -> Int { s % 2 == 0 ? blank : labels[s / 2] }
        let negInf = -Float.infinity
        var score = [Float](repeating: negInf, count: states)
        var back = [[Int32]](repeating: [Int32](repeating: -1, count: states), count: frames)
        score[0] = logProbs[label(0)]
        if states > 1 { score[1] = logProbs[label(1)] }
        for t in 1..<frames {
            var next = [Float](repeating: negInf, count: states)
            let row = t * classes
            for s in 0..<states {
                var best = score[s], from = s
                if s >= 1 && score[s - 1] > best { best = score[s - 1]; from = s - 1 }
                if s >= 2 && s % 2 == 1 && labels[s / 2] != labels[(s - 2) / 2] && score[s - 2] > best {
                    best = score[s - 2]; from = s - 2
                }
                guard best > negInf else { continue }
                next[s] = best + logProbs[row + label(s)]
                back[t][s] = Int32(from)
            }
            score = next
        }
        var s = score[states - 1] >= (states > 1 ? score[states - 2] : negInf) ? states - 1 : states - 2
        guard score[s] > negInf else { return nil }
        var path = [Int](repeating: 0, count: frames)
        for t in stride(from: frames - 1, through: 0, by: -1) {
            path[t] = s
            if t > 0 { s = Int(back[t][s]) }
        }
        var spans: [Int: (Int, Int)] = [:]
        for (t, s) in path.enumerated() where s % 2 == 1 {
            let i = s / 2
            spans[i] = (min(spans[i]?.0 ?? t, t), max(spans[i]?.1 ?? t, t))
        }
        var out: [LetterSpan] = []
        for (i, o) in owner.enumerated() {
            guard let o, let span = spans[i] else { continue }
            out.append(LetterSpan(word: o.word, letter: letters[o.word][o.letter], first: span.0, last: span.1))
        }
        return out
    }

    /// The vowel-letter groups of a word, as letter index ranges: maximal runs of a, e, i, o, u (and y when it isn't
    /// the first letter); a final "e" after a consonant is silent when the word has another group.
    public static func vowelGroups(_ word: [Character]) -> [ClosedRange<Int>] {
        let lower = word.map { Character($0.lowercased()) }
        func vowel(_ i: Int) -> Bool { "aeiou".contains(lower[i]) || (lower[i] == "y" && i > 0) }
        var groups: [ClosedRange<Int>] = []
        var i = 0
        while i < lower.count {
            if vowel(i) {
                var j = i
                while j + 1 < lower.count && vowel(j + 1) { j += 1 }
                groups.append(i...j)
                i = j + 1
            } else { i += 1 }
        }
        if groups.count > 1, let last = groups.last, last == (lower.count - 1)...(lower.count - 1), lower.last == "e",
           lower.count >= 2, !vowel(lower.count - 2) {
            groups.removeLast()
        }
        return groups
    }

    /// The word's nuclei under arm C: one per vowel group (nearest peak to the group's centre, within reach), or nil.
    public static func select(_ nuclei: [MeasuredNucleus], groupCentres: [Double], syllables: Int) -> [Int]? {
        guard groupCentres.count == syllables, syllables >= 2 else { return nil }
        var picks: [Int] = []
        for centre in groupCentres {
            guard let best = nuclei.indices.min(by: { abs(nuclei[$0].peakTime - centre) < abs(nuclei[$1].peakTime - centre) }),
                  abs(nuclei[best].peakTime - centre) <= reachSeconds else { return nil }
            picks.append(best)
        }
        guard Set(picks).count == picks.count, picks == picks.sorted() else { return nil }
        return picks
    }
}
