import AMCapture
import AMCore
import AMLibrary
import AMPipeline
import Foundation
import os

/// One take's audio window, for playback: 16 kHz mono samples and the stretch the timeline covers (seconds).
struct AudioClip: Sendable {
    var samples: [Float]
    var start: Double
    var end: Double

    var seconds: Double { max(0, end - start) }

    static let sampleRate = TakeAudio.sampleRate

    init(samples: [Float], start: Double = 0, end: Double? = nil) {
        self.samples = samples
        self.start = max(0, start)
        self.end = end ?? Double(samples.count) / Self.sampleRate
    }
}

/// Spec 21's live flow, UI-free: the phrase and voice, the take being recorded, the coordinator's answers and the
/// take store. `AppModel` draws `screen` through `LivePresenter`; the unit tests drive this class with
/// `FileCaptureSource` and replayed word timings (no microphone, no ASR, no window).
@MainActor
final class LiveSession {
    struct Services {
        var coordinator: AnalysisCoordinator
        var store: TakeStore
        var capture: any CaptureSource
        var references: StarterReferences
        var starter: StarterManifest
        /// The bundled starter folder (`Contents/Resources/Starter`), for the native recordings' audio.
        var starterFolder: URL
        var defaults: UserDefaults = .standard
    }

    let services: Services
    private(set) var live: LivePhrase
    private(set) var screen = LiveScreen()
    /// Called after every change of `screen` or `live`.
    var onChange: (@MainActor () -> Void)?
    /// Called with each batch of 10 ms envelope values while recording (the live strip, spec 20).
    var onEnvelope: (@MainActor ([Double]) -> Void)?
    /// Called with each 10 ms level while recording (E5's meter).
    var onLevel: (@MainActor (InputLevel) -> Void)?
    /// Called once with what VoiceOver says ("Recording", "Analysing", "Recording cancelled", …).
    var announce: (@MainActor (LiveAnnouncement) -> Void)?

    /// The envelope recorded so far in this take (RMS, 0…1, one per 10 ms).
    private(set) var envelope: [Double] = []
    /// Your audio on screen (the analysed take or the unsaved last try); nil when You has nothing to play.
    private(set) var youClip: AudioClip?
    /// The saved take on screen, if any.
    private(set) var shownTake: StoredTake?
    private(set) var savedTakes: [StoredTake] = []
    var isRecording: Bool { capture != nil }
    var isAnalysing: Bool { pending != nil }

    private var capture: CaptureSession?
    private var captureTasks: [Task<Void, Never>] = []
    private var takeGeneration = 0
    /// The request in flight and the audio it analyses.
    private var pending: (request: RequestID, audio: TakeAudio)?
    /// The last analysed request (its persistence updates follow its response) and its audio.
    private var analysed: (request: RequestID, audio: TakeAudio)?
    /// What was on screen when the take started: Esc, a cancelled take and a phrase switch go back to it.
    private var beforeTake: (screen: LiveScreen, you: AudioClip?, shown: StoredTake?)?
    private var lastFloorDBFS: Double?
    private var events: Task<Void, Never>?
    private var modelAudio: [RecordingID: [Float]] = [:]
    /// The input device for the next take (the Input pop-up); nil follows the system default.
    var inputDevice: InputDevice.ID? {
        didSet { services.defaults.set(inputDevice, forKey: Self.inputKey) }
    }

    static let analysingDelay: Duration = .milliseconds(400)
    static let inputKey = "InputDevice"
    static let log = Logger(subsystem: "AccentMirror", category: "Live")

    init(services: Services, modelUnavailable: ModelFailure? = nil) {
        self.services = services
        let first = LivePresenter.firstPhrase(services.starter) ?? services.starter.phrases[0].id
        let phrase = services.starter.phrase(first) ?? services.starter.phrases[0]
        live = LivePhrase(phrase: phrase, packTitle: LivePresenter.packTitle(services.starter, phrase: first),
                          voice: Self.rememberedVoice(phrase, defaults: services.defaults))
        inputDevice = services.defaults.string(forKey: Self.inputKey)
        if let modelUnavailable { screen.operationalError = .modelUnavailable(modelUnavailable) }
        let stream = services.coordinator.events
        events = Task { @MainActor [weak self] in
            for await event in stream { self?.receive(event) }
        }
    }

    // MARK: Phrases and voices

    static func voiceKey(_ phrase: PhraseID) -> String { "Voice.\(phrase.rawValue)" }

    /// The voice remembered for `phrase`, else its manifest headline voice.
    static func rememberedVoice(_ phrase: StarterManifest.Phrase, defaults: UserDefaults) -> RecordingID {
        if let raw = defaults.string(forKey: voiceKey(phrase.id)), phrase.recording(RecordingID(raw)) != nil {
            return RecordingID(raw)
        }
        return phrase.headlineVoice
    }

    /// Loads the selected phrase's takes and shows its newest saved take (or the empty state).
    func start() async {
        await showPhrase()
        recheckAvailability()
    }

    /// Selecting another phrase (click, ⌥⌘↑/↓): a take being recorded or analysed is dropped with nothing kept.
    func select(phrase id: PhraseID) async {
        guard id != live.phrase.id, let phrase = services.starter.phrase(id) else { return }
        if isRecording {
            discardTake()
            announce?(.recordingCancelled)
        }
        services.coordinator.invalidate(.phraseSwitched)
        pending = nil
        analysed = nil
        beforeTake = nil
        live = LivePhrase(phrase: phrase, packTitle: LivePresenter.packTitle(services.starter, phrase: id),
                          voice: Self.rememberedVoice(phrase, defaults: services.defaults))
        let error = screen.operationalError.flatMap { if case .modelUnavailable = $0 { $0 } else { nil } }
        screen = LiveScreen(operationalError: error)
        youClip = nil
        shownTake = nil
        changed()
        await showPhrase()
    }

    /// The phrase IDs in sidebar order, for ⌥⌘↑ / ⌥⌘↓.
    var phraseOrder: [PhraseID] { services.starter.packs.flatMap(\.phrases) }

    func selectAdjacentPhrase(_ offset: Int) async {
        let order = phraseOrder
        guard let index = order.firstIndex(of: live.phrase.id) else { return }
        let next = index + offset
        guard order.indices.contains(next) else { return }
        await select(phrase: order[next])
    }

    /// No microphone shows its row (and disables Record) until a device appears; access granted in System Settings
    /// clears the micDenied row when the app becomes active again, with no restart.
    func recheckAvailability() {
        guard !isRecording else { return }
        let availability = services.capture.availability()
        if case .takeProblem(let problem, false) = screen.shown, problem == .micDenied || problem == .noMicrophone {
            guard availability != problem, availability != .noMicrophone else { return }
            screen.shown = .nothing
            screen.phase = .empty
            changed()
            Task { await showPhrase() }
        } else if availability == .noMicrophone, screen.shown.isNothing {
            screen.shown = .takeProblem(.noMicrophone, hasAudio: false)
            screen.phase = .showingTake
            changed()
        }
    }

    private func showPhrase() async {
        savedTakes = await services.store.takes(for: live.phrase.id)
        screen.savedTakes = savedTakes.map(\.number)
        if let latest = savedTakes.first(where: { $0.status == .comparable }) {
            await show(saved: latest)
        } else {
            screen.modelSeconds = modelClip().seconds
            changed()
        }
    }

    /// Model Voice (E7): the subtitle names the new voice at once; your take is compared again (L2 only).
    func select(voice: RecordingID) async {
        guard !isRecording, voice != live.voice, live.phrase.recording(voice) != nil else { return }
        live.voice = voice
        services.defaults.set(voice.rawValue, forKey: Self.voiceKey(live.phrase.id))
        changed()
        if let shownTake {
            await show(saved: shownTake)
        } else if analysed != nil, case .result = screen.shown {
            // The band stays drawn; no "Analysing…" for a voice switch (spec 20's ease follows the new L2).
            submitAgain(showsAnalysing: false)
        } else {
            screen.modelSeconds = modelClip().seconds
            changed()
        }
    }

    // MARK: Takes (⌘[ ⌘], the take menu)

    func select(takeNumber: Int) async {
        guard !isRecording, let take = savedTakes.first(where: { $0.number == takeNumber }) else { return }
        services.coordinator.invalidate(.newRecordingStarted)
        pending = nil
        await show(saved: take)
    }

    /// ⌘[ (older, +1) and ⌘] (newer, −1) through the saved takes, newest first.
    func moveTake(_ offset: Int) async {
        guard !savedTakes.isEmpty else { return }
        let index = shownTake.flatMap { shown in savedTakes.firstIndex { $0.ref == shown.ref } } ?? -1
        let next = index + offset
        guard savedTakes.indices.contains(next) else { return }
        await select(takeNumber: savedTakes[next].number)
    }

    /// A saved take's stored result with the selected voice (spec 16 recomputes L2 when stale).
    private func show(saved take: StoredTake) async {
        let voice = live.voice
        let phrase = live.phrase.id
        guard let record = try? await services.store.result(take: take.ref, voice: voice),
              let l2 = DerivedCoding.value(L2Analysis.self, in: record, key: record.key),
              live.phrase.id == phrase, live.voice == voice, !isRecording
        else { return }
        guard case .analysed(let result) = l2.outcome else { return }
        shownTake = take
        analysed = nil
        screen.shown = .result(result, number: take.number)
        screen.phase = .showingTake
        screen.persistence = nil
        clearTransientError()
        let samples = Self.readAudio(services.store.folder(take.ref).appending(path: "audio.caf")) ?? []
        setClips(result: result, yours: samples)
        screen.ghosts = await ghosts(before: take.ref)
        changed()
        announce?(.resultReady)
    }

    private func ghosts(before take: TakeRef) async -> [GhostPitch] {
        await services.store.ghosts(before: take, voice: live.voice).compactMap(GhostPitch.init)
    }

    // MARK: Recording

    /// Record / Stop (Space, ⌘R, the toolbar button). While analysing, Record starts a new take and drops the old.
    func recordOrStop() async {
        if let capture {
            capture.stop()
            return
        }
        await startTake()
    }

    private func startTake() async {
        if pending != nil {
            services.coordinator.invalidate(.newRecordingStarted)
            pending = nil
        }
        takeGeneration += 1
        let generation = takeGeneration
        let session: CaptureSession
        do {
            session = try await services.capture.start(device: inputDevice, lastSessionFloorDBFS: lastFloorDBFS)
        } catch {
            guard generation == takeGeneration else { return }
            if let problem = error.takeProblem {
                screen.shown = .takeProblem(problem, hasAudio: false)
                screen.phase = .showingTake
                screen.persistence = nil
                youClip = nil
                shownTake = nil
                announce?(.takeProblem(LivePresenter.takeProblem(problem)))
            } else {
                Self.log.error("capture failed to start: \(String(describing: error), privacy: .public)")
                screen.operationalError = .audioUnreadable
            }
            changed()
            return
        }
        guard generation == takeGeneration else { session.cancel(); return }
        beforeTake = (screen, youClip, shownTake)
        capture = session
        envelope = []
        screen.phase = .recording(elapsedSeconds: 0)
        clearTransientError()
        changed()
        announce?(.recording)
        captureTasks = [
            Task { @MainActor [weak self] in
                var batch: [Double] = []
                for await frame in session.envelope {
                    batch.append(Double(min(1, frame.rms * 4)))
                    if batch.count >= 5 { self?.appendEnvelope(batch, generation: generation); batch = [] }
                }
                if !batch.isEmpty { self?.appendEnvelope(batch, generation: generation) }
            },
            Task { @MainActor [weak self] in
                for await level in session.levels {
                    guard let self, generation == self.takeGeneration else { return }
                    self.onLevel?(level)
                }
            },
            Task { @MainActor [weak self] in
                var seconds = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, generation == self.takeGeneration, self.capture != nil else { return }
                    seconds += 1
                    self.screen.phase = .recording(elapsedSeconds: seconds)
                    self.changed()
                }
            },
        ]
        let outcome = await session.result()
        guard generation == takeGeneration else { return }
        finishCapture()
        switch outcome {
        case .recorded(let take):
            lastFloorDBFS = take.floorDBFS
            submit(TakeAudio(samples: take.samples, sha256: take.sha256))
        case .cancelled, .deviceLost:
            restoreBeforeTake()
        }
    }

    private func appendEnvelope(_ values: [Double], generation: Int) {
        guard generation == takeGeneration, capture != nil else { return }
        envelope += values
        onEnvelope?(envelope)
    }

    private func finishCapture() {
        capture = nil
        for task in captureTasks { task.cancel() }
        captureTasks = []
    }

    /// Drops the take being recorded: nothing kept.
    private func discardTake() {
        takeGeneration += 1
        capture?.cancel()
        finishCapture()
    }

    private func restoreBeforeTake() {
        if let before = beforeTake {
            screen = before.screen
            youClip = before.you
            shownTake = before.shown
        } else {
            screen.phase = screen.shown.isNothing ? .empty : .showingTake
        }
        beforeTake = nil
        changed()
    }

    /// Esc: cancels a recording or an analysis; nothing is kept and what was on screen comes back. False when there
    /// was nothing to cancel (Esc then stops playback).
    @discardableResult
    func cancel() -> Bool {
        if isRecording {
            discardTake()
            restoreBeforeTake()
            announce?(.recordingCancelled)
            return true
        }
        if pending != nil {
            // No "cancelled by the user" reason exists in `InvalidationReason`; a new take is the closest.
            services.coordinator.invalidate(.newRecordingStarted)
            pending = nil
            restoreBeforeTake()
            return true
        }
        return false
    }

    // MARK: Analysis

    private func submit(_ audio: TakeAudio, showsAnalysing: Bool = true) {
        let request = services.coordinator.submit(
            AnalysisSubmission(take: audio, phrase: phraseInput(), voice: live.voice))
        pending = (request.id, audio)
        if showsAnalysing { announce?(.analysing) }
        let id = request.id
        // "Analysing your take…" only after 0.4 s; until then what was on screen before the take stays.
        if let before = beforeTake { screen.shown = before.screen.shown }
        screen.phase = screen.shown.isNothing ? .empty : .showingTake
        changed()
        guard showsAnalysing else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.analysingDelay)
            guard let self, self.pending?.request == id else { return }
            self.screen.phase = .analysing
            self.changed()
        }
    }

    /// Retry, Try Again Saving and a voice switch: the same take again (L0 and L1 come from the analyzer's cache).
    func submitAgain(showsAnalysing: Bool = true) {
        guard let audio = analysed?.audio ?? pending?.audio else { return }
        beforeTake = (screen, youClip, shownTake)
        submit(audio, showsAnalysing: showsAnalysing)
    }

    private func phraseInput() -> PhraseInput {
        services.references.phraseInput(live.phrase.id) ?? PhraseInput(id: live.phrase.id, words: [])
    }

    private func receive(_ event: CoordinatorEvent) {
        switch event {
        case .response(let response):
            guard let pending, pending.request == response.requestID else { return }
            self.pending = nil
            beforeTake = nil
            respond(response.outcome, audio: pending.audio, request: response.requestID)
        case .persistence(let id, let status):
            guard analysed?.request == id else { return }
            persisted(status)
        }
    }

    private func respond(_ outcome: AnalysisOutcome, audio: TakeAudio, request: RequestID) {
        switch outcome {
        case .analysed(let result):
            analysed = (request, audio)
            shownTake = nil
            screen.shown = .result(result, number: nil)
            screen.phase = .showingTake
            screen.persistence = nil
            clearTransientError()
            setClips(result: result, yours: audio.samples)
            announce?(.resultReady)
        case .takeProblem(let problem):
            // Never saved (§7): You plays the attempt until the next take or a phrase change.
            analysed = nil
            shownTake = nil
            let hasAudio = problem != .noSpeech && !audio.samples.isEmpty
            screen.shown = .takeProblem(problem, hasAudio: hasAudio)
            screen.phase = .showingTake
            screen.persistence = .notSaved(.takeProblem)
            clearTransientError()
            youClip = hasAudio ? AudioClip(samples: audio.samples) : nil
            screen.youSeconds = youClip?.seconds
            screen.modelSeconds = modelClip().seconds
            announce?(.takeProblem(LivePresenter.takeProblem(problem)))
        case .failed(let error):
            // The cards keep the last result or the empty state; the banner says what happened.
            analysed = (request, audio)
            screen.operationalError = error
            if screen.shown.isNothing { screen.phase = .empty } else { screen.phase = .showingTake }
        case .cancelled:
            break
        }
        changed()
    }

    private func persisted(_ status: AMCore.PersistenceStatus) {
        switch status {
        case .pending, .notSaved:
            return
        case .saveFailed:
            screen.persistence = status
            changed()
        case .saved(let id), .savedPruneFailed(let id, _):
            if case .savedPruneFailed = status { Self.log.error("saved, but the prune failed") }
            screen.persistence = nil
            Task { @MainActor [weak self] in await self?.reloadTakes(showing: id) }
        }
    }

    private func reloadTakes(showing id: TakeID) async {
        let phrase = live.phrase.id
        let takes = await services.store.takes(for: phrase)
        guard live.phrase.id == phrase else { return }
        savedTakes = takes
        screen.savedTakes = takes.map(\.number)
        if let take = takes.first(where: { $0.id == id }), case .result(let result, _) = screen.shown,
           result.takeID == id {
            shownTake = take
            screen.shown = .result(result, number: take.number)
            screen.ghosts = await ghosts(before: take.ref)
        }
        changed()
    }

    // MARK: Banner

    /// The banner's button: Retry re-runs on the same audio; Rebuild rebuilds the native recording's cache first.
    func bannerAction() async {
        guard let error = screen.operationalError else {
            if case .saveFailed = screen.persistence { submitAgain() }
            return
        }
        if case .referenceCacheCorrupt(let recording) = error {
            try? await services.coordinator.reference.rebuild(recording, phrase: live.phrase.id)
        }
        screen.operationalError = nil
        changed()
        submitAgain()
    }

    /// The save notice's close button.
    func closeNotice() {
        if case .saveFailed = screen.persistence { screen.persistence = nil }
        changed()
    }

    private func clearTransientError() {
        if case .modelUnavailable = screen.operationalError { return }
        screen.operationalError = nil
    }

    // MARK: Audio

    /// The selected voice's recording, its phrase window when a result is on screen.
    func modelClip() -> AudioClip {
        let voice = live.recording?.id ?? live.voice
        let samples: [Float]
        if let cached = modelAudio[voice] {
            samples = cached
        } else if let recording = live.recording,
                  let decoded = try? StarterReferences.decode16k(services.starterFolder.appending(path: recording.audio)) {
            samples = decoded
            modelAudio[voice] = decoded
        } else {
            samples = []
        }
        if case .result(let result, _) = screen.shown, result.identity.reference.recordingID == voice {
            return AudioClip(samples: samples, start: result.modelAxis.start, end: result.modelAxis.end)
        }
        return AudioClip(samples: samples)
    }

    private func setClips(result: AnalysisResult, yours samples: [Float]) {
        let span = LivePresenter.yourSpan(result)
        youClip = samples.isEmpty ? nil : AudioClip(samples: samples, start: span.start, end: span.end)
        screen.youSeconds = youClip?.seconds
        screen.modelSeconds = result.modelAxis.end - result.modelAxis.start
    }

    static func readAudio(_ url: URL) -> [Float]? {
        try? StarterReferences.decode16k(url)
    }

    private func changed() { onChange?() }
}

/// What VoiceOver says, once each (v3 §5, r6 E8); the app maps these to `Copy`.
enum LiveAnnouncement: Equatable, Sendable {
    case recording, analysing, recordingCancelled, resultReady
    case takeProblem(TakeProblem)
}

extension LiveScreen.Shown {
    var isNothing: Bool { if case .nothing = self { true } else { false } }
}
