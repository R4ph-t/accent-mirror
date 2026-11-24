import AMAlignment
import AMAlignmentCTC
import AMCapture
import AMCore
import AMProsody
import AMTimestampEval
import Foundation

/// The spec 23 downstream ship gate's harness (CTO ruling 2026-11-23 14:05): spec 07's `SyllableSegmenter` run twice
/// on the same take, once on oracle word boundaries and once on b2's, with everything else identical:
///
/// - the phrase words and pronunciations (spec 06's bundled selector, starter origin, on the transcript);
/// - the comparable words: phrase words both the oracle and b2 time and that have a pronunciation. Only they are
///   `present`, in both runs; every other phrase word is `missing` in both;
/// - the voicing (spec 05's `ACFVoicing`, as the pipeline wires it), the audio and the thresholds.
///
/// Only the word spans differ, and their probability: the oracle run carries the recogniser's word probability,
/// b2's run the same probability through the CTC confidence gate (0 below `ctcConfidenceMin`).
struct DownstreamHarness {
    let selector: PronunciationSelector
    let segmenter: SyllableSegmenter

    init() throws {
        selector = try PronunciationSelector.bundled()
        segmenter = SyllableSegmenter(voicing: ACFVoicing())
    }

    struct Result {
        var pairs: [(oracle: WordVerdict, candidate: WordVerdict)]
        /// Comparable words the confidence gate made inconclusive.
        var gatedByConfidence: Int
    }

    func compare(transcript: String, samples: [Float], sampleRate: Double, oracle: [BaselineWord],
                 candidate: [ConfidentWord], clipID: String) throws -> Result {
        let phrase = selector.expectedPhrase(for: PhraseText(text: transcript, origin: .starter))
        let tokens = phrase.words.map { Tokens.normalize($0.text) }
        let oracleIndex = Tokens.match(tokens: tokens, words: oracle.map(\.word))
        let candidateIndex = Tokens.match(tokens: tokens, words: candidate.map(\.word.word))

        var oraclePairs: [AlignedWordPair] = [], candidatePairs: [AlignedWordPair] = []
        var oracleSpans: [WordIndex: SyllableSegmenter.WordSpan] = [:]
        var candidateSpans: [WordIndex: SyllableSegmenter.WordSpan] = [:]
        var pronunciations: [WordIndex: Pronunciation] = [:]
        var gated = 0
        for (position, expected) in phrase.words.enumerated() {
            let word = WordIndex(position)
            guard let o = oracleIndex[position], let c = candidateIndex[position],
                  let pronunciation = expected.pronunciation
            else {
                oraclePairs.append(.missing(phrase: word))
                candidatePairs.append(.missing(phrase: word))
                continue
            }
            let b2 = candidate[c]
            let oracleWord = oracle[o]
            let probability = b2.word.probability
            let gatedProbability = b2.spanProbability()
            if gatedProbability == 0 && probability > 0 { gated += 1 }
            oracleSpans[word] = try SyllableSegmenter.WordSpan(
                start: oracleWord.start, end: oracleWord.end, probability: probability)
            candidateSpans[word] = try SyllableSegmenter.WordSpan(
                start: b2.word.start, end: b2.word.end, probability: gatedProbability)
            pronunciations[word] = pronunciation
            oraclePairs.append(.present(phrase: word, you: try TimeRange(start: oracleWord.start, end: oracleWord.end)))
            candidatePairs.append(.present(phrase: word, you: try TimeRange(start: b2.word.start, end: b2.word.end)))
        }

        func run(_ pairs: [AlignedWordPair], _ spans: [WordIndex: SyllableSegmenter.WordSpan]) throws -> [WordIndex: WordVerdict] {
            let input = SyllableSegmenter.Input(
                samples: samples, sampleRate: sampleRate, alignment: try WordAlignment(pairs: pairs),
                pronunciations: pronunciations, spans: spans, l0Key: clipID, transcriptRevision: 1)
            let segmentation = try segmenter.segment(input)
            return Dictionary(uniqueKeysWithValues: segmentation.words.map { word in
                (word.phraseWord, WordVerdict(word))
            })
        }
        let oracleVerdicts = try run(oraclePairs, oracleSpans)
        let candidateVerdicts = try run(candidatePairs, candidateSpans)
        let compared = oracleVerdicts.keys.sorted().compactMap { word in
            candidateVerdicts[word].map { (oracle: oracleVerdicts[word]!, candidate: $0) }
        }
        return Result(pairs: compared, gatedByConfidence: gated)
    }
}
