import AppKit
import SwiftUI
@testable import AccentMirror

/// Renders the real shell in a real 1200 × 800 pt window and captures it at 2× (2400 × 1600 px).
/// The capture draws the window's own view hierarchy (title bar included) into a bitmap: no screen grab,
/// no cursor, no overlays, nothing from the user's screen.
@MainActor
enum WindowRenderer {
    enum Appearance: String, CaseIterable, Sendable {
        case light, dark
        var nsAppearance: NSAppearance { NSAppearance(named: self == .light ? .aqua : .darkAqua)! }
    }

    static let pointSize = Metrics.defaultWindow
    static let scale = 2

    /// Builds a window with the same chrome and root view the app uses.
    static func makeWindow(model: ShellModel, appearance: Appearance) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: pointSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance.nsAppearance
        window.animationBehavior = .none
        WindowChrome.configure(window)
        let host = NSHostingController(rootView: ShellView(model: model))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(pointSize)
        return window
    }

    /// Shows the window, lets SwiftUI settle, and returns the 2× PNG data of the whole window.
    static func capture(_ window: NSWindow) async throws -> Data {
        NSApp.activate()
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.makeKeyAndOrderFront(nil)
        // A few run-loop turns so SwiftUI and the split view finish layout.
        for _ in 0..<6 {
            window.layoutIfNeeded()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
        window.makeFirstResponder(nil)
        guard let frameView = window.contentView?.superview else { throw RenderError.noFrameView }
        let pixels = NSSize(width: pointSize.width * CGFloat(scale), height: pointSize.height * CGFloat(scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw RenderError.bitmap }
        rep.size = frameView.bounds.size
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        guard let srgb = rep.converting(to: .sRGB, renderingIntent: .default),
              let png = srgb.representation(using: .png, properties: [:])
        else { throw RenderError.encode }
        return png
    }

    /// One window per appearance, reused for every fixture: a fresh hosting controller (so fresh SwiftUI state)
    /// goes into the same window each time. Closing a window per frame didn't free it, and 124 frames passed
    /// AppKit's 100-live-window warning.
    private static var windows: [Appearance: NSWindow] = [:]

    static func window(model: ShellModel, appearance: Appearance) -> NSWindow {
        guard let window = windows[appearance] else {
            let window = makeWindow(model: model, appearance: appearance)
            windows[appearance] = window
            return window
        }
        let host = NSHostingController(rootView: ShellView(model: model))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(pointSize)
        return window
    }

    /// Takes the fixture out of a reused window after its capture.
    static func clear(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentViewController = nil
    }

    /// Closes the reused windows at the end of a run.
    static func closeAll() {
        for window in windows.values { window.close() }
        windows = [:]
    }

    enum RenderError: Error { case noFrameView, bitmap, encode }
}
