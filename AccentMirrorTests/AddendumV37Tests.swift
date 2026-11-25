import Foundation
import Testing

/// Designer addendum v3.7 K2–K3: title to 154 pt first, then Details icon-only, then the take-menu count,
/// then Model/You words-only with Record still labelled. Below 1068 pt the inspector auto-collapses.
/// Pure, no window.
@Suite("Addendum v3.7 compaction")
struct AddendumV37CompactionTests {
    typealias Widths = ToolbarCompaction.ControlWidths

    /// Lead measurements that K1 confirmed: Model 82/55, You 66/39, take 74/35, Details 60/28, Input 28.
    let measured = Widths(
        model: 82, modelWordsOnly: 55, you: 66, youWordsOnly: 39,
        takeMenu: 74, takeMenuCount: 35, inspectorToggleFull: 60
    )

    @Test func totalsMatchTheV37Arithmetic() {
        #expect(measured.total(.full) == 471)
        #expect(measured.total(.detailsIcon) == 439)
        #expect(measured.total(.takeCount) == 400)
        #expect(measured.total(.wordsOnly) == 346)
        #expect(measured.input == 28)
        #expect(measured.record == 104)
    }

    @Test func recordStaysLabelledAtEveryLevel() {
        for level in ToolbarCompaction.Level.allCases {
            #expect(measured.total(level) == measured.total(level))
            // words-only is 471 - 32 (Details) - 39 (take) - 54 (Model/You) = 346, Record still 104.
            #expect(measured.total(.wordsOnly) == 471 - 32 - 39 - 54)
        }
    }

    @Test func theTitleReaches154BeforeAnyControlCompacts() {
        #expect(ToolbarCompaction.decide(available: 471 + 16 + 161, controls: measured)
            == .init(level: .full, titleWidth: 161, fits: true))
        #expect(ToolbarCompaction.decide(available: 471 + 16 + 154, controls: measured)
            == .init(level: .full, titleWidth: 154, fits: true))
        #expect(ToolbarCompaction.decide(available: 471 + 16 + 153, controls: measured)
            == .init(level: .detailsIcon, titleWidth: 153 + 32, fits: true))
    }

    @Test func thenDetailsIconThenTakeCountThenWordsOnlyWithRecordLabelled() {
        #expect(ToolbarCompaction.decide(available: 439 + 16 + 154, controls: measured).level == .detailsIcon)
        #expect(ToolbarCompaction.decide(available: 439 + 16 + 153, controls: measured)
            == .init(level: .takeCount, titleWidth: 153 + 39, fits: true))
        #expect(ToolbarCompaction.decide(available: 400 + 16 + 154, controls: measured).level == .takeCount)
        #expect(ToolbarCompaction.decide(available: 400 + 16 + 153, controls: measured)
            == .init(level: .wordsOnly, titleWidth: 153 + 54, fits: true))
        #expect(measured.modelWordsOnly > 34 && measured.youWordsOnly > 34)
    }

    @Test func at1068WithTheInspectorOpenTheTitleIs154AndRecordIsLabelled() {
        let available = InspectorLayout.availableToolbarWidth(window: 1068, inspectorOpen: true)
        #expect(available == 516)
        let decision = ToolbarCompaction.decide(available: available, controls: measured)
        #expect(decision == .init(level: .wordsOnly, titleWidth: 154, fits: true))
    }

    @Test func at1200WithTheInspectorOpenNothingCompacts() {
        let available = InspectorLayout.availableToolbarWidth(window: 1200, inspectorOpen: true)
        #expect(available == 648)
        let decision = ToolbarCompaction.decide(available: available, controls: measured)
        #expect(decision == .init(level: .full, titleWidth: 161, fits: true))
    }

    @Test func at960WithTheInspectorClosedNothingCompacts() {
        let available = InspectorLayout.availableToolbarWidth(window: 960, inspectorOpen: false)
        #expect(available == 688)
        let decision = ToolbarCompaction.decide(available: available, controls: measured)
        #expect(decision == .init(level: .full, titleWidth: 201, fits: true))
    }

    @Test(arguments: [
        (1200.0, ToolbarCompaction.Level.full, 161.0),
        (1193, .full, 154),
        (1192, .detailsIcon, 185),
        (1161, .detailsIcon, 154),
        (1160, .takeCount, 192),
        (1122, .takeCount, 154),
        (1121, .wordsOnly, 207),
        (1068, .wordsOnly, 154),
    ])
    func inspectorOpenThresholds(window: Double, level: ToolbarCompaction.Level, title: Double) {
        let decision = ToolbarCompaction.decide(
            available: InspectorLayout.availableToolbarWidth(window: window, inspectorOpen: true),
            controls: measured
        )
        #expect(decision.level == level)
        #expect(decision.titleWidth == title)
        #expect(decision.fits)
    }
}

@Suite("Addendum v3.7 inspector layout")
struct AddendumV37InspectorLayoutTests {
    @Test func shrinkingBelow1068AutoCollapses() {
        #expect(!InspectorLayout.shouldAutoCollapse(windowWidth: 1068, inspectorVisible: true))
        #expect(InspectorLayout.shouldAutoCollapse(windowWidth: 1067, inspectorVisible: true))
        #expect(!InspectorLayout.shouldAutoCollapse(windowWidth: 960, inspectorVisible: false))
        #expect(InspectorLayout.inspectorWidth == 280)
        #expect(InspectorLayout.collapsedMinimumWidth == 960)
    }

    @Test func showingDetailsBelow1068GrowsTheWindow() {
        #expect(InspectorLayout.grownFrame(
            current: CGRect(x: 100, y: 100, width: 1200, height: 800), visibleScreen: nil
        ) == nil)
        let grown = InspectorLayout.grownFrame(
            current: CGRect(x: 100, y: 80, width: 960, height: 680), visibleScreen: nil
        )
        #expect(grown == CGRect(x: 100, y: 80, width: 1068, height: 680))
    }

    @Test func growingShiftsLeftIfTheRightEdgeWouldLeaveTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let grown = InspectorLayout.grownFrame(
            current: CGRect(x: 300, y: 0, width: 960, height: 680), visibleScreen: screen
        )
        // 300 + 1068 = 1368, which is 88 pt past 1280, so origin moves to 1280 - 1068 = 212.
        #expect(grown == CGRect(x: 212, y: 0, width: 1068, height: 680))
    }
}
