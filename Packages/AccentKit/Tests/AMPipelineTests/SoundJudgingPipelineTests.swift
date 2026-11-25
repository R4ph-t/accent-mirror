// Sound judging in the analysis (sound-judging plan, 2026-11-25), with stub judges: no Core ML. The judge runs beside
// the stages, never fails the analysis, answers at once while the model loads, is cancelled with the request, and its
// outcome lands in `AnalysisResult.sounds` and in the saved L2 record.

import AMAlignment
import AMCore
import AMJudging
import AMLibrary
import AMProsody
@testable import AMPipeline
import Foundation
import Synchronization
import Testing

@Suite("Sound judging in the analysis") struct SoundJudgingPipelineTests {
    static let voice = PipelineFixtures.voice(PipelineFixtures.modelItem)

    /// A judgement that judges every word with a dictionary pronunciation, one sound a phone, the first word's first
    /// sound flagged; each word placed at a made-up range on your timeline.
    static func judgement(_ words: [AMJudging.ExpectedWord]) -> SoundJudgement {
        SoundJudgement(
            modelID: "stub@0#00000000", judgeID: "stub", errorThreshold: 0.22,
            words: words.map { word in
                let range = try? TimeRange(start: Double(word.index.rawValue), end: Double(word.index.rawValue) + 0.5)
                guard let variant = word.variants.first else {
                    return JudgedWord(index: word.index, text: word.text, youRange: nil, modelRange: word.modelRange,
                                      state: .unjudged(.notInDictionary))
                }
                return JudgedWord(
                    index: word.index, text: word.text, youRange: range, modelRange: word.modelRange,
                    state: .judged(variant.enumerated().map { k, phone in
                        let flagged = word.index.rawValue == 0 && k == 0
                        return JudgedPhone(
                            phone: phone.filter { !$0.isNumber }, gop: flagged ? -9 : -0.1,
                            confidence: flagged ? 0.1 : 0.95, flagged: flagged,
                            heardInstead: flagged ? .nothing : nil, youRange: range)
                    }))
            })
    }

    /// Records what the judge was called with and how often.
    final class JudgeLog: Sendable {
        let calls = Atomic<Int>(0)
        let cancelled = Atomic<Bool>(false)
        let words = Mutex<[AMJudging.ExpectedWord]>([])
    }

    static func analyzer(
        _ world: PipelineFixtures.World, sounds: SoundJudgeHost?,
        beforeStage: (@Sendable (Stage) async throws -> Void)? = nil
    ) throws -> Analyzer {
        var configuration = try Analyzer.Configuration.shipped()
        configuration.beforeStage = beforeStage
        return Analyzer(speech: SpeechModelHost(ready: world.timings), sounds: sounds, configuration: configuration)
    }

    static func run(_ analyzer: Analyzer, _ world: PipelineFixtures.World, voice: RecordingID = voice) async
        -> Analyzer.Run
    {
        await analyzer.run(take: world.you, phrase: world.phrase, reference: world.reference, voice: voice)
    }

    static func sounds(_ run: Analyzer.Run) -> SoundJudgementOutcome?? {
        guard case .analysed(let result) = run.response.outcome else { return .none }
        return .some(result.sounds)
    }

    @Test("a judged take: the judgement is in the result and the saved L2 record, words placed on the native")
    func judged() async throws {
        let world = try await PipelineFixtures.world()
        let log = JudgeLog()
        let host = SoundJudgeHost(ready: { _, words in
            log.calls.add(1, ordering: .relaxed)
            log.words.withLock { $0 = words }
            return Self.judgement(words)
        })
        let run = await Self.run(try Self.analyzer(world, sounds: host), world)
        guard case .analysed(let result) = run.response.outcome, case .judged(let judgement)? = result.sounds else {
            Issue.record("expected a judged result, got \(run.response.outcome)")
            return
        }
        #expect(log.calls.load(ordering: .relaxed) == 1)
        // Every phrase word, with every CMUdict variant; the judge is called before the native is read.
        let words = log.words.withLock { $0 }
        #expect(words.map(\.index) == world.phrase.words.map(\.index))
        #expect(words.allSatisfy { $0.modelRange == nil })
        let dictionary = try PronouncingDictionary.bundled()
        for word in words {
            #expect(word.variants == dictionary.pronunciations(of: word.text).map(\.phones), "\(word.text)")
        }
        // Placed on the selected native's timeline afterwards, your-side ranges kept for words you said.
        #expect(judgement.words.count == world.phrase.words.count)
        #expect(judgement.words.allSatisfy { $0.modelRange != nil })
        let present = Set(result.alignment.pairs.compactMap { pair -> WordIndex? in
            if case .present(let w, _) = pair { w } else { nil }
        })
        for word in judgement.words where present.contains(word.index) {
            #expect(word.youRange != nil && word.phones.allSatisfy { $0.youRange != nil })
        }
        #expect(judgement.flaggedSounds.count == 1)
        // The saved comparison carries the same sounds.
        let l2 = try #require(run.derived.first { $0.level == .l2 })
        let stored = try JSONDecoder().decode(L2Analysis.self, from: l2.bytes)
        guard case .analysed(let saved) = stored.outcome else { Issue.record("stored L2 not analysed"); return }
        #expect(saved.sounds == result.sounds)
    }

    @Test("a word you didn't say loses its your-side ranges; the others keep the judge's")
    func missingWordHasNoYourRange() throws {
        let words = [0, 1, 2].map {
            AMJudging.ExpectedWord(index: WordIndex($0), text: "cat", variants: [["K", "AE1", "T"]])
        }
        let r = try TimeRange(start: 0, end: 0.4)
        let alignment = try WordAlignment(pairs: [
            .present(phrase: WordIndex(0), you: r), .missing(phrase: WordIndex(1)),
            .substituted(phrase: WordIndex(2), heard: "cap", you: try TimeRange(start: 0.5, end: 0.9)),
        ])
        let model = try TimeRange(start: 1, end: 2)
        let placed = SoundJudgeWords.placing(
            .judged(Self.judgement(words)), modelRanges: [WordIndex(1): model], alignment: alignment)
        guard case .judged(let judgement) = placed else { Issue.record("expected judged"); return }
        #expect(judgement.words[0].youRange != nil && judgement.words[0].modelRange == nil)
        #expect(judgement.words[1].youRange == nil && judgement.words[1].phones.allSatisfy { $0.youRange == nil })
        #expect(judgement.words[1].modelRange == model)
        #expect(judgement.words[1].phones.count == 3 && judgement.words[1].flagged == false)
        #expect(judgement.words[2].youRange != nil && judgement.words[2].phones.allSatisfy { $0.youRange != nil })
    }

    @Test("judge and load errors become unavailable outcomes; the analysis still succeeds",
          arguments: [
              (SoundJudgeError.takeOutOfRange(seconds: 16), SoundJudgementUnavailable.takeOutOfRange),
              (SoundJudgeError.modelFailed("ANE"), .modelFailed),
              (SoundJudgeError.modelNotInstalled, .modelNotInstalled),
              (SoundJudgeError.notImplemented, .modelNotInstalled),
          ])
    func judgeErrors(error: SoundJudgeError, expected: SoundJudgementUnavailable) async throws {
        let world = try await PipelineFixtures.world()
        let host = SoundJudgeHost(ready: { _, _ in throw error })
        let run = await Self.run(try Self.analyzer(world, sounds: host), world)
        #expect(Self.sounds(run) == .some(.unavailable(expected)))
    }

    @Test("other errors map onto unavailable reasons")
    func errorMapping() {
        #expect(SoundJudgeHost.unavailable(for: CocoaError(.fileReadNoSuchFile)) == .modelNotInstalled)
        #expect(SoundJudgeHost.unavailable(for: InjectedError()) == .modelFailed)
    }

    @Test("a judge that judges no word gives nothingJudgeable")
    func nothingJudgeable() async throws {
        let world = try await PipelineFixtures.world()
        let host = SoundJudgeHost(ready: { _, words in
            SoundJudgement(
                modelID: "stub", judgeID: "stub", errorThreshold: 0.22,
                words: words.map {
                    JudgedWord(index: $0.index, text: $0.text, youRange: nil, modelRange: nil,
                               state: .unjudged(.notInDictionary))
                })
        })
        let run = await Self.run(try Self.analyzer(world, sounds: host), world)
        #expect(Self.sounds(run) == .some(.unavailable(.nothingJudgeable)))
    }

    @Test("a phrase with no dictionary word is nothingJudgeable without calling the judge")
    func outOfVocabularyPhrase() async throws {
        let log = JudgeLog()
        let host = SoundJudgeHost(ready: { _, words in
            log.calls.add(1, ordering: .relaxed)
            return Self.judgement(words)
        })
        let words = SoundJudgeWords.expected(
            [PlacementTake.Word(index: WordIndex(0), text: "Zxqvbn", pronunciation: try Pronunciation(arpabet: "AH0"),
                                accepted: nil)],
            dictionary: try PronouncingDictionary.bundled())
        #expect(words.first?.variants == [])
        #expect(try await host.outcome(samples: [0], words: words) == .unavailable(.nothingJudgeable))
        #expect(log.calls.load(ordering: .relaxed) == 0)
    }

    @Test("a judge still loading answers modelNotInstalled at once; a failed load is remembered",
          .timeLimit(.minutes(2)))
    func loadingJudgeDoesNotWait() async throws {
        let world = try await PipelineFixtures.world()
        let release = AsyncStream<Void>.makeStream()
        let host = SoundJudgeHost {
            for await _ in release.stream { break }
            throw SoundJudgeError.modelFailed("refused")
        }
        await host.prepare()
        let analyzer = try Self.analyzer(world, sounds: host)
        // The load never finishes on its own: if the analysis waited for it, this would hit the time limit.
        let run = await Self.run(analyzer, world)
        #expect(Self.sounds(run) == .some(.unavailable(.modelNotInstalled)))
        release.continuation.yield()
        while await host.loadAttempts == 1, case .unavailable(.modelNotInstalled) = await host.readyJudge() {
            await Task.yield()
        }
        guard case .unavailable(let reason) = await host.readyJudge() else { Issue.record("expected failed"); return }
        #expect(reason == .modelFailed)
        // Not cached as settled: the next request asks the host again and gets the remembered failure, no reload.
        let again = await Self.run(analyzer, world, voice: PipelineFixtures.voice(PipelineFixtures.otherItem))
        #expect(Self.sounds(again) == .some(.unavailable(.modelFailed)))
        #expect(await host.loadAttempts == 1)
    }

    @Test("a host never prepared starts loading on the first take and doesn't wait for it")
    func unpreparedHostStartsLoading() async throws {
        let host = SoundJudgeHost { { _, words in Self.judgement(words) } }
        #expect(await host.loadAttempts == 0)
        let words = [AMJudging.ExpectedWord(index: WordIndex(0), text: "cat", variants: [["K", "AE1", "T"]])]
        #expect(try await host.outcome(samples: [0], words: words) == .unavailable(.modelNotInstalled))
        #expect(await host.loadAttempts == 1)
        while await !host.isLoaded { await Task.yield() }
        guard case .judged = try await host.outcome(samples: [0], words: words) else {
            Issue.record("expected judged once loaded")
            return
        }
    }

    @Test("judging runs beside the stages, not before or after them", .timeLimit(.minutes(2)))
    func judgingOverlapsStages() async throws {
        let world = try await PipelineFixtures.world()
        // The judge holds until the analysis reaches the time map; the time map checks the judge already started.
        // Judging run before the stages would never finish (time limit); run after them, `startedFirst` is false.
        let reachedMapTime = AsyncStream<Void>.makeStream()
        let started = Atomic<Bool>(false)
        let startedFirst = Mutex<Bool?>(nil)
        let host = SoundJudgeHost(ready: { _, words in
            started.store(true, ordering: .sequentiallyConsistent)
            for await _ in reachedMapTime.stream { break }
            return Self.judgement(words)
        })
        let analyzer = try Self.analyzer(world, sounds: host, beforeStage: { stage in
            guard stage == .mapTime else { return }
            startedFirst.withLock { if $0 == nil { $0 = started.load(ordering: .sequentiallyConsistent) } }
            reachedMapTime.continuation.yield()
        })
        let run = await Self.run(analyzer, world)
        #expect(startedFirst.withLock { $0 } == true)
        guard case .some(.some(.judged)) = Self.sounds(run) else { Issue.record("expected judged"); return }
    }

    @Test("a slow judge adds only its own run time, not the stages' on top", .timeLimit(.minutes(2)))
    func slowJudgeOverlaps() async throws {
        let world = try await PipelineFixtures.world()
        let stageDelay = Duration.milliseconds(800)
        let judgeDelay = Duration.milliseconds(800)
        let host = SoundJudgeHost(ready: { _, words in
            try await Task.sleep(for: judgeDelay)
            return Self.judgement(words)
        })
        let delayed: @Sendable (Stage) async throws -> Void = { stage in
            if stage == .decodeAudio { try await Task.sleep(for: stageDelay) }
        }
        let baselineStart = ContinuousClock.now
        _ = await Self.run(try Self.analyzer(world, sounds: nil, beforeStage: delayed), world)
        let baseline = baselineStart.duration(to: .now)
        let start = ContinuousClock.now
        let run = await Self.run(try Self.analyzer(world, sounds: host, beforeStage: delayed), world)
        let elapsed = start.duration(to: .now)
        print("slow judge: baseline \(baseline), with judging \(elapsed)")
        guard case .some(.some(.judged)) = Self.sounds(run) else { Issue.record("expected judged"); return }
        // Run in sequence it would add the whole 800 ms; beside the stages, it hides behind the delayed decode.
        #expect(elapsed < baseline + .milliseconds(600))
    }

    @Test("cancelling the request cancels the judge", .timeLimit(.minutes(2)))
    func cancelledWithTheRequest() async throws {
        let world = try await PipelineFixtures.world()
        let log = JudgeLog()
        let host = SoundJudgeHost(ready: { _, words in
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                log.cancelled.store(true, ordering: .sequentiallyConsistent)
                throw error
            }
            return Self.judgement(words)
        })
        let analyzer = try Self.analyzer(world, sounds: host)
        let task = Task { await Self.run(analyzer, world) }
        // Analysed in well under a second, then waits for the judge: cancel while it waits.
        try await Task.sleep(for: .seconds(2))
        task.cancel()
        let run = await task.value
        #expect(run.response.outcome == .cancelled)
        while !log.cancelled.load(ordering: .sequentiallyConsistent) { await Task.yield() }
    }

    @Test("a take problem doesn't wait for the judge", .timeLimit(.minutes(2)))
    func takeProblemDoesNotWait() async throws {
        let world = try await PipelineFixtures.world()
        let host = SoundJudgeHost(ready: { _, words in
            try await Task.sleep(for: .seconds(60))
            return Self.judgement(words)
        })
        let silent = TakeAudio(samples: [Float](repeating: 0, count: 48_000), recordedAt: PipelineFixtures.recordedAt)
        let start = ContinuousClock.now
        let analyzer = try Self.analyzer(world, sounds: host)
        let response = await analyzer.analyse(
            take: silent, phrase: world.phrase, reference: world.reference, voice: Self.voice)
        #expect(response.outcome == .takeProblem(.noSpeech))
        #expect(start.duration(to: .now) < .seconds(10))
    }

    @Test("a voice switch reuses the judgement: the judge runs once per take and phrase")
    func voiceSwitchReusesJudgement() async throws {
        let world = try await PipelineFixtures.world()
        let log = JudgeLog()
        let host = SoundJudgeHost(ready: { _, words in
            log.calls.add(1, ordering: .relaxed)
            return Self.judgement(words)
        })
        let analyzer = try Self.analyzer(world, sounds: host)
        let first = await Self.run(analyzer, world)
        let second = await Self.run(analyzer, world, voice: PipelineFixtures.voice(PipelineFixtures.otherItem))
        #expect(log.calls.load(ordering: .relaxed) == 1)
        guard case .some(.some(.judged(let a))) = Self.sounds(first), case .some(.some(.judged(let b))) = Self.sounds(second)
        else { Issue.record("expected judged twice"); return }
        // Same sounds, each placed on its own voice's timeline.
        #expect(a.words.map(\.state) == b.words.map(\.state))
        #expect(a.words.map(\.modelRange) != b.words.map(\.modelRange))
    }

    @Test("an analyzer without a judge leaves sounds nil")
    func noJudge() async throws {
        let world = try await PipelineFixtures.world()
        let run = await Self.run(try Self.analyzer(world, sounds: nil), world)
        #expect(Self.sounds(run) == .some(nil))
    }

    @Test("a result saved before sound judging decodes with sounds nil, and nil is omitted from JSON")
    func oldResultDecodes() throws {
        let data = try Data(contentsOf: AnalyzerTests.golden)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"sounds\""))
        let result = try CanonicalJSON.decoder().decode(AnalysisResult.self, from: data)
        #expect(result.sounds == nil)
        let encoded = try CanonicalJSON.encode(result)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("\"sounds\""))
        let judged = result.with(sounds: .unavailable(.modelNotInstalled))
        let back = try CanonicalJSON.decoder().decode(AnalysisResult.self, from: try CanonicalJSON.encode(judged))
        #expect(back.sounds == .unavailable(.modelNotInstalled))
        #expect(back.identity == result.identity && back.verdict == result.verdict && back.takeID == result.takeID)
    }
}

@MainActor @Suite("Sound judging through the coordinator") struct SoundJudgingCoordinatorTests {
    @Test("the coordinator publishes and saves the judged result")
    func coordinatorSavesSounds() async throws {
        let world = try await PipelineFixtures.world()
        let host = SoundJudgeHost(ready: { _, words in SoundJudgingPipelineTests.judgement(words) })
        let store = FakeTakeStore()
        let coordinator = AnalysisCoordinator(
            analyzer: try SoundJudgingPipelineTests.analyzer(world, sounds: host), reference: world.reference,
            store: store)
        let request = coordinator.submit(CoordinatorTests.submission(world))
        let events = await CoordinatorTests.next(3, of: coordinator)
        guard case .response(let response) = events[0], case .analysed(let result) = response.outcome,
            case .judged? = result.sounds
        else { Issue.record("expected a judged response first: \(events)"); return }
        #expect(events[2] == .persistence(request.id, .saved(result.takeID)))
        let saved = try #require(await store.saved.first?.derived.first { $0.level == .l2 })
        guard case .analysed(let stored) = try JSONDecoder().decode(L2Analysis.self, from: saved.bytes).outcome else {
            Issue.record("stored L2 not analysed"); return
        }
        #expect(stored.sounds == result.sounds)
    }

    @Test("invalidating the request cancels its judge; nothing stale is published", .timeLimit(.minutes(2)))
    func invalidateCancelsJudge() async throws {
        let world = try await PipelineFixtures.world()
        let log = SoundJudgingPipelineTests.JudgeLog()
        let host = SoundJudgeHost(ready: { _, words in
            do { try await Task.sleep(for: .seconds(60)) } catch {
                log.cancelled.store(true, ordering: .sequentiallyConsistent)
                throw error
            }
            return SoundJudgingPipelineTests.judgement(words)
        })
        let coordinator = AnalysisCoordinator(
            analyzer: try SoundJudgingPipelineTests.analyzer(world, sounds: host), reference: world.reference,
            store: FakeTakeStore())
        coordinator.submit(CoordinatorTests.submission(world))
        try await Task.sleep(for: .milliseconds(300))
        coordinator.invalidate(.newRecordingStarted)
        await coordinator.settle()
        #expect(coordinator.staleDropped == 1)
        while !log.cancelled.load(ordering: .sequentiallyConsistent) { await Task.yield() }
    }
}
