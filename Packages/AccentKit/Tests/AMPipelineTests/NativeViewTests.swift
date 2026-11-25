// Addendum v3.2 W1: the native model before the first take. `NativeView.load` reads the bundled starter analyses and
// must draw the same model, axis, band and native range a result later draws for that voice (scoring off).
// Replayed timings only: no ASR, no network, no microphone.

import AMAlignment
import AMCore
import AMLibrary
import AMPipeline
import Foundation
import Testing

private let starterFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/Starter")

@Suite("Native view before the first take") struct NativeViewTests {
    @Test("The bundled model has its words, syllables, prominence, context-resolved stress, band and axis")
    func bundledDisplay() async throws {
        let caches = FileManager.default.temporaryDirectory.appending(path: "am-native-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: caches) }
        let (library, references) = try ReferenceLibrary.bundled(
            folder: starterFolder, caches: caches, configuration: try .shipped())
        let phrase = try #require(library.manifest.phrases.first { $0.recordings.count >= 3 })
        let input = try #require(references.phraseInput(phrase.id))

        let display = try await NativeView.load(phrase: input, voice: phrase.headlineVoice, reference: library)

        #expect(display.phraseID == phrase.id)
        #expect(display.recordingID == phrase.headlineVoice)
        #expect(display.model.words.map(\.text) == input.words.map(\.text))
        #expect(display.model.words.map(\.expectedStress) == input.words.map(\.expectedStress))
        #expect(display.model.words.allSatisfy { !$0.syllables.isEmpty })
        #expect(display.model.syllables.contains { $0.prominence > 0 })
        #expect(display.model.syllables.allSatisfy { $0.stressSource == .dictionary })
        #expect(display.model.syllables.contains { $0.stress == .primary })
        // Words are timed from the recording, not spread evenly.
        let starts = display.model.words.map(\.range.start)
        #expect(starts == starts.sorted())
        #expect(display.modelAxis.end > display.modelAxis.start)
        #expect(display.modelAxis.start == display.model.words.first?.range.start)
        #expect(!display.nativeBand.isEmpty)
        #expect(display.pitchAxis.upperBound > display.pitchAxis.lowerBound)
        #expect(display.native.voices == phrase.recordings.count)
        #expect(await library.rebuilds.isEmpty)
    }

    @Test("It matches the native side of a result for the same voice")
    func matchesResult() async throws {
        let caches = FileManager.default.temporaryDirectory.appending(path: "am-native-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: caches) }
        let (library, references) = try ReferenceLibrary.bundled(
            folder: starterFolder, caches: caches, configuration: try .shipped())
        let phrase = try #require(library.manifest.phrases.first { $0.recordings.count >= 3 })
        let input = try #require(references.phraseInput(phrase.id))
        let you = try #require(phrase.recordings.last)
        let timings = try JSONDecoder().decode(
            RecordedTimestamps.self, from: Data(contentsOf: starterFolder.appending(path: you.timings)))
        let take = TakeAudio(
            samples: try StarterReferences.decode16k(starterFolder.appending(path: you.audio)),
            sha256: "take-" + you.audioSHA256, clipID: you.id.rawValue)
        let analyzer = Analyzer(
            speech: SpeechModelHost(ready: Replay(asrModelID: timings.asrModelID, words: timings.words)),
            configuration: references.configuration)
        let response = await analyzer.analyse(take: take, phrase: input, reference: library, voice: phrase.headlineVoice)
        guard case .analysed(let result) = response.outcome else {
            Issue.record("analysis did not produce a result: \(response.outcome)")
            return
        }

        let display = try await NativeView.load(phrase: input, voice: phrase.headlineVoice, reference: library)

        #expect(display.model == result.model)
        #expect(display.modelAxis == result.modelAxis)
        #expect(display.nativeBand == result.nativeBand)
        #expect(display.native == result.describe?.native)
    }

    @Test("A voice the phrase has no recording for throws notFound")
    func unknownVoice() async throws {
        let caches = FileManager.default.temporaryDirectory.appending(path: "am-native-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: caches) }
        let (library, references) = try ReferenceLibrary.bundled(
            folder: starterFolder, caches: caches, configuration: try .shipped())
        let phrase = try #require(library.manifest.phrases.first)
        let input = try #require(references.phraseInput(phrase.id))
        await #expect(throws: ReferenceLoadError.notFound(RecordingID("nobody"))) {
            try await NativeView.load(phrase: input, voice: RecordingID("nobody"), reference: library)
        }
    }
}

private struct Replay: WordTimestamper {
    let asrModelID: String
    let words: [WordTimestamp]
    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] { words }
}
