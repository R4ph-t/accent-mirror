import Foundation

/// Where the Input popover sits relative to the window (Designer addendum v3.5 I2).
///
/// The 300 pt body is centred on the Input control when that leaves a 16 pt margin inside the *window*.
/// If it would hit a window edge, the body shifts so that margin is kept, and the arrow stays on Input.
/// NSPopover cannot do this: it only clamps to the screen, so a mid-screen window would let the body
/// sit flush with (or past) the window’s right edge. This type is UI-free and is tested without a window.
enum InputPopoverLayout {
    static let width: Double = 300
    static let windowMargin: Double = 16
    /// The system-style chevron sits outside the 300 pt body (v3.6 J3).
    static let arrowHeight: Double = 10
    static let arrowWidth: Double = 20
    /// Keep the arrow tip off the body’s 10 pt corner radius.
    static let arrowSideInset: Double = 20

    struct Placement: Equatable, Sendable {
        /// The 300 pt body, in the same coordinate space as the window and anchor (arrow not included).
        var body: CGRect
        /// The arrow tip’s X, on Input’s midX unless that would sit on a corner.
        var arrowX: Double

        /// Body plus the upward-pointing arrow (AppKit y-up: the arrow sits on the body’s top edge).
        var frame: CGRect {
            CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height + InputPopoverLayout.arrowHeight)
        }
    }

    /// `height` is the body height. The popover is placed below the anchor (the toolbar Input button).
    static func placement(window: CGRect, anchor: CGRect, height: Double) -> Placement {
        let minX = window.minX + windowMargin
        let maxX = window.maxX - windowMargin
        var x = anchor.midX - width / 2
        if x + width > maxX { x = maxX - width }
        if x < minX { x = minX }
        let arrowX = min(max(anchor.midX, x + arrowSideInset), x + width - arrowSideInset)
        let bodyMaxY = anchor.minY
        let body = CGRect(x: x, y: bodyMaxY - height, width: width, height: height)
        return Placement(body: body, arrowX: arrowX)
    }

    /// Horizontal-only helper for the unit tests (the body height is not part of I2’s margin rule).
    static func bodyXRange(window: CGRect, anchor: CGRect) -> (minX: Double, maxX: Double, arrowX: Double) {
        let placement = placement(window: window, anchor: anchor, height: 1)
        return (placement.body.minX, placement.body.maxX, placement.arrowX)
    }
}
