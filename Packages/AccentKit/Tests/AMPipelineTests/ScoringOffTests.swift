// Spec 28: scoring off, show-don't-judge v1. The shipped analyzer (default configuration, `NoOpScorer`) on every
// starter phrase's bundled inputs: the take-problem gate still runs, the verdict is `.notScored`, nothing is judged or
// measured as stress, and the overlay is exactly what a `VerdictScorer` run draws. Replayed timings only: no ASR, no
// network, no microphone.

import AMAlignment
import AMCore
import AMLibrary
@testable import AMPipeline
import AMPlacement
import AMProsody
import AMScoring
import AMVerdicts
import AMWarp
import Foundation
import Synchronization
import Testing

/// The bundled starter library and one replayed take per phrase (its last voice against its headline voice).
struct StarterWorld: Sendable {
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/Starter")

    struct Case: Sendable {
        let phrase: StarterManifest.Phrase
        let input: PhraseInput
        let take: TakeAudio
        let words: [WordTimestamp]
        let asrModelID: String
    }

    let library: ReferenceLibrary
    let references: StarterReferences
    let caches: URL

    static func load() throws -> StarterWorld {
        let caches = FileManager.default.temporaryDirectory.appending(path: "am-scoring-off-\(UUID().uuidString)")
        let (library, references) = try ReferenceLibrary.bundled(
            folder: folder, caches: caches, configuration: try .shipped())
        return StarterWorld(library: library, references: references, caches: caches)
    }

    func cases() throws -> [Case] {
        try library.manifest.phrases.compactMap { phrase -> Case? in
            guard phrase.recordings.count >= 2, let you = phrase.recordings.last(where: { $0.id != phrase.headlineVoice }),
                let input = references.phraseInput(phrase.id)
            else { return nil }
            let timings = try JSONDecoder().decode(
                RecordedTimestamps.self, from: Data(contentsOf: Self.folder.appending(path: you.timings)))
            let take = TakeAudio(
                samples: try StarterReferences.decode16k(Self.folder.appending(path: you.audio)),
                sha256: "take-" + you.audioSHA256, clipID: you.id.rawValue)
            return Case(phrase: phrase, input: input, take: take, words: timings.words, asrModelID: timings.asrModelID)
        }
    }

    func analyzer(_ c: Case, scorer: (any PairScorer)? = nil, words: [WordTimestamp]? = nil, spy: SpyScorer? = nil)
        -> Analyzer
    {
        var configuration = references.configuration
        if let scorer { configuration.scorer = scorer }
        if let spy { configuration.scorer = spy }
        return Analyzer(
            speech: SpeechModelHost(ready: ReplayedStarterWords(asrModelID: c.asrModelID, words: words ?? c.words)),
            configuration: configuration)
    }

    /// The phrase's natives as the analyzer reads them.
    func natives(_ phrase: PhraseID) async throws -> [(recording: NativeRecording, analysis: NativeAnalysis)] {
        try await library.loadNatives(phrase: phrase) { recording in
            DerivedCoding.native(in: recording.analysis).map { (recording, $0) }
        }
    }
}

struct ReplayedStarterWords: WordTimestamper {
    let asrModelID: String
    let words: [WordTimestamp]
    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] { words }
}

/// A scorer that counts its calls (it must not be called when the gate fires).
final class SpyScorer: PairScorer {
    private let calls = Mutex(0)
    var count: Int { calls.withLock { $0 } }
    var mode: ScoringMode { .off }
    func score(_ input: PairScorerInput, thresholds: Thresholds) throws -> PairScore {
        calls.withLock { $0 += 1 }
        return .notScored
    }
}

@Suite("Scoring off (spec 28)", .serialized) struct ScoringOffTests {
    @Test("the shipped configuration's scorer is NoOpScorer and ShippedConfig.scoring follows it")
    func shippedDefaults() throws {
        #expect(ShippedConfig.scorer is NoOpScorer)
        #expect(ShippedConfig.scoring == .off && ShippedConfig.scoring == ShippedConfig.scorer.mode)
        #expect(try Analyzer.Configuration.shipped().scorer is NoOpScorer)
        #expect(VerdictScorer().mode == .on)
    }

    @Test("every starter phrase: .notScored, nothing measured, the overlay equals a VerdictScorer run")
    func everyStarterPhrase() async throws {
        let world = try StarterWorld.load()
        defer { try? FileManager.default.removeItem(at: world.caches) }
        let cases = try world.cases()
        #expect(cases.count == world.library.manifest.phrases.filter { $0.recordings.count >= 2 }.count)
        #expect(!cases.isEmpty)
        var analysed = 0, failedBoth = 0
        for c in cases {
            let voice = c.phrase.headlineVoice
            let off = await world.analyzer(c).run(take: c.take, phrase: c.input, reference: world.library, voice: voice)
            let on = await world.analyzer(c, scorer: VerdictScorer())
                .run(take: c.take, phrase: c.input, reference: world.library, voice: voice)
            #expect(off.response.identity.scoringMode == .off, "\(c.phrase.id)")
            #expect(on.response.identity.scoringMode == .on, "\(c.phrase.id)")
            switch (off.response.outcome, on.response.outcome) {
            case (.takeProblem(let a), .takeProblem(let b)):
                // The gate is the same function either way.
                #expect(a == b, "\(c.phrase.id)")
                continue
            case (.analysed(let result), .analysed(let scored)):
                analysed += 1
                #expect(result.verdict == .notScored, "\(c.phrase.id)")
                #expect(result.identity.scoringMode == .off)
                #expect(result.measures.isEmpty && result.applicability.isEmpty && result.stress.isEmpty, "\(c.phrase.id)")
                #expect(scored.verdict != .notScored, "the VerdictScorer run is scored")
                // No syllable on either speaker is `.measured`.
                #expect((result.model.syllables + result.you.syllables).allSatisfy { $0.stressSource == .dictionary })
                // Stress follows the context-resolved pattern, or is unstressed for an ambiguous word.
                for speaker in [result.model, result.you] {
                    for word in speaker.words {
                        for i in word.syllables {
                            let s = speaker.syllables[i]
                            let pattern = word.expectedStress
                            let expected = pattern.flatMap { $0.indices.contains(s.indexInWord) ? $0[s.indexInWord] : nil }
                            #expect(s.stress == (expected ?? .unstressed), "\(c.phrase.id) \(word.text)")
                        }
                    }
                }
                // The overlay equals a VerdictScorer run on the same inputs.
                #expect(result.timeMap == scored.timeMap, "\(c.phrase.id): timeMap")
                #expect(result.youPitchOnModel == scored.youPitchOnModel, "\(c.phrase.id): youPitchOnModel")
                #expect(result.nativeBand == scored.nativeBand, "\(c.phrase.id): nativeBand")
                #expect(result.pitchAxis == scored.pitchAxis && result.timing == scored.timing)
                #expect(result.describe == scored.describe)
                // comparableCoverage is TimeWarp.comparableCoverage for this pair.
                let natives = try await world.natives(c.phrase.id)
                let model = try #require(natives.first { $0.recording.id == voice }).analysis.l1.analysis
                let l1 = try #require(off.derived.first { $0.level == .l1 })
                let yours = try JSONDecoder().decode(L1Analysis.self, from: l1.bytes).analysis
                let warp = try PairScoring.warp(you: yours, model: model, words: c.input.words)
                #expect(result.comparableCoverage != nil)
                #expect(result.comparableCoverage == warp.comparableCoverage, "\(c.phrase.id)")
                // No diff row anywhere in the encoded result.
                let json = String(decoding: try CanonicalJSON.encode(result), as: UTF8.self)
                for key in ["\"rows\"", "\"feedback\"", "\"heardSyllable\"", "\"acceptedSyllable\"", "\"close\""] {
                    #expect(!json.contains(key), "\(c.phrase.id): \(key) in the encoded result")
                }
            case (.failed(let a), .failed(let b)) where a == b:
                // The same operational failure either way (vctk-005: this take/model pair has no time map): not a
                // scoring question, so it is counted, not judged.
                failedBoth += 1
            default:
                Issue.record("\(c.phrase.id): off \(off.response.outcome), on \(on.response.outcome)")
            }
        }
        #expect(analysed >= cases.count - 2, "analysed \(analysed) of \(cases.count) (\(failedBoth) failed both ways)")
    }

    @Test("the L2 key includes the scoring mode, so an .on comparison is never served for .off")
    func l2KeySeparatesModes() throws {
        let world = try StarterWorld.load()
        defer { try? FileManager.default.removeItem(at: world.caches) }
        let c = try #require(try world.cases().first)
        let off = world.analyzer(c), on = world.analyzer(c, scorer: VerdictScorer())
        let l1 = off.l1Key(l0: off.l0Key(takeAudioSHA256: c.take.sha256), phrase: c.input)
        let reference = world.library.identity(phrase: c.phrase.id, voice: c.phrase.headlineVoice)
        #expect(off.l2Key(l1: l1, reference: reference).text != on.l2Key(l1: l1, reference: reference).text)
        #expect(off.l1Key(l0: off.l0Key(takeAudioSHA256: "x"), phrase: c.input)
            == on.l1Key(l0: on.l0Key(takeAudioSHA256: "x"), phrase: c.input), "L1 is shared")
    }

    // MARK: - §1a: the take-problem gate stays on the shipped path

    @Test("a words-don't-match take is still a take problem under NoOpScorer, and the scorer isn't called")
    func wordsDontMatch() async throws {
        let world = try StarterWorld.load()
        defer { try? FileManager.default.removeItem(at: world.caches) }
        let c = try #require(try world.cases().first)
        let wrong = c.words.map { WordTimestamp(word: "banana", start: $0.start, end: $0.end, probability: $0.probability) }
        let spy = SpyScorer()
        let response = await world.analyzer(c, words: wrong, spy: spy)
            .analyse(take: c.take, phrase: c.input, reference: world.library, voice: c.phrase.headlineVoice)
        #expect(response.outcome == .takeProblem(.wordsDontMatch))
        #expect(spy.count == 0)
        let shipped = await world.analyzer(c, words: wrong)
            .analyse(take: c.take, phrase: c.input, reference: world.library, voice: c.phrase.headlineVoice)
        #expect(shipped.outcome == .takeProblem(.wordsDontMatch))
    }

    @Test("a too-short take is still a take problem under NoOpScorer, and the scorer isn't called")
    func tooShort() async throws {
        let world = try StarterWorld.load()
        defer { try? FileManager.default.removeItem(at: world.caches) }
        let c = try #require(try world.cases().first)
        let short = TakeAudio(samples: Array(c.take.samples.prefix(Int(0.2 * TakeAudio.sampleRate))), clipID: c.take.clipID)
        let spy = SpyScorer()
        let response = await world.analyzer(c, spy: spy)
            .analyse(take: short, phrase: c.input, reference: world.library, voice: c.phrase.headlineVoice)
        guard case .takeProblem(let problem) = response.outcome else {
            Issue.record("expected a take problem, got \(response.outcome)")
            return
        }
        #expect(problem == .tooShort || problem == .noSpeech, "got \(problem)")
        #expect(spy.count == 0)
    }

    @Test("a clean take comes back .notScored, and the scorer is called once")
    func cleanTake() async throws {
        let world = try StarterWorld.load()
        defer { try? FileManager.default.removeItem(at: world.caches) }
        let c = try #require(try world.cases().first)
        let spy = SpyScorer()
        let response = await world.analyzer(c, spy: spy)
            .analyse(take: c.take, phrase: c.input, reference: world.library, voice: c.phrase.headlineVoice)
        guard case .analysed(let result) = response.outcome else {
            Issue.record("expected analysed, got \(response.outcome)")
            return
        }
        #expect(result.verdict == .notScored && spy.count == 1)
    }

    // MARK: - §4: context-resolved expected stress

    @Test("an override that differs from CMUdict's first entry sets expectedStress, on the input and the result")
    func overrideFollowsContext() async throws {
        let world = try StarterWorld.load()
        defer { try? FileManager.default.removeItem(at: world.caches) }
        let dictionary = try PronouncingDictionary.bundled()
        var checked = 0
        for c in try world.cases() {
            for (index, arpabet) in c.phrase.pronunciations {
                let override = try Pronunciation(arpabet: arpabet)
                let word = try #require(c.input.words.first { $0.index.rawValue == index })
                guard let first = dictionary.pronunciations(of: WordText.fold(word.text)).first,
                    first.stressPattern != override.stressPattern
                else { continue }
                #expect(word.expectedStress == override.stressPattern, "\(c.phrase.id) \(word.text)")
                let response = await world.analyzer(c)
                    .analyse(take: c.take, phrase: c.input, reference: world.library, voice: c.phrase.headlineVoice)
                if case .analysed(let result) = response.outcome {
                    let span = try #require(result.model.words.first { $0.text == word.text })
                    #expect(span.expectedStress == override.stressPattern, "\(c.phrase.id) \(word.text)")
                    #expect(span.expectedStress?.firstIndex(of: .primary) == override.primarySyllable)
                }
                checked += 1
                break
            }
            if checked >= 2 { break }
        }
        #expect(checked > 0, "no starter override differs from CMUdict's first entry")
    }

    @Test("an expectedAmbiguous word has expectedStress nil")
    func ambiguousWordHasNoExpectedStress() throws {
        let selector = try PronunciationSelector.bundled(tagger: NaturalLanguageTagger())
        let first = selector.expectedPhrase(for: PhraseText(text: "Record it.", origin: .imported(persisted: [:])))
        let persisted = Dictionary(uniqueKeysWithValues: first.persistable.map { ($0.word, $0) })
        var ambiguous = selector.expectedPhrase(for: PhraseText(text: "Record it.", origin: .imported(persisted: persisted)))
        if !(ambiguous.words.first?.expectedAmbiguous ?? false) {
            // Force the stored choice ambiguous, as a persisted ambiguous word is.
            let forced = first.persistable.map {
                PersistedPronunciation(
                    word: $0.word, text: $0.text, pronunciation: $0.pronunciation, expectedAmbiguous: true,
                    chosenBy: $0.chosenBy)
            }
            ambiguous = selector.expectedPhrase(for: PhraseText(
                text: "Record it.",
                origin: .imported(persisted: Dictionary(uniqueKeysWithValues: forced.map { ($0.word, $0) }))))
        }
        let record = try #require(ambiguous.words.first)
        #expect(record.expectedAmbiguous)
        let words = ImportedPhrases.words(ambiguous, measuring: false)
        #expect(try #require(words.first).expectedStress == nil)
        #expect(words.last?.expectedStress != nil, "\"it\" has its pattern")
    }

    // MARK: - L1 stores no decision

    @Test("a pre-spec-28 L1 record with observed stress and decisions decodes; the fields are gone")
    func legacyL1Decodes() async throws {
        let world = try StarterWorld.load()
        defer { try? FileManager.default.removeItem(at: world.caches) }
        // The bundled analyses were built before spec 28: a phrase with a polysyllabic target still carries `words`
        // with observed stress and placement decisions in its L1.
        var found: (bytes: Data, words: [[String: Any]])?
        for phrase in world.library.manifest.phrases {
            for recording in phrase.recordings {
                let bytes = try Data(contentsOf: StarterWorld.folder.appending(path: recording.analysis))
                let raw = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                let analysis = (raw["l1"] as? [String: Any])?["analysis"] as? [String: Any]
                if let words = analysis?["words"] as? [[String: Any]],
                    words.contains(where: { $0["decision"] != nil && $0["observed"] != nil })
                {
                    found = (bytes, words)
                    break
                }
            }
            if found != nil { break }
        }
        let bytes = try #require(found, "no pre-spec-28 L1 with decisions among the bundled analyses").bytes
        let native = try JSONDecoder().decode(NativeAnalysis.self, from: bytes)
        let reencoded = try #require(
            try JSONSerialization.jsonObject(with: DerivedCoding.encode(native.l1.analysis)) as? [String: Any])
        #expect(Set(reencoded.keys) == ["segmentation", "alignment", "pitch"])
    }
}
