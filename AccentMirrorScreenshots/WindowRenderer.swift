import AppKit
import SwiftUI
@testable import AccentMirror

/// Renders the real shell in a real window, 1200 × 800 pt unless the fixture names another size, and captures it
/// at 2× (2400 × 1600 px for the default). The capture draws the window's own view hierarchy (title bar included)
/// into a bitmap: no screen grab, no cursor, no overlays, nothing from the user's screen.
@MainActor
enum WindowRenderer {
    enum Appearance: String, CaseIterable, Sendable {
        case light, dark
        var nsAppearance: NSAppearance { NSAppearance(named: self == .light ? .aqua : .darkAqua)! }
    }

    static let scale = 2

    /// The window size a fixture renders at: its `window` field, else the default 1200 × 800 pt.
    static func pointSize(for fixture: UIFixture) -> CGSize {
        fixture.window.map { CGSize(width: $0.width, height: $0.height) } ?? Metrics.defaultWindow
    }

    /// A window that keeps the size it is given. AppKit otherwise shrinks a window that is bigger than its screen
    /// when it is ordered front, and the test VM's screen is narrower than 1200 pt: that is why the round 4 frames
    /// held a ~1020 × 680 pt window drawn into 2400 × 1600 px (fixes round 5, item 1).
    private final class RenderWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    /// Builds a window with the same chrome and root view the app uses.
    static func makeWindow(model: ShellModel, appearance: Appearance, size: CGSize = Metrics.defaultWindow) -> NSWindow {
        autoreleasepool { buildWindow(model: model, appearance: appearance, size: size) }
    }

    private static func buildWindow(model: ShellModel, appearance: Appearance, size: CGSize) -> NSWindow {
        let window = RenderWindow(
            contentRect: NSRect(origin: .zero, size: size),
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
        window.setContentSize(size)
        return window
    }

    /// Shows the window, lets SwiftUI settle, and returns the 2× PNG data of the whole window. Throws if the
    /// window isn't exactly `size` points, so a frame can never again be a smaller window scaled up.
    static func capture(_ window: NSWindow, size: CGSize = Metrics.defaultWindow) async throws -> Data {
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
        guard frameView.bounds.size == size, window.contentView?.bounds.size == size else {
            throw RenderError.wrongSize(expected: size, frame: frameView.bounds.size,
                                        content: window.contentView?.bounds.size ?? .zero)
        }
        let pixels = NSSize(width: size.width * CGFloat(scale), height: size.height * CGFloat(scale))
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

    /// Builds the window, captures it, then tears it down. The teardown runs after the capture, so the frames don't
    /// change. Also returns whether the window was freed by then and how many windows the app still lists, for the
    /// run's log: in the VM none is freed, so AppKit's "excessive live window count" warning still shows once per run
    /// (an open point of fixes round 5).
    static func render(model: ShellModel, appearance: Appearance, size: CGSize) async throws
        -> (png: Data, released: Bool, liveWindows: Int) {
        var window: NSWindow? = makeWindow(model: model, appearance: appearance, size: size)
        weak let weakWindow = window
        let png: Data
        do {
            png = try await capture(window!, size: size)
        } catch {
            if let window { tearDown(window) }
            throw error
        }
        tearDown(window!)
        window = nil
        // Let the run loop turn so AppKit and SwiftUI can drop their last references.
        try? await Task.sleep(for: .milliseconds(30))
        await Task.yield()
        return (png, weakWindow == nil, NSApp.windows.count)
    }

    private static func tearDown(_ window: NSWindow) {
        autoreleasepool {
            window.orderOut(nil)
            window.toolbar = nil
            window.contentViewController = nil
            window.delegate = nil
            window.close()
        }
    }

    enum RenderError: Error {
        case noFrameView, bitmap, encode
        case wrongSize(expected: CGSize, frame: CGSize, content: CGSize)
    }
}
