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
        // The whole window is `size` (full-size content view): set the frame itself. `contentRect:` and
        // `setContentSize` measure below the title bar, which the toolbar adds after init, so they leave a
        // window 52 pt taller than asked (r4 C8, fixes round 5b).
        let target = NSRect(origin: NSPoint(x: 40, y: 40), size: size)
        window.setFrame(target, display: false)
        window.makeKeyAndOrderFront(nil)
        var settled: [String] = []
        // A few run-loop turns so SwiftUI and the split view finish layout.
        for _ in 0..<6 {
            window.layoutIfNeeded()
            if window.frame.size != size {
                settled.append("frame \(window.frame.size) after layout")
                window.setFrame(target, display: false)
            }
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
        if !settled.isEmpty || size != Metrics.defaultWindow {
            print("[screenshots] size \(size): \(sizeReport(window)); \(settled.joined(separator: ", "))")
        }
        window.makeFirstResponder(nil)
        guard let frameView = window.contentView?.superview else { throw RenderError.noFrameView }
        guard frameView.bounds.size == size, window.contentView?.bounds.size == size else {
            throw RenderError.wrongSize(
                expected: size, frame: frameView.bounds.size, content: window.contentView?.bounds.size ?? .zero,
                why: sizeReport(window)
            )
        }
        let pixels = NSSize(width: size.width * CGFloat(scale), height: size.height * CGFloat(scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw RenderError.bitmap }
        rep.size = frameView.bounds.size
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        // v3.6 J3: the Input popover is a real NSPopover (a child window). Composite it so fixture frames
        // still show the open popover. Anything that sits outside the parent window is clipped.
        compositeChildWindows(of: window, into: rep, frameView: frameView)
        guard let srgb = rep.converting(to: .sRGB, renderingIntent: .default),
              let png = srgb.representation(using: .png, properties: [:])
        else { throw RenderError.encode }
        return png
    }

    /// The window's minimums and the fitting size of each view that could hold it taller, for size errors.
    private static func sizeReport(_ window: NSWindow) -> String {
        var parts = [
            "contentMinSize \(window.contentMinSize)", "minSize \(window.minSize)",
            "contentLayoutRect \(window.contentLayoutRect.size)",
            "content fittingSize \(window.contentView?.fittingSize ?? .zero)",
        ]
        if let content = window.contentView {
            let vertical = content.constraintsAffectingLayout(for: .vertical)
                + (content.superview?.constraintsAffectingLayout(for: .vertical) ?? [])
            parts.append("vertical constraints [\(vertical.map { "\($0)" }.joined(separator: "; "))]")
        }
        if let split = window.contentViewController.flatMap(firstSplit) {
            parts.append("split fittingSize \(split.splitView.fittingSize)")
            for (index, item) in split.splitViewItems.enumerated() {
                let view = item.viewController.view
                parts.append("pane \(index) \(item.isCollapsed ? "collapsed" : "open") fittingSize \(view.fittingSize) "
                    + "frame \(view.frame.size)")
            }
        }
        return parts.joined(separator: ", ")
    }

    private static func firstSplit(_ controller: NSViewController) -> NSSplitViewController? {
        if let split = controller as? NSSplitViewController { return split }
        for child in controller.children { if let found = firstSplit(child) { return found } }
        return nil
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

    /// Draws each visible child window (the Input popover) into the parent window's bitmap, in window coordinates.
    private static func compositeChildWindows(of window: NSWindow, into rep: NSBitmapImageRep, frameView: NSView) {
        guard let children = window.childWindows, !children.isEmpty,
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.current = previous }
        let parent = window.frame
        for child in children where child.isVisible {
            guard let childFrame = child.contentView?.superview else { continue }
            var dest = child.frame
            dest.origin.x -= parent.origin.x
            dest.origin.y -= parent.origin.y
            let pixels = NSSize(
                width: childFrame.bounds.width * CGFloat(scale),
                height: childFrame.bounds.height * CGFloat(scale)
            )
            guard let childRep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ) else { continue }
            childRep.size = childFrame.bounds.size
            childFrame.cacheDisplay(in: childFrame.bounds, to: childRep)
            childRep.draw(in: dest)
        }
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
        case wrongSize(expected: CGSize, frame: CGSize, content: CGSize, why: String)
    }
}
