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

    /// r4 C6 hide order: unstressed syllables first, then heard ("photograph", "+ so") and missing words; stressed,
    /// mistake (and target) labels never.
    @Test func syllableAndWordPrioritiesFollowTheHideOrder() {
        #expect(LabelLayout.syllablePriority(.lower, stressedBar: false) == .low)
        #expect(LabelLayout.syllablePriority(.heard, stressedBar: false) == .high)
        #expect(LabelLayout.missingWordPriority == .high)
        #expect(LabelLayout.syllablePriority(.caps, stressedBar: true) == .always)
        #expect(LabelLayout.syllablePriority(.caps, stressedBar: false) == .always)
        #expect(LabelLayout.syllablePriority(.mistake, stressedBar: true) == .always)
        // A lowercase label on a bar measured as stressed is still stressed.
        #expect(LabelLayout.syllablePriority(.lower, stressedBar: true) == .always)
        #expect(LabelLayout.wordPriority(isTarget: true) == .always)
        #expect(LabelLayout.wordPriority(isTarget: false) == .low)
    }

    /// The hide order end to end on one crowded row: an unstressed syllable, a heard word, a missing word and a
    /// stressed syllable all collide. Only the stressed one and the first higher-priority label (left to right) show.
    @Test func crowdedRowHidesInTheR4Order() {
        let items = [
            Item(center: 10, width: 20, priority: LabelLayout.syllablePriority(.lower, stressedBar: false)),
            Item(center: 26, width: 20, priority: LabelLayout.syllablePriority(.heard, stressedBar: false)),
            Item(center: 50, width: 20, priority: LabelLayout.missingWordPriority),
            Item(center: 66, width: 20, priority: LabelLayout.syllablePriority(.caps, stressedBar: true)),
        ]
        #expect(LabelLayout.visibility(items) == [false, true, false, true])
    }

    @MainActor @Test func targetWordsCarryAStressOrAreNamedInCardOne() throws {
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        let pitch = ShellPresenter.pitch(try library.load("result-feedback"))
        let targets = pitch.words.filter(\.isTarget).map { ShellPresenter.normalizedWord($0.text) }
        // Stressed: photography, harder, looks. "than" is named as a whole word in "ra, phy, der, than".
        #expect(targets == ["photography", "harder", "than", "looks"])
    }

    /// r5 D3: "than" has no rule of its own. It is a target word only in a take where a card-1 diff row or the
    /// card-1 sentence names it (the reduction row "ra, phy, than."); everywhere else it is an unstressed,
    /// non-target word label and hides first in a collision.
    @MainActor @Test(.disabled("Spec 28: card 1 shows no rows and no verdict copy (show-don't-judge v1); spec 29 rewrites this for v3")) func thanIsATargetOnlyWhereCardOneNamesIt() throws {
        let library = try #require(FixtureLibrary(bundle: Bundle(for: ShellModel.self)))
        var named = 0, unnamed = 0
        for name in try library.allNames() {
            let loaded = try library.load(name)
            guard loaded.phrase.words.contains(where: { ShellPresenter.normalizedWord($0.text) == "than" }) else { continue }
            let verdict = loaded.fixture.analysis?.verdict
            let rows = verdict?.kind == .feedback ? ShellPresenter.orderedRows(verdict?.rows ?? []) : []
            let cardOneNames = rows.flatMap { ($0.word.map { [$0] } ?? []) + ($0.targets ?? []) }
                + (verdict?.inconclusive?.words ?? [])
            let isNamed = cardOneNames.map(ShellPresenter.normalizedWord).contains("than")
            let than = try #require(ShellPresenter.pitch(loaded).words.first { ShellPresenter.normalizedWord($0.text) == "than" })
            #expect(than.isTarget == isNamed, "\(name)")
            #expect(LabelLayout.wordPriority(isTarget: than.isTarget) == (isNamed ? .always : .low), "\(name)")
            if isNamed { named += 1 } else { unnamed += 1 }
        }
        // Both cases occur: result-feedback and feedback-too-much-contrast-last name it; rows-too-much-contrast doesn't.
        #expect(named >= 2 && unnamed >= 2)
        let tooMuch = try library.load("rows-too-much-contrast")
        #expect(ShellPresenter.pitch(tooMuch).words.first { $0.text == "than" }?.isTarget == false)
        let last = try library.load("feedback-too-much-contrast-last")
        #expect(ShellPresenter.pitch(last).words.first { $0.text == "than" }?.isTarget == true)
    }

    @MainActor @Test func namedTargetWordsComeFromRowsTheSentenceAndTheManifest() {
        let phrase = ["Photography", "is", "harder", "than", "it", "looks."]
        // A row's word, and a row target that is a whole word; a syllable (HAR) names no word.
        let rows = [DiffRow(kind: .placement, word: "photography"), DiffRow(kind: .contrast, targets: ["HAR", "LOOKS"])]
        #expect(ShellPresenter.namedTargetWords(rows: rows, sentenceWords: [], manifestTargets: [], phraseWords: phrase)
            == ["photography", "looks"])
        // Words the card-1 sentence names (targetWordsMissing).
        #expect(ShellPresenter.namedTargetWords(rows: [], sentenceWords: ["is"], manifestTargets: [], phraseWords: phrase)
            == ["is"])
        // Manifest targets add to the set, never replace it, and a stressed word stays a target without them.
        let named = ShellPresenter.namedTargetWords(rows: rows, sentenceWords: [], manifestTargets: ["it"], phraseWords: phrase)
        #expect(named == ["photography", "looks", "it"])
        let harder = NativeWord(text: "harder", stressCheck: nil, start: 0, end: 1, syllables: [
            Syllable(text: "har", start: 0, end: 0.5, prominence: 1, stressed: true, label: .caps),
            Syllable(text: "der", start: 0.5, end: 1, prominence: 0.2, stressed: false, label: .lower),
        ])
        #expect(ShellPresenter.isTargetWord(harder, named: named))
        let than = NativeWord(text: "than", stressCheck: nil, start: 0, end: 1, syllables: [
            Syllable(text: "than", start: 0, end: 1, prominence: 0.2, stressed: false, label: .lower),
        ])
        #expect(!ShellPresenter.isTargetWord(than, named: named))
        #expect(ShellPresenter.isTargetWord(than, named: ["than"]))
    }
}
