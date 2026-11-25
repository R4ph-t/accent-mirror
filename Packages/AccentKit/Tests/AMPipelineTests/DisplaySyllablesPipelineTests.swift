import AMAlignment
import AMCore
import AMLibrary
import AMPitch
@testable import AMPipeline
import AMProsody
import Foundation
import Testing

private let starterFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/Starter")

@Suite("Pipeline display syllable labels (v3.4 Y1–Y3)")
struct DisplaySyllablesPipelineTests {
    private static func hasPhoneToken(_ s: String) -> Bool { s.firstMatch(of: /\b[A-Za-z]+[012]\b/) != nil }

    @Test("Every starter phrase produces table display labels and zero ARPAbet phone tokens")
    func everyStarterPhraseProducesReadableLabels() async throws {
        let caches = FileManager.default.temporaryDirectory.appending(path: "am-labels-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: caches) }
        let (library, references) = try ReferenceLibrary.bundled(
            folder: starterFolder, caches: caches, configuration: try .shipped())
        let table = try DisplaySyllableTable.bundled()

        #expect(library.manifest.phrases.count == 14)

        for phrase in library.manifest.phrases {
            let input = try #require(references.phraseInput(phrase.id))
            let display = try await NativeView.load(phrase: input, voice: phrase.headlineVoice, reference: library)
            #expect(display.model.words.count == input.words.count, "\(phrase.id)")

            for (wordIndex, span) in display.model.words.enumerated() {
                let folded = DisplayWord.fold(span.text)
                let expectedPieces = try #require(
                    table.syllables(forFolded: folded),
                    "\(phrase.id) word \(wordIndex) '\(folded)' missing from starter-syllables.json")
                let actualPieces = span.syllables.map { display.model.syllables[$0].text }
                #expect(actualPieces == expectedPieces, "\(phrase.id) '\(folded)'")
                #expect(actualPieces.joined() == folded, "\(phrase.id) '\(folded)' concatenation")
                for piece in actualPieces {
                    #expect(!piece.isEmpty)
                    #expect(!Self.hasPhoneToken(piece), "\(phrase.id) phone token in '\(piece)'")
                }
            }
        }
    }

    @Test("ResultAssembly emits empty syllable label (never phones or spellingSyllables) for chocolate mismatch")
    func resultAssemblyChocolateUsesMergedWordFallback() throws {
        let dictionary = try PronouncingDictionary.bundled()
        let chocoPron = try #require(dictionary.pronunciations(of: "chocolate").first)
        #expect(chocoPron.syllables.count == 2)

        let phraseWord = WordIndex(0)
        let s0 = SegmentedSyllable(
            phraseWord: phraseWord, indexInWord: 0, phones: chocoPron.syllables[0].phones, stress: .primary,
            range: try TimeRange(start: 0.1, end: 0.4), duration: 0.3, energyDBFS: -18,
            lengtheningExposed: false, confidence: 0.9, level: .high)
        let s1 = SegmentedSyllable(
            phraseWord: phraseWord, indexInWord: 1, phones: chocoPron.syllables[1].phones, stress: .unstressed,
            range: try TimeRange(start: 0.42, end: 0.7), duration: 0.28, energyDBFS: -24,
            lengtheningExposed: true, confidence: 0.9, level: .high)
        let segmented = SegmentedWord(
            phraseWord: phraseWord, kind: .present, range: try TimeRange(start: 0.1, end: 0.7),
            injected: try SyllableSegmenter.WordSpan(start: 0.1, end: 0.7, probability: 0.9),
            searchWindow: try TimeRange(start: 0.08, end: 0.72), spanSanity: 1.0, confidence: 0.9,
            split: SyllableSplit(method: .valleys, dictionaryCount: 2, peakCount: 2, confidence: 0.9),
            syllables: [s0, s1])
        let prosody = TakeProsody(
            segmentation: SyllableSegmentation(
                key: .init(l0Key: "k", transcriptRevision: 0, pronunciationHash: "h"),
                words: [segmented], timingShare: 1.0, timing: .good),
            alignment: try WordAlignment(pairs: [.present(phrase: phraseWord, you: try TimeRange(start: 0.1, end: 0.7))]),
            pitch: PitchTrack(frameF0Hz: []))

        let entry = ResultAssembly.Entry(
            text: "chocolate", range: segmented.range, syllables: [s0, s1], expected: [.primary, .unstressed])
        let speaker = ResultAssembly.speaker(
            [entry], analysis: prosody, measured: [:], mode: .off, thresholds: .current)

        #expect(speaker.words.count == 1)
        #expect(speaker.syllables.count == 2)
        #expect(speaker.syllables.allSatisfy { $0.text.isEmpty }, "mismatch triggers merged-word fallback, never phones")
        for syllable in speaker.syllables {
            #expect(!Self.hasPhoneToken(syllable.text))
        }
    }
}
