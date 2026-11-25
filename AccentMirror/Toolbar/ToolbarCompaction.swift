import Foundation

/// How far the toolbar's controls compact on a narrow detail pane (Designer addendum v3.6 J2, which wins over
/// r4 C7 and r5 D1's 160 pt first floor, and over v3.5 I2 where it disagrees). Pure: the available width and the
/// controls' widths in, the compaction level out. UI-free, so it is tested without a window; `ToolbarView` measures
/// the widths and draws the level.
///
/// Order (J2):
/// 0. the title truncates to its 154 pt floor before any control compacts. Nothing compacts at the default 1200 pt
///    window, including with the inspector open;
/// 1. Details goes icon-only (`sidebar.trailing`);
/// 2. the take menu becomes the count plus the chevron ("03" ▾), which replaces C7's chevron-only form;
/// 3. Record becomes its Lime dot (40 pt) and Model and You drop the play triangle — C7's later steps, kept so the
///    960 pt window with the inspector open still fits. Input stays a 28 pt icon at every level: it never goes to
///    overflow, and is never hidden or reduced further.
/// The gaps between controls never shrink. If even the last step leaves the title under 154 pt, the level is still
/// the last step and the title gets what is left (`fits` is false): Designer gets the numbers rather than cramped
/// gaps.
enum ToolbarCompaction {
    enum Level: Int, CaseIterable, Comparable, Sendable {
        case full, detailsIcon, takeCount, recordDot, wordsOnly
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// The title's floor before any control compact (v3.6 J2). Also the floor after every step.
    static let titleMinimum: Double = 154
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
        /// "03" plus the chevron (v3.6 J2). Replaces the 28 pt chevron-only form at this size.
        var takeMenuCount: Double
        /// The Input button (v3.5 I2 / v3.6 J1): a 28 pt icon at every level.
        var input: Double = 28
        /// The Details button's labeled form ("Details").
        var inspectorToggleFull: Double
        /// The Details button's icon-only form (`sidebar.trailing`, 28 pt).
        var inspectorToggle: Double = 28

        /// Model, Record and You.
        static let playbackSpacing: Double = 8
        /// Before the take menu.
        static let takeMenuGap: Double = 17
        /// After the take menu, before Input.
        static let toggleGap: Double = 16
        /// Between Input and the inspector toggle (the v3.5 mockup).
        static let inputGap: Double = 8

        /// The whole controls group at a level, gaps included.
        func total(_ level: Level) -> Double {
            let words = level >= .wordsOnly
            return (words ? modelWordsOnly : model) + Self.playbackSpacing
                + (level >= .recordDot ? recordDot : record) + Self.playbackSpacing
                + (words ? youWordsOnly : you)
                + Self.takeMenuGap + (level >= .takeCount ? takeMenuCount : takeMenu)
                + Self.toggleGap + input + Self.inputGap
                + (level >= .detailsIcon ? inspectorToggle : inspectorToggleFull)
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
    /// part: the title block gets everything the controls leave and truncates below its natural width, the
    /// subtitle first, with the full title in the tooltip and for VoiceOver.
    static func decide(available: Double, controls: ControlWidths) -> Decision {
        for level in [Level.full, .detailsIcon, .takeCount, .recordDot]
        where controls.total(level) + titleGap + titleMinimum <= available {
            return Decision(level: level, titleWidth: available - titleGap - controls.total(level), fits: true)
        }
        let titleWidth = available - titleGap - controls.total(.wordsOnly)
        return Decision(level: .wordsOnly, titleWidth: titleWidth, fits: titleWidth >= titleMinimum)
    }
}
