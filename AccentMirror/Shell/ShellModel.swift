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

    init(manifest: LibraryManifest, sidebar: SidebarState, toolbar: ToolbarState, detail: DetailPresentation? = nil) {
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
        detail = ShellPresenter.detail(for: loaded)
        inspectorVisible = loaded.fixture.inspectorOpen ?? false
        fixtureName = loaded.fixture.name
    }
}
