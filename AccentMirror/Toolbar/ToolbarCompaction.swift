import Foundation

/// How far the toolbar's controls compact on a narrow detail pane (Designer addendum v3.7 K2, which wins over
/// v3.6 J2 and over C7). Pure: the available width and the controls' widths in, the compaction level out.
/// UI-free, so it is tested without a window; `ToolbarView` measures the widths and draws the level.
///
/// Order (K2):
/// 0. the title truncates to its 154 pt floor before any control compacts. Nothing compacts at the default 1200 pt
///    window, including with the inspector open;
/// 1. Details goes icon-only (`sidebar.trailing`);
/// 2. the take menu becomes the count plus the chevron ("03" ▾);
/// 3. Model and You go words-only (the play triangles drop, the labels stay). This comes before anything that
///    would remove Record's label. Record keeps "Record"; it never becomes a bare Lime dot.
/// Input stays a 28 pt icon at every level: it never goes to overflow, and is never hidden or reduced further.
/// The gaps between controls never shrink. If even the last step leaves the title under 154 pt, the level is still
/// the last step and the title gets what is left (`fits` is false). Below 1068 pt with the inspector open the
/// inspector auto-collapses instead (K3), so that case should not arise in a live window.
enum ToolbarCompaction {
    enum Level: Int, CaseIterable, Comparable, Sendable {
        case full, detailsIcon, takeCount, wordsOnly
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// The title's floor before any control compact (v3.7 K2). Also the floor after every step.
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
        var takeMenu: Double
        /// "03" plus the chevron (v3.6 J2 / v3.7 K2).
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

        /// The whole controls group at a level, gaps included. Record is the labelled 104 pt button at every level.
        func total(_ level: Level) -> Double {
            let words = level >= .wordsOnly
            return (words ? modelWordsOnly : model) + Self.playbackSpacing
                + record + Self.playbackSpacing
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
        for level in [Level.full, .detailsIcon, .takeCount]
        where controls.total(level) + titleGap + titleMinimum <= available {
            return Decision(level: level, titleWidth: available - titleGap - controls.total(level), fits: true)
        }
        let titleWidth = available - titleGap - controls.total(.wordsOnly)
        return Decision(level: .wordsOnly, titleWidth: titleWidth, fits: titleWidth >= titleMinimum)
    }
}
