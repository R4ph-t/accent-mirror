import AMAlignment
import AMCapture
import AMCore
import AMLibrary
import AMPipeline
import Foundation
import Synchronization
import Testing

// Spec 21's unit tests: the live flow on the bundled starter library with `FileCaptureSource` and replayed word
// timings. No microphone, no ASR, no window, no network.

private let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let starterFolder = repo.appending(path: "Resources/Starter", directoryHint: .isDirectory)

/// Replays a native recording's recorded words for whatever take it's given, shifted onto the captured audio (the
/// capture keeps from just before the first onset to the end of the file).
private struct ReplayedTimestamper: WordTimestamper {
    let asrModelID: String
    let words: [WordTimestamp]
    let originalCount: Int

    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] {
        try Task.checkCancellation()
        let shift = Double(max(0, originalCount - request.samples.count)) / 16_000
        return words.map { WordTimestamp(word: $0.word, start: max(0, $0.start - shift), end: max(0, $0.end - shift),
                                         probability: $0.probability) }
    }
}

/// A live session on the bundled library, a fresh take store, and a file "microphone".
@MainActor
private struct World {
    let session: LiveSession
    let analyzer: Analyzer
    let store: TakeStore
    let starter: StarterManifest
    let announcements: AnnouncementLog
    let root: URL

    /// `take`: the samples the file source plays. Default: a second native reader of the first Stress Shifts phrase
    /// (a real, clean take of the right words).
    static func make(
        take: [Float]? = nil, pacing: FileCaptureSource.Pacing = .immediate, capture: FileCaptureSource? = nil
    ) throws -> World {
        let root = FileManager.default.temporaryDirectory.appending(path: "am-live-\(UUID().uuidString)")
        let configuration = try Analyzer.Configuration.shipped()
        let (library, references) = try ReferenceLibrary.bundled(
            folder: starterFolder, caches: root.appending(path: "caches"), configuration: configuration)
        let starter = library.manifest
        let phraseID = try #require(LivePresenter.firstPhrase(starter))
        let phrase = try #require(starter.phrase(phraseID))
        let reader = try #require(phrase.recordings.first { $0.id != phrase.headlineVoice })
        let readerAudio = try StarterReferences.decode16k(starterFolder.appending(path: reader.audio))
        let timings = try JSONDecoder().decode(
            RecordedTimestamps.self, from: Data(contentsOf: starterFolder.appending(path: reader.timings)))
        let speech = SpeechModelHost(ready: ReplayedTimestamper(
            asrModelID: starter.asrModelID, words: timings.words, originalCount: readerAudio.count))
        let analyzer = Analyzer(speech: speech, configuration: configuration)
        let store = TakeStore(
            root: root.appending(path: "takes"),
            recomputer: .pipeline(analyzer: analyzer, reference: library, phrase: { references.phraseInput($0) }))
        let coordinator = AnalysisCoordinator(analyzer: analyzer, reference: library, store: store)
        let defaults = try #require(UserDefaults(suiteName: "am-live-\(UUID().uuidString)"))
        let session = LiveSession(services: .init(
            coordinator: coordinator, store: store,
            capture: capture ?? FileCaptureSource(samples: take ?? readerAudio, pacing: pacing), references: references,
            starter: starter, starterFolder: starterFolder, defaults: defaults))
        let log = AnnouncementLog()
        session.announce = { log.append($0) }
        return World(session: session, analyzer: analyzer, store: store, starter: starter, announcements: log,
                     root: root)
    }

    /// Waits (up to `seconds`) for `condition`.
    func until(_ seconds: Double = 60, _ condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    var result: AnalysisResult? {
        if case .result(let result, _) = session.screen.shown { result } else { nil }
    }
}

@MainActor
private final class AnnouncementLog {
    private(set) var items: [LiveAnnouncement] = []
    func append(_ item: LiveAnnouncement) { items.append(item) }
}

// MARK: - Presenter and drift (spec 01's table, mapped in one place)

@Suite("Live presenter") @MainActor
struct LivePresenterTests {
    @Test func takeProblemsMapOneToOne() {
        for problem in AMCore.TakeProblem.allCases {
            #expect(LivePresenter.takeProblem(problem).rawValue == problem.rawValue)
        }
    }

    @Test func everyStageHasCopyWords() {
        let expected: [Stage: OperationalError.Stage] = [
            .decodeAudio: .findingWords, .recogniseWords: .findingWords, .alignWords: .findingWords,
            .trackPitch: .measuringPitch, .detectVoicing: .measuringPitch,
            .segmentSyllables: .measuringStress, .measureStress: .measuringStress,
            .mapTime: .comparing, .compare: .comparing,
        ]
        for stage in Stage.allCases { #expect(LivePresenter.stage(stage) == expected[stage], "\(stage)") }
    }

    @Test func operationalErrorsAndPersistence() {
        #expect(LivePresenter.operationalError(.audioUnreadable).source == "take")
        #expect(LivePresenter.operationalError(.modelUnavailable(.notInstalled)).kind == .modelUnavailable)
        #expect(LivePresenter.operationalError(.inferenceFailed(stage: .trackPitch)).stage == .measuringPitch)
        #expect(LivePresenter.operationalError(.referenceCacheCorrupt(RecordingID("p225"))).kind == .referenceCacheCorrupt)
        let take = TakeID("take-1")
        #expect(LivePresenter.persistence(.pending) == nil)
        #expect(LivePresenter.persistence(.saved(take)) == .saved)
        #expect(LivePresenter.persistence(.notSaved(.takeProblem)) == .notSaved)
        #expect(LivePresenter.persistence(.saveFailed(.diskFull)) == .saveFailed)
        #expect(LivePresenter.persistence(.savedPruneFailed(take, .diskFull)) == .savedPruneFailed)
        #expect(LivePresenter.timing(.good) == .good)
        #expect(LivePresenter.timing(.rough) == .rough)
        #expect(LivePresenter.timing(.poor) == .rough)
    }

    @Test func libraryVoicesAndSubtitle() throws {
        let starter = try StarterManifest.load(from: starterFolder)
        let manifest = LivePresenter.manifest(starter)
        #expect(manifest.packs.map(\.title) == starter.packs.map(\.title))
        #expect(!manifest.packs.contains { $0.title.lowercased() == "my phrases" })
        let first = try #require(LivePresenter.firstPhrase(starter))
        #expect(starter.packs.first { $0.title == "Stress Shifts" }?.phrases.first == first)
        let phrase = try #require(starter.phrase(first))
        let recording = try #require(phrase.recording(phrase.headlineVoice))
        #expect(LivePresenter.voiceRow(recording) == "\(recording.region) (\(recording.accent))")
        #expect(LivePresenter.voiceTag(recording).hasPrefix(recording.speaker + " \u{00B7} "))
        #expect(LivePresenter.voiceTitle(recording) == "\(recording.region) \u{00B7} \(recording.speaker)")
        let live = LivePhrase(phrase: phrase, packTitle: "Stress Shifts", voice: phrase.headlineVoice)
        #expect(LivePresenter.subtitle(live) == "Stress Shifts \u{00B7} Native speaker from \(recording.region), VCTK")
    }

    @Test func analysedTakeMapsOntoTheFixtureShapes() async throws {
        let world = try World.make()
        await world.session.start()
        await world.session.recordOrStop()
        #expect(await world.until { world.result != nil })
        let result = try #require(world.result)
        let manifest = LivePresenter.manifest(world.starter)
        let loaded = LivePresenter.loaded(world.session.live, screen: world.session.screen, manifest: manifest)
        #expect(loaded.fixture.phase == .showingTake)
        #expect(loaded.fixture.analysis?.verdict?.kind == .notScored)
        #expect(loaded.fixture.analysis?.takeProblems == nil)
        #expect(loaded.phrase.words.count == result.model.words.count)
        var fractions: [Double] = []
        for word in loaded.phrase.words {
            fractions += [word.start, word.end]
            for syllable in word.syllables { fractions += [syllable.start, syllable.end] }
        }
        let yourSyllables: [Syllable] = loaded.take?.words.flatMap(\.syllables) ?? []
        for syllable in yourSyllables { fractions += [syllable.start, syllable.end] }
        let bandPoints: [BandPoint] = loaded.phrase.band.flatMap(\.points)
        fractions += bandPoints.map(\.t)
        let pitchPoints: [PitchPoint] = loaded.take?.pitch.flatMap(\.points) ?? []
        fractions += pitchPoints.map(\.t)
        #expect(!yourSyllables.isEmpty)
        #expect(fractions.allSatisfy { (0...1).contains($0) })
        #expect(loaded.take?.words.count == result.alignment.pairs.count)
        #expect(loaded.fixture.analysis?.describe?.native.voices == result.describe?.native.voices)
        #expect(loaded.liveSeconds?.model == result.modelAxis.end - result.modelAxis.start)
        #expect(loaded.fixture.modelRecording?.voices.count == world.session.live.phrase.recordings.count)
        #expect(world.announcements.items.contains(.resultReady))
    }
}

// MARK: - Before the first take (addendum v3.2 W1)

@Suite("Native before the first take", .serialized) @MainActor
struct NativeBeforeFirstTakeTests {
    /// The live state with the native display loaded.
    private func loaded(_ world: World) -> LoadedFixture {
        LivePresenter.loaded(world.session.live, screen: world.session.screen,
                             manifest: LivePresenter.manifest(world.starter))
    }

    /// The native words as the strip draws them: text, spans, syllables and dictionary stress.
    private func signature(_ phrase: PhraseFixture) -> [String] {
        phrase.words.map { word in
            "\(word.text) \(word.start) \(word.end) \(word.expectedStress ?? []) "
                + word.syllables.map { "\($0.text)@\($0.start)-\($0.end):\($0.prominence)" }.joined(separator: ",")
        }
    }

    @Test func preTakeShowsTheNativeModel() async throws {
        let world = try World.make()
        await world.session.start()
        await world.session.nativeLoad?.value
        let native = try #require(world.session.screen.native)
        #expect(native.recordingID == world.session.live.voice)
        let state = loaded(world)

        #expect(state.fixture.phase == .empty)
        #expect(state.take == nil)
        #expect(state.earlierTakes.isEmpty)
        // Words come from the recording, not spread evenly; every word has syllables; some have dictionary stress.
        let words = state.phrase.words
        #expect(words.count == native.model.words.count)
        let step = 1 / Double(words.count)
        let even = words.indices.allSatisfy { abs(words[$0].start - Double($0) * step) < 1e-9 }
        #expect(!even)
        #expect(words.allSatisfy { !$0.syllables.isEmpty })
        #expect(words.contains { $0.expectedStress?.contains(.primary) == true })
        #expect(words.flatMap(\.syllables).contains { $0.prominence > 0 })
        #expect(!state.phrase.band.isEmpty)
        #expect(state.phrase.band.flatMap(\.points).allSatisfy { (0...1).contains($0.t) })
        // Nothing of yours: no take (so the strip's You row is the placeholder, no connectors, no You line),
        // nothing saved (the take menu reads TAKES), and the inspector's You column is empty with the native range.
        #expect(state.fixture.savedTakes.isEmpty)
        let analysis = try #require(state.fixture.analysis)
        #expect(analysis.takeProblems == nil)
        #expect(analysis.timing == nil)
        let describe = try #require(analysis.describe)
        #expect(describe.you.lengthSeconds.value == nil && describe.you.rhythmNPVI.value == nil)
        #expect(describe.you.endingDirection == nil)
        #expect(describe.native.voices == world.session.live.phrase.recordings.count)
        #expect(describe.native.lengthSeconds.min != nil && describe.native.lengthSeconds.max != nil)
        // Model plays the phrase window the charts draw.
        #expect(state.liveSeconds?.model == native.modelAxis.end - native.modelAxis.start)
        #expect(world.session.modelClip().seconds == native.modelAxis.end - native.modelAxis.start)
    }

    @Test func recordingKeepsTheNativeCharts() async throws {
        let world = try World.make(pacing: .manual)
        await world.session.start()
        await world.session.nativeLoad?.value
        let before = signature(loaded(world).phrase)
        let take = Task { await world.session.recordOrStop() }
        #expect(await world.until(5) { world.session.isRecording })
        let recording = loaded(world)
        #expect(recording.fixture.phase == .recording)
        #expect(signature(recording.phrase) == before)
        #expect(!recording.phrase.band.isEmpty)
        #expect(world.session.cancel())
        await take.value
        #expect(signature(loaded(world).phrase) == before)
    }

    @Test func aTakeProblemKeepsTheNativeCharts() async throws {
        let world = try World.make(take: [Float](repeating: 0, count: 32_000))
        await world.session.start()
        await world.session.nativeLoad?.value
        let before = signature(loaded(world).phrase)
        await world.session.recordOrStop()
        #expect(await world.until { if case .takeProblem = world.session.screen.shown { true } else { false } })
        let state = loaded(world)
        #expect(state.fixture.analysis?.takeProblems?.isEmpty == false)
        #expect(signature(state.phrase) == before)
        #expect(!state.phrase.band.isEmpty)
    }

    @Test func aVoiceSwitchReloadsTheNativeDisplay() async throws {
        let world = try World.make()
        await world.session.start()
        await world.session.nativeLoad?.value
        let other = try #require(world.session.live.phrase.recordings.first { $0.id != world.session.live.voice }?.id)
        await world.session.select(voice: other)
        await world.session.nativeLoad?.value
        #expect(world.session.screen.native?.recordingID == other)
        #expect(!loaded(world).phrase.band.isEmpty)
    }
}

// MARK: - Takes

@Suite("Live takes", .serialized) @MainActor
struct LiveTakeTests {
    @Test func anAnalysedTakeIsSavedAndNumbered() async throws {
        let world = try World.make()
        await world.session.start()
        await world.session.recordOrStop()
        #expect(await world.until { world.session.screen.savedTakes == [1] })
        let phrase = world.session.live.phrase.id
        #expect(await world.store.takes(for: phrase).map(\.number) == [1])
        if case .result(_, let number) = world.session.screen.shown { #expect(number == 1) } else { Issue.record("no result") }
        #expect(world.announcements.items.prefix(2) == [.recording, .analysing])
    }

    @Test func aTakeProblemIsNeverSaved() async throws {
        // 2 s of silence: no speech, so a take problem; nothing reaches the store.
        let world = try World.make(take: [Float](repeating: 0, count: 32_000))
        await world.session.start()
        await world.session.recordOrStop()
        #expect(await world.until { if case .takeProblem = world.session.screen.shown { true } else { false } })
        #expect(world.session.screen.persistence == .notSaved(.takeProblem))
        await world.session.services.coordinator.settle()
        #expect(await world.store.takes(for: world.session.live.phrase.id).isEmpty)
        #expect(world.session.screen.savedTakes.isEmpty)
    }

    @Test func escCancelsARecordingAndKeepsNothing() async throws {
        let world = try World.make(pacing: .manual)
        await world.session.start()
        let take = Task { await world.session.recordOrStop() }
        #expect(await world.until(5) { world.session.isRecording })
        #expect(world.session.cancel())
        await take.value
        #expect(!world.session.isRecording)
        #expect(world.session.screen.phase == .empty)
        #expect(world.session.screen.shown.isNothing)
        #expect(world.announcements.items.contains(.recordingCancelled))
        await world.session.services.coordinator.settle()
        #expect(await world.store.takes(for: world.session.live.phrase.id).isEmpty)
    }

    @Test func switchingPhraseWhileRecordingCancelsTheTake() async throws {
        let world = try World.make(pacing: .manual)
        await world.session.start()
        let first = world.session.live.phrase.id
        let take = Task { await world.session.recordOrStop() }
        #expect(await world.until(5) { world.session.isRecording })
        let other = try #require(world.session.phraseOrder.first { $0 != first })
        await world.session.select(phrase: other)
        await take.value
        #expect(!world.session.isRecording)
        #expect(world.session.live.phrase.id == other)
        #expect(world.session.screen.phase == .empty)
        #expect(world.announcements.items.contains(.recordingCancelled))
        await world.session.services.coordinator.settle()
        #expect(await world.store.takes(for: first).isEmpty)
    }

    @Test func escDuringAnalysisDropsTheResponse() async throws {
        let world = try World.make()
        await world.session.start()
        await world.session.recordOrStop()
        // The take has ended and its request is in flight.
        #expect(world.session.isAnalysing)
        #expect(world.session.cancel())
        await world.session.services.coordinator.settle()
        try await Task.sleep(for: .milliseconds(100))
        #expect(world.session.screen.shown.isNothing)
        #expect(await world.store.takes(for: world.session.live.phrase.id).isEmpty)
    }

    @Test func aVoiceSwitchRecomputesL2Only() async throws {
        let world = try World.make()
        await world.session.start()
        await world.session.recordOrStop()
        #expect(await world.until { world.session.screen.savedTakes == [1] && world.session.shownTake != nil })
        let before = await world.analyzer.statistics
        let other = try #require(world.session.live.phrase.recordings.first { $0.id != world.session.live.voice }?.id)
        await world.session.select(voice: other)
        #expect(await world.until { world.result?.identity.reference.recordingID == other })
        let after = await world.analyzer.statistics
        #expect(after.l0Computed == before.l0Computed)
        #expect(after.l1Computed == before.l1Computed)
        #expect(after.l2Computed == before.l2Computed + 1)
        #expect(world.session.live.voice == other)
        // Remembered per phrase.
        #expect(world.session.services.defaults.string(forKey: LiveSession.voiceKey(world.session.live.phrase.id))
            == other.rawValue)
    }

    @Test func theVoicePopUpCantSwitchWhileRecording() async throws {
        let world = try World.make(pacing: .manual)
        await world.session.start()
        let voice = world.session.live.voice
        let take = Task { await world.session.recordOrStop() }
        #expect(await world.until(5) { world.session.isRecording })
        let other = try #require(world.session.live.phrase.recordings.first { $0.id != voice }?.id)
        await world.session.select(voice: other)
        #expect(world.session.live.voice == voice)
        world.session.cancel()
        await take.value
    }

    @Test func deviceLostWithAnotherMicSurfacesAudioUnreadableBanner() async throws {
        let builtIn = InputDevice(id: "built-in", name: "Built-in Mic", isDefault: true)
        let usb = InputDevice(id: "usb", name: "USB Mic", isDefault: false)
        let capture = FileCaptureSource(
            samples: [Float](repeating: 0, count: 64_000), pacing: .manual, devices: [builtIn, usb])
        let world = try World.make(capture: capture)
        world.session.inputDevice = usb.id
        await world.session.start()

        let take = Task { await world.session.recordOrStop() }
        #expect(await world.until(5) { world.session.isRecording })
        capture.setDevices([builtIn])
        await take.value

        #expect(!world.session.isRecording)
        #expect(world.session.screen.operationalError == .audioUnreadable)
        let loaded = LivePresenter.loaded(
            world.session.live, screen: world.session.screen, manifest: LivePresenter.manifest(world.starter))
        #expect(loaded.fixture.operationalError?.kind == .audioUnreadable)
        #expect(loaded.fixture.operationalError?.source == "take")
    }

    @Test func deviceLostWithNoMicLeftSurfacesNoMicrophoneProblem() async throws {
        let builtIn = InputDevice(id: "built-in", name: "Built-in Mic", isDefault: true)
        let capture = FileCaptureSource(
            samples: [Float](repeating: 0, count: 64_000), pacing: .manual, devices: [builtIn])
        let world = try World.make(capture: capture)
        await world.session.start()

        let take = Task { await world.session.recordOrStop() }
        #expect(await world.until(5) { world.session.isRecording })
        capture.setDevices([])
        await take.value

        #expect(!world.session.isRecording)
        if case .takeProblem(.noMicrophone, hasAudio: false) = world.session.screen.shown {} else {
            Issue.record("expected noMicrophone takeProblem")
        }
        #expect(world.session.screen.operationalError == nil)
        #expect(world.announcements.items.contains(.takeProblem(.noMicrophone)))
        let loaded = LivePresenter.loaded(
            world.session.live, screen: world.session.screen, manifest: LivePresenter.manifest(world.starter))
        #expect(loaded.fixture.phase == .showingTake)
        #expect(loaded.fixture.analysis?.takeProblems == [.noMicrophone])
    }
}

// MARK: - Playback (Play Both on an injected clock)

@Suite("Live playback")
struct LivePlaybackTests {
    @Test func playBothRendersModelPauseThenYou() {
        let model = AudioClip(samples: [Float](repeating: 0.5, count: 16_000))
        let you = AudioClip(samples: [Float](repeating: -0.5, count: 8_000))
        let schedule = PlaybackSchedule.both(model: model.seconds, you: you.seconds)
        let samples = AudioPlayback.render(schedule, model: model, you: you)
        #expect(samples.count == 16_000 + 6_400 + 8_000)
        #expect(samples[..<16_000].allSatisfy { $0 == 0.5 })
        #expect(samples[16_000..<22_400].allSatisfy { $0 == 0 })
        #expect(samples[22_400...].allSatisfy { $0 == -0.5 })

        // The playhead follows the same sequence on an injected clock.
        let clock = FrozenPlaybackClock(now: 0)
        let run = PlaybackRun(schedule, clock: clock)
        clock.now = 0.5
        #expect(run.phase == .playing(.model, progress: 0.5))
        clock.now = 1.2
        #expect(run.phase == .pause)
        clock.now = 1.65
        if case .playing(.you, let progress) = run.phase { #expect(abs(progress - 0.5) < 1e-9) } else { Issue.record("not you") }
        clock.now = 2.0
        #expect(run.phase == .finished)
    }

    @Test func aWordLoopPlaysTheSlicesOfEachClipWindow() {
        // Your clip's window is 1…2 s of its samples; the loop plays its second half.
        var samples = [Float](repeating: 0, count: 48_000)
        for i in 24_000..<32_000 { samples[i] = 1 }
        let you = AudioClip(samples: samples, start: 1, end: 2)
        let model = AudioClip(samples: [Float](repeating: 0.25, count: 16_000))
        let schedule = PlaybackSchedule.loop(model: (from: 0, to: 0.5, seconds: 0.5), you: (from: 0.5, to: 1, seconds: 0.5))
        let out = AudioPlayback.render(schedule, model: model, you: you)
        #expect(schedule.repeats)
        #expect(out.count == 8_000 + 6_400 + 8_000 + 6_400)
        #expect(out[..<8_000].allSatisfy { $0 == 0.25 })
        #expect(out[14_400..<22_400].allSatisfy { $0 == 1 })
    }

    @Test func aMissingSideIsSilence() {
        let model = AudioClip(samples: [Float](repeating: 0.5, count: 1_600))
        let out = AudioPlayback.render(.you(0.1), model: model, you: nil)
        #expect(out.count == 1_600)
        #expect(out.allSatisfy { $0 == 0 })
    }

    @Test func aFullPlayReachesTheTrueAudioEndPastLastWordEvenBeyond300ms() {
        // Analysis window is 0…0.7 s of a 1.5 s clip (0.8 s tail > old 300 ms cap); the tail holds a distinct marker.
        var samples = [Float](repeating: 0.5, count: 24_000)
        for i in 11_200..<24_000 { samples[i] = 0.25 }
        let model = AudioClip(samples: samples, start: 0, end: 0.7)
        #expect(abs(model.tailSeconds - 0.8) < 1e-9)
        #expect(abs(model.playbackEnd - 1.5) < 1e-9)

        let schedule = PlaybackSchedule.model(model.seconds).applyingTail(model: model, you: nil)
        #expect(schedule.steps.count == 2)
        guard case .play(.model, let body, let from, let to) = schedule.steps[0] else { Issue.record("missing body"); return }
        #expect(abs(body - 0.7) < 1e-9 && from == 0 && to == 1)
        guard case .play(.model, let tail, let tailFrom, let tailTo) = schedule.steps[1] else { Issue.record("missing tail"); return }
        #expect(abs(tail - 0.8) < 1e-9 && tailFrom == 1 && tailTo == 1)
        let out = AudioPlayback.render(schedule, model: model, you: nil)
        #expect(out.count == 24_000)
        #expect(out[..<11_200].allSatisfy { $0 == 0.5 })
        #expect(out[11_200...].allSatisfy { $0 == 0.25 })

        let clock = FrozenPlaybackClock(now: 0)
        let run = PlaybackRun(schedule, clock: clock)
        clock.now = 0.7
        #expect(run.phase == .playing(.model, progress: 1))
        clock.now = 1.1
        #expect(run.phase == .playing(.model, progress: 1))
        clock.now = 1.5
        #expect(run.phase == .finished)
    }

    @Test func playYouAndPlayBothPlayToTrueEndOnBothSides() {
        var modelSamples = [Float](repeating: 0.5, count: 24_000) // 1.5 s
        for i in 11_200..<24_000 { modelSamples[i] = 0.25 }       // end=0.7 s, tail=0.8 s
        var youSamples = [Float](repeating: -0.5, count: 20_800) // 1.3 s
        for i in 14_400..<20_800 { youSamples[i] = -0.25 }       // end=0.9 s, tail=0.4 s
        let model = AudioClip(samples: modelSamples, start: 0, end: 0.7)
        let you = AudioClip(samples: youSamples, start: 0, end: 0.9)

        let youSchedule = PlaybackSchedule.you(you.seconds).applyingTail(model: model, you: you)
        let youOut = AudioPlayback.render(youSchedule, model: model, you: you)
        #expect(youOut.count == 20_800)
        #expect(youOut[..<14_400].allSatisfy { $0 == -0.5 })
        #expect(youOut[14_400...].allSatisfy { $0 == -0.25 })

        let bothSchedule = PlaybackSchedule.both(model: model.seconds, you: you.seconds).applyingTail(model: model, you: you)
        let bothOut = AudioPlayback.render(bothSchedule, model: model, you: you)
        #expect(bothOut.count == 24_000 + 6_400 + 20_800)
        #expect(bothOut[11_200..<24_000].allSatisfy { $0 == 0.25 })
        #expect(bothOut[24_000..<30_400].allSatisfy { $0 == 0 })
        #expect(bothOut[(24_000 + 6_400 + 14_400)...].allSatisfy { $0 == -0.25 })
    }

    @Test func noTailWhenTheWindowAlreadyRunsToTheClipEnd() {
        let model = AudioClip(samples: [Float](repeating: 0.5, count: 16_000))
        #expect(model.tailSeconds == 0)
        let schedule = PlaybackSchedule.model(model.seconds).applyingTail(model: model, you: nil)
        #expect(schedule.steps == [.play(.model, seconds: 1)])
        #expect(AudioPlayback.render(schedule, model: model, you: nil).count == 16_000)
    }

    @Test func aLastWordLoopAlsoPlaysToTheTrueEndAndEarlierWordsDoNot() {
        var samples = [Float](repeating: 0.5, count: 24_000)
        for i in 11_200..<24_000 { samples[i] = 0.25 }
        let model = AudioClip(samples: samples, start: 0, end: 0.7)
        let last = PlaybackSchedule.loopModel((from: 0.5, to: 1, seconds: 0.35)).applyingTail(model: model, you: nil)
        let lastOut = AudioPlayback.render(last, model: model, you: nil)
        #expect(last.steps.contains { step in
            if case .play(.model, let seconds, let from, let to) = step { return from == 1 && to == 1 && abs(seconds - 0.8) < 1e-9 }
            return false
        })
        #expect(lastOut.suffix(12_800).allSatisfy { $0 == 0.25 })

        let earlier = PlaybackSchedule.loopModel((from: 0, to: 0.5, seconds: 0.35)).applyingTail(model: model, you: nil)
        #expect(earlier.steps.count == 1)
        let earlierOut = AudioPlayback.render(earlier, model: model, you: nil)
        #expect(earlierOut.count == 5_600)
        #expect(earlierOut.allSatisfy { $0 == 0.5 })
    }

    @Test("Every bundled p311 starter recording plays through the true end of its FLAC")
    func everyStarterModelPlaysToTrueEndOfFLAC() async throws {
        let caches = FileManager.default.temporaryDirectory.appending(path: "am-tail-starter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: caches) }
        let (library, references) = try ReferenceLibrary.bundled(
            folder: starterFolder, caches: caches, configuration: try .shipped())

        for phrase in library.manifest.phrases {
            let input = try #require(references.phraseInput(phrase.id))
            let display = try await NativeView.load(phrase: input, voice: phrase.headlineVoice, reference: library)
            let recording = try #require(phrase.recording(phrase.headlineVoice))
            let samples = try StarterReferences.decode16k(starterFolder.appending(path: recording.audio))
            let clip = AudioClip(samples: samples, start: display.modelAxis.start, end: display.modelAxis.end)
            #expect(clip.duration >= display.modelAxis.end, "\(phrase.id)")

            let schedule = PlaybackSchedule.model(clip.seconds).applyingTail(model: clip, you: nil)
            let rendered = AudioPlayback.render(schedule, model: clip, you: nil)
            let startSample = max(0, min(samples.count, Int((clip.start * AudioClip.sampleRate).rounded())))
            #expect(abs(rendered.count - (samples.count - startSample)) <= 1, "\(phrase.id)")
            if let expectedLast = samples.last, let renderedLast = rendered.last {
                #expect(renderedLast == expectedLast, "\(phrase.id) final sample mismatch")
            }
        }
    }

    @Test("AppModel and ShellModel wire adjustPlayback so live playback keeps the tail")
    func appModelWiresAdjustPlaybackToTrueEnd() throws {
        let appModel = try String(contentsOf: repo.appending(path: "AccentMirror/Live/AppModel.swift"), encoding: .utf8)
        let shellModel = try String(contentsOf: repo.appending(path: "AccentMirror/Shell/ShellModel.swift"), encoding: .utf8)
        #expect(appModel.contains("shell.adjustPlayback"))
        #expect(appModel.contains("applyingTail(model: session.modelClip(), you: session.youClip)"))
        #expect(shellModel.contains("let schedule = adjustPlayback?(schedule) ?? schedule"))
    }
}

// MARK: - Menus and keyboard (v1 §10)

@Suite("Menu table")
struct MenuTableTests {
    @Test func everyShortcutTheSpecNames() {
        let expected: [MenuCommand.Action: (MenuCommand.Menu, String, Set<MenuCommand.Modifier>)] = [
            .record: (.take, "r", [.command]),
            .cancel: (.take, "escape", []),
            .playModel: (.take, "l", [.command]),
            .playYou: (.take, "l", [.shift, .command]),
            .playBoth: (.take, "l", [.option, .command]),
            .previousTake: (.take, "[", [.command]),
            .nextTake: (.take, "]", [.command]),
            .previousPhrase: (.view, "up", [.option, .command]),
            .nextPhrase: (.view, "down", [.option, .command]),
            .showDetails: (.view, "i", [.option, .command]),
            .showSidebar: (.view, "s", [.control, .command]),
            .showEarlierTakes: (.view, "g", [.shift, .command]),
            .find: (.edit, "f", [.command]),
        ]
        #expect(MenuTable.commands.count == MenuCommand.Action.allCases.count)
        for command in MenuTable.commands {
            let want = expected[command.action]
            #expect(want?.0 == command.menu, "\(command.action)")
            #expect(want?.1 == command.key, "\(command.action)")
            #expect(want?.2 == command.modifiers, "\(command.action)")
        }
        #expect(MenuTable.recordAlsoOnSpace)
    }

    @Test func noTwoItemsShareAShortcutAndNoNumberKeys() {
        let keys = MenuTable.commands.map { "\($0.key)|\($0.modifiers.map(\.rawValue).sorted())" }
        #expect(Set(keys).count == keys.count)
        #expect(!MenuTable.commands.contains { $0.key.first?.isNumber == true })
    }
}

// MARK: - No network (the app adds no URL session)

@Suite("App no network")
struct AppNoNetworkTests {
    @Test func noAppSourceOpensAConnection() throws {
        let app = repo.appending(path: "AccentMirror")
        let enumerator = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 20)
        let banned = ["URLSession", "URLRequest", "NWConnection", "import Network", "CFNetwork", "WebSocket",
                      "dataTask(", "download:"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in banned { #expect(!text.contains(token), "\(file.lastPathComponent) uses \(token)") }
        }
    }

    @Test func theModelIsReadFromTheBundleOnly() throws {
        let text = try String(contentsOf: repo.appending(path: "AccentMirror/Live/AppModel.swift"), encoding: .utf8)
        #expect(text.contains("resources.appending(path: \"Models/"))
        #expect(!text.contains(".cache/models"))
        #expect(!text.contains("MODELS_CACHE"))
    }
}
