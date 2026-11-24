import Observation
import SwiftUI

/// Toolbar content (spec 18 §Toolbar, spec 19 A7).
struct ToolbarState: Equatable, Sendable {
    enum Subtitle: Equatable, Sendable {
        case source(String)
        /// "● RECORDING 0:02": lime.text Geist Mono.
        case recording(elapsed: String)
    }

    enum RecordButton: Equatable, Sendable {
        case record(enabled: Bool)
        case stop
    }

    enum TakeMenuLabel: Equatable, Sendable {
        /// "TAKES" when there are no saved takes.
        case takes
        /// "TAKE 03".
        case take(Int)
        /// "LAST TRY · NOT SAVED" while You plays an unsaved attempt (A7).
        case lastTryNotSaved
    }

    var title: String
    var subtitle: Subtitle
    var modelEnabled: Bool
    var youEnabled: Bool
    var record: RecordButton
    var takeMenu: TakeMenuLabel
    /// Shown next to the take label in Geist Mono tertiary ("NOT COMPARABLE", §13.6).
    var takeMenuNote: String?
    /// Saved take numbers, newest first, for the menu.
    var savedTakes: [Int]
}

/// Window-level state shared by the split panes and the menu commands. UI state, so main-actor isolated.
@MainActor
@Observable
final class ShellModel {
    var sidebarVisible = true
    /// The Details inspector is closed by default (spec 18 Defaults).
    var inspectorVisible = false
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
        manifest = loaded.fixture.manifest ?? .stub
        sidebar = loaded.fixture.sidebar ?? .stub
        toolbar = ShellPresenter.toolbar(for: loaded)
        detail = ShellPresenter.detail(for: loaded, showEarlierTakes: showEarlierTakes)
        inspectorVisible = loaded.fixture.inspectorOpen ?? false
        fixtureName = loaded.fixture.name
        self.loaded = loaded
        playback = nil
        loopingWord = nil
        clock = SystemPlaybackClock()
        if let frame = loaded.fixture.playBoth {
            // The fixture freezes Play Both at `elapsed` on an injected clock.
            let frozen = FrozenPlaybackClock(now: 0)
            clock = frozen
            playback = PlaybackRun(.both(model: frame.modelSeconds, you: frame.youSeconds), clock: frozen)
            frozen.now = frame.elapsed
        }
        if ShellPresenter.isResult(loaded) {
            AccessibilityAnnouncer.announce(Copy.resultReady)
        }
    }

    // MARK: View ▸ Show Earlier Takes

    func toggleEarlierTakes() {
        showEarlierTakes = preference.toggle()
        if let loaded { detail = ShellPresenter.detail(for: loaded, showEarlierTakes: showEarlierTakes) }
    }

    // MARK: Take ▸ Play

    var canPlay: Bool { loaded.map(ShellPresenter.isResult) ?? false }

    func play(_ schedule: (Double, Double) -> PlaybackSchedule) {
        guard let loaded, canPlay else { return }
        let seconds = ShellPresenter.playbackSeconds(loaded)
        start(schedule(seconds.model, seconds.you))
    }

    private func start(_ schedule: PlaybackSchedule) {
        if clock is FrozenPlaybackClock { clock = SystemPlaybackClock() }
        loopingWord = nil
        playback = PlaybackRun(schedule, clock: clock)
    }

    /// Clicking a word or syllable label (v3 §3.5).
    func loop(word index: Int) {
        guard let loaded, let loop = ShellPresenter.loopSchedule(loaded, word: index) else { return }
        start(loop.schedule)
        loopingWord = loop.word
    }

    func playModel() { play { model, _ in .model(model) } }
    func playYou() { play { _, you in .you(you) } }
    func playBoth() { play { model, you in .both(model: model, you: you) } }

    /// Esc.
    func stopPlaying() {
        playback?.stop()
        playback = nil
        loopingWord = nil
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
