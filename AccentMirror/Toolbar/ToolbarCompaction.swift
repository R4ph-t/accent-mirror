import Foundation

/// How far the toolbar's controls compact on a narrow detail pane (Addendum r4 C7). Pure: the available width,
/// the title's natural width and the controls' widths in, the compaction level out. UI-free, so it is tested
/// without a window; `ToolbarView` measures the widths and draws the level.
///
/// Order, each step only when the previous one doesn't fit next to the full-width title:
/// 1. the take menu becomes its chevron;
/// 2. Record becomes its Lime dot (40 pt);
/// then the title gives up its extra width, down to 160 pt;
/// 3. Model and You drop the play triangle and keep their words (8 pt side padding). They never become icon-only.
/// The gaps between controls never shrink. If even step 3 doesn't fit, the level is still step 3 and the title
/// gets what is left (`fits` is false): Designer gets the numbers rather than cramped gaps.
enum ToolbarCompaction {
    enum Level: Int, CaseIterable, Comparable, Sendable {
        case full, menuChevron, recordDot, wordsOnly
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// The title block never asks for less than this.
    static let titleMinimum: Double = 160
    /// Between the title block and the controls.
    static let titleGap: Double = 16

    /// Each control's width in its full and compact forms, and the fixed gaps between them (spec 18 Toolbar).
    struct ControlWidths: Equatable, Sendable {
        var model: Double
        var modelWordsOnly: Double
        var you: Double
        var youWordsOnly: Double
        var record: Double = 104
        var recordDot: Double = 40
        var takeMenu: Double
        var takeMenuChevron: Double = 28
        var inspectorToggle: Double = 28

        /// Model, Record and You.
        static let playbackSpacing: Double = 8
        /// Before the take menu.
        static let takeMenuGap: Double = 17
        /// Before the inspector toggle.
        static let toggleGap: Double = 16

        /// The whole controls group at a level, gaps included.
        func total(_ level: Level) -> Double {
            let words = level >= .wordsOnly
            return (words ? modelWordsOnly : model) + Self.playbackSpacing
                + (level >= .recordDot ? recordDot : record) + Self.playbackSpacing
                + (words ? youWordsOnly : you)
                + Self.takeMenuGap + (level >= .menuChevron ? takeMenuChevron : takeMenu)
                + Self.toggleGap + inspectorToggle
        }
    }

    struct Decision: Equatable, Sendable {
        var level: Level
        /// The width the title block gets.
        var titleWidth: Double
        /// False when even the most compact level leaves the title under 160 pt.
        var fits: Bool
    }

    /// `available` is the toolbar's width inside its 16 pt side padding. `titleIdeal` is the phrase title's
    /// natural width (the subtitle truncates first, so it doesn't count).
    static func decide(available: Double, titleIdeal: Double, controls: ControlWidths) -> Decision {
        let fullTitle = max(titleMinimum, titleIdeal)
        for level in [Level.full, .menuChevron, .recordDot]
        where controls.total(level) + titleGap + fullTitle <= available {
            return Decision(level: level, titleWidth: available - titleGap - controls.total(level), fits: true)
        }
        // The title gives up its extra width before Model and You change.
        if controls.total(.recordDot) + titleGap + titleMinimum <= available {
            return Decision(level: .recordDot, titleWidth: available - titleGap - controls.total(.recordDot), fits: true)
        }
        let titleWidth = available - titleGap - controls.total(.wordsOnly)
        return Decision(level: .wordsOnly, titleWidth: titleWidth, fits: titleWidth >= titleMinimum)
    }
}
