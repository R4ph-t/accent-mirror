import AppKit
import SwiftUI

/// The AppKit split-view fallback from spec 18: `NavigationSplitView` on macOS 26 always draws the sidebar as a
/// floating glass panel, and the only opt-out is an Info.plist key this project may not change. So the window
/// uses a plain `NSSplitViewController` whose items are ordinary (non-sidebar) panes: opaque, no vibrancy, no
/// blur, no glass. Each pane hosts a SwiftUI root that paints its own token surface.
struct ShellSplitView<Sidebar: View, Detail: View, Inspector: View>: NSViewControllerRepresentable {
    var sidebarVisible: Bool
    var inspectorVisible: Bool
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var inspector: () -> Inspector

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSViewController(context: Context) -> ShellSplitViewController {
        let hosts = (
            NSHostingController(rootView: ThemeRoot { sidebar() }),
            NSHostingController(rootView: ThemeRoot { detail() }),
            NSHostingController(rootView: ThemeRoot { inspector() })
        )
        // The panes take their size from the split view, not from their SwiftUI content.
        hosts.0.sizingOptions = []
        hosts.1.sizingOptions = []
        hosts.2.sizingOptions = []
        return ShellSplitViewController(
            sidebar: hosts.0,
            detail: hosts.1,
            inspector: hosts.2,
            sidebarVisible: sidebarVisible,
            inspectorVisible: inspectorVisible
        )
    }

    func updateNSViewController(_ controller: ShellSplitViewController, context: Context) {
        controller.setRootViews(sidebar: ThemeRoot { sidebar() }, detail: ThemeRoot { detail() }, inspector: ThemeRoot { inspector() })
        controller.setCollapsed(sidebar: !sidebarVisible, inspector: !inspectorVisible, animated: !reduceMotion)
    }
}

/// A split view with no visible divider: the surfaces meet edge to edge, as in the mockups.
final class SeamlessSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 0 }
    override func drawDivider(in rect: NSRect) {}
}

final class ShellSplitViewController: NSSplitViewController {
    private let sidebarHost: NSViewController
    private let detailHost: NSViewController
    private let inspectorHost: NSViewController
    private var sidebarItem: NSSplitViewItem!
    private var inspectorItem: NSSplitViewItem!
    private let initialSidebarVisible: Bool
    private let initialInspectorVisible: Bool

    init<S: View, D: View, I: View>(
        sidebar: NSHostingController<S>,
        detail: NSHostingController<D>,
        inspector: NSHostingController<I>,
        sidebarVisible: Bool,
        inspectorVisible: Bool
    ) {
        sidebarHost = sidebar
        detailHost = detail
        inspectorHost = inspector
        initialSidebarVisible = sidebarVisible
        initialInspectorVisible = inspectorVisible
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        splitView = SeamlessSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        super.loadView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sidebarItem = NSSplitViewItem(viewController: sidebarHost)
        sidebarItem.minimumThickness = Metrics.sidebarWidth
        sidebarItem.maximumThickness = Metrics.sidebarWidth
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = .defaultHigh
        sidebarItem.isCollapsed = !initialSidebarVisible

        let detailItem = NSSplitViewItem(viewController: detailHost)
        detailItem.holdingPriority = .defaultLow

        inspectorItem = NSSplitViewItem(viewController: inspectorHost)
        inspectorItem.minimumThickness = Metrics.inspectorWidth
        inspectorItem.maximumThickness = Metrics.inspectorWidth
        inspectorItem.canCollapse = true
        inspectorItem.holdingPriority = .defaultHigh
        inspectorItem.isCollapsed = !initialInspectorVisible

        splitViewItems = [sidebarItem, detailItem, inspectorItem]
    }

    func setRootViews<S: View, D: View, I: View>(sidebar: S, detail: D, inspector: I) {
        (sidebarHost as? NSHostingController<S>)?.rootView = sidebar
        (detailHost as? NSHostingController<D>)?.rootView = detail
        (inspectorHost as? NSHostingController<I>)?.rootView = inspector
    }

    func setCollapsed(sidebar: Bool, inspector: Bool, animated: Bool) {
        guard isViewLoaded else { return }
        for (item, collapsed) in [(sidebarItem!, sidebar), (inspectorItem!, inspector)] where item.isCollapsed != collapsed {
            if animated { item.animator().isCollapsed = collapsed } else { item.isCollapsed = collapsed }
        }
    }

    // The panes are fixed-width; there is nothing to drag.
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
                            forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        .zero
    }
}
