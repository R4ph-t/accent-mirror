import AppKit
import SwiftUI

@main
struct AccentMirrorApp: App {
    @State private var model: ShellModel
    private let library = FixtureLibrary()
    private let sampleNames: [String]

    init() {
        BundledFonts.register()
        sampleNames = (try? library?.allNames()) ?? []
        // Samples ▸ (or `-UIFixture <name>`, spec 19) picks a committed fixture; without either, the empty state.
        let model = ShellModel(manifest: .stub, sidebar: .stub, toolbar: Self.fallbackToolbar)
        FixtureChoice.show(FixtureChoice.stored, in: model, from: library)
        _model = State(initialValue: model)
    }

    /// Only seen when the stored fixture can't be read.
    private static let fallbackToolbar = ToolbarState(
        title: "Photography is harder than it looks.",
        subtitle: .source("My Phrases · From demo-talk.m4a"),
        modelEnabled: true,
        youEnabled: false,
        record: .record(enabled: true),
        takeMenu: .takes,
        takeMenuNote: nil,
        savedTakes: []
    )

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
            SamplesCommands(model: model, library: library, names: sampleNames)
        }
    }
}
