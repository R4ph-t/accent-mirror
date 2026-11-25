import Foundation
import Testing
@testable import AccentMirror

/// Designer addendum v3.7 K2–K3: title to 154 pt first, then Details icon-only, then take-menu count,
/// then Model/You words-only with Record still labelled. Nothing compact at 1200 pt. At 960 pt the
/// inspector is closed and nothing compact. `decide` is pure; this scheme also measures the typography.
@Suite("Toolbar compaction")
struct ToolbarCompactionTests {
    typealias Widths = ToolbarCompaction.ControlWidths

    /// Lead measurements confirmed in v3.7 K1.
    let measured = Widths(
        model: 82, modelWordsOnly: 55, you: 66, youWordsOnly: 39,
        takeMenu: 74, takeMenuCount: 35, inspectorToggleFull: 60
    )

    @Test func totalsMatchK1() {
        #expect(measured.total(.full) == 471)
        #expect(measured.total(.detailsIcon) == 439)
        #expect(measured.total(.takeCount) == 400)
        #expect(measured.total(.wordsOnly) == 346)
    }

    @Test func inspectorOpenThresholdsUseTheDocumentedWidths() {
        let cases: [(Double, ToolbarCompaction.Level, Double)] = [
            (1200, .full, 161),
            (1193, .full, 154),
            (1192, .detailsIcon, 185),
            (1161, .detailsIcon, 154),
            (1160, .takeCount, 192),
            (1122, .takeCount, 154),
            (1121, .wordsOnly, 207),
            (1068, .wordsOnly, 154),
        ]
        for (window, level, title) in cases {
            let decision = ToolbarCompaction.decide(
                available: InspectorLayout.availableToolbarWidth(window: window, inspectorOpen: true),
                controls: measured
            )
            #expect(decision.level == level, "\(window) pt")
            #expect(decision.titleWidth == title, "\(window) pt")
        }
    }

    @MainActor @Test func liveTypographyAt1200And1068And960() throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let state = ShellPresenter.toolbar(for: try library.load("inspector-open"))
        let live = ToolbarView.controlWidths(for: state)
        let at1200 = ToolbarCompaction.decide(
            available: InspectorLayout.availableToolbarWidth(window: 1200, inspectorOpen: true), controls: live
        )
        let at1068 = ToolbarCompaction.decide(
            available: InspectorLayout.availableToolbarWidth(window: 1068, inspectorOpen: true), controls: live
        )
        let at960 = ToolbarCompaction.decide(
            available: InspectorLayout.availableToolbarWidth(window: 960, inspectorOpen: false), controls: live
        )
        print("[toolbar] live widths \(live); 1200 \(at1200); 1068 \(at1068); 960 collapsed \(at960)")
        #expect(at1200.level == .full)
        #expect(at1200.titleWidth >= ToolbarCompaction.titleMinimum)
        #expect(at1068.level == .wordsOnly)
        #expect(at1068.fits)
        #expect(abs(at1068.titleWidth - 154) < 2, "title at 1068 should be the 154 pt floor")
        #expect(at960.level == .full)
        #expect(at960.titleWidth >= 200)
        #expect(live.input == 28)
        #expect(live.record == 104)
    }
}

@Suite("Addendum v3.7 window policy")
struct AddendumV37WindowPolicyTests {
    @MainActor
    @Test func shrinkingBelow1068ClosesTheInspector() async throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let model = ShellModel(fixture: try library.load("inspector-open"))
        #expect(model.inspectorVisible)
        let window = WindowRenderer.makeWindow(
            model: model, appearance: .light, size: CGSize(width: 1200, height: 680)
        )
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
        window.setFrame(NSRect(x: 40, y: 40, width: 1200, height: 680), display: true)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.inspectorVisible, "stays open at 1200")
        window.setFrame(NSRect(x: 40, y: 40, width: 960, height: 680), display: true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(!model.inspectorVisible, "auto-collapses below 1068")
    }

    @MainActor
    @Test func showingDetailsBelow1068GrowsTheWindow() async throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let model = ShellModel(fixture: try library.load("result"))
        model.inspectorVisible = false
        let window = WindowRenderer.makeWindow(
            model: model, appearance: .light, size: CGSize(width: 960, height: 680)
        )
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
        window.setFrame(NSRect(x: 40, y: 40, width: 960, height: 680), display: true)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(window.frame.width == 960)
        model.toggleInspector()
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(window.frame.width - 1068) < 0.5)
        #expect(model.inspectorVisible)
    }
}
