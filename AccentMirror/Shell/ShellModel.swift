import Observation
import SwiftUI

/// Window-level state shared by the split panes and the menu commands. UI state, so main-actor isolated.
@MainActor
@Observable
final class ShellModel {
    var sidebarVisible = true
    /// The Details inspector is closed by default (spec 18 Defaults).
    var inspectorVisible = false

    /// Opens or closes Details (v3.7 K3): opening below 1068 pt grows the window first so the inspector
    /// can stay open at the 154 pt title floor.
    func toggleInspector() {
        if inspectorVisible {
            inspectorVisible = false
        } else {
            showInspector()
        }
    }

    /// The hosting window, set by `WindowChromeConfigurator`. Used so Show Details grows *this* window,
    /// not some other visible app window.
    @ObservationIgnored
    weak var window: NSWindow?

    func showInspector() {
        if let window {
            InspectorLayout.growForInspectorIfNeeded(window)
        }
        inspectorVisible = true
    }
    /// The Input popover (v3.5 I2) when it's open: a fixture's frozen state, or the live app's `InputPanel`.
    var inputPopover: InputPopoverState?
    /// Which control the open popover is anchored to (v3.6 J3). Fixtures use the toolbar Input button.
    var inputPopoverSource: InputPopoverSource = .toolbar
    var manifest: LibraryManifest
    var sidebar: SidebarState
    var toolbar: ToolbarState
    /// The cards, banner and inspector content; nil shows the plain spec 18 surface.
    var detail: DetailPresentation?
    /// The fixture on screen, if the shell came from one. Samples ▸ checks it.
    private(set) var fixtureName: String?
    /// The loaded fixture, so View ▸ Show Earlier Takes can redraw it.
    private(set) var loaded: LoadedFixture?
    /// View ▸ Show Earlier Takes (⇧⌘G): on by default, remembered.
    private(set) var showEarlierTakes: Bool
    /// Play Model, Play You or Play Both on `clock`; nil when nothing plays. Spec 21 wires the audio.
    private(set) var playback: PlaybackRun?
    /// The word a label click is looping ("Looping "harder" · Esc to stop").
    private(set) var loopingWord: String?
    /// The playback clock. A fixture with `playBoth` swaps in a frozen one.
    private var clock: any PlaybackClock = SystemPlaybackClock()
    @ObservationIgnored private let preference: EarlierTakesPreference
    /// Spec 21: the audio follows the playhead. Called with each schedule that starts, and when playback stops.
    @ObservationIgnored var onPlay: ((PlaybackSchedule) -> Void)?
    @ObservationIgnored var onStopPlaying: (() -> Void)?

    // MARK: Chart motion (spec 20)

    /// Everything the charts draw besides the presentation: hover, loop, ghost and voice-switch changes, the time
    /// map. Fixtures freeze it; spec 21 feeds it live.
    private(set) var chartInputs = ChartInputs()
    /// The clock the fades and eases run on. A fixture with a `chart` block freezes it at `clockMs`.
    @ObservationIgnored private(set) var motionClock: any PlaybackClock = SystemPlaybackClock()
    /// The screenshot runner forces Reduce Motion on; nil follows the system setting.
    var reduceMotionOverride: Bool?
    /// True while a fade or ease runs, so the cards' timeline keeps ticking.
    private(set) var motionActive = false
    @ObservationIgnored private var motionGeneration = 0
    /// The pitch axis's half-range per phrase (keyed by its text, so it holds across voices): it never shrinks.
    @ObservationIgnored private var axisFloors: [String: Double] = [:]

    init(manifest: LibraryManifest, sidebar: SidebarState, toolbar: ToolbarState, detail: DetailPresentation? = nil,
         defaults: UserDefaults = .standard) {
        preference = EarlierTakesPreference(defaults: defaults)
        showEarlierTakes = preference.isOn
        self.manifest = manifest
        self.sidebar = sidebar
        self.toolbar = toolbar
        self.detail = detail
    }

    /// A shell seeded entirely from one fixture (spec 19).
    convenience init(fixture loaded: LoadedFixture) {
        self.init(manifest: .stub, sidebar: .stub, toolbar: ShellPresenter.toolbar(for: loaded))
        apply(loaded)
    }

    /// Switches this window to another fixture in place. Fixtures don't set sidebar visibility, so it stays.
    func apply(_ loaded: LoadedFixture) {
        apply(loaded, announce: true)
    }

    /// Spec 21: a live state. The inspector stays as the user left it, and VoiceOver hears "Result ready" only when
    /// the result is new (`announce`). The live recording row is fed by `recordingEnvelope(_:)`.
    func applyLive(_ loaded: LoadedFixture, announce: Bool) {
        let inspector = inspectorVisible
        let popover = inputPopover
        let popoverSource = inputPopoverSource
        onStopPlaying?()
        apply(loaded, announce: announce)
        inspectorVisible = inspector
        inputPopover = popover
        inputPopoverSource = popoverSource
    }

    /// The live strip while recording (spec 20's envelope stream, binned by `EnvelopeBins`).
    func recordingEnvelope(_ rms: [Double]) {
        guard case .recording = detail?.strip.you else { return }
        detail?.strip.you = .recording(envelope: RecordingEnvelope(rms: rms))
    }

    private func apply(_ loaded: LoadedFixture, announce: Bool) {
        inputPopover = loaded.fixture.inputPopover.map {
            InputPopoverState(fixture: $0, isRecording: loaded.fixture.phase == .recording)
        }
        inputPopoverSource = .toolbar
        let chart = loaded.fixture.chart
        // A voice switch shows the new voice in the subtitle at once; the drawing follows when its L2 arrives.
        var shown = loaded
        var previous: LoadedFixture?
        if let change = chart?.voiceSwitch, let phrase = loaded.chartPhrases[change.phrase] {
            var next = loaded
            next.phrase = phrase
            if let id = change.take, let take = loaded.chartTakes[id] { next.take = take }
            switch change.stage {
            case .pending: shown = loaded
            case .easing: shown = next; previous = loaded
            case .done: shown = next
            }
            toolbar = ShellPresenter.toolbar(for: next)
        } else {
            toolbar = ShellPresenter.toolbar(for: loaded)
        }
        manifest = loaded.fixture.manifest ?? .stub
        sidebar = loaded.fixture.sidebar ?? .stub
        var detail = ShellPresenter.detail(for: shown, showEarlierTakes: showEarlierTakes)
        if let change = chart?.voiceSwitch {
            detail.inspector.model?.title = change.voice
            detail.inspector.model?.selected = change.voice
        }
        inspectorVisible = loaded.fixture.inspectorOpen ?? false
        fixtureName = loaded.fixture.name
        self.loaded = shown
        playback = nil
        loopingWord = nil
        clock = SystemPlaybackClock()
        motionClock = SystemPlaybackClock()
        motionActive = false
        motionGeneration += 1

        var inputs = ChartInputs()
        inputs.timeMap = Self.timeMap(shown)
        inputs.modelSeconds = ShellPresenter.playbackSeconds(shown).model
        if let previous {
            let before = ShellPresenter.detail(for: previous, showEarlierTakes: showEarlierTakes)
            let range = growAxis(phrase: previous.phrase.text, before.pitch)
            var pitch = before.pitch
            pitch.rangeSemitones = range
            inputs.voiceFrom = (before.strip, pitch)
            inputs.voiceTransition = ChartTransition(start: 0, duration: ChartMotion.voiceSwitch)
        }
        detail.pitch.rangeSemitones = growAxis(phrase: shown.phrase.text, detail.pitch)
        self.detail = detail

        if let frame = loaded.fixture.playBoth {
            // The fixture freezes Play Both at `elapsed` on an injected clock.
            playback = Self.frozenRun(.both(model: frame.modelSeconds, you: frame.youSeconds), at: frame.elapsed, clock: &clock)
        }
        if let chart {
            motionClock = FrozenPlaybackClock(now: (chart.clockMs ?? 0) / 1000)
            let seconds = ShellPresenter.playbackSeconds(shown)
            if let frozen = chart.playback {
                let schedule: PlaybackSchedule = frozen.side == .model ? .model(seconds.model) : .you(seconds.you)
                let length = frozen.side == .model ? seconds.model : seconds.you
                playback = Self.frozenRun(schedule, at: frozen.position * length, clock: &clock)
            }
            if let word = chart.loopingWord, let loop = ShellPresenter.loopSchedule(shown, word: word) {
                playback = Self.frozenRun(loop.schedule, at: chart.loopElapsed ?? 0, clock: &clock)
                loopingWord = loop.word
                inputs.loopingWord = word
                inputs.loopingLabel = loop.word
            }
            inputs.hoveredWord = chart.hoveredWord
            if let change = chart.earlierTakes, ShellPresenter.isResult(shown) {
                switch change.change {
                case .saved:
                    let before = (change.before ?? []).compactMap { loaded.chartTakes[$0] }
                    inputs.ghostsBefore = EarlierTakes.lines(before, visible: showEarlierTakes)
                    inputs.ghostTransition = ChartTransition(start: 0, duration: ChartMotion.earlierTakeSaved)
                case .toggledOff, .toggledOn:
                    let on = change.change == .toggledOn
                    self.detail?.pitch.earlier = EarlierTakes.lines(shown.earlierTakes, visible: on)
                    inputs.ghostsBefore = EarlierTakes.lines(shown.earlierTakes, visible: !on)
                    inputs.ghostTransition = ChartTransition(start: 0, duration: ChartMotion.earlierTakesToggle)
                }
            }
            if let id = chart.menuPreview, let take = loaded.chartTakes[id] {
                inputs.menuPreview = EarlierTakes.preview(take)
            }
        }
        chartInputs = inputs
        if announce, ShellPresenter.isResult(shown) {
            AccessibilityAnnouncer.announce(Copy.resultReady)
        }
    }

    /// A run of `schedule` frozen `elapsed` seconds in, on its own injected clock.
    private static func frozenRun(_ schedule: PlaybackSchedule, at elapsed: Double, clock: inout any PlaybackClock) -> PlaybackRun {
        let frozen = FrozenPlaybackClock(now: 0)
        clock = frozen
        let run = PlaybackRun(schedule, clock: frozen)
        frozen.now = elapsed
        return run
    }

    /// Spec 09's time map for a take drawn over the model; nil for anything else.
    static func timeMap(_ loaded: LoadedFixture) -> (any ChartTimeMap)? {
        guard ShellPresenter.isResult(loaded), let take = loaded.take else { return nil }
        let seconds = ShellPresenter.playbackSeconds(loaded)
        return WarpTimeMap(phrase: loaded.phrase, take: take, modelSeconds: seconds.model, youSeconds: seconds.you)
    }

    /// The pitch axis for `pitch`: 6 st steps up to ±24, and never smaller than it has been for this phrase.
    private func growAxis(phrase: String, _ pitch: PitchPresentation) -> Double {
        let floor = max(axisFloors[phrase] ?? 0, pitch.rangeSemitones)
        let range = PitchAxis.range(needed: PitchAxis.needed(pitch), floor: floor)
        axisFloors[phrase] = range
        return range
    }

    // MARK: Charts (spec 20)

    /// Both cards resolved at the chart clock's now.
    func charts(systemReduceMotion: Bool) -> (strip: StripChart, pitch: PitchChart)? {
        guard let detail else { return nil }
        var inputs = chartInputs
        if case .playing(let side, let progress) = playbackPhase {
            inputs.playback = PlaybackPosition(side: side, position: progress)
        }
        return ChartModel.make(detail, inputs: inputs, now: motionClock.now,
                               reduceMotion: reduceMotionOverride ?? systemReduceMotion)
    }

    /// Keeps the cards' timeline ticking for `duration`, then lets it pause.
    private func startMotion(_ duration: Double) {
        guard !(motionClock is FrozenPlaybackClock) else { return }
        motionActive = true
        motionGeneration += 1
        let generation = motionGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int((duration + 0.05) * 1000)))
            guard let self, self.motionGeneration == generation else { return }
            self.motionActive = false
        }
    }

    /// The pointer entered (a word index) or left (nil) a strip label: the hover box fades in over 120 ms.
    func hover(word: Int?) {
        guard chartInputs.hoveredWord != word else { return }
        chartInputs.hoveredWord = word
        chartInputs.hoverStart = motionClock.now
        if word != nil { startMotion(ChartMotion.highlightFade) }
    }

    /// Hovering a take in the open take menu previews it as the only ghost; nil ends the preview. Spec 21 calls this
    /// with the take store's take.
    func previewTake(_ take: TakeFixture?) {
        chartInputs.menuPreview = take.map(EarlierTakes.preview)
    }

    /// The ghosts as drawn right now, the starting point of the next fade.
    private var drawnGhosts: [EarlierTakeLine] {
        charts(systemReduceMotion: false)?.pitch.pitch.earlier ?? detail?.pitch.earlier ?? []
    }

    /// Spec 21, when a take is saved: the new ghosts fade in over 150 ms as the oldest drops out.
    func earlierTakesChanged(to loaded: LoadedFixture) {
        let before = drawnGhosts
        self.loaded = loaded
        detail?.pitch.earlier = EarlierTakes.lines(loaded.earlierTakes, visible: showEarlierTakes)
        chartInputs.ghostsBefore = before
        chartInputs.ghostTransition = ChartTransition(start: motionClock.now, duration: ChartMotion.earlierTakeSaved)
        startMotion(ChartMotion.earlierTakeSaved)
    }

    /// Spec 21, when the selected voice changes: the subtitle names the new voice at once and the drawing stays.
    func voiceSelected(subtitle: String) {
        toolbar.subtitle = .source(subtitle)
    }

    /// Spec 21, when the new voice's L2 arrives: the band, your line, the strip and the connectors re-time onto it in
    /// one 150 ms ease (at once with Reduce Motion). The band is never blanked.
    func voiceArrived(_ next: LoadedFixture) {
        guard let current = charts(systemReduceMotion: false) else { apply(next); return }
        let phrase = next.phrase.text
        var detail = ShellPresenter.detail(for: next, showEarlierTakes: showEarlierTakes)
        detail.pitch.rangeSemitones = growAxis(phrase: phrase, detail.pitch)
        loaded = next
        self.detail = detail
        chartInputs.timeMap = Self.timeMap(next)
        chartInputs.modelSeconds = ShellPresenter.playbackSeconds(next).model
        chartInputs.voiceFrom = (current.strip.strip, current.pitch.pitch)
        chartInputs.voiceTransition = ChartTransition(start: motionClock.now, duration: ChartMotion.voiceSwitch)
        startMotion(ChartMotion.voiceSwitch)
    }

    // MARK: View ▸ Show Earlier Takes

    /// ⇧⌘G: the ghosts fade out or in over 120 ms (at once with Reduce Motion), and the choice is remembered.
    func toggleEarlierTakes() {
        let before = drawnGhosts
        showEarlierTakes = preference.toggle()
        guard let loaded else { return }
        detail?.pitch.earlier = ShellPresenter.pitch(loaded, showEarlierTakes: showEarlierTakes).earlier
        chartInputs.menuPreview = nil
        chartInputs.ghostsBefore = before
        chartInputs.ghostTransition = ChartTransition(start: motionClock.now, duration: ChartMotion.earlierTakesToggle)
        startMotion(ChartMotion.earlierTakesToggle)
    }

    // MARK: Take ▸ Play

    var canPlay: Bool { loaded.map(ShellPresenter.isResult) ?? false }

    func play(_ schedule: (Double, Double) -> PlaybackSchedule) {
        guard let loaded, canPlay else { return }
        let seconds = ShellPresenter.playbackSeconds(loaded)
        start(schedule(seconds.model, seconds.you))
    }

    /// Play Model (⌘L) whenever Model is enabled, even before a take; the same button stops it (v1 §5.3).
    func playModel() {
        guard let loaded, toolbar.modelEnabled else { return }
        if playbackPhase != nil { stopPlaying(); return }
        start(.model(ShellPresenter.playbackSeconds(loaded).model))
    }

    /// Play You (⇧⌘L) whenever You is enabled: a result, or a take problem's attempt ("LAST TRY · NOT SAVED").
    func playYou() {
        guard let loaded, toolbar.youEnabled else { return }
        if playbackPhase != nil { stopPlaying(); return }
        start(.you(ShellPresenter.playbackSeconds(loaded).you))
    }

    private func start(_ schedule: PlaybackSchedule) {
        if clock is FrozenPlaybackClock { clock = SystemPlaybackClock() }
        if motionClock is FrozenPlaybackClock { motionClock = SystemPlaybackClock() }
        loopingWord = nil
        chartInputs.loopingWord = nil
        chartInputs.loopingLabel = nil
        playback = PlaybackRun(schedule, clock: clock)
        onPlay?(schedule)
    }

    /// Clicking a word or syllable label (v3 §3.5): the loop box fades in at the stronger fill.
    func loop(word index: Int) {
        guard let loaded, let loop = ShellPresenter.loopSchedule(loaded, word: index) else { return }
        start(loop.schedule)
        loopingWord = loop.word
        chartInputs.loopingWord = index
        chartInputs.loopingLabel = loop.word
        chartInputs.loopStart = motionClock.now
    }

    func playBoth() { play { model, you in .both(model: model, you: you) } }

    /// Esc.
    func stopPlaying() {
        onStopPlaying?()
        playback?.stop()
        playback = nil
        loopingWord = nil
        chartInputs.loopingWord = nil
        chartInputs.loopingLabel = nil
    }

    /// Where the playhead is now, or nil.
    var playbackPhase: PlaybackSchedule.Phase? {
        guard let playback else { return nil }
        let phase = playback.phase
        return phase == .finished ? nil : phase
    }
}

/// Posts a VoiceOver announcement (v3 §5: "Result ready. Your take is drawn over the model's.").
@MainActor
enum AccessibilityAnnouncer {
    static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
