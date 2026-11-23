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
        autoreleasepool { buildWindow(model: model, appearance: appearance) }
    }

    private static func buildWindow(model: ShellModel, appearance: Appearance) -> NSWindow {
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

    /// Tears a captured window down so it is deallocated before the next one: 124 frames otherwise leave over
    /// 100 live windows (AppKit's excessive-window warning). Runs after the capture, so the frames don't change.
    static func dispose(_ window: NSWindow) async {
        autoreleasepool {
            window.orderOut(nil)
            window.toolbar = nil
            window.contentViewController = nil
            window.delegate = nil
            window.close()
        }
        // Let the run loop turn so AppKit and SwiftUI drop their last references.
        try? await Task.sleep(for: .milliseconds(30))
        await Task.yield()
    }

    enum RenderError: Error { case noFrameView, bitmap, encode }
}
