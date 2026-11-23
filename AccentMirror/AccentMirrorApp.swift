import AppKit
import SwiftUI

@main
struct AccentMirrorApp: App {
    @State private var model: ShellModel

    init() {
        BundledFonts.register()
        // `-UIFixture <name>` picks a committed fixture (spec 19); without it the app shows the empty state.
        let name = UserDefaults.standard.string(forKey: "UIFixture") ?? FixtureLibrary.defaultFixture
        if let library = FixtureLibrary(), let loaded = try? library.load(name) {
            _model = State(initialValue: ShellModel(fixture: loaded))
            return
        }
        _model = State(initialValue: ShellModel(
            manifest: .stub,
            sidebar: .stub,
            toolbar: ToolbarState(
                title: "Photography is harder than it looks.",
                subtitle: .source("My Phrases · From demo-talk.m4a"),
                modelEnabled: true,
                youEnabled: false,
                record: .record(enabled: true),
                takeMenu: .takes,
                takeMenuNote: nil,
                savedTakes: []
            )
        ))
    }

    var body: some Scene {
        WindowGroup {
            ShellView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(Metrics.defaultWindow)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Accent Mirror") { AboutPanel.show() }
            }
            // No sidebar button in the chrome: View ▸ Hide Sidebar and ⌃⌘S. No number-key shortcuts (AZERTY).
            CommandGroup(replacing: .sidebar) {
                Button(model.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    model.sidebarVisible.toggle()
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }
    }
}
