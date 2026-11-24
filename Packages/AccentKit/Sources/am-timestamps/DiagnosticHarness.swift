import AMAlignment
import AMAlignmentCTC
import AMCore
import AMPitch
import AMProsody
import AMTimestampEval
import Foundation

/// The CTO diagnostic round on spec 23's downstream gate (decision on #27, 2026-11-23). The same steps as
/// `DownstreamHarness.compare` (same selector, segmenter, voicing, comparable words, probabilities and thresholds),
/// keeping every comparable word's verdict pair, plus a third segmenter run with the CTC confidence gate bypassed
/// (diagnostic only: the candidate's span keeps the recogniser's probability). Nothing here is read by the gate.
extension DownstreamHarness {
    struct Diagnosed {
        var words: [DiagnosticWord]
        /// Phrase words the oracle times, with a pronunciation, that the recogniser's words do not match.
        var substituted: Int
        var deleted: Int
    }

    /// Phrase tokens of `transcript` as the gate derives them.
    func tokens(_ transcript: String) -> [String] {
        selector.expectedPhrase(for: PhraseText(text: transcript, origin: .starter)).words.map { Tokens.normalize($0.text) }
    }

    /// The candidate keyed by phrase position, matched as the gate matches it.
    func matched(_ candidate: [ConfidentWord], transcript: String) -> [Int: ConfidentWord] {
        var keyed: [Int: ConfidentWord] = [:]
        for (position, index) in Tokens.match(tokens: tokens(transcript), words: candidate.map(\.word.word)).enumerated() {
            if let index { keyed[position] = candidate[index] }
        }
        return keyed
    }

    /// `candidate` is keyed by phrase position; `recognised` is the recogniser's words (for the substitution count).
    /// `pitch` is the take's spec 04 track: `.nucleus` measurement needs it (spec 25), and with it each word records
    /// whether a nucleus peak lies within `nearEdgeMs` of an oracle edge (CTO markup 3's diagnostic).
    func diagnose(transcript: String, samples: [Float], sampleRate: Double, oracle: [BaselineWord],
                  candidate: [Int: ConfidentWord], recognised: [WordTimestamp], clipID: String,
                  pitch: PitchTrack? = nil, markerCheck: [BaselineWord]? = nil) throws -> Diagnosed {
        let phrase = selector.expectedPhrase(for: PhraseText(text: transcript, origin: .starter))
        let tokens = phrase.words.map { Tokens.normalize($0.text) }
        let oracleIndex = Tokens.match(tokens: tokens, words: oracle.map(\.word))
        let recognisedIndex = Tokens.match(tokens: tokens, words: recognised.map(\.word))
        let unmatched = VerdictDiagnostics.unmatched(
            matches: recognisedIndex,
            eligible: phrase.words.indices.map { oracleIndex[$0] != nil && phrase.words[$0].pronunciation != nil },
            recognised: recognised.count)

        var oraclePairs: [AlignedWordPair] = [], candidatePairs: [AlignedWordPair] = []
        var oracleSpans: [WordIndex: SyllableSegmenter.WordSpan] = [:]
        var gatedSpans: [WordIndex: SyllableSegmenter.WordSpan] = [:]
        var ungatedSpans: [WordIndex: SyllableSegmenter.WordSpan] = [:]
        var pronunciations: [WordIndex: Pronunciation] = [:]
        var info: [WordIndex: (text: String, errorMs: Double, gated: Bool)] = [:]
        // Spec 26 §2: N_w per word in `.nucleus` (unless the run asks for spec 25's context counts only).
        var allowed: [WordIndex: AllowedSyllableCounts] = [:]
        var primaries: [WordIndex: Int] = [:]
        // Spec 26 §5 (synthetic): the other aligner on the same audio, for the TTS-marker check.
        let markerIndex = markerCheck.map { Tokens.match(tokens: tokens, words: $0.map(\.word)) }
        var markerDelta: [WordIndex: [Double]] = [:]
        for (position, expected) in phrase.words.enumerated() {
            let word = WordIndex(position)
            guard let o = oracleIndex[position], let c = candidate[position], let pronunciation = expected.pronunciation
            else {
                oraclePairs.append(.missing(phrase: word))
                candidatePairs.append(.missing(phrase: word))
                continue
            }
            let oracleWord = oracle[o]
            let probability = c.word.probability
            let gatedProbability = c.spanProbability()
            oracleSpans[word] = try SyllableSegmenter.WordSpan(start: oracleWord.start, end: oracleWord.end, probability: probability)
            gatedSpans[word] = try SyllableSegmenter.WordSpan(start: c.word.start, end: c.word.end, probability: gatedProbability)
            ungatedSpans[word] = try SyllableSegmenter.WordSpan(start: c.word.start, end: c.word.end, probability: probability)
            pronunciations[word] = pronunciation
            primaries[word] = pronunciation.primarySyllable
            if segmenter.thresholds.prominence.measurement == .nucleus && !contextCountsOnly {
                allowed[word] = AllowedSyllableCounts.of(
                    word: expected.text, context: pronunciation, dictionary: Self.dictionary, reducedForms: Self.reducedForms)
            }
            if let markerCheck, let m = markerIndex?[position] {
                markerDelta[word] = [(oracleWord.start - markerCheck[m].start) * 1000, (oracleWord.end - markerCheck[m].end) * 1000]
            }
            oraclePairs.append(.present(phrase: word, you: try TimeRange(start: oracleWord.start, end: oracleWord.end)))
            candidatePairs.append(.present(phrase: word, you: try TimeRange(start: c.word.start, end: c.word.end)))
            info[word] = (expected.text,
                          max(abs(c.word.start - oracleWord.start), abs(c.word.end - oracleWord.end)) * 1000,
                          gatedProbability == 0 && probability > 0)
        }

        func run(_ pairs: [AlignedWordPair], _ spans: [WordIndex: SyllableSegmenter.WordSpan]) throws -> [WordIndex: WordVerdict] {
            var ignored: [WordIndex: SegmentedWord] = [:]
            return try run(pairs, spans, segmented: &ignored)
        }
        func run(_ pairs: [AlignedWordPair], _ spans: [WordIndex: SyllableSegmenter.WordSpan],
                 segmented: inout [WordIndex: SegmentedWord]) throws -> [WordIndex: WordVerdict] {
            let input = SyllableSegmenter.Input(
                samples: samples, sampleRate: sampleRate, alignment: try WordAlignment(pairs: pairs),
                pronunciations: pronunciations, spans: spans, l0Key: clipID, transcriptRevision: 1, pitch: pitch,
                allowedCounts: allowed)
            let words = try segmenter.segment(input).words
            for word in words { segmented[word.phraseWord] = word }
            return Dictionary(uniqueKeysWithValues: words.map { word in (word.phraseWord, WordVerdict(word)) })
        }
        // Peaks of the take's nuclei: detection reads no word edge, so one pass serves every run and both modes.
        let peaks = pitch.map {
            NucleusDetector(thresholds: segmenter.thresholds).detect(samples: samples, sampleRate: sampleRate, pitch: $0)
                .map(\.peakTime)
        }
        var oracleWords: [WordIndex: SegmentedWord] = [:], candidateWords: [WordIndex: SegmentedWord] = [:]
        let oracleVerdicts = try run(oraclePairs, oracleSpans, segmented: &oracleWords)
        let gated = try run(candidatePairs, gatedSpans, segmented: &candidateWords)
        let ungated = try run(candidatePairs, ungatedSpans)
        let words = oracleVerdicts.keys.sorted().compactMap { word -> DiagnosticWord? in
            guard let c = gated[word], let u = ungated[word], let o = oracleVerdicts[word], let meta = info[word] else { return nil }
            let near = peaks.map { peaks in
                oracleSpans[word].map { span in
                    peaks.contains { abs($0 - span.start) <= Self.nearEdgeS || abs($0 - span.end) <= Self.nearEdgeS }
                } ?? false
            }
            var diagnostic = DiagnosticWord(clipID: clipID, word: meta.text, oracle: o, candidate: c, candidateUngated: u,
                                            boundaryErrorMs: meta.errorMs, gatedByConfidence: meta.gated,
                                            nucleusNearEdge: near)
            let oracleAssignment = oracleWords[word]?.nucleusAssignment
            diagnostic.oracleNucleusAvailable = oracleAssignment?.available
            diagnostic.oracleNucleusShort = oracleAssignment?.short
            diagnostic.contextPrimary = primaries[word]
            diagnostic.markerMinusMFAMs = markerDelta[word]
            if let ow = oracleWords[word], let cw = candidateWords[word], let oa = oracleAssignment {
                diagnostic.oracleReason = Self.inconclusiveReason(ow, verdict: o)
                diagnostic.candidateReason = Self.inconclusiveReason(cw, verdict: c)
                let set = oa.allowed ?? [oa.dictionaryCount]
                diagnostic.oracleConfident = !oa.short && !(oa.ambiguous ?? false) && set.contains(oa.available)
                diagnostic.oracleCountMatch = !oa.short && set.contains(oa.available)
                if !oa.short {
                    diagnostic.oracleCountSource = oa.assignedCount.flatMap { count in
                        allowed[word]?.form(for: count)?.source.rawValue
                    } ?? "context"
                }
                diagnostic.nucleiMoved = ow.syllables.map { $0.nucleus?.peakTime } != cw.syllables.map { $0.nucleus?.peakTime }
                diagnostic.exposureChanged = ow.syllables.map(\.lengtheningExposed) != cw.syllables.map(\.lengtheningExposed)
                let ca = cw.nucleusAssignment
                diagnostic.availableChanged = oa.available != ca?.available || oa.confidence != ca?.confidence
                    || ow.confidence != cw.confidence
            }
            return diagnostic
        }
        return Diagnosed(words: words, substituted: unmatched.substituted, deleted: unmatched.deleted)
    }
}

extension DownstreamHarness {
    /// CTO markup 3: a word is "near an edge" when a nucleus peak lies within 40 ms of either oracle edge (the ±40 ms
    /// jitter radius). Diagnostic only.
    static let nearEdgeS = 0.040

    /// Spec 26 §5: why a `.nucleus` word is inconclusive, in the order the gate reads it.
    static func inconclusiveReason(_ word: SegmentedWord, verdict: WordVerdict) -> String? {
        guard verdict.inconclusive else { return nil }
        if word.isNucleusShort { return "nucleusShort" }
        if word.isAssignmentAmbiguous { return "assignmentAmbiguous" }
        return "lowConfidence"
    }

    static let dictionary = try! PronouncingDictionary.bundled()
    static let reducedForms = try! ReducedForms.bundled()
}

extension WordVerdict {
    /// The gate's verdict of one segmented word. A nucleus-short word (spec 25 §2) has no stress features: it is
    /// inconclusive, with no longest or loudest syllable (its display spans are not measured).
    init(_ word: SegmentedWord) {
        if word.isNucleusShort {
            self.init(inconclusive: true, syllableCount: word.syllables.count, longestSyllable: nil, loudestSyllable: nil)
        } else if word.nucleusAssignment != nil {
            // Spec 26: an assignment-ambiguous word is inconclusive too. A context syllable with no nucleus (a reduced
            // form or CMUdict alternate dropped it) isn't measured; the others keep their context indices.
            let measured = word.syllables.filter { $0.nucleus != nil }
            func first(_ value: (SegmentedSyllable) -> Double) -> Int? {
                guard let best = measured.map(value).max() else { return nil }
                return measured.first { value($0) == best }?.indexInWord
            }
            self.init(inconclusive: word.isAssignmentAmbiguous || word.syllables.contains { $0.level == .low },
                      syllableCount: word.syllables.count, longestSyllable: first(\.duration),
                      loudestSyllable: first(\.energyDBFS))
        } else {
            self.init(syllables: word.syllables.map {
                (duration: $0.duration, intensityDB: $0.energyDBFS, low: $0.level == .low)
            })
        }
    }
}

extension ConfidentWord {
    /// A candidate with no CTC confidence gate (Whisper only, dsp-snap-1, MFA): its probability passes unchanged.
    static func ungated(_ word: WordTimestamp) -> ConfidentWord { ConfidentWord(word: word, confidence: 1) }
}
