import AppKit
import Foundation
import Testing
@testable import AccentMirror

/// v3.7 K4: 960 inspector-collapsed, 1068 inspector-open, and the Input popover at 1200, light and dark.
@MainActor
@Suite("Addendum v3.7 renders")
struct AddendumV37RenderTests {
    @Test func render960Collapsed1068OpenAndInputPopover() async throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("am-v37-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var lines: [String] = []

        // 960 × 680, inspector collapsed: full controls, title 201 pt on the documented widths.
        let collapsed = try library.load("inspector-open")
        do {
            let model = ShellModel(fixture: collapsed)
            model.inspectorVisible = false
            let live = ToolbarView.controlWidths(for: model.toolbar)
            let decision = ToolbarCompaction.decide(
                available: InspectorLayout.availableToolbarWidth(window: 960, inspectorOpen: false),
                controls: live
            )
            let line = "960×680 inspector collapsed: title \(decision.titleWidth) pt; level \(decision.level); fits \(decision.fits)"
            lines.append(line)
            print("[v3.7] \(line)")
            let size = CGSize(width: 960, height: 680)
            for appearance in WindowRenderer.Appearance.allCases {
                let model = ShellModel(fixture: collapsed)
                model.inspectorVisible = false
                let result = try await WindowRenderer.render(model: model, appearance: appearance, size: size)
                let name = "960-collapsed-\(appearance.rawValue)-v3.7-2x.png"
                try result.png.write(to: folder.appendingPathComponent(name))
                print("[v3.7] wrote \(folder.appendingPathComponent(name).path)")
            }
        }

        // 1068 × 680, inspector open: words-only, Record labelled, title 154 pt.
        do {
            let model = ShellModel(fixture: collapsed)
            let live = ToolbarView.controlWidths(for: model.toolbar)
            let decision = ToolbarCompaction.decide(
                available: InspectorLayout.availableToolbarWidth(window: 1068, inspectorOpen: true),
                controls: live
            )
            let line = "1068×680 inspector open: title \(decision.titleWidth) pt; level \(decision.level); fits \(decision.fits)"
            lines.append(line)
            print("[v3.7] \(line)")
            let size = CGSize(width: 1068, height: 680)
            for appearance in WindowRenderer.Appearance.allCases {
                let model = ShellModel(fixture: collapsed)
                #expect(model.inspectorVisible)
                let result = try await WindowRenderer.render(model: model, appearance: appearance, size: size)
                let name = "1068-open-\(appearance.rawValue)-v3.7-2x.png"
                try result.png.write(to: folder.appendingPathComponent(name))
                print("[v3.7] wrote \(folder.appendingPathComponent(name).path)")
            }
        }

        // Input popover at 1200 × 800, anchored to the Input button with the system arrow.
        let popover = try library.load("input-popover")
        do {
            let model = ShellModel(fixture: popover)
            let live = ToolbarView.controlWidths(for: model.toolbar)
            let open = model.inspectorVisible
            let decision = ToolbarCompaction.decide(
                available: InspectorLayout.availableToolbarWidth(window: 1200, inspectorOpen: open),
                controls: live
            )
            let line = "1200×800 input popover open (inspector \(open ? "open" : "collapsed")): title \(decision.titleWidth) pt; level \(decision.level); fits \(decision.fits)"
            lines.append(line)
            print("[v3.7] \(line)")
            let size = CGSize(width: 1200, height: 800)
            for appearance in WindowRenderer.Appearance.allCases {
                let model = ShellModel(fixture: popover)
                #expect(model.inputPopover != nil)
                let result = try await WindowRenderer.render(model: model, appearance: appearance, size: size)
                let name = "input-popover-\(appearance.rawValue)-v3.7-2x.png"
                try result.png.write(to: folder.appendingPathComponent(name))
                print("[v3.7] wrote \(folder.appendingPathComponent(name).path)")
            }
        }

        try (lines.joined(separator: "\n") + "\n").write(
            to: folder.appendingPathComponent("measures.txt"), atomically: true, encoding: .utf8
        )
    }
}
