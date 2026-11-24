import Foundation

/// How far the toolbar's controls compact on a narrow detail pane (Addendum r4 C7, r5 D1). Pure: the available
/// width, the title's natural width and the controls' widths in, the compaction level out. UI-free, so it is tested
/// without a window; `ToolbarView` measures the widths and draws the level.
///
/// Order (r5 D1 wins over r4 C7):
/// 0. the title gives up its extra width, down to 160 pt, before any control compacts (at the default 1200 pt
///    window with the inspector open the take menu keeps "TAKE 03" and the title truncates);
/// 1. the take menu becomes its chevron;
/// 2. Record becomes its Lime dot (40 pt);
/// 3. Model and You drop the play triangle and keep their words (8 pt side padding). They never become icon-only.
/// Only after step 3 may the title go below 160 pt, down to 154 pt (960 pt with the inspector open). The gaps
/// between controls never shrink. If even step 3 leaves the title under 154 pt, the level is still step 3 and the
/// title gets what is left (`fits` is false): Designer gets the numbers rather than cramped gaps.
enum ToolbarCompaction {
    enum Level: Int, CaseIterable, Comparable, Sendable {
        case full, menuChevron, recordDot, wordsOnly
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// The title block never gets less than this while any control could still compact.
    static let titleMinimum: Double = 160
    /// The title's floor once all three steps are taken (r5 D1: 154 pt at 960 pt with the inspector open).
    static let titleMinimumCompact: Double = 154
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
        /// False when even the most compact level leaves the title under 154 pt.
        var fits: Bool
    }

    /// `available` is the toolbar's width inside its 16 pt side padding. The title's natural width doesn't take
    /// part (r5 D1): the title block gets everything the controls leave and truncates below its natural width,
    /// the subtitle first, with the full title in the tooltip and for VoiceOver.
    static func decide(available: Double, controls: ControlWidths) -> Decision {
        for level in [Level.full, .menuChevron, .recordDot]
        where controls.total(level) + titleGap + titleMinimum <= available {
            return Decision(level: level, titleWidth: available - titleGap - controls.total(level), fits: true)
        }
        let titleWidth = available - titleGap - controls.total(.wordsOnly)
        return Decision(level: .wordsOnly, titleWidth: titleWidth, fits: titleWidth >= titleMinimumCompact)
    }
}
