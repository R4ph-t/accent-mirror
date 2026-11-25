import Foundation

/// When the Details inspector may stay open, and how the window grows to show it (Designer addendum v3.7 K3).
/// Pure geometry, tested without a window. The inspector itself stays 280 pt; the overall minimum stays 960 × 680
/// with the inspector closed. Shrinking below 1068 pt auto-collapses the inspector. Clicking Show Details when the
/// window is narrower than 1068 pt grows it to 1068 pt.
enum InspectorLayout {
    /// Minimum window width while the inspector stays open.
    static let openMinimumWidth: Double = 1068
    /// Overall minimum width, inspector closed.
    static let collapsedMinimumWidth: Double = 960
    static let minimumHeight: Double = 680
    static let sidebarWidth: Double = 240
    static let inspectorWidth: Double = 280
    static let outer: Double = 16

    /// The toolbar's width inside its 16 pt side padding.
    static func availableToolbarWidth(window: Double, inspectorOpen: Bool, sidebarOpen: Bool = true) -> Double {
        window - (sidebarOpen ? sidebarWidth : 0) - (inspectorOpen ? inspectorWidth : 0) - 2 * outer
    }

    /// True when a resize has left the window too narrow to keep the inspector at the 154 pt title floor.
    static func shouldAutoCollapse(windowWidth: Double, inspectorVisible: Bool) -> Bool {
        inspectorVisible && windowWidth < openMinimumWidth
    }

    /// The frame to apply when the user opens Details and the window is narrower than 1068 pt. `nil` if no
    /// resize is needed. Grows to the right; if that would cross the screen's visible edge, shifts left.
    static func grownFrame(current: CGRect, visibleScreen: CGRect?) -> CGRect? {
        guard current.width < openMinimumWidth else { return nil }
        var frame = current
        frame.size.width = openMinimumWidth
        if let visible = visibleScreen, visible.width > 0 {
            if frame.maxX > visible.maxX {
                frame.origin.x = visible.maxX - frame.width
            }
            if frame.origin.x < visible.minX {
                frame.origin.x = visible.minX
            }
        }
        return frame
    }
}
