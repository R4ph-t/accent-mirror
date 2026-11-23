import AMAlignment
import AMCore
import AMProsody
import Foundation
import Testing

@Suite("SyllableSegmenterTests") struct SyllableSegmenterTests {
    // MARK: Boundaries

    @Test("on the pulse train, every boundary is within 40 ms of truth") func pulseTrainBoundaries() throws {
        let take = SyntheticTake.pulseTrain
        let result = try take.segment()
        #expect(result.words.count == take.words.count)
        for (word, truth) in zip(result.words, take.words) {
            let reported = [word.range.start] + word.syllables.map(\.range.end)
            #expect(reported.count == truth.edges.count, "\(truth.text): syllable count")
            for (got, expected) in zip(reported, truth.edges) {
                #expect(abs(got - expected) <= 0.040, "\(truth.text): boundary \(got) vs \(expected)")
            }
            #expect(word.split?.method == .valleys, "\(truth.text)")
            #expect(word.split?.peakCount == truth.edges.count - 1, "\(truth.text)")
            #expect(word.split?.confidence == 0.9, "\(truth.text)")
        }
        // Word timing is the union of its syllables.
        for word in result.words {
            #expect(word.syllables.first?.range.start == word.range.start)
            #expect(word.syllables.last?.range.end == word.range.end)
        }
    }

    @Test("a word with one peak fewer than the dictionary count keeps the dictionary count and gets s_w = 0.6")
    func onePeakFewer() throws {
        // "photography", 4 syllables; the last two share one bump with a 2 dB dip, so the energy shows 3 peaks.
        let edges = [0.20, 0.40, 0.60, 0.80, 1.00]
        let word = SyntheticWord(
            text: "photography", arpabet: "F AH0 T AA1 G R AH0 F IY0", edges: edges,
            shape: { time, syllable, edges in
                guard syllable >= 2 else { return SyntheticTake.bump(time, syllable, edges) }
                // A flat-topped bump over both syllables with a 2 dB dip at their boundary: under the 3 dB rule.
                let taper = min(1, (time - edges[2]) / 0.06, (edges[4] - time) / 0.06)
                let dip = 1 - (1 - pow(10, -2.0 / 20)) * exp(-pow((time - edges[3]) / 0.03, 2) / 2)
                return max(0, taper) * dip
            })
        let result = try SyntheticTake(words: [word], duration: 1.2).segment()
        let segmented = try #require(result.words.first)
        #expect(segmented.syllables.count == 4)
        for (syllable, truth) in zip(segmented.syllables, edges.dropFirst()) {
            #expect(abs(syllable.range.end - truth) <= 0.040, "boundary \(syllable.range.end) vs \(truth)")
        }
        #expect(segmented.split?.dictionaryCount == 4)
        #expect(segmented.split?.peakCount == 3)
        #expect(segmented.split?.method == .valleys)
        #expect(abs((segmented.split?.confidence ?? 0) - 0.6) < 1e-9)
        #expect(segmented.syllables.allSatisfy { abs($0.confidence - 0.6) < 1e-9 && $0.level == .medium })
    }

    @Test("with no usable valleys the split is proportional to phone count, s_w = 0.35") func proportionalFallback() throws {
        // "lesson" (L EH1 | S AH0 N): one steady tone, no envelope minimum inside the word.
        let word = SyntheticWord(text: "lesson", arpabet: "L EH1 S AH0 N", edges: [0.2, 0.4, 0.7], shape: { _, _, _ in 1 })
        let segmented = try #require(try SyntheticTake(words: [word], duration: 1.0).segment().words.first)
        #expect(segmented.split?.method == .proportional)
        #expect(segmented.split?.confidence == 0.35)
        let boundary = try #require(segmented.syllables.first?.range.end)
        #expect(abs(boundary - (0.2 + 0.5 * 2.0 / 5.0)) < 1e-9)  // 2 of 5 phones
        #expect(segmented.syllables.map(\.level) == [.low, .low])
    }

    // MARK: Word confidence and padding

    @Test("a 1.8 s word span gets span sanity 0.3") func longSpan() throws {
        let word = SyntheticWord(text: "the", arpabet: "DH AH0", edges: [0.1, 1.9])
        let segmented = try #require(try SyntheticTake(words: [word], duration: 2.2).segment().words.first)
        #expect(segmented.spanSanity == 0.3)
        #expect(segmented.confidence == 0.3)
        #expect(segmented.syllables.allSatisfy { $0.level == .low })
    }

    @Test("span sanity is 1 for 60 ms–1.5 s, 0.3 below 60 ms or when overlapping a neighbour; c_w = min(p, sanity)")
    func spanSanity() throws {
        let take = SyntheticTake(words: [
            SyntheticWord(text: "the", arpabet: "DH AH0", edges: [0.10, 0.15]),
            SyntheticWord(text: "the", arpabet: "DH AH0", edges: [0.30, 0.60], probability: 0.62),
            SyntheticWord(text: "the", arpabet: "DH AH0", edges: [0.55, 0.80]),
        ], duration: 1.0)
        let words = try take.segment().words
        #expect(words.map(\.spanSanity) == [0.3, 0.3, 0.3])
        let clean = SyntheticTake(words: [SyntheticWord(text: "the", arpabet: "DH AH0", edges: [0.3, 0.6], probability: 0.62)],
                                  duration: 1.0)
        let word = try #require(try clean.segment().words.first)
        #expect(word.spanSanity == 1.0)
        #expect(word.confidence == 0.62)
    }

    @Test("padding never crosses a neighbouring word, and reported word boundaries are never the padded edges")
    func paddingStaysInside() throws {
        // "the" ends at 0.50; "lesson" starts at 0.55, its first bump peaking inside "the"'s 80 ms padding.
        let take = SyntheticTake(words: [
            SyntheticWord(text: "the", arpabet: "DH AH0", edges: [0.03, 0.50]),
            SyntheticWord(text: "lesson", arpabet: "L EH1 S AH0 N", edges: [0.55, 0.65, 0.90]),
            SyntheticWord(text: "today", arpabet: "T AH0 D EY1", edges: [1.50, 1.70, 1.96]),
        ], duration: 2.0)
        let words = try take.segment().words
        let spans = take.words.map { ($0.start, $0.end) }
        for (index, word) in words.enumerated() {
            // Reported edges are the injected ones, never the padded window's.
            #expect(word.range.start == spans[index].0 && word.range.end == spans[index].1)
            #expect(word.searchWindow.start <= word.range.start && word.searchWindow.end >= word.range.end)
            for (other, span) in spans.enumerated() where other != index {
                #expect(word.searchWindow.end <= span.0 || word.searchWindow.start >= span.1,
                        "word \(index)'s window crosses word \(other)")
            }
        }
        // Clamped by the neighbour and by the take's start; a free side gets the full 80 ms.
        #expect(words[0].searchWindow.start == 0)
        #expect(words[0].searchWindow.end == 0.55)
        #expect(words[1].searchWindow.start == 0.50)
        #expect(abs(words[1].searchWindow.end - 0.98) < 1e-9)
        #expect(abs(words[2].searchWindow.start - 1.42) < 1e-9)
        #expect(words[2].searchWindow.end == 2.0)
        // The neighbour's nucleus in the padding is not counted as a peak of "the".
        #expect(words[0].split?.peakCount == 1)
        #expect(words[0].split?.confidence == 0.9)
    }

    @Test("a substituted word has edges but no syllables") func substitutedWord() throws {
        var take = SyntheticTake.pulseTrain
        take.substituted = [1]
        let words = try take.segment().words
        let word = try #require(words.first { $0.phraseWord == WordIndex(1) })
        #expect(word.kind == .substituted)
        #expect(word.range.start == 0.55 && word.range.end == 0.70)
        #expect(word.syllables.isEmpty)
        #expect(word.split == nil)
        #expect(words.filter { $0.kind == .present }.allSatisfy { !$0.syllables.isEmpty })
    }

    @Test("a missing span or pronunciation is an error, not a guess") func missingInputs() throws {
        var input = SyntheticTake.pulseTrain.input
        input.spans[WordIndex(2)] = nil
        #expect(throws: SyllableSegmenter.Failure.missingSpan(WordIndex(2))) {
            try SyllableSegmenter(voicing: EnergyVoicing()).segment(input)
        }
        input = SyntheticTake.pulseTrain.input
        input.pronunciations[WordIndex(0)] = nil
        #expect(throws: SyllableSegmenter.Failure.missingPronunciation(WordIndex(0))) {
            try SyllableSegmenter(voicing: EnergyVoicing()).segment(input)
        }
    }

    // MARK: Exposure

    @Test("the last syllable and a syllable before a 200 ms pause are exposed; one before a 100 ms pause isn't")
    func lengtheningExposure() throws {
        let syllables = try SyntheticTake.pulseTrain.segment().syllables
        let exposed = syllables.filter(\.lengtheningExposed).map { "\($0.phraseWord):\($0.indexInWord)" }
        // "photography" (word 2) ends before the 200 ms pause; "today" (word 4) ends the take. "lesson" (word 3)
        // ends before a 100 ms pause.
        #expect(exposed == ["2:3", "4:1"])
    }

    // MARK: Features and timing

    @Test("per-syllable duration and energy: d in seconds, e in dBFS floored at −60") func rawFeatures() throws {
        // "lesson" is a loud pulse pair; "the" is a silent span.
        let take = SyntheticTake(words: [
            SyntheticWord(text: "lesson", arpabet: "L EH1 S AH0 N", edges: [0.2, 0.45, 0.6]),
            SyntheticWord(text: "the", arpabet: "DH AH0", edges: [0.8, 1.0], shape: { _, _, _ in 0 }),
        ], duration: 1.2)
        let syllables = try take.segment().syllables
        #expect(syllables.count == 3)
        for syllable in syllables { #expect(abs(syllable.duration - syllable.range.duration) < 1e-12) }
        // A raised-cosine bump of a 0.25-peak carrier: around −18 dBFS.
        #expect(syllables[0].energyDBFS > -22 && syllables[0].energyDBFS < -14)
        #expect(syllables[2].energyDBFS == -60)
    }

    @Test("a take with 60% of syllables at medium or above is Rough") func roughTiming() throws {
        #expect(SyllableSegmenter.timing(of: [.high, .medium, .high, .low, .low], thresholds: .init()) == (.rough, 0.6))
        // End to end: 2 high + 1 medium of 5 syllables.
        let take = SyntheticTake(words: [
            SyntheticWord(text: "record", arpabet: "R EH1 K ER0 D", edges: [0.10, 0.30, 0.55], probability: 0.95),
            SyntheticWord(text: "the", arpabet: "DH AH0", edges: [0.70, 0.85], probability: 0.5),
            SyntheticWord(text: "lesson", arpabet: "L EH1 S AH0 N", edges: [1.00, 1.20, 1.40], probability: 0.3),
        ], duration: 1.6)
        let result = try take.segment()
        #expect(result.syllables.map(\.level) == [.high, .high, .medium, .low, .low])
        #expect(result.timing == .rough)
        #expect(abs(result.timingShare - 0.6) < 1e-12)
        #expect(SyllableSegmenter.timing(of: [.high, .high, .high, .high, .medium], thresholds: .init()).level == .good)
        #expect(SyllableSegmenter.timing(of: [.high, .low, .low], thresholds: .init()).level == .poor)
        #expect(SyllableSegmenter.timing(of: [], thresholds: .init()).level == .poor)
    }

    // MARK: L1 output

    @Test("L1 output round-trips through JSON with its identity key, and its digest follows the key")
    func codableWithKeyAndDigest() throws {
        let take = SyntheticTake.pulseTrain
        let result = try take.segment()
        #expect(result.key.l0Key == "test-l0")
        #expect(result.key.transcriptRevision == 1)
        #expect(result.key.algorithmVersion == Versions.algorithmVersion)
        #expect(result.key.pronunciationHash == SyllableSegmenter.pronunciationHash(take.input.pronunciations))
        let json = try CanonicalJSON.encode(result)
        let decoded = try CanonicalJSON.decoder().decode(SyllableSegmentation.self, from: json)
        #expect(try CanonicalJSON.encode(decoded) == json)
        #expect(decoded.words.map(\.syllables.count) == result.words.map(\.syllables.count))
        #expect(try decoded.digest() == result.digest())
        #expect(try take.segment().digest() == result.digest(), "same input, same digest")

        var revised = take.input
        revised.transcriptRevision = 2
        let other = try SyllableSegmenter(voicing: EnergyVoicing()).segment(revised)
        #expect(try other.digest() != result.digest())
        var repronounced = take.input
        repronounced.pronunciations[WordIndex(0)] = try Pronunciation(arpabet: "R IH0 K AO1 R D")
        #expect(try SyllableSegmenter(voicing: EnergyVoicing()).segment(repronounced).key.pronunciationHash
            != result.key.pronunciationHash)
    }

    @Test("WordSpan rejects bad values, in code and in JSON") func wordSpanValidation() throws {
        #expect(throws: SyllableSegmenter.WordSpan.Invalid.endBeforeStart) {
            try SyllableSegmenter.WordSpan(start: 1, end: 0.5, probability: 1)
        }
        #expect(throws: SyllableSegmenter.WordSpan.Invalid.probabilityOutOfRange) {
            try SyllableSegmenter.WordSpan(start: 0, end: 0.5, probability: 1.2)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SyllableSegmenter.WordSpan.self, from: Data(#"{"start":1,"end":0,"probability":1}"#.utf8))
        }
    }
}
