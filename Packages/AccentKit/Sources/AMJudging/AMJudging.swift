// AMJudging: per-sound pronunciation judging on device (sound-judging plan, 2026-11-25).
// facebook/wav2vec2-lv-60-espeak-cv-ft (Apache-2.0) in Core ML gives CTC log-posteriors over espeak IPA tokens; a
// segmentation-free GOP (after Cao et al.) scores each expected ARPAbet phone, a per-phone logistic calibration turns
// it into P(error), and a sound is flagged above the frozen threshold. Depends on AMCore and Apple frameworks only.
//
// This file is the agreed interface. sj-engine fills in the bodies; sj-wire calls only what is declared here.

import AMCore
import Foundation

/// One phrase word as the judge expects it.
public struct ExpectedWord: Sendable, Hashable {
    public let index: WordIndex
    public let text: String
    /// Every CMUdict variant for the word, ARPAbet with stress digits (e.g. `["DH", "AH0"]`), dictionary order. Empty
    /// means out of vocabulary: the word is reported `.unjudged(.notInDictionary)`. The judge picks one variant per
    /// word greedily by CTC likelihood, as the spike did.
    public let variants: [[String]]
    /// The word on the native recording's timeline, copied into `JudgedWord.modelRange`.
    public let modelRange: TimeRange?

    public init(index: WordIndex, text: String, variants: [[String]], modelRange: TimeRange? = nil) {
        self.index = index
        self.text = text
        self.variants = variants
        self.modelRange = modelRange
    }
}

/// CTC log-posteriors from the model: `frames` rows of `vocabularySize` log-softmax values, row-major, 20 ms a frame.
public struct LogPosteriors: Sendable, Hashable {
    public let frames: Int
    public let vocabularySize: Int
    public let values: [Float]
    public static let frameSeconds = 0.02

    public init(frames: Int, vocabularySize: Int, values: [Float]) {
        precondition(values.count == frames * vocabularySize, "LogPosteriors: values must be frames × vocabularySize")
        self.frames = frames
        self.vocabularySize = vocabularySize
        self.values = values
    }
}

public enum SoundJudgeError: Error, Sendable, Hashable {
    case notImplemented
    case modelNotInstalled
    case modelFailed(String)
    case takeOutOfRange(seconds: Double)
}

/// The pure part: posteriors + expected words -> judged words. Deterministic; what the parity fixtures test.
public enum SoundScorer {
    /// `gop-sf-2`: flags at P(error) > 0.13 (2026-11-26); `gop-sf-1` flagged at 0.22. Same GOP and calibration.
    public static let judgeID = "gop-sf-2"

    /// Judges with the lv-60 vocabulary's token ids (`TokenVocabulary.lv60Espeak`).
    public static func judge(_ posteriors: LogPosteriors, words: [ExpectedWord]) -> [JudgedWord] {
        judge(posteriors, words: words, vocabulary: .lv60Espeak)
    }

    /// Judges with `vocabulary`'s token ids (the installed model's manifest). `takeSeconds` clamps the ranges to
    /// the unpadded take; nil clamps to the posteriors' length.
    public static func judge(_ posteriors: LogPosteriors, words: [ExpectedWord], vocabulary: TokenVocabulary,
                             takeSeconds: Double? = nil,
                             errorThreshold: Double = Thresholds.current.soundJudging.errorThreshold) -> [JudgedWord] {
        let emissions = Emissions(posteriors, blank: vocabulary.blank)
        // Each word's buildable variants (a variant with an unmappable phone is dropped; none left = unjudged).
        let candidates: [[(phones: [String], units: [JudgingUnit])]] = words.map { word in
            word.variants.compactMap { phones in
                guard !phones.isEmpty,
                      let units = UnitBuilder.units(word: word.text, phones: phones, vocabulary: vocabulary)
                else { return nil }
                return (phones, units)
            }
        }
        let judgeable = candidates.indices.filter { !candidates[$0].isEmpty }
        guard !judgeable.isEmpty, posteriors.frames > 0 else { return words.map(unjudged) }

        // Variant choice: greedy, word by word, by the canonical sequence's CTC likelihood (spike `score.py`).
        let blankColumn = emissions.column(vocabulary.blank)
        var choice = [Int](repeating: 0, count: words.count)
        func canonical(_ choice: [Int]) -> [Int] {
            judgeable.flatMap { w in candidates[w][choice[w]].units.flatMap(\.canonical) }
        }
        var best = CTC.logLikelihood(canonical(choice), emissions: emissions, blankColumn: blankColumn)
        for w in judgeable where candidates[w].count > 1 {
            for v in 1..<candidates[w].count {
                var trial = choice
                trial[w] = v
                let ll = CTC.logLikelihood(canonical(trial), emissions: emissions, blankColumn: blankColumn)
                if ll > best {
                    best = ll
                    choice = trial
                }
            }
        }

        let units = judgeable.flatMap { w in candidates[w][choice[w]].units }
        let scores = GOP.score(units: units, emissions: emissions, vocabulary: vocabulary)
        let labels = units.flatMap(\.canonical)
        let spans = CTC.align(labels, emissions: emissions, blankColumn: blankColumn)
        let limit = takeSeconds ?? Double(posteriors.frames) * LogPosteriors.frameSeconds
        func range(_ frames: ClosedRange<Int>?) -> TimeRange? {
            guard let frames else { return nil }
            let start = min(Double(frames.lowerBound) * LogPosteriors.frameSeconds, limit)
            let end = min(Double(frames.upperBound + 1) * LogPosteriors.frameSeconds, limit)
            return try? TimeRange(start: start, end: end)
        }
        let tokens = vocabulary.tokensByID
        let calibration = Calibration.bundled

        var judged: [Int: JudgedWord] = [:]
        var unitIndex = 0, labelIndex = 0
        for w in judgeable {
            let (phones, wordUnits) = candidates[w][choice[w]]
            var out = [JudgedPhone?](repeating: nil, count: phones.count)
            var wordFrames: ClosedRange<Int>?
            for unit in wordUnits {
                let score = scores[unitIndex]
                var frames: ClosedRange<Int>?
                if let spans {
                    let first = spans[labelIndex], last = spans[labelIndex + unit.canonical.count - 1]
                    frames = first.lowerBound...last.upperBound
                    wordFrames = wordFrames.map { $0.lowerBound...last.upperBound } ?? frames
                }
                // Calibration uses the first member's stress-stripped phone, as calibrate.py does.
                let headPhone = Lexicon.stripStress(phones[unit.members[0]])
                let pError = calibration.errorProbability(gop: score.gop, phone: headPhone) ?? 1
                let heard: HeardInstead? = score.competitor.map {
                    $0 == GOP.deletion ? .nothing : .sound(tokens[$0] ?? "")
                }
                for member in unit.members {
                    out[member] = JudgedPhone(
                        phone: displayPhone(phones[member]), gop: score.gop, confidence: 1 - pError,
                        flagged: pError > errorThreshold, heardInstead: heard, youRange: range(frames))
                }
                unitIndex += 1
                labelIndex += unit.canonical.count
            }
            let word = words[w]
            judged[w] = JudgedWord(index: word.index, text: word.text, youRange: range(wordFrames),
                                   modelRange: word.modelRange, state: .judged(out.compactMap { $0 }))
        }
        return words.indices.map { judged[$0] ?? unjudged(words[$0]) }
    }

    /// The phone as the result shows it: stress digits stripped, except unstressed AH stays `AH0` (schwa, "a" as in
    /// about) so it reads apart from AH1/AH2 (`AH`, "u" as in cup). Designer ruling, 2026-11-25.
    static func displayPhone(_ phone: String) -> String {
        phone == "AH0" ? "AH0" : Lexicon.stripStress(phone)
    }

    static func unjudged(_ word: ExpectedWord) -> JudgedWord {
        JudgedWord(index: word.index, text: word.text, youRange: nil, modelRange: word.modelRange,
                   state: .unjudged(.notInDictionary))
    }
}
