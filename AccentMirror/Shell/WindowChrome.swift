import AppKit
import SwiftUI

/// Solid window chrome (spec 18): no title text, a transparent 52 pt title bar over our own token surfaces,
/// so the traffic lights sit over the sidebar and the toolbar is drawn by SwiftUI on surface.base.
/// The NSToolbar has no items; it only gives the title bar its 52 pt height. Nothing here uses glass,
/// vibrancy or blur.
@MainActor
enum WindowChrome {
    static func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "AccentMirror.chrome")
            toolbar.allowsUserCustomization = false
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unified
        window.isOpaque = true
        // The 960 × 680 window minimum comes from `ShellView`'s minimum frame (see there), not from here.
    }
}

/// Hands the hosting window to `WindowChrome` once the view is in a window, and to the shell so
/// Show Details grows this window (v3.7 K3).
struct WindowChromeConfigurator: NSViewRepresentable {
    var onWindow: ((NSWindow?) -> Void)? = nil

    func makeNSView(context: Context) -> ChromeProbeView {
        let view = ChromeProbeView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: ChromeProbeView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class ChromeProbeView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WindowChrome.configure(window) }
            onWindow?(window)
        }
    }
}

/// Grows the window to 1068 pt when Show Details is chosen below that width (v3.7 K3).
extension InspectorLayout {
    @MainActor
    static func growForInspectorIfNeeded(_ window: NSWindow) {
        if let frame = grownFrame(current: window.frame, visibleScreen: window.screen?.visibleFrame) {
            window.setFrame(frame, display: true)
        }
    }
}

/// Collapses the inspector when the window shrinks below 1068 pt (v3.7 K3).
struct InspectorCollapseObserver: NSViewRepresentable {
    @Binding var inspectorVisible: Bool

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onResize = { [binding = $inspectorVisible] window in
            if InspectorLayout.shouldAutoCollapse(
                windowWidth: Double(window.frame.width), inspectorVisible: binding.wrappedValue
            ) {
                binding.wrappedValue = false
            }
        }
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onResize = { [binding = $inspectorVisible] window in
            if InspectorLayout.shouldAutoCollapse(
                windowWidth: Double(window.frame.width), inspectorVisible: binding.wrappedValue
            ) {
                binding.wrappedValue = false
            }
        }
    }

    final class ObserverView: NSView {
        var onResize: ((NSWindow) -> Void)?
        /// Held so `deinit` can drop the observer without crossing a non-Sendable `Any` from a MainActor type.
        private let bag = ObserverBag()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            bag.clear()
            if let window {
                bag.token = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let window = self.window else { return }
                        self.onResize?(window)
                    }
                }
                onResize?(window)
            }
        }
    }

    /// NotificationCenter tokens are not Sendable; isolating the remove in this box keeps `deinit` legal under Swift 6.
    private final class ObserverBag: @unchecked Sendable {
        var token: (any NSObjectProtocol)? {
            didSet { if let old = oldValue { NotificationCenter.default.removeObserver(old) } }
        }
        func clear() { token = nil }
        deinit { clear() }
    }
}
