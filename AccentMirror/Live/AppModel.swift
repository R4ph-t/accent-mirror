import AMAlignment
import AMCapture
import AMCore
import AMLibrary
import AMPipeline
import AppKit
import Observation
import SwiftUI
import os

/// The live app (spec 21): spec 12's coordinator and model host, spec 15's starter library, spec 16's take store,
/// spec 14's recorder and the playback engine, drawn through the fixture-shaped shell. Fixture mode (`-UIFixture`
/// or Samples ▸) draws committed states exactly as before and every control stays inert.
@MainActor
@Observable
final class AppModel {
    let shell: ShellModel
    /// Nil in fixture mode, or when the bundled library can't be opened.
    @ObservationIgnored private(set) var session: LiveSession?
    private(set) var actions = ShellActions()
    let meter = LevelMeterModel()
    /// The Input popover's mic check (v3.5 I3): fed only while the popover is open and nothing records.
    let inputMeter = LevelMeterModel()
    @ObservationIgnored private var inputPanel: InputPanel?
    @ObservationIgnored private let playback = AudioPlayback()
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    @ObservationIgnored private var devices: [InputDevice] = []
    @ObservationIgnored private var rendered: (take: TakeID?, voice: RecordingID?)?
    @ObservationIgnored private let manifest: LibraryManifest?

    static let modelName = "openai_whisper-base.en"
    static let log = Logger(subsystem: "AccentMirror", category: "App")

    /// True while the window shows the live phrase (not a fixture picked from Samples ▸).
    var isLive: Bool { session != nil && shell.fixtureName == LivePresenter.fixtureName }

    init(shell: ShellModel, fixtureMode: Bool) {
        self.shell = shell
        guard !fixtureMode, let built = Self.makeSession() else {
            manifest = nil
            return
        }
        session = built
        manifest = LivePresenter.manifest(built.services.starter)
        wire(built)
        Task { await built.start() }
    }

    // MARK: Building the pipeline

    /// Opens the bundled starter library, the take store in the app's container and the speech model in the app
    /// bundle (`Contents/Resources/Models/<model>/`, copied there by the "Bundle speech model" build phase). Nothing
    /// outside the bundle and the container is read; nothing is downloaded.
    static func makeSession() -> LiveSession? {
        do {
            guard let resources = Bundle.main.resourceURL else { return nil }
            let starterFolder = resources.appending(path: "Starter", directoryHint: .isDirectory)
            let configuration = try Analyzer.Configuration.shipped()
            let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil,
                                                     create: true)
                .appending(path: "Accent Mirror/References", directoryHint: .isDirectory)
            let (library, references) = try ReferenceLibrary.bundled(
                folder: starterFolder, caches: caches, configuration: configuration)

            let modelFolder = resources.appending(path: "Models/\(modelName)", directoryHint: .isDirectory)
            let manifestURL = modelFolder.appending(path: "manifest.json")
            let speech: SpeechModelHost
            var unavailable: ModelFailure?
            if let modelManifest = try? ModelManifest(contentsOf: manifestURL) {
                speech = SpeechModelHost.whisperKit(folder: modelFolder, manifest: modelManifest)
            } else {
                unavailable = .notInstalled
                speech = SpeechModelHost(asrModelID: library.manifest.asrModelID) {
                    throw ModelUnavailable(.notInstalled)
                }
            }
            let analyzer = Analyzer(speech: speech, configuration: configuration)
            let store = TakeStore(
                root: try TakeStore.applicationSupportRoot(),
                recomputer: .pipeline(analyzer: analyzer, reference: library, phrase: { references.phraseInput($0) }))
            let coordinator = AnalysisCoordinator(analyzer: analyzer, reference: library, store: store)
            #if os(macOS)
                let capture: any CaptureSource = MicRecorder()
            #endif
            let session = LiveSession(
                services: .init(coordinator: coordinator, store: store, capture: capture, references: references,
                                starter: library.manifest, starterFolder: starterFolder),
                modelUnavailable: unavailable)
            // The model loads and warms up at launch, off the main actor; recovery runs before the first save.
            Task.detached(priority: .utility) {
                _ = await store.recover()
                if unavailable == nil { await speech.prepare() }
            }
            return session
        } catch {
            log.error("live library unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func wire(_ session: LiveSession) {
        session.onChange = { [weak self] in self?.render() }
        session.onEnvelope = { [weak self] rms in self?.shell.recordingEnvelope(rms) }
        session.onLevel = { [weak self] level in self?.meter.update(level) }
        session.announce = { [weak self] announcement in self?.announce(announcement) }
        shell.onPlay = { [weak self] schedule in self?.playAudio(schedule) }
        shell.onStopPlaying = { [weak self] in self?.playback.stop() }
        shell.adjustPlayback = { [weak self] schedule in
            guard let session = self?.session else { return schedule }
            return schedule.applyingTail(model: session.modelClip(), you: session.youClip)
        }
        installKeyMonitor()
        wireInput()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.session?.recheckAvailability() }
        })
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            // Quitting during an analysis keeps nothing.
            MainActor.assumeIsolated { self?.session?.services.coordinator.invalidate(.appTerminating) }
        })
        let stream = session.services.capture.deviceChanges()
        deviceTask = Task { @MainActor [weak self] in
            for await devices in stream {
                guard let self else { return }
                self.devices = devices
                self.session?.recheckAvailability()
                self.refreshActions()
            }
        }
        render()
    }

    // MARK: Drawing

    private func render() {
        guard let session, let manifest else { return }
        // Samples ▸ took the window: the live phrase waits until the next launch.
        if shell.fixtureName != LivePresenter.fixtureName, rendered != nil { refreshActions(); return }
        let loaded = LivePresenter.loaded(session.live, screen: session.screen, manifest: manifest)
        var take: TakeID?
        var voice: RecordingID?
        if case .result(let result, _) = session.screen.shown {
            take = result.takeID
            voice = result.identity.reference.recordingID
        }
        let sameTake = take != nil && rendered?.take == take && session.screen.phase == .showingTake
            && shell.detail != nil
        if sameTake, let voice, let before = rendered?.voice, before != voice {
            // The new voice's L2 arrived: the band, your line and the strip re-time onto it in one ease (spec 20).
            shell.voiceArrived(loaded)
            shell.toolbar = ShellPresenter.toolbar(for: loaded)
        } else if sameTake, voice != session.live.voice {
            // A voice was picked and its L2 is on its way: the subtitle names it at once, the drawing stays (E7).
            shell.voiceSelected(subtitle: LivePresenter.subtitle(session.live))
        } else {
            shell.applyLive(loaded, announce: false)
            if case .recording = session.screen.phase { shell.recordingEnvelope(session.envelope) }
        }
        rendered = (take, voice)
        if case .recording = session.screen.phase {} else { meter.reset() }
        refreshActions()
    }

    private func refreshActions() {
        guard let session, isLive || rendered == nil else {
            actions = ShellActions()
            inputPanel?.close()
            return
        }
        var actions = ShellActions(isLive: true)
        actions.record = { [weak self] in self?.record() }
        actions.playModel = { [weak self] in self?.shell.playModel() }
        actions.playYou = { [weak self] in self?.shell.playYou() }
        actions.selectPhrase = { [weak self] id in self?.selectPhrase(PhraseID(id)) }
        actions.selectTake = { [weak self] number in self?.run { await $0.select(takeNumber: number) } }
        actions.cardButton = { [weak self] in self?.cardButton() }
        actions.bannerButton = { [weak self] in self?.run { await $0.bannerAction() } }
        actions.bannerClose = { [weak self] in self?.session?.closeNotice() }
        actions.copyDetails = { [weak self] in self?.copyDetails() }
        let recordings = session.live.phrase.recordings
        actions.voiceTags = recordings.map(LivePresenter.voiceTag)
        actions.selectedVoice = recordings.firstIndex { $0.id == session.live.voice }
        actions.voiceDisabled = session.isRecording
        actions.selectVoice = { [weak self] index in
            guard recordings.indices.contains(index) else { return }
            self?.selectVoice(recordings[index].id)
        }
        // v3.5: the Input popover. The inspector names the chosen input ("System Default" while it follows it).
        actions.inputName = session.inputDevice.flatMap { id in devices.first { $0.id == id }?.name }
        actions.selectInput = { [weak self] id in self?.selectInput(id) }
        actions.openInput = { [weak self] source in
            self?.shell.inputPopoverSource = source
            self?.inputPanel?.open()
        }
        actions.toggleInput = { [weak self] in
            self?.shell.inputPopoverSource = .toolbar
            self?.inputPanel?.toggle()
        }
        actions.closeInput = { [weak self] in self?.inputPanel?.close() }
        actions.setInputVolume = { [weak self] value in self?.inputPanel?.setVolume(value) }
        actions.openSoundSettings = { Self.openSettings(Self.soundInputPane) }
        actions.openMicrophonePrivacy = { Self.openSettings(Self.microphonePrivacyPane) }
        self.actions = actions
        inputPanel?.update(devices: devices, requested: session.inputDevice,
                           authorization: session.services.capture.authorization(), isRecording: session.isRecording)
    }

    // MARK: Input popover (v3.5)

    /// System Settings › Sound › Input and Privacy & Security › Microphone: local settings panes, not the network.
    static let soundInputPane = "x-apple.systempreferences:com.apple.preference.sound?input"
    static let microphonePrivacyPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

    private static func openSettings(_ pane: String) {
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    /// The popover's state, its mic check and the Mac input volume. Live only: fixtures draw a frozen popover.
    private func wireInput() {
        let panel = InputPanel(volume: InputVolume(CoreAudioVolumeScalars()), monitor: MicLevelMonitor())
        panel.onChange = { [weak self] state in
            // Samples ▸ owns the window while it shows a fixture (its own frozen popover, if any).
            guard let self, self.isLive else { return }
            self.shell.inputPopover = state
        }
        panel.onLevel = { [weak self] level in self?.inputMeter.update(level) }
        panel.onStopListening = { [weak self] in self?.inputMeter.reset() }
        // The input ended by itself (permission refused at the prompt, device gone): re-read both.
        panel.onListeningEnded = { [weak self] in self?.refreshActions() }
        inputPanel = panel
    }

    private func selectInput(_ id: InputDevice.ID?) {
        guard let session, !session.isRecording else { return }
        session.inputDevice = id
        refreshActions()
    }

    private func announce(_ announcement: LiveAnnouncement) {
        let text: String = switch announcement {
        case .recording: Copy.recordingAnnouncement
        case .analysing: Copy.analysingAnnouncement
        case .recordingCancelled: Copy.recordingCancelled
        case .resultReady: Copy.resultReady
        case .takeProblem(let problem): Copy.takeProblem(problem)
        }
        AccessibilityAnnouncer.announce(text)
    }

    // MARK: Commands

    private func run(_ body: @escaping @MainActor (LiveSession) async -> Void) {
        guard isLive, let session else { return }
        Task { await body(session) }
    }

    func record() {
        guard isLive else { return }
        shell.stopPlaying()
        run { await $0.recordOrStop() }
    }

    /// Esc: cancels a recording or an analysis first, else stops playback.
    func cancel() {
        // The Input popover is frontmost: Esc closes it first.
        if isLive, let inputPanel, inputPanel.isOpen {
            inputPanel.close()
            return
        }
        if isLive, session?.cancel() == true { return }
        shell.stopPlaying()
    }

    func selectPhrase(_ id: PhraseID) {
        shell.stopPlaying()
        run { await $0.select(phrase: id) }
    }

    func adjacentPhrase(_ offset: Int) {
        shell.stopPlaying()
        run { await $0.selectAdjacentPhrase(offset) }
    }

    func moveTake(_ offset: Int) {
        shell.stopPlaying()
        run { await $0.moveTake(offset) }
    }

    func selectVoice(_ voice: RecordingID) {
        guard let session, !session.isRecording else { return }
        shell.stopPlaying()
        run { await $0.select(voice: voice) }
    }

    private func cardButton() {
        guard let session else { return }
        if case .takeProblem(.micDenied, _) = session.screen.shown {
            // Privacy & Security ▸ Microphone (a local settings pane, not the network).
            Self.openSettings(Self.microphonePrivacyPane)
            return
        }
        record()
    }

    private func copyDetails() {
        guard let error = session?.screen.operationalError else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(describing: error), forType: .string)
    }

    private func playAudio(_ schedule: PlaybackSchedule) {
        guard isLive, let session else { return }
        playback.play(schedule, model: session.modelClip(), you: session.youClip)
    }

    /// Space records or stops when no text field has focus (v1 §10).
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            guard event.keyCode == 49, flags.isEmpty, !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isLive else { return false }
                self.record()
                return true
            }
            return handled ? nil : event
        }
    }
}

/// E5's level meter, fed by spec 14's level stream while recording; idle otherwise (the mic is never opened just to
/// show a level).
@MainActor
@Observable
final class LevelMeterModel {
    /// The frame's RMS, −60…0 dBFS; nil outside a take.
    private(set) var rmsDBFS: Double?
    /// The peak tick, held for 1 s.
    private(set) var peakDBFS: Double = -60
    /// "Too loud": a frame peaked at −1 dBFS or more within the last 1.5 s.
    private(set) var tooLoud = false
    @ObservationIgnored private var peakAt: Double = 0
    @ObservationIgnored private var loudAt: Double = -.infinity
    @ObservationIgnored private var announcedLoud = false

    static let tooLoudDBFS = -1.0
    static let peakHold = 1.0
    static let tooLoudHold = 1.5

    func update(_ level: InputLevel, now: Double = ProcessInfo.processInfo.systemUptime) {
        rmsDBFS = max(InputLevel.floorDBFS, min(0, level.rmsDBFS))
        if level.peakDBFS >= peakDBFS || now - peakAt > Self.peakHold {
            peakDBFS = max(InputLevel.floorDBFS, min(0, level.peakDBFS))
            peakAt = now
        }
        if level.peakDBFS >= Self.tooLoudDBFS {
            loudAt = now
            if !announcedLoud {
                announcedLoud = true
                AccessibilityAnnouncer.announce(Copy.tooLoud)
            }
        }
        let loud = now - loudAt <= Self.tooLoudHold
        if loud != tooLoud { tooLoud = loud }
    }

    func reset() {
        guard rmsDBFS != nil || tooLoud else { return }
        rmsDBFS = nil
        peakDBFS = -60
        tooLoud = false
        loudAt = -.infinity
        announcedLoud = false
    }
}
