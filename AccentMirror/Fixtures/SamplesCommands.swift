import SwiftUI

/// Samples ▸ <fixture>: switches the window to any bundled fixture state, no launch arguments needed. The names
/// come from the bundle at run time, so a new `states/*.json` shows up without touching this file.
struct SamplesCommands: Commands {
    var model: ShellModel
    var library: FixtureLibrary?
    /// `FixtureLibrary.allNames()`, read once at launch.
    var names: [String]

    var body: some Commands {
        CommandMenu("Samples") {
            ForEach(names, id: \.self) { name in
                // A Toggle draws the checkmark; choosing the current one reloads it.
                Toggle(name, isOn: Binding(
                    get: { model.fixtureName == name },
                    set: { _ in FixtureChoice.show(name, in: model, from: library) }
                ))
            }
        }
    }
}

/// The fixture the app opens on, kept in `UserDefaults` under `UIFixture`. `-UIFixture <name>` lands in the
/// argument domain and wins for that launch; a successful load also writes the application domain, so the next
/// launch without arguments reopens there.
@MainActor
enum FixtureChoice {
    static let defaultsKey = "UIFixture"

    static var stored: String { UserDefaults.standard.string(forKey: defaultsKey) ?? FixtureLibrary.defaultFixture }

    /// Loads `name` into `model` and remembers it. A failed load leaves the window and the stored name alone.
    @discardableResult
    static func show(_ name: String, in model: ShellModel, from library: FixtureLibrary?) -> Bool {
        guard let loaded = try? library?.load(name) else { return false }
        model.apply(loaded)
        UserDefaults.standard.set(name, forKey: defaultsKey)
        return true
    }
}
