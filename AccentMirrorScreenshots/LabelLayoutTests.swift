import Foundation
import Testing
@testable import AccentMirror

/// The label layout rule from fixes round 5: at least 4 pt between neighbouring labels that show; stressed syllables,
/// dotted native caps and target words always show; heard and missing-word labels give way after unstressed
/// syllables and non-target words. Pure, so these need no window (they run with the screenshot scheme only because
/// the function lives in the app target).
@Suite("Label layout")
struct LabelLayoutTests {
    typealias Item = LabelLayout.Item

    @Test func nothingCollidesSoEveryLabelShows() {
        let items = [
            Item(center: 20, width: 24, priority: .low),
            Item(center: 60, width: 30, priority: .always),
            Item(center: 100, width: 20, priority: .low),
            Item(center: 140, width: 40, priority: .high),
        ]
        #expect(LabelLayout.visibility(items) == [true, true, true, true])
    }

    /// "der than it" from the Designer's narrow-window crop: three unstressed labels with no room between them.
    @Test func collidingUnstressedLabelsKeepFourPointsBetweenThoseThatShow() {
        let items = [
            Item(center: 100, width: 20, priority: .low), // der
            Item(center: 122, width: 26, priority: .low), // than
            Item(center: 142, width: 10, priority: .low), // it
        ]
        let shown = LabelLayout.visibility(items)
        #expect(shown == [true, false, true])
        let visible = items.indices.filter { shown[$0] }.map { items[$0] }
        for (a, b) in zip(visible, visible.dropFirst()) {
            #expect((b.center - b.width / 2) - (a.center + a.width / 2) >= LabelLayout.minimumGap)
        }
    }

    @Test func exactlyFourPointsApartIsEnoughButLessIsNot() {
        let apart = [Item(center: 10, width: 20, priority: .low), Item(center: 34, width: 20, priority: .low)]
        #expect(LabelLayout.visibility(apart) == [true, true])
        let closer = [Item(center: 10, width: 20, priority: .low), Item(center: 33.5, width: 20, priority: .low)]
        #expect(LabelLayout.visibility(closer) == [true, false])
    }

    @Test(arguments: [LabelLayout.Priority.low, .high])
    func stressedAndTargetLabelsAlwaysShow(_ other: LabelLayout.Priority) {
        // The always label is on the right, so a left-to-right pass would otherwise keep its neighbour.
        let items = [Item(center: 50, width: 30, priority: other), Item(center: 60, width: 30, priority: .always)]
        #expect(LabelLayout.visibility(items) == [false, true])
    }

    @Test func alwaysLabelsShowEvenWhenTheyTouchEachOther() {
        let items = [Item(center: 50, width: 40, priority: .always), Item(center: 60, width: 40, priority: .always)]
        #expect(LabelLayout.visibility(items) == [true, true])
    }

    @Test func heardAndMissingLabelsWinOverUnstressedOnes() {
        // The low label comes first from the left, but the high one is placed first.
        let items = [
            Item(center: 40, width: 30, priority: .low),
            Item(center: 60, width: 30, priority: .high),
            Item(center: 100, width: 20, priority: .low),
        ]
        #expect(LabelLayout.visibility(items) == [false, true, true])
    }

    @Test func priorityOrderIsAlwaysThenHighThenLow() {
        // A low label between a high and an always label that both fit gives way; one far away still shows.
        let items = [
            Item(center: 0, width: 30, priority: .high),
            Item(center: 30, width: 26, priority: .low),
            Item(center: 60, width: 30, priority: .always),
            Item(center: 200, width: 20, priority: .low),
        ]
        #expect(LabelLayout.visibility(items) == [true, false, true, true])
        #expect(LabelLayout.Priority.allCases == [.always, .high, .low])
    }

    /// r4 C6 hide order (v3.1): plain syllables first (yours included), then heard ("photograph", "+ so") and missing
    /// words; dotted caps and target words never.
    @Test func syllableAndWordPrioritiesFollowTheHideOrder() {
        #expect(LabelLayout.syllablePriority(.lower) == .low)
        #expect(LabelLayout.syllablePriority(.yours) == .low)
        #expect(LabelLayout.syllablePriority(.heard) == .high)
        #expect(LabelLayout.missingWordPriority == .high)
        #expect(LabelLayout.syllablePriority(.caps) == .always)
        #expect(LabelLayout.wordPriority(isTarget: true) == .always)
        #expect(LabelLayout.wordPriority(isTarget: false) == .low)
    }

    /// The hide order end to end on one crowded row: a plain syllable, a heard word, a missing word and a dotted
    /// syllable all collide. Only the dotted one and the first higher-priority label (left to right) show.
    @Test func crowdedRowHidesInTheR4Order() {
        let items = [
            Item(center: 10, width: 20, priority: LabelLayout.syllablePriority(.lower)),
            Item(center: 26, width: 20, priority: LabelLayout.syllablePriority(.heard)),
            Item(center: 50, width: 20, priority: LabelLayout.missingWordPriority),
            Item(center: 66, width: 20, priority: LabelLayout.syllablePriority(.caps)),
        ]
        #expect(LabelLayout.visibility(items) == [false, true, false, true])
    }

    /// Target words under the pitch plot: a word with a dictionary-stressed (dotted) syllable, or one the manifest
    /// names. Nothing else ("than" is no longer named by a card-1 row: v1 has none).
    @MainActor @Test func targetWordsCarryDictionaryStressOrAreNamedInTheManifest() throws {
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let pitch = ShellPresenter.pitch(try library.load("result"))
        let targets = pitch.words.filter(\.isTarget).map { ShellPresenter.normalizedWord($0.text) }
        #expect(targets == ["photography", "harder", "looks"])
        let harder = NativeWord(text: "harder", stressCheck: nil, expectedStress: [.primary, .unstressed], start: 0, end: 1,
                                syllables: [Syllable(text: "har", start: 0, end: 0.5, prominence: 1),
                                            Syllable(text: "der", start: 0.5, end: 1, prominence: 0.2)])
        #expect(ShellPresenter.isTargetWord(harder, named: []))
        let than = NativeWord(text: "than", stressCheck: nil, expectedStress: [.unstressed], start: 0, end: 1,
                              syllables: [Syllable(text: "than", start: 0, end: 1, prominence: 0.2)])
        #expect(!ShellPresenter.isTargetWord(than, named: []))
        #expect(ShellPresenter.isTargetWord(than, named: ["than"]))
    }

    @Test func placeClampsEdgeLabelsInsideLaneAndNudgesMinorOverlapWithoutDropping() {
        // Mirrors "through" + "OUT" + "the" at the start of vctk-012: "through" would overhang x=0 and graze "OUT".
        let items = [
            Item(center: 20, width: 45, priority: .low),    // through
            Item(center: 55, width: 26, priority: .always), // OUT
            Item(center: 77, width: 19, priority: .low),    // the
            Item(center: 112, width: 25, priority: .always),// CEN
        ]
        let placed = LabelLayout.place(items, within: 400)
        #expect(placed.allSatisfy(\.shown))
        for (item, p) in zip(items, placed) {
            #expect(p.center - item.width / 2 >= -1e-6)
            #expect(p.center + item.width / 2 <= 400 + 1e-6)
        }
        for i in 1..<placed.count {
            let prevRight = placed[i - 1].center + items[i - 1].width / 2
            let nextLeft = placed[i].center - items[i].width / 2
            #expect(nextLeft - prevRight >= LabelLayout.minimumGap - 1e-6)
        }
    }

    @Test func placeFallsBackToPriorityHidingWhenTooNarrow() {
        let items = [
            Item(center: 100, width: 40, priority: .low),
            Item(center: 120, width: 40, priority: .high),
            Item(center: 140, width: 40, priority: .always),
        ]
        // Total required = 128 > lane width 110 -> clamps inside 0...110 and drops .low/.high per C6.
        let placed = LabelLayout.place(items, within: 110)
        #expect(placed.map(\.shown) == [false, false, true])
        #expect(placed[2].center + items[2].width / 2 <= 110 + 1e-6)
    }
}
