import Foundation
import Testing
@testable import AccentMirror

/// The label layout rule from fixes round 5: at least 4 pt between neighbouring labels that show; stressed syllables,
/// the mistake marker and target words always show; heard and missing-word labels give way after unstressed
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

    @MainActor @Test func targetWordsCarryAStressOrAreNamedByARow() throws {
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let pitch = ShellPresenter.pitch(try library.load("result-feedback"))
        let targets = pitch.words.filter(\.isTarget).map { ShellPresenter.normalizedWord($0.text) }
        #expect(targets == ["photography", "harder", "looks"])
    }
}
