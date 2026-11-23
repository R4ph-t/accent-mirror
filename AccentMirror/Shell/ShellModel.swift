import Observation
import SwiftUI

/// Starter library manifest stub (spec 18). Spec 15 supplies the real manifest. A pack with zero phrases is
/// "coming soon" because it is empty, not because of its name.
struct LibraryManifest: Codable, Equatable, Sendable {
    struct Phrase: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var text: String
    }

    struct Pack: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var phrases: [Phrase]
        var isComingSoon: Bool { phrases.isEmpty }
    }

    var packs: [Pack]
}

/// What the sidebar shows: the manifest, the selected phrase and which packs are open.
struct SidebarState: Codable, Equatable, Sendable {
    var selectedPhraseID: String?
    var expandedPackIDs: [String]
}

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

    init(manifest: LibraryManifest, sidebar: SidebarState, toolbar: ToolbarState, detail: DetailPresentation? = nil) {
        self.manifest = manifest
        self.sidebar = sidebar
        self.toolbar = toolbar
        self.detail = detail
    }

    /// A shell seeded entirely from one fixture (spec 19).
    convenience init(fixture loaded: LoadedFixture) {
        self.init(
            manifest: loaded.fixture.manifest ?? .stub,
            sidebar: loaded.fixture.sidebar ?? .stub,
            toolbar: ShellPresenter.toolbar(for: loaded),
            detail: ShellPresenter.detail(for: loaded)
        )
        inspectorVisible = loaded.fixture.inspectorOpen ?? false
    }
}

extension LibraryManifest {
    /// Static stub used until spec 15: the imported Photography clip under My Phrases, real VCTK shared-text
    /// starter phrases in the other packs, and an empty Noun and Verb Pairs pack.
    static let stub = LibraryManifest(packs: [
        Pack(id: "my-phrases", title: "My Phrases", phrases: [
            Phrase(id: "photography", text: "Photography is harder than it looks."),
            Phrase(id: "walkthrough", text: "Let me walk you through the details of the plan."),
        ]),
        Pack(id: "stress-shifts", title: "Stress Shifts", phrases: [
            Phrase(id: "complicated-ideas", text: "Many complicated ideas about the rainbow have been formed."),
            Phrase(id: "tried-to-explain", text: "Others have tried to explain the phenomenon physically."),
            Phrase(id: "accepted-miracle", text: "Some have accepted it as a miracle without physical explanation."),
        ]),
        Pack(id: "noun-verb-pairs", title: "Noun and Verb Pairs", phrases: []),
        Pack(id: "compound-nouns", title: "Compound Nouns", phrases: [
            Phrase(id: "sunlight-raindrops", text: "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow."),
        ]),
        Pack(id: "weak-forms", title: "Weak Forms", phrases: [
            Phrase(id: "call-stella", text: "Please call Stella."),
        ]),
    ])
}

extension SidebarState {
    static let stub = SidebarState(selectedPhraseID: "photography", expandedPackIDs: ["my-phrases", "stress-shifts"])
}
