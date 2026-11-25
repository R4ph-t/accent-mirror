import AppKit
import Foundation
import ScreenCaptureKit
import Testing
@testable import AccentMirror

/// On-screen captures of the real NSPopover Input popover (v3.5 I2, v3.6 J3). Light and dark:
/// (1) 1200 wide, mid-screen, arrow on Input and the body overhanging the window edge;
/// (2) 1068 wide with the inspector open, same;
/// (3) 1200 wide, window against the screen’s right edge, showing NSPopover’s screen clamp.
/// Disabled unless `AML_ONSCREEN_CAPTURE=1` (see `scripts/capture-input-popover-margin.sh`).
/// Do not run this from an agent on Raph's Mac.
@MainActor
@Suite("Input popover on-screen capture")
struct InputPopoverMarginCaptureTests {
    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["AML_ONSCREEN_CAPTURE"] == "1"
    }

    private struct Shot {
        var name: String
        var size: CGSize
        var inspectorOpen: Bool
        var againstScreenRight: Bool
    }

    @Test(.enabled(if: isEnabled))
    func capturePopoverOverhangAndScreenClamp() async throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let fixture = try library.load("input-popover")
        let folder: URL
        if let dir = ProcessInfo.processInfo.environment["AML_RENDER_DIR"], !dir.isEmpty {
            folder = URL(fileURLWithPath: dir, isDirectory: true)
        } else {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                "am-input-popover-nspopover", isDirectory: true
            )
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let shots: [Shot] = [
            Shot(name: "1200-midscreen", size: CGSize(width: 1200, height: 800), inspectorOpen: false, againstScreenRight: false),
            Shot(name: "1068-inspector", size: CGSize(width: 1068, height: 680), inspectorOpen: true, againstScreenRight: false),
            Shot(name: "1200-screen-right", size: CGSize(width: 1200, height: 800), inspectorOpen: false, againstScreenRight: true),
        ]

        var lines: [String] = []
        for shot in shots {
            for appearance in WindowRenderer.Appearance.allCases {
                let model = ShellModel(fixture: fixture)
                model.inspectorVisible = shot.inspectorOpen
                model.inputPopoverSource = .toolbar
                #expect(model.inputPopover != nil)
                let window = WindowRenderer.makeWindow(model: model, appearance: appearance, size: shot.size)
                defer {
                    window.orderOut(nil)
                    window.contentViewController = nil
                    window.close()
                }
                if shot.againstScreenRight {
                    placeAgainstScreenRight(window, size: shot.size)
                } else {
                    placeMidScreen(window, size: shot.size)
                }
                window.makeKeyAndOrderFront(nil)
                try await waitForPopover(in: window)

                let popover = try #require(visiblePopover(in: window))
                let input = findToolbarInput(in: window)
                let inputCentre = input.map(screenMidX)
                let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
                let overhangRight = popover.frame.maxX - window.frame.maxX
                let overhangLeft = window.frame.minX - popover.frame.minX
                let screenMarginRight = (screen?.maxX ?? .nan) - popover.frame.maxX
                let screenMarginLeft = popover.frame.minX - (screen?.minX ?? .nan)
                var line = "\(shot.name) \(appearance.rawValue): "
                    + "window \(fmt(window.frame)); popover \(fmt(popover.frame)); "
                    + "screen \(screen.map(fmt) ?? "nil"); "
                    + "inputCentreX \(inputCentre.map { String(format: "%.1f", $0) } ?? "nil"); "
                    + "arrowTipX≈ \(inputCentre.map { String(format: "%.1f", $0) } ?? "nil") (NSPopover keeps the arrow on Input); "
                    + "popoverMidX \(String(format: "%.1f", popover.frame.midX)); "
                    + "overhangR \(String(format: "%.1f", overhangRight)) pt, overhangL \(String(format: "%.1f", overhangLeft)) pt; "
                    + "screenMarginR \(String(format: "%.1f", screenMarginRight)) pt, screenMarginL \(String(format: "%.1f", screenMarginLeft)) pt"
                lines.append(line)
                print("[input-popover-capture] \(line)")

                let image = try await capture(window: window, including: [popover])
                let file = "input-popover-\(shot.name)-\(appearance.rawValue)-2x.png"
                try pngData(image).write(to: folder.appendingPathComponent(file))
                print("[input-popover-capture] wrote \(folder.appendingPathComponent(file).path)")
            }
        }

        try (lines.joined(separator: "\n") + "\n").write(
            to: folder.appendingPathComponent("measures.txt"), atomically: true, encoding: .utf8
        )
    }

    private func placeMidScreen(_ window: NSWindow, size: CGSize) {
        let screen = visibleScreen(for: window)
        var frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        frame.origin.x = screen.midX - size.width / 2
        frame.origin.y = screen.midY - size.height / 2
        clampOrigin(&frame, to: screen)
        window.setFrame(frame, display: true)
    }

    private func placeAgainstScreenRight(_ window: NSWindow, size: CGSize) {
        let screen = visibleScreen(for: window)
        var frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        frame.origin.x = screen.maxX - size.width
        frame.origin.y = screen.midY - size.height / 2
        clampOrigin(&frame, to: screen)
        // After clamping height, keep the right edge on the screen’s right edge.
        frame.origin.x = screen.maxX - frame.width
        window.setFrame(frame, display: true)
    }

    private func visibleScreen(for window: NSWindow) -> CGRect {
        window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1800, height: 1100)
    }

    private func clampOrigin(_ frame: inout CGRect, to screen: CGRect) {
        if frame.maxX > screen.maxX { frame.origin.x = screen.maxX - frame.width }
        if frame.minX < screen.minX { frame.origin.x = screen.minX }
        if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }
        if frame.minY < screen.minY { frame.origin.y = screen.minY }
    }

    private func waitForPopover(in window: NSWindow) async throws {
        for _ in 0..<30 {
            if visiblePopover(in: window) != nil {
                try await Task.sleep(for: .milliseconds(80))
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Input popover window did not appear")
    }

    private func visiblePopover(in window: NSWindow) -> NSWindow? {
        if let child = window.childWindows?.first(where: \.isVisible) { return child }
        return NSApp.windows.first { other in
            other !== window && other.isVisible
                && String(describing: type(of: other)).localizedCaseInsensitiveContains("popover")
        }
    }

    private func findToolbarInput(in window: NSWindow) -> NSView? {
        guard let root = window.contentView else { return nil }
        return firstView(in: root) { view in
            view.accessibilityLabel() == Copy.inputButton
        }
    }

    private func firstView(in view: NSView, matching: (NSView) -> Bool) -> NSView? {
        if matching(view) { return view }
        for child in view.subviews {
            if let found = firstView(in: child, matching: matching) { return found }
        }
        return nil
    }

    private func screenMidX(_ view: NSView) -> CGFloat {
        guard let window = view.window else { return view.frame.midX }
        let inWindow = view.convert(view.bounds, to: nil)
        return window.convertToScreen(inWindow).midX
    }

    /// Real window capture of the parent plus its children, without clipping children to the parent,
    /// so an overhang past the window edge is visible. Uses ScreenCaptureKit (CGWindowListCreateImage
    /// is unavailable on this SDK). The copied test host may need Screen Recording permission.
    private func capture(window: NSWindow, including children: [NSWindow]) async throws -> NSBitmapImageRep {
        var union = window.frame
        for child in children { union = union.union(child.frame) }
        union = union.insetBy(dx: -24, dy: -24)
        let scale = max(window.backingScaleFactor, 2)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ids = Set(([window] + children).map { UInt32($0.windowNumber) })
        let scWindows = content.windows.filter { ids.contains($0.windowID) }
        guard !scWindows.isEmpty, let display = content.displays.first(where: { $0.frame.intersects(union) }) ?? content.displays.first else {
            throw CaptureError.noWindow
        }
        let filter = SCContentFilter(display: display, including: scWindows)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.width = Int((union.width * scale).rounded())
        config.height = Int((union.height * scale).rounded())
        // sourceRect is in display coordinates (origin at the display’s bottom-left, points).
        var source = union
        source.origin.x -= display.frame.minX
        source.origin.y -= display.frame.minY
        config.sourceRect = source
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSBitmapImageRep(cgImage: cg)
    }

    private enum CaptureError: Error { case noWindow }

    private func pngData(_ rep: NSBitmapImageRep) throws -> Data {
        try #require(rep.representation(using: .png, properties: [:]))
    }

    private func fmt(_ r: CGRect) -> String {
        String(format: "(%.1f, %.1f, %.1f × %.1f)", r.origin.x, r.origin.y, r.width, r.height)
    }
}
