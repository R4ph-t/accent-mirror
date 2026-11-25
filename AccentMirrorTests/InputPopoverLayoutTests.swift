import Foundation
import Testing

/// v3.5 I2: a 300 pt popover centred on Input, shifted to keep a 16 pt margin inside the *window*
/// (not the screen), with the arrow staying on Input.
@Suite("Input popover window margin")
struct InputPopoverLayoutTests {
    /// Toolbar Input at a 1200 pt window with the inspector closed: 16 pt trailing pad, labelled
    /// Details (60), 8 pt gap, 28 pt Input. MidX 1102, so a centred 300 pt body would run 952…1252.
    @Test func at1200TheBodyShiftsToKeepA16ptWindowMarginAndTheArrowStaysOnInput() {
        let window = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let input = CGRect(x: 1088, y: 748, width: 28, height: 28)
        let range = InputPopoverLayout.bodyXRange(window: window, anchor: input)
        #expect(range.maxX == 1184)
        #expect(range.minX == 884)
        #expect(range.maxX - range.minX == 300)
        #expect(range.arrowX == Double(input.midX))
        #expect(range.arrowX == 1102)
        #expect(Double(window.maxX) - range.maxX == InputPopoverLayout.windowMargin)
    }

    /// 1068 pt, inspector closed, Input still next to labelled Details: midX 970, centred body would
    /// run 820…1120, past the window. After the shift the right edge is 1052.
    @Test func at1068TheBodyShiftsToKeepA16ptWindowMarginAndTheArrowStaysOnInput() {
        let window = CGRect(x: 0, y: 0, width: 1068, height: 680)
        let input = CGRect(x: 956, y: 628, width: 28, height: 28)
        let range = InputPopoverLayout.bodyXRange(window: window, anchor: input)
        #expect(range.maxX == 1052)
        #expect(range.minX == 752)
        #expect(range.maxX - range.minX == 300)
        #expect(range.arrowX == Double(input.midX))
        #expect(Double(window.maxX) - range.maxX == InputPopoverLayout.windowMargin)
    }

    /// The same 1200 pt window sitting mid-screen: NSPopover would clamp only to the *screen* and leave
    /// the body flush with (or past) the window edge. I2 is a window margin, so the body still ends 16 pt
    /// in from the window, not from the screen.
    @Test func aMidScreenWindowStillKeepsTheMarginAgainstTheWindow() {
        let window = CGRect(x: 400, y: 100, width: 1200, height: 800)
        let input = CGRect(x: 400 + 1088, y: 100 + 748, width: 28, height: 28)
        let range = InputPopoverLayout.bodyXRange(window: window, anchor: input)
        #expect(range.maxX == Double(window.maxX) - 16)
        #expect(range.minX == Double(window.maxX) - 16 - 300)
        #expect(range.arrowX == Double(input.midX))
        #expect(range.maxX == 1584)
    }

    @Test func aCentredButtonDoesNotShift() {
        let window = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let input = CGRect(x: 586, y: 748, width: 28, height: 28) // midX 600
        let range = InputPopoverLayout.bodyXRange(window: window, anchor: input)
        #expect(range.minX == 450)
        #expect(range.maxX == 750)
        #expect(range.arrowX == 600)
        #expect(range.minX - Double(window.minX) >= 16)
        #expect(Double(window.maxX) - range.maxX >= 16)
    }
}
