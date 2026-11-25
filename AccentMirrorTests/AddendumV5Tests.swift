import AMCore
import AMPipeline
import Foundation
import Testing

// Designer addendum v5 (sound flags and word playback) and the Designer's rulings of 2026-11-25. Unhosted: these
// read the committed fixtures and sources and run the presenter, so nothing opens a window.

private let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let library = FixtureLibrary(root: repo.appending(path: "AccentMirror/Resources/Fixtures", directoryHint: .isDirectory))

@MainActor private func card(_ name: String) throws -> CardPresentation { ShellPresenter.card(try library.load(name)) }
@MainActor private func phrase(_ name: String) throws -> PhrasePresentation { ShellPresenter.phrase(try library.load(name)) }

@MainActor
struct V5CardOneTests {
    nonisolated static let states = [
        "sounds-flags", "sounds-many-flags", "sounds-zero-flags", "sounds-popover", "sounds-popover-two-sounds",
        "sounds-popover-missing-word", "sounds-unavailable", "sounds-expanded",
    ]

    @Test(arguments: states)
    func soundStatesDecode(_ name: String) throws {
        #expect(try library.allNames().contains(name))
        #expect(try library.load(name).fixture.analysis?.sounds != nil)
    }

    @Test func flagsShowThreeRowsLeastConfidentFirst() throws {
        let card = try card("sounds-flags")
        #expect(card.title == "SOUNDS TO CHECK")
        guard case .flagged(let rows, let more) = card.sounds else { Issue.record("no flags"); return }
        #expect(rows.map(\.word) == ["Throughout", "explained", "various"])
        #expect(rows.map(\.expected.plain) == ["th as in think", "d as in dog", "v as in van"])
        #expect(rows.map(\.heardLine) == ["sounded closer to t as in tin", "sounded closer to t as in tin",
                                          "sounded closer to w as in wet"])
        #expect(more == 0)
    }

    @Test func manyFlagsCapAtThreeAndCountTheRest() throws {
        guard case .flagged(let rows, let more) = try card("sounds-many-flags").sounds else {
            Issue.record("no flags"); return
        }
        #expect(rows.map(\.word) == ["Throughout", "various", "explained"])
        #expect(more == 2)
        #expect(Copy.moreFlagged(more) == "+2 more highlighted in the phrase below")
    }

    @Test func zeroFlagsIsNeutralAndUnjudgedIsNeverCalledClean() throws {
        #expect(try card("sounds-zero-flags").sounds == .noneFlagged)
        #expect(try card("sounds-unavailable").sounds == .notChecked)
        #expect(try card("result").sounds == .notChecked, "a take saved before judging")
        #expect(Copy.soundsNotChecked != Copy.noSoundsToCheck)
        #expect(!Copy.soundsNotChecked.lowercased().contains("no sounds"))
    }

    @Test func nonResultStatesKeepYourTake() throws {
        for name in ["empty", "recording", "analysing", "tooQuiet", "tp-clipped", "unalignable"] {
            let card = try card(name)
            #expect(card.title == "YOUR TAKE", "\(name)")
            #expect(card.sounds == nil, "\(name)")
        }
        #expect(try card("empty").rows.first?.sentence.plain == "Press Record or Space to record your take.")
    }

    /// v5 §1.3: no spinner flash. A fixture draws the >400 ms frame; live analysis waits 400 ms before showing it.
    @Test func analysingShowsCheckingSoundsOnlyAfterTheDelayLive() throws {
        let loaded = try library.load("analysing")
        let fixture = ShellPresenter.card(loaded)
        #expect(fixture.rows.first?.icon == .progress)
        #expect(fixture.rows.first?.sentence.plain == "Checking sounds\u{2026}")
        #expect(fixture.revealAfter == nil)
        var live = loaded
        live.fixture.name = LivePresenter.fixtureName
        #expect(ShellPresenter.card(live).revealAfter == 0.4)
    }

    @Test func theClippedQuietLineStaysUnderTheSounds() throws {
        let card = try card("result-clipped")
        #expect(card.sounds != nil)
        #expect(card.quietLineInput)
    }
}

@MainActor
struct V5PhraseCardTests {
    @Test func flaggedWordsAreWholeWordsAndTheLegendNamesThem() throws {
        let phrase = try phrase("sounds-flags")
        #expect(phrase.words.filter { $0.kind == .flagged }.map(\.text) == ["Throughout", "explained", "various"])
        #expect(phrase.words.allSatisfy { $0.kind == .flagged || $0.kind == .checkable })
        #expect(phrase.legend == .flags)
    }

    @Test func notInDictionaryWordsAreGreyAndSkipped() throws {
        let phrase = try phrase("sounds-zero-flags")
        #expect(phrase.words.first?.kind == .notInDictionary)
        #expect(phrase.words.first?.isInteractive == false)
        #expect(phrase.legend == .notInDictionary)
        // ← from "explained" has nowhere to go: "Grok" isn't checkable.
        #expect(phrase.step(from: 1, by: -1) == nil)
        #expect(phrase.step(from: 1, by: 1) == 2)
    }

    @Test func aWordMissingFromYourTakeStaysNeutralButClickable() throws {
        let phrase = try phrase("sounds-popover-missing-word")
        let people = try #require(phrase.words.first { $0.text == "people" })
        #expect(people.kind == .checkable, "its flag isn't drawn")
        #expect(!people.heardInTake)
        #expect(people.hints.isEmpty)
    }

    @Test func thePopoverListsEveryFlaggedSoundInWordOrder() throws {
        let explained = try #require(try phrase("sounds-popover-two-sounds").words.first { $0.text == "explained" })
        #expect(explained.hints.map(\.expected.plain) == ["ay as in day", "d as in dog"])
        #expect(explained.hints.map(\.heardLine) == ["sounded unclear", "sounded unclear"])
    }

    @Test func withoutJudgingEveryWordStillPlaysAndNoneIsFlagged() throws {
        let unavailable = try phrase("sounds-unavailable")
        #expect(unavailable.words.allSatisfy { $0.kind == .checkable })
        #expect(unavailable.legend == .hint)
        #expect(try phrase("words-missing").words.contains { !$0.heardInTake })
    }

    @Test func beforeATakeTheWordsArePlain() throws {
        for name in ["empty", "recording", "tooQuiet"] {
            let phrase = try phrase(name)
            #expect(phrase.legend == .none, "\(name)")
            #expect(phrase.words.allSatisfy { !$0.isInteractive }, "\(name)")
        }
    }

    @Test func theHintReadsAsCorrected() {
        #expect(Copy.clickAnyWord == "Click any word to hear Native vs You")
    }
}

@MainActor
struct V5PlaybackTests {
    /// sounds-flags: model 3.6 s, you 3.9 s.
    @Test func nativePlaysTheModelWordAndYouIsPaddedThirtyMilliseconds() throws {
        let loaded = try library.load("sounds-flags")
        guard case .judged(let judgement) = loaded.fixture.analysis?.sounds else { Issue.record("not judged"); return }
        let native = try #require(ShellPresenter.wordSchedule(loaded, word: 0, action: .native))
        #expect(native.fadeSeconds == 0.01)
        #expect(!native.repeats)
        guard case .play(.model, let seconds, let from, let to) = native.steps.first else {
            Issue.record("no model step"); return
        }
        let model = try #require(judgement.words[0].modelRange)
        #expect(abs(seconds - model.duration) < 1e-9, "the native word, unpadded")
        #expect(abs(from - model.start / 3.6) < 1e-9 && abs(to - model.end / 3.6) < 1e-9)

        // "the" sits between heard words with gaps wider than 30 ms, so it gains the full 30 ms each side.
        let you = try #require(ShellPresenter.wordSchedule(loaded, word: 1, action: .you))
        guard case .play(.you, let youSeconds, _, _) = you.steps.first else { Issue.record("no you step"); return }
        let heard = try #require(judgement.words[1].youRange)
        #expect(abs(youSeconds - (heard.duration + 0.06)) < 1e-9)
    }

    @Test func playBothIsNativeThreeHundredMillisecondsThenYou() throws {
        let both = try #require(ShellPresenter.wordSchedule(try library.load("sounds-flags"), word: 0, action: .both))
        #expect(both.steps.count == 3)
        #expect(both.steps[1] == .pause(seconds: 0.3))
        if case .play(.model, _, _, _) = both.steps[0] {} else { Issue.record("model first") }
        if case .play(.you, _, _, _) = both.steps[2] {} else { Issue.record("you last") }
    }

    @Test func playThisSoundPlaysYourTakeOnly() throws {
        let sound = try #require(ShellPresenter.wordSchedule(try library.load("sounds-flags"), word: 0, action: .sound(0)))
        #expect(sound.steps.count == 1)
        if case .play(.you, _, _, _) = sound.steps[0] {} else { Issue.record("your take only") }
    }

    @Test func aWordMissingFromYourTakePlaysNativeOnly() throws {
        let loaded = try library.load("sounds-popover-missing-word")
        #expect(ShellPresenter.wordSchedule(loaded, word: 3, action: .native) != nil)
        #expect(ShellPresenter.wordSchedule(loaded, word: 3, action: .you) == nil)
        #expect(ShellPresenter.wordSchedule(loaded, word: 3, action: .both) == nil)
        #expect(ShellPresenter.wordSchedule(loaded, word: 3, action: .sound(0)) == nil)
        #expect(Copy.wordNotHeard == "This word wasn\u{2019}t heard in your take")
    }

    @Test func theFadeRampsBothEnds() {
        var chunk = [Float](repeating: 1, count: 1000)
        AudioPlayback.fade(&chunk, seconds: 0.01, rate: 16_000)
        #expect(chunk[0] == 0 && chunk[999] == 0)
        #expect(chunk[80] == 0.5)
        #expect(chunk[160] == 1 && chunk[500] == 1)
    }

    @Test func aFadeLongerThanTheChunkMeetsInTheMiddle() {
        var chunk = [Float](repeating: 1, count: 10)
        AudioPlayback.fade(&chunk, seconds: 0.01, rate: 16_000)
        #expect(chunk.allSatisfy { $0 < 1 })
    }

    @Test func theRenderedSegmentIsTheWordAndFaded() {
        // A 1 s clip whose timeline is 0…1 s; play 0.5…0.6 s with the fade.
        let clip = AudioClip(samples: [Float](repeating: 1, count: 16_000))
        let schedule = PlaybackSchedule.segment(.you, (from: 0.5, to: 0.6, seconds: 0.1))
        let samples = AudioPlayback.render(schedule, model: nil, you: clip)
        #expect(samples.count == 1600)
        #expect(samples.first == 0 && samples.last == 0)
        #expect(samples[800] == 1)
    }
}

/// v5's guards on top of `BannedWordTests`: the sound wording never grades, confidence never reaches a view, and the
/// one underline in the app is the flagged word's.
struct V5GuardTests {
    /// v5 §1.1's list covers the sound wording: the v5 views, the plain-English labels, and Copy's v5 sections. (Log
    /// lines and the save notice, "the save failed", describe the app, not your take.)
    @Test func noV5StringGradesExceptTheCaveat() throws {
        let banned = ["wrong", "error", "mistake", "bad", "fail", "grade", "score"]
        let views = ["SoundsToCheckCard.swift", "PhraseCard.swift", "WordPopover.swift", "RhythmPitchDisclosure.swift"]
        var texts = try BannedWordTests.sources().filter { views.contains($0.lastPathComponent) }
            .map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(texts.count == views.count)
        let copy = try String(contentsOf: repo.appending(path: "AccentMirror/Fixtures/Copy.swift"), encoding: .utf8)
        let v5 = try #require(copy.range(of: "// MARK: Sounds to check (v5 §1)"))
        let end = try #require(copy.range(of: "// MARK: Result (v3 §3.1)"))
        texts.append(String(copy[v5.lowerBound..<end.lowerBound]))
        texts.append(try String(contentsOf: repo.appending(path: "Packages/AccentKit/Sources/AMPipeline/SoundPresentation.swift"),
                                encoding: .utf8))
        for text in texts {
            for literal in BannedWordTests.literals(text) where literal != Copy.flagsAreHints {
                let lower = literal.lowercased()
                for word in banned {
                    #expect(lower.firstMatch(of: try Regex("\\b\(word)")) == nil, "\"\(literal)\" uses \"\(word)\"")
                }
            }
        }
        #expect(Copy.flagsAreHints == "Flags are hints, not a grade.")
    }

    @Test func confidenceNeverReachesTheApp() throws {
        for file in try BannedWordTests.sources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains(".confidence") && !text.contains(".gop"), "\(file.lastPathComponent)")
        }
    }

    @Test func onlyThePhraseCardDrawsTheFlagUnderline() throws {
        for file in try BannedWordTests.sources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let draws = text.contains("flagUnderline(")
            #expect(draws == (file.lastPathComponent == "PhraseCard.swift"), "\(file.lastPathComponent)")
        }
    }

    @Test func noRawPhoneCodeOrIPAInVisibleCopy() throws {
        let copy = try String(contentsOf: repo.appending(path: "AccentMirror/Fixtures/Copy.swift"), encoding: .utf8)
        #expect(!copy.contains("/θ/") && !copy.contains("ARPAbet"))
    }
}
