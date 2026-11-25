import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import AccentMirror

/// On-screen capture of the Input popover at 1200 × 800, light and dark, mid-screen, so the 16 pt
/// *window* margin and the arrow on Input can be checked on a real window (v3.5 I2). Offscreen
/// compositing in `WindowRenderer` clips anything past the parent window, which is what hid the
/// overflow on the v3.7 frames. Disabled unless `AML_ONSCREEN_CAPTURE=1` (see
/// `scripts/capture-input-popover-margin.sh`). Do not run this from an agent on Raph's Mac.
@MainActor
@Suite("Input popover margin capture")
struct InputPopoverMarginCaptureTests {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["AML_ONSCREEN_CAPTURE"] == "1"
    }

    @Test(.enabled(if: isEnabled))
    func capture1200LightAndDarkOnScreen() async throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let fixture = try library.load("input-popover")
        let folder: URL
        if let dir = ProcessInfo.processInfo.environment["AML_RENDER_DIR"], !dir.isEmpty {
            folder = URL(fileURLWithPath: dir, isDirectory: true)
        } else {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                "am-input-popover-margin", isDirectory: true
            )
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var lines: [String] = []
        let size = CGSize(width: 1200, height: 800)

        for appearance in WindowRenderer.Appearance.allCases {
            let model = ShellModel(fixture: fixture)
            #expect(model.inputPopover != nil)
            let window = WindowRenderer.makeWindow(model: model, appearance: appearance, size: size)
            defer {
                window.orderOut(nil)
                window.contentViewController = nil
                window.close()
            }
            placeMidScreen(window, size: size)
            window.makeKeyAndOrderFront(nil)
            try await waitForPopover(in: window)

            let popover = try #require(window.childWindows?.first { $0.isVisible })
            let margin = window.frame.maxX - popover.frame.maxX
            let line = "1200×800 mid-screen \(appearance.rawValue): window.maxX \(window.frame.maxX), "
                + "popover.maxX \(popover.frame.maxX), margin \(margin) pt, "
                + "popover \(Int(popover.frame.width))×\(Int(popover.frame.height))"
            lines.append(line)
            print("[input-popover-margin] \(line)")
            #expect(abs(margin - InputPopoverLayout.windowMargin) < 1.5, "16 pt window margin in \(appearance.rawValue)")

            let image = try #require(capture(window: window, including: [popover]))
            let name = "input-popover-margin-\(appearance.rawValue)-1200-2x.png"
            try pngData(image).write(to: folder.appendingPathComponent(name))
            print("[input-popover-margin] wrote \(folder.appendingPathComponent(name).path)")
        }

        try (lines.joined(separator: "\n") + "\n").write(
            to: folder.appendingPathComponent("measures.txt"), atomically: true, encoding: .utf8
        )
    }

    private func placeMidScreen(_ window: NSWindow, size: CGSize) {
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1800, height: 1100)
        var frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        frame.origin.x = screen.midX - size.width / 2
        frame.origin.y = screen.midY - size.height / 2
        if frame.maxX > screen.maxX { frame.origin.x = screen.maxX - frame.width }
        if frame.minX < screen.minX { frame.origin.x = screen.minX }
        if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }
        if frame.minY < screen.minY { frame.origin.y = screen.minY }
        window.setFrame(frame, display: true)
    }

    private func waitForPopover(in window: NSWindow) async throws {
        for _ in 0..<30 {
            if let children = window.childWindows, children.contains(where: \.isVisible) {
                try await Task.sleep(for: .milliseconds(80))
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Input popover child window did not appear")
    }

    /// Real window capture of the parent plus its children, without clipping children to the parent.
    private func capture(window: NSWindow, including children: [NSWindow]) -> NSBitmapImageRep? {
        var union = window.frame
        for child in children { union = union.union(child.frame) }
        let scale = max(window.backingScaleFactor, 2)
        let pixels = NSSize(width: union.width * scale, height: union.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixels.width.rounded()),
            pixelsHigh: Int(pixels.height.rounded()), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = union.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for w in [window] + children {
            guard let image = windowImage(w) else { continue }
            let dest = CGRect(
                x: w.frame.minX - union.minX, y: w.frame.minY - union.minY,
                width: w.frame.width, height: w.frame.height
            )
            image.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func windowImage(_ window: NSWindow) -> NSImage? {
        let id = CGWindowID(window.windowNumber)
        guard let cg = CGWindowListCreateImage(
            .null, [.optionIncludingWindow], id, [.boundsIgnoreFraming, .bestResolution]
        ) else { return nil }
        return NSImage(cgImage: cg, size: window.frame.size)
    }

    private func pngData(_ rep: NSBitmapImageRep) throws -> Data {
        try #require(rep.representation(using: .png, properties: [:]))
    }
}
