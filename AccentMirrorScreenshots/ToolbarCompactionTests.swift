import Foundation
import Testing
@testable import AccentMirror

/// Designer addendum v3.6 J2 (wins over r4 C7, r5 D1's 160 pt first floor, and v3.5 I2 where they disagree):
/// the title goes to 154 pt before any control compact; then Details goes icon-only; then the take menu becomes
/// the count plus the chevron. Record → dot and Model/You words-only stay as later steps so the 960 pt window
/// still fits. Input is a 28 pt icon at every level. Nothing compact at 1200 pt, including with the inspector
/// open. `ToolbarCompaction.decide` is pure; this scheme also measures the real typography.
@Suite("Toolbar compaction")
struct ToolbarCompactionTests {
    typealias Widths = ToolbarCompaction.ControlWidths

    /// Round numbers close to the real ones: Model 80, You 67, take menu 72, count 40, Details 64.
    let widths = Widths(
        model: 80, modelWordsOnly: 53, you: 67, youWordsOnly: 40,
        takeMenu: 72, takeMenuCount: 40, inspectorToggleFull: 64
    )

    /// The toolbar's width inside its padding for a window width with the inspector open.
    static func inspectorOpen(_ window: Double) -> Double {
        window - Double(Metrics.sidebarWidth + Metrics.inspectorWidth + 2 * Metrics.outer)
    }

    @Test func totalsAddEveryControlAndTheFixedGaps() {
        #expect(widths.total(.full) == 472)
        #expect(widths.total(.detailsIcon) == 436)
        #expect(widths.total(.takeCount) == 404)
        #expect(widths.total(.recordDot) == 340)
        #expect(widths.total(.wordsOnly) == 286)
    }

    @Test func theTitleReaches154BeforeAnyControlCompacts() {
        #expect(ToolbarCompaction.decide(available: 472 + 16 + 154, controls: widths)
            == .init(level: .full, titleWidth: 154, fits: true))
        #expect(ToolbarCompaction.decide(available: 472 + 16 + 153, controls: widths)
            == .init(level: .detailsIcon, titleWidth: 153 + 36, fits: true))
    }

    /// v3.6 J2: at the default 1200 pt window with the inspector open, nothing compact and the title stays
    /// at or above 154 pt.
    @MainActor @Test func at1200WithTheInspectorOpenNothingCompacts() {
        BundledFonts.register()
        let library = FixtureLibrary(bundle: Bundle(for: ShellModel.self))!
        let state = ShellPresenter.toolbar(for: try! library.load("inspector-open"))
        let measured = ToolbarView.controlWidths(for: state)
        let decision = ToolbarCompaction.decide(available: Self.inspectorOpen(1200), controls: measured)
        let title = Double(TextMeasure.width(state.title, role: .phraseTitle))
        print("[toolbar] 1200 inspector-open: title ideal \(title); measured \(measured); decision \(decision)")
        #expect(decision.level == .full)
        #expect(decision.titleWidth >= ToolbarCompaction.titleMinimum)
        #expect(decision.titleWidth < title, "the title truncates at 1200 pt with the inspector open")
        #expect(decision.fits)
        #expect(measured.input == 28)
    }

    /// v3.6 J2: at 960 pt with the inspector open, measure the title width after the new compact order (Details
    /// icon-only, take count, then C7's later steps if needed). The number is for Designer; the test does not
    /// lower the 154 pt floor.
    @MainActor @Test func at960WithTheInspectorOpenMeasuresTheTitleWidth() {
        BundledFonts.register()
        let library = FixtureLibrary(bundle: Bundle(for: ShellModel.self))!
        let state = ShellPresenter.toolbar(for: try! library.load("inspector-open"))
        let measured = ToolbarView.controlWidths(for: state)
        let decision = ToolbarCompaction.decide(available: Self.inspectorOpen(960), controls: measured)
        print("[toolbar] 960 inspector-open: level \(decision.level); title \(decision.titleWidth); fits \(decision.fits); "
            + "Model \(measured.model)/\(measured.modelWordsOnly); You \(measured.you)/\(measured.youWordsOnly); "
            + "take \(measured.takeMenu)/count \(measured.takeMenuCount); Details \(measured.inspectorToggleFull)/"
            + "\(measured.inspectorToggle); Input \(measured.input); "
            + "totals full \(measured.total(.full)) icon \(measured.total(.detailsIcon)) count \(measured.total(.takeCount)) "
            + "dot \(measured.total(.recordDot)) words \(measured.total(.wordsOnly))")
        #expect(decision.level >= .takeCount, "J2's take-count step has been applied at 960 pt")
        #expect(measured.input == 28)
        #expect(decision.titleWidth == Self.inspectorOpen(960) - ToolbarCompaction.titleGap - measured.total(decision.level))
    }

    @MainActor @Test func theLevelOnlyGrowsAsTheWindowNarrowsAndTheTitleKeeps154UntilTheLastStep() {
        BundledFonts.register()
        let library = FixtureLibrary(bundle: Bundle(for: ShellModel.self))!
        let state = ShellPresenter.toolbar(for: try! library.load("inspector-open"))
        let measured = ToolbarView.controlWidths(for: state)
        var previous = ToolbarCompaction.Level.full
        for window in stride(from: 1200.0, through: 960, by: -1) {
            let decision = ToolbarCompaction.decide(available: Self.inspectorOpen(window), controls: measured)
            #expect(decision.level >= previous, "\(window) pt")
            if decision.level < .wordsOnly {
                #expect(decision.titleWidth >= ToolbarCompaction.titleMinimum, "\(window) pt")
            }
            previous = decision.level
        }
    }


    @Test func takeCountVoiceOverDropsTheLeadingZero() {
        #expect(Copy.takeMenuCountLabel(.take(3)) == "Take 3")
        #expect(Copy.takeMenuCountLabel(.take(12)) == "Take 12")
        #expect(Copy.details == "Details")
    }
}
