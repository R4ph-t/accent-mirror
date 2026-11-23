import Foundation
import Testing
@testable import AccentMirror

/// Addendum r4 C7: the toolbar compacts in order (take menu chevron, Record dot, then the title gives up its extra
/// width down to 160 pt, then Model and You lose the triangle and keep their words), never cramping the gaps.
/// `ToolbarCompaction.decide` is pure; it runs with the screenshot scheme only because it lives in the app target.
@Suite("Toolbar compaction")
struct ToolbarCompactionTests {
    typealias Widths = ToolbarCompaction.ControlWidths

    /// Round numbers close to the real ones: Model 80, You 67, take menu 72; words only 53 and 40.
    let widths = Widths(model: 80, modelWordsOnly: 53, you: 67, youWordsOnly: 40, takeMenu: 72)

    @Test func totalsAddEveryControlAndTheFixedGaps() {
        // 80 + 8 + 104 + 8 + 67 + 17 + 72 + 16 + 28
        #expect(widths.total(.full) == 400)
        #expect(widths.total(.menuChevron) == 400 - 72 + 28)
        #expect(widths.total(.recordDot) == 356 - 104 + 40)
        #expect(widths.total(.wordsOnly) == 292 - 80 - 67 + 53 + 40)
    }

    @Test func fullWhenEverythingFitsNextToTheFullTitle() {
        let decision = ToolbarCompaction.decide(available: 400 + 16 + 260, titleIdeal: 260, controls: widths)
        #expect(decision == .init(level: .full, titleWidth: 260, fits: true))
    }

    @Test func theTakeMenuCompactsFirstThenRecord() {
        #expect(ToolbarCompaction.decide(available: 675, titleIdeal: 260, controls: widths).level == .menuChevron)
        #expect(ToolbarCompaction.decide(available: 356 + 16 + 260, titleIdeal: 260, controls: widths).level == .menuChevron)
        #expect(ToolbarCompaction.decide(available: 631, titleIdeal: 260, controls: widths).level == .recordDot)
    }

    @Test func theTitleGivesUpItsExtraWidthBeforeModelAndYouChange() {
        // Too narrow for the full title even with Record as a dot, but room for a 160 pt title: stay at the dot.
        let decision = ToolbarCompaction.decide(available: 292 + 16 + 200, titleIdeal: 260, controls: widths)
        #expect(decision == .init(level: .recordDot, titleWidth: 200, fits: true))
        let tight = ToolbarCompaction.decide(available: 292 + 16 + 160, titleIdeal: 260, controls: widths)
        #expect(tight == .init(level: .recordDot, titleWidth: 160, fits: true))
    }

    @Test func modelAndYouKeepTheirWordsWhenTheyCompact() {
        let decision = ToolbarCompaction.decide(available: 292 + 16 + 159, titleIdeal: 260, controls: widths)
        #expect(decision.level == .wordsOnly)
        #expect(decision.titleWidth == 292 + 159 - 238)
        #expect(decision.fits)
        // Never icon-only: the words-only forms are wider than a bare triangle button would be.
        #expect(widths.modelWordsOnly > 34 && widths.youWordsOnly > 34)
    }

    @Test func tooNarrowReportsRatherThanCrampingTheGaps() {
        let decision = ToolbarCompaction.decide(available: 238 + 16 + 150, titleIdeal: 260, controls: widths)
        #expect(decision == .init(level: .wordsOnly, titleWidth: 150, fits: false))
    }

    @Test func aShortTitleStillAsksForAtLeast160() {
        let decision = ToolbarCompaction.decide(available: 400 + 16 + 160, titleIdeal: 90, controls: widths)
        #expect(decision.level == .full)
        #expect(ToolbarCompaction.decide(available: 400 + 16 + 159, titleIdeal: 90, controls: widths).level == .menuChevron)
    }

    /// The real numbers at the minimum window with the inspector open (960 pt: a 440 pt detail pane, 408 pt inside
    /// the toolbar's padding), measured with the bundled fonts. They go to Designer when the controls don't fit.
    @MainActor @Test func narrowInspectorNumbers() throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let state = ShellPresenter.toolbar(for: try library.load("narrow-inspector-open"))
        let measured = ToolbarView.controlWidths(for: state)
        let title = Double(TextMeasure.width(state.title, role: .phraseTitle))
        let available = 960.0 - 240 - 280 - 2 * 16
        let decision = ToolbarCompaction.decide(available: available, titleIdeal: title, controls: measured)
        print("[toolbar] 960 pt, inspector open: available \(available); title ideal \(title); "
            + "Model \(measured.model) / words only \(measured.modelWordsOnly); You \(measured.you) / \(measured.youWordsOnly); "
            + "Record \(measured.record) / dot \(measured.recordDot); take menu \(measured.takeMenu) / chevron \(measured.takeMenuChevron); "
            + "toggle \(measured.inspectorToggle); gaps 8, 8, 17, 16 and 16 before the controls; "
            + "controls total full \(measured.total(.full)), chevron \(measured.total(.menuChevron)), dot \(measured.total(.recordDot)), "
            + "words only \(measured.total(.wordsOnly)); decision \(decision)")
        #expect(decision.level == .wordsOnly)
    }
}
