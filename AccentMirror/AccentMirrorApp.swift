import AppKit
import SwiftUI

@main
struct AccentMirrorApp: App {
    @State private var model: ShellModel
    @State private var app: AppModel
    private let library = FixtureLibrary()
    private let sampleNames: [String]

    init() {
        BundledFonts.register()
        sampleNames = (try? library?.allNames()) ?? []
        let model = ShellModel(manifest: .stub, sidebar: .stub, toolbar: Self.fallbackToolbar)
        // `-UIFixture <name>` (spec 19) opens a committed fixture with every control inert, as before. Without it the
        // app is live (spec 21): the starter library, the microphone and the speech model. Samples ▸ still switches
        // the window to any fixture.
        let fixtureMode = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[FixtureChoice.defaultsKey] != nil
        if fixtureMode {
            FixtureChoice.show(FixtureChoice.stored, in: model, from: library)
        }
        let app = AppModel(shell: model, fixtureMode: fixtureMode)
        if !fixtureMode, app.session == nil {
            // The bundled library couldn't be opened: fall back to the fixture shell rather than a blank window.
            FixtureChoice.show(FixtureLibrary.defaultFixture, in: model, from: library)
        }
        _model = State(initialValue: model)
        _app = State(initialValue: app)
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
                .environment(\.shellActions, app.actions)
                .environment(app.meter)
                .environment(\.inputMeter, app.inputMeter)
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
                .shortcut(.showSidebar)
                Button(model.inspectorVisible ? Copy.hideDetails : Copy.showDetails) {
                    model.toggleInspector()
                }
                .shortcut(.showDetails)
                // ⇧⌘G (v3 §3.3): on by default, remembered.
                Toggle(Copy.showEarlierTakes, isOn: Binding(
                    get: { model.showEarlierTakes },
                    set: { _ in model.toggleEarlierTakes() }
                ))
                .shortcut(.showEarlierTakes)
                Divider()
                Button(Copy.previousPhrase) { app.adjacentPhrase(-1) }
                    .shortcut(.previousPhrase)
                    .disabled(!app.isLive)
                Button(Copy.nextPhrase) { app.adjacentPhrase(1) }
                    .shortcut(.nextPhrase)
                    .disabled(!app.isLive)
            }
            CommandGroup(after: .textEditing) {
                // Search behaviour isn't specified yet (spec gap): ⌘F shows the sidebar, where the search well is.
                Button(Copy.find) { model.sidebarVisible = true }
                    .shortcut(.find)
            }
            CommandMenu(Copy.takeMenu) {
                Button(model.toolbar.record == .stop ? Copy.stopRecording : Copy.recordTake) { app.record() }
                    .shortcut(.record)
                    .disabled(!app.isLive || model.toolbar.record == .record(enabled: false))
                Button(Copy.cancel) { app.cancel() }
                    .shortcut(.cancel)
                Divider()
                Button(Copy.playModel) { model.playModel() }
                    .shortcut(.playModel)
                Button(Copy.playYou) { model.playYou() }
                    .shortcut(.playYou)
                Button(Copy.playModelThenYou) { model.playBoth() }
                    .shortcut(.playBoth)
                    .disabled(!model.canPlay)
                Divider()
                Button(Copy.previousTake) { app.moveTake(1) }
                    .shortcut(.previousTake)
                    .disabled(!app.isLive)
                Button(Copy.nextTake) { app.moveTake(-1) }
                    .shortcut(.nextTake)
                    .disabled(!app.isLive)
            }
            SamplesCommands(model: model, library: library, names: sampleNames)
        }
    }
}

extension View {
    /// The shortcut `MenuTable` gives `action`, so the menus and the table can't drift apart.
    func shortcut(_ action: MenuCommand.Action) -> some View {
        let command = MenuTable.command(action)
        let key: KeyEquivalent = switch command.key {
        case "space": .space
        case "escape": .escape
        case "up": .upArrow
        case "down": .downArrow
        default: KeyEquivalent(Character(command.key))
        }
        var modifiers: EventModifiers = []
        if command.modifiers.contains(.command) { modifiers.insert(.command) }
        if command.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if command.modifiers.contains(.option) { modifiers.insert(.option) }
        if command.modifiers.contains(.control) { modifiers.insert(.control) }
        return keyboardShortcut(key, modifiers: modifiers)
    }
}
