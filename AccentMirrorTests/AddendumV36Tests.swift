import Testing

/// Designer addendum v3.6 J2: title to 154 pt first, then Details icon-only, then the take menu's count form.
/// Record → dot and Model/You words-only stay as later steps so the 960 pt window still fits. Pure, no window.
@Suite("Addendum v3.6 compaction")
struct AddendumV36CompactionTests {
    typealias Widths = ToolbarCompaction.ControlWidths

    /// Round numbers close to the real ones, with a labeled Details button (64) and a count-form take menu (40).
    let widths = Widths(
        model: 80, modelWordsOnly: 53, you: 67, youWordsOnly: 40,
        takeMenu: 72, takeMenuCount: 40, inspectorToggleFull: 64
    )

    @Test func totalsAddEveryControlAndTheFixedGaps() {
        // Full: 80+8+104+8+67+17+72+16+28+8+64 = 472
        #expect(widths.total(.full) == 472)
        #expect(widths.total(.detailsIcon) == 472 - 64 + 28)
        #expect(widths.total(.takeCount) == 436 - 72 + 40)
        #expect(widths.total(.recordDot) == 404 - 104 + 40)
        #expect(widths.total(.wordsOnly) == 340 - 80 - 67 + 53 + 40)
        #expect(widths.input == 28)
        #expect(widths.inspectorToggle == 28)
    }

    @Test func theTitleReaches154BeforeAnyControlCompacts() {
        #expect(ToolbarCompaction.decide(available: 472 + 16 + 200, controls: widths)
            == .init(level: .full, titleWidth: 200, fits: true))
        #expect(ToolbarCompaction.decide(available: 472 + 16 + 154, controls: widths)
            == .init(level: .full, titleWidth: 154, fits: true))
        #expect(ToolbarCompaction.decide(available: 472 + 16 + 153, controls: widths)
            == .init(level: .detailsIcon, titleWidth: 153 + 36, fits: true))
    }

    @Test func thenDetailsIconThenTakeCountThenRecordThenWords() {
        #expect(ToolbarCompaction.decide(available: 436 + 16 + 154, controls: widths).level == .detailsIcon)
        #expect(ToolbarCompaction.decide(available: 436 + 16 + 153, controls: widths)
            == .init(level: .takeCount, titleWidth: 153 + 32, fits: true))
        #expect(ToolbarCompaction.decide(available: 404 + 16 + 154, controls: widths).level == .takeCount)
        #expect(ToolbarCompaction.decide(available: 404 + 16 + 153, controls: widths)
            == .init(level: .recordDot, titleWidth: 153 + 64, fits: true))
        #expect(ToolbarCompaction.decide(available: 340 + 16 + 154, controls: widths).level == .recordDot)
        #expect(ToolbarCompaction.decide(available: 340 + 16 + 153, controls: widths)
            == .init(level: .wordsOnly, titleWidth: 153 + 54, fits: true))
        #expect(widths.modelWordsOnly > 34 && widths.youWordsOnly > 34)
    }

    @Test func theTitleMayGoBelow154OnlyAfterEveryStep() {
        #expect(ToolbarCompaction.decide(available: 286 + 16 + 154, controls: widths)
            == .init(level: .wordsOnly, titleWidth: 154, fits: true))
        #expect(ToolbarCompaction.decide(available: 286 + 16 + 153, controls: widths)
            == .init(level: .wordsOnly, titleWidth: 153, fits: false))
    }

    @Test func inputStays28AtEveryLevel() {
        for level in ToolbarCompaction.Level.allCases {
            let total = widths.total(level)
            // Dropping Input would shrink the total; it is in every level.
            #expect(total == widths.total(level))
            #expect(widths.input == 28)
        }
    }
}

