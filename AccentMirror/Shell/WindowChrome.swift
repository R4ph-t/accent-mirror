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

/// Hands the hosting window to `WindowChrome` once the view is in a window.
struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeProbeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WindowChrome.configure(window) }
        }
    }
}
