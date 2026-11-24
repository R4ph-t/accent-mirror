// Spec 15's CI check: every bundled starter analysis is recomputed from the committed audio and word timings with the
// shipped configuration, and must match the bundled identity and bytes. Then one take goes through the analyzer
// against the bundled library. Replayed timings only: no ASR, no network.

import AMAlignment
import AMCore
import AMLibrary
import AMPipeline
import Foundation
import Testing

private let starterFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/Starter")

@Suite("Bundled starter library") struct BundledStarterTests {
    @Test("Every phrase passes spec 06's starter validator and has a target")
    func phrasesPassValidator() throws {
        let manifest = try StarterManifest.load(from: starterFolder, checkFiles: false)
        let dictionary = try PronouncingDictionary.bundled()
        for phrase in manifest.phrases {
            let file = PhrasePronunciationFile(
                text: phrase.text, targets: phrase.targets, pronunciations: phrase.pronunciations)
            #expect(StarterPhraseValidator.problems(in: file, dictionary: dictionary).isEmpty, "\(phrase.id)")
            #expect(!phrase.targets.isEmpty, "\(phrase.id)")
        }
    }

    @Test("Every bundled analysis recomputes to its bundled identity and bytes")
    func bundledAnalysesRecompute() async throws {
        let manifest = try StarterManifest.load(from: starterFolder)
        let references = try StarterReferences(manifest: manifest, configuration: try .shipped())
        let sources = manifest.phrases.flatMap { phrase in
            phrase.recordings.map {
                StarterRecordingSource(
                    phrase: phrase, recording: $0, audio: starterFolder.appending(path: $0.audio),
                    timings: starterFolder.appending(path: $0.timings), asrModelID: manifest.asrModelID)
            }
        }
        let differences = try await withThrowingTaskGroup(of: String?.self) { group in
            for source in sources {
                group.addTask {
                    let recording = source.recording
                    if references.expectedKey(source) != recording.analysisKey {
                        return "\(recording.id): bundled identity is stale for the running code"
                    }
                    let record = try await references.analyse(source)
                    if record.key != recording.analysisKey { return "\(recording.id): recomputed key differs" }
                    if SHA256Digest.hex(of: record.bytes) != recording.analysisSHA256 {
                        return "\(recording.id): recomputed analysis digest differs"
                    }
                    return nil
                }
            }
            var found: [String] = []
            for try await difference in group { if let difference { found.append(difference) } }
            return found.sorted()
        }
        #expect(differences.isEmpty, "rebuild Resources/Starter with scripts/build-starter.sh: \(differences)")
        #expect(sources.count == manifest.phrases.map(\.recordings.count).reduce(0, +))
    }

    @Test("A take is analysed against the bundled library without a rebuild or a write to the bundle")
    func takeAgainstBundledLibrary() async throws {
        let caches = FileManager.default.temporaryDirectory.appending(path: "am-starter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: caches) }
        let (library, references) = try ReferenceLibrary.bundled(
            folder: starterFolder, caches: caches, configuration: try .shipped())
        let phrase = try #require(library.manifest.phrases.first { $0.recordings.count >= 3 })
        // Your take: the phrase's last voice, replayed; the reference: its headline voice.
        let you = try #require(phrase.recordings.last)
        let timings = try JSONDecoder().decode(
            RecordedTimestamps.self, from: Data(contentsOf: starterFolder.appending(path: you.timings)))
        let take = TakeAudio(
            samples: try StarterReferences.decode16k(starterFolder.appending(path: you.audio)),
            sha256: "take-" + you.audioSHA256, clipID: you.id.rawValue)
        let analyzer = Analyzer(
            speech: SpeechModelHost(ready: Replay(asrModelID: timings.asrModelID, words: timings.words)),
            configuration: references.configuration)
        let input = try #require(references.phraseInput(phrase.id))
        let response = await analyzer.analyse(take: take, phrase: input, reference: library, voice: phrase.headlineVoice)
        if case .failed(let error) = response.outcome { Issue.record("analysis failed: \(error)") }
        #expect(response.identity.reference == library.identity(phrase: phrase.id, voice: phrase.headlineVoice))
        #expect(await library.rebuilds.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: caches.path))
    }
}

private struct Replay: WordTimestamper {
    let asrModelID: String
    let words: [WordTimestamp]
    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] { words }
}
