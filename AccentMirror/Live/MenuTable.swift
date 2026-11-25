import Foundation

/// Every menu command with a shortcut (v1 §10, no number keys: AZERTY). UI-free, so the unhosted tests check it;
/// `AccentMirrorApp` builds its menus from it and `Copy` titles each item.
struct MenuCommand: Equatable, Sendable {
    enum Menu: String, Sendable { case take = "Take", view = "View", edit = "Edit" }

    enum Action: String, CaseIterable, Sendable {
        case record, cancel, playModel, playYou, playBoth, previousTake, nextTake
        case previousPhrase, nextPhrase, showDetails, showSidebar, showEarlierTakes, find
    }

    enum Modifier: String, Sendable, Hashable { case command, shift, option, control }

    var action: Action
    var menu: Menu
    /// The key: a character, or "space", "escape", "up", "down".
    var key: String
    var modifiers: Set<Modifier>
}

enum MenuTable {
    static let commands: [MenuCommand] = [
        MenuCommand(action: .record, menu: .take, key: "r", modifiers: [.command]),
        MenuCommand(action: .cancel, menu: .take, key: "escape", modifiers: []),
        MenuCommand(action: .playModel, menu: .take, key: "l", modifiers: [.command]),
        MenuCommand(action: .playYou, menu: .take, key: "l", modifiers: [.shift, .command]),
        MenuCommand(action: .playBoth, menu: .take, key: "l", modifiers: [.option, .command]),
        MenuCommand(action: .previousTake, menu: .take, key: "[", modifiers: [.command]),
        MenuCommand(action: .nextTake, menu: .take, key: "]", modifiers: [.command]),
        MenuCommand(action: .previousPhrase, menu: .view, key: "up", modifiers: [.option, .command]),
        MenuCommand(action: .nextPhrase, menu: .view, key: "down", modifiers: [.option, .command]),
        MenuCommand(action: .showDetails, menu: .view, key: "i", modifiers: [.option, .command]),
        MenuCommand(action: .showSidebar, menu: .view, key: "s", modifiers: [.control, .command]),
        MenuCommand(action: .showEarlierTakes, menu: .view, key: "g", modifiers: [.shift, .command]),
        MenuCommand(action: .find, menu: .edit, key: "f", modifiers: [.command]),
    ]

    /// Space records or stops too, when no text field has focus. A menu item takes one shortcut, so Take ▸ Record
    /// Take shows ⌘R and Space is caught by the window (`AppModel`'s key monitor).
    static let recordAlsoOnSpace = true

    static func command(_ action: MenuCommand.Action) -> MenuCommand {
        commands.first { $0.action == action }!
    }
}
