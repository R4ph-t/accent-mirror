import AppKit
import QuartzCore
import SwiftUI

/// Presents the Input popover as a child window, positioned with `InputPopoverLayout`.
///
/// A SwiftUI `.popover` (NSPopover) only clamps to the screen, not the window, and would not keep I2’s
/// 16 pt window margin when the window is mid-screen. This host keeps a real popover-style panel with
/// a system-material arrow, shifts the body to stay 16 pt inside the window, and leaves the arrow on
/// the opening control.
struct InputPopoverHost<Content: View>: NSViewRepresentable {
    var isPresented: Bool
    var onClose: () -> Void
    @ViewBuilder var popoverContent: Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.anchor = view
        context.coordinator.onClose = onClose
        context.coordinator.sync(isPresented: isPresented, content: popoverContent)
    }

    @MainActor
    final class Coordinator {
        weak var anchor: NSView?
        var onClose: () -> Void = {}
        private var panel: InputPopoverPanel?
        private var hosting: NSHostingController<Content>?
        private let monitors = MonitorBag()
        private var isPresented = false

        func sync(isPresented: Bool, content: Content) {
            if isPresented {
                if self.isPresented, let hosting {
                    hosting.rootView = content
                    reposition()
                } else {
                    present(content)
                }
            } else if self.isPresented {
                dismiss(notify: false)
            }
        }

        private func present(_ content: Content) {
            guard let anchor, let parent = anchor.window else { return }
            let hosting = NSHostingController(rootView: content)
            hosting.sizingOptions = []
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            let fitted = hosting.sizeThatFits(in: NSSize(width: InputPopoverLayout.width, height: 4000))
            let height = max(fitted.height, 1)
            hosting.view.frame = NSRect(x: 0, y: 0, width: InputPopoverLayout.width, height: height)

            let panel = InputPopoverPanel()
            panel.appearance = parent.appearance
            let chrome = InputPopoverChromeView()
            chrome.addSubview(hosting.view)
            panel.contentView = chrome
            panel.delegate = panel
            panel.onRequestClose = { [weak self] in self?.closeFromUser() }

            self.hosting = hosting
            self.panel = panel
            self.isPresented = true

            apply(placementIn: parent, anchor: anchor, height: height, chrome: chrome, panel: panel)
            parent.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            installMonitors(parent: parent)
        }

        private func apply(
            placementIn parent: NSWindow, anchor: NSView, height: CGFloat,
            chrome: InputPopoverChromeView, panel: InputPopoverPanel
        ) {
            let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorInScreen = parent.convertToScreen(anchorInWindow)
            let placement = InputPopoverLayout.placement(
                window: parent.frame, anchor: anchorInScreen, height: Double(height)
            )
            chrome.arrowX = placement.arrowX - placement.frame.minX
            chrome.bodyHeight = height
            panel.setFrame(placement.frame, display: true)
            hosting?.view.frame = NSRect(x: 0, y: 0, width: InputPopoverLayout.width, height: height)
            panel.invalidateShadow()
        }

        func reposition() {
            guard isPresented, let panel, let chrome = panel.contentView as? InputPopoverChromeView,
                  let anchor, let parent = anchor.window, let hosting else { return }
            let height = hosting.view.frame.height
            apply(placementIn: parent, anchor: anchor, height: height, chrome: chrome, panel: panel)
        }

        private func closeFromUser() {
            dismiss(notify: true)
        }

        func dismiss(notify: Bool) {
            removeMonitors()
            if let panel, let parent = panel.parent {
                parent.removeChildWindow(panel)
            }
            panel?.orderOut(nil)
            panel?.contentView = nil
            panel = nil
            hosting = nil
            isPresented = false
            if notify { onClose() }
        }

        private func installMonitors(parent: NSWindow) {
            removeMonitors()
            monitors.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
                [weak self] event in
                if event.type == .keyDown, event.keyCode == 53 {
                    Task { @MainActor in self?.closeFromUser() }
                    return nil
                }
                Task { @MainActor in self?.handle(event) }
                return event
            }
            let center = NotificationCenter.default
            monitors.windowObservers = [
                center.addObserver(forName: NSWindow.didMoveNotification, object: parent, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.reposition() }
                },
                center.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.reposition() }
                },
            ]
        }

        private func handle(_ event: NSEvent) {
            guard isPresented, let panel, let anchor else { return }
            if event.type == .keyDown, event.keyCode == 53 { // Escape
                closeFromUser()
                return
            }
            guard event.type == .leftMouseDown || event.type == .rightMouseDown else { return }
            if event.window === panel { return }
            if event.window === anchor.window {
                let point = anchor.convert(event.locationInWindow, from: nil)
                if anchor.bounds.contains(point) { return } // the control toggles itself
            }
            closeFromUser()
        }

        private func removeMonitors() { monitors.clear() }
    }
}

/// Event and notification tokens are not Sendable; isolating remove in this box keeps `deinit` legal under Swift 6.
private final class MonitorBag: @unchecked Sendable {
    var eventMonitor: Any? {
        didSet { if let old = oldValue { NSEvent.removeMonitor(old) } }
    }
    var windowObservers: [any NSObjectProtocol] = [] {
        didSet {
            for token in oldValue { NotificationCenter.default.removeObserver(token) }
        }
    }
    func clear() {
        eventMonitor = nil
        windowObservers = []
    }
    deinit { clear() }
}

/// A borderless child panel with popover material and a triangular arrow.
final class InputPopoverPanel: NSPanel, NSWindowDelegate {
    var onRequestClose: (() -> Void)?

    convenience init() {
        self.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        level = .floating
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onRequestClose?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onRequestClose?()
        return false
    }
}

/// Rounded 300 pt body with an upward arrow at `arrowX`. AppKit y-up: the body sits at y = 0, the arrow on top.
final class InputPopoverChromeView: NSView {
    var arrowX: CGFloat = InputPopoverLayout.width / 2 {
        didSet { needsLayout = true }
    }
    var bodyHeight: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    private let effect = NSVisualEffectView()
    private let maskLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        addSubview(effect, positioned: .below, relativeTo: nil)
        effect.layer?.mask = maskLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        effect.frame = bounds
        maskLayer.frame = bounds
        maskLayer.path = popoverPath(in: bounds).cgPath
    }

    private func popoverPath(in rect: NSRect) -> NSBezierPath {
        let arrowH = InputPopoverLayout.arrowHeight
        let arrowW = InputPopoverLayout.arrowWidth
        let radius = InputPopoverMetrics.radius
        let body = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0, rect.height - arrowH))
        let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        let tipX = min(max(arrowX, InputPopoverLayout.arrowSideInset), rect.width - InputPopoverLayout.arrowSideInset)
        let tipY = rect.maxY
        let baseY = body.maxY
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: tipX - arrowW / 2, y: baseY))
        arrow.line(to: NSPoint(x: tipX, y: tipY))
        arrow.line(to: NSPoint(x: tipX + arrowW / 2, y: baseY))
        arrow.close()
        path.append(arrow)
        return path
    }
}
