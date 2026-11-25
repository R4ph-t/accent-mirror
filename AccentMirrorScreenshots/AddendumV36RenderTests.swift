import AppKit
import Foundation
import Testing
@testable import AccentMirror

/// v3.6 J2: a 960 pt inspector-open render in light and dark, with the measured title width, for Designer.
@MainActor
@Suite("Addendum v3.6 960 render")
struct AddendumV36RenderTests {
    @Test func render960InspectorOpenLightAndDark() async throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let fixture = try library.load("inspector-open")
        let size = CGSize(width: Metrics.minimumWindow.width, height: Metrics.minimumWindow.height)
        let measured = ToolbarView.controlWidths(for: ShellPresenter.toolbar(for: fixture))
        let available = Double(
            Metrics.minimumWindow.width - Metrics.sidebarWidth - Metrics.inspectorWidth - 2 * Metrics.outer
        )
        let decision = ToolbarCompaction.decide(available: available, controls: measured)
        let line = "960×680 inspector-open title width: \(decision.titleWidth) pt; "
            + "level: \(decision.level); fits: \(decision.fits)"
        print("[v3.6] \(line)")

        // Prefer AML_RENDER_DIR; otherwise the process temp (xcodebuild does not pass the shell env into a
        // hosted test, and the sandbox may refuse an arbitrary folder).
        let folder: URL
        if let dir = ProcessInfo.processInfo.environment["AML_RENDER_DIR"], !dir.isEmpty {
            folder = URL(fileURLWithPath: dir, isDirectory: true)
        } else {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("am-v36-renders", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try (line + "\n").write(to: folder.appendingPathComponent("960-inspector-open-measure.txt"), atomically: true, encoding: .utf8)
        for appearance in WindowRenderer.Appearance.allCases {
            let model = ShellModel(fixture: fixture)
            let result = try await WindowRenderer.render(model: model, appearance: appearance, size: size)
            let name = "960-inspector-open-\(appearance.rawValue)-v3.6@2x.png"
            try result.png.write(to: folder.appendingPathComponent(name))
            print("[v3.6] wrote \(folder.appendingPathComponent(name).path)")
        }
    }
}
