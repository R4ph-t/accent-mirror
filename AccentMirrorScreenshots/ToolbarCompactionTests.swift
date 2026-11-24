import Foundation
import Testing
@testable import AccentMirror

/// Addendum r5 D1 (over r4 C7): the title gives up its extra width, down to 160 pt, before any control compacts;
/// then the take menu becomes its chevron, Record its dot, and Model and You lose the triangle and keep their
/// words. Only after all three may the title go to 154 pt. The gaps never shrink.
/// `ToolbarCompaction.decide` is pure; it runs with the screenshot scheme only because it lives in the app target.
@Suite("Toolbar compaction")
struct ToolbarCompactionTests {
    typealias Widths = ToolbarCompaction.ControlWidths

    /// Round numbers close to the real ones: Model 80, You 67, take menu 72; words only 53 and 40.
    let widths = Widths(model: 80, modelWordsOnly: 53, you: 67, youWordsOnly: 40, takeMenu: 72)
    /// The widths measured in the VM with the bundled fonts (round 5b): Model 81 / 54, You 66 / 39, take menu 74.
    /// Totals: full 402, chevron 356, dot 292, words only 238.
    let measured = Widths(model: 81, modelWordsOnly: 54, you: 66, youWordsOnly: 39, takeMenu: 74)

    /// The toolbar's width inside its padding for a window width with the inspector open.
    static func inspectorOpen(_ window: Double) -> Double {
        window - Double(Metrics.sidebarWidth + Metrics.inspectorWidth + 2 * Metrics.outer)
    }

    @Test func totalsAddEveryControlAndTheFixedGaps() {
        // 80 + 8 + 104 + 8 + 67 + 17 + 72 + 16 + 28
        #expect(widths.total(.full) == 400)
        #expect(widths.total(.menuChevron) == 400 - 72 + 28)
        #expect(widths.total(.recordDot) == 356 - 104 + 40)
        #expect(widths.total(.wordsOnly) == 292 - 80 - 67 + 53 + 40)
        #expect(measured.total(.full) == 402)
        #expect(measured.total(.wordsOnly) == 238)
    }

    @Test func fullWhenEverythingFitsNextToTheFullTitle() {
        let decision = ToolbarCompaction.decide(available: 400 + 16 + 260, controls: widths)
        #expect(decision == .init(level: .full, titleWidth: 260, fits: true))
    }

    @Test func theTitleTruncatesTo160BeforeTheTakeMenuCompacts() {
        // Room for every control at full size next to a 200 pt or a 160 pt title: nothing compacts.
        #expect(ToolbarCompaction.decide(available: 400 + 16 + 200, controls: widths)
            == .init(level: .full, titleWidth: 200, fits: true))
        #expect(ToolbarCompaction.decide(available: 400 + 16 + 160, controls: widths)
            == .init(level: .full, titleWidth: 160, fits: true))
        // One point less: the take menu is the first control to compact, and the title gets its width back.
        #expect(ToolbarCompaction.decide(available: 400 + 16 + 159, controls: widths)
            == .init(level: .menuChevron, titleWidth: 159 + 44, fits: true))
    }

    @Test func thenRecordThenModelAndYou() {
        #expect(ToolbarCompaction.decide(available: 356 + 16 + 160, controls: widths).level == .menuChevron)
        #expect(ToolbarCompaction.decide(available: 356 + 16 + 159, controls: widths)
            == .init(level: .recordDot, titleWidth: 159 + 64, fits: true))
        #expect(ToolbarCompaction.decide(available: 292 + 16 + 160, controls: widths)
            == .init(level: .recordDot, titleWidth: 160, fits: true))
        let words = ToolbarCompaction.decide(available: 292 + 16 + 159, controls: widths)
        #expect(words == .init(level: .wordsOnly, titleWidth: 159 + 54, fits: true))
        // Never icon-only: the words-only forms are wider than a bare triangle button would be.
        #expect(widths.modelWordsOnly > 34 && widths.youWordsOnly > 34)
    }

    @Test func onlyAfterAllThreeStepsMayTheTitleGoTo154() {
        #expect(ToolbarCompaction.decide(available: 238 + 16 + 154, controls: widths)
            == .init(level: .wordsOnly, titleWidth: 154, fits: true))
        #expect(ToolbarCompaction.decide(available: 238 + 16 + 153, controls: widths)
            == .init(level: .wordsOnly, titleWidth: 153, fits: false))
    }

    /// r5 D1: at the default 1200 pt window with the inspector open, nothing compacts ("TAKE 03" keeps its label)
    /// and the title truncates, keeping at least 160 pt.
    @Test func at1200WithTheInspectorOpenNothingCompacts() {
        let decision = ToolbarCompaction.decide(available: Self.inspectorOpen(1200), controls: measured)
        #expect(decision.level == .full)
        #expect(decision.titleWidth >= ToolbarCompaction.titleMinimum)
        #expect(decision.titleWidth == 648 - 16 - 402)
        #expect(decision.fits)
    }

    /// r5 D1: at 960 pt with the inspector open, all three steps, and the title gets 154 pt.
    @Test func at960WithTheInspectorOpenAllThreeStepsAndA154Title() {
        let decision = ToolbarCompaction.decide(available: Self.inspectorOpen(960), controls: measured)
        #expect(decision == .init(level: .wordsOnly, titleWidth: 154, fits: true))
    }

    /// Window widths in between, inspector open: each step starts exactly where the one before would push the title
    /// under 160 pt, and the title is back above 160 pt right after each step.
    @Test(arguments: [
        (1200.0, ToolbarCompaction.Level.full, 230.0),
        (1130, .full, 160),
        (1129, .menuChevron, 205),
        (1084, .menuChevron, 160),
        (1083, .recordDot, 223),
        (1020, .recordDot, 160),
        (1019, .wordsOnly, 213),
        (960, .wordsOnly, 154),
    ])
    func theOrderHoldsBetween960And1200(window: Double, level: ToolbarCompaction.Level, title: Double) {
        let decision = ToolbarCompaction.decide(available: Self.inspectorOpen(window), controls: measured)
        #expect(decision.level == level)
        #expect(decision.titleWidth == title)
    }

    @Test func theLevelOnlyGrowsAsTheWindowNarrowsAndTheTitleKeeps160UntilTheLastStep() {
        var previous = ToolbarCompaction.Level.full
        for window in stride(from: 1200.0, through: 960, by: -1) {
            let decision = ToolbarCompaction.decide(available: Self.inspectorOpen(window), controls: measured)
            #expect(decision.level >= previous, "\(window) pt")
            #expect(decision.titleWidth >= (decision.level < .wordsOnly ? 160 : 154), "\(window) pt")
            #expect(decision.fits)
            previous = decision.level
        }
    }

    /// The real numbers with the bundled fonts: at 1200 pt with the inspector open nothing compacts and the title
    /// truncates; at 960 pt (408 pt inside the toolbar's padding) all three steps and a 154 pt title.
    @MainActor @Test func measuredAt1200And960() throws {
        BundledFonts.register()
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let state = ShellPresenter.toolbar(for: try library.load("inspector-open"))
        let measured = ToolbarView.controlWidths(for: state)
        let title = Double(TextMeasure.width(state.title, role: .phraseTitle))
        let wide = ToolbarCompaction.decide(available: Self.inspectorOpen(1200), controls: measured)
        let narrow = ToolbarCompaction.decide(available: Self.inspectorOpen(960), controls: measured)
        print("[toolbar] inspector open: title ideal \(title); "
            + "Model \(measured.model) / words only \(measured.modelWordsOnly); You \(measured.you) / \(measured.youWordsOnly); "
            + "Record \(measured.record) / dot \(measured.recordDot); take menu \(measured.takeMenu) / chevron \(measured.takeMenuChevron); "
            + "toggle \(measured.inspectorToggle); gaps 8, 8, 17, 16 and 16 before the controls; "
            + "controls total full \(measured.total(.full)), chevron \(measured.total(.menuChevron)), dot \(measured.total(.recordDot)), "
            + "words only \(measured.total(.wordsOnly)); 1200 pt \(wide); 960 pt \(narrow)")
        #expect(wide.level == .full)
        #expect(wide.titleWidth >= ToolbarCompaction.titleMinimum)
        #expect(wide.titleWidth < title, "the title truncates at 1200 pt with the inspector open")
        #expect(narrow.level == .wordsOnly)
        #expect(narrow.fits)
        #expect(abs(narrow.titleWidth - 154) < 1)
    }
}
