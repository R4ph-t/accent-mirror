import Foundation

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
