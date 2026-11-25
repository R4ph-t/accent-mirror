import Foundation
import Testing
@testable import AccentMirror

/// Designer addendum v5 §3–4 through the shell model (app-hosted: the test VM runs it, never the host or CI). The
/// presenter's rules are tested unhosted in `AccentMirrorTests/AddendumV5Tests`.
@MainActor
@Suite("Addendum v5 contract")
struct AddendumV5ContractTests {
    let library = FixtureLibrary(bundle: Bundle(for: ShellModel.self))!

    private func model(_ name: String) throws -> ShellModel {
        ShellModel(fixture: try library.load(name))
    }

    @Test func theDisclosureStartsCollapsedAndFixturesCanExpandIt() throws {
        #expect(try !model("sounds-flags").rhythmExpanded)
        #expect(try model("sounds-expanded").rhythmExpanded)
        #expect(try model("label-hover").rhythmExpanded, "chart states keep their charts on screen")
    }

    @Test func aFixtureOpensItsWordPopover() throws {
        #expect(try model("sounds-popover").wordPopover == 0)
        #expect(try model("sounds-flags").wordPopover == nil)
    }

    @Test func arrowsStepOverWordsThatArentChecked() throws {
        let shell = try model("sounds-zero-flags")
        shell.openWord(0)
        #expect(shell.wordPopover == nil, "Grok isn't in the dictionary: no popover")
        shell.openWord(1)
        shell.stepWord(by: -1)
        #expect(shell.wordPopover == 1)
        shell.stepWord(by: 1)
        #expect(shell.wordPopover == 2)
        shell.closeWordPopover()
        #expect(shell.wordPopover == nil)
    }

    @Test func spaceReplaysPlayBothUntilAnotherButtonIsPressed() throws {
        let shell = try model("sounds-popover")
        var played: [PlaybackSchedule] = []
        shell.onPlay = { played.append($0) }
        shell.replayWord()
        #expect(played.last?.steps.count == 3, "Play both before any button")
        #expect(shell.playingPhraseWord == 0)
        shell.playWord(0, .sound(0))
        shell.replayWord()
        #expect(played.count == 3)
        #expect(played[1] == played[2], "Space replays Play this sound")
    }

    @Test func aWordMissingFromYourTakeReplaysNative() throws {
        let shell = try model("sounds-popover-missing-word")
        #expect(shell.wordPopover == 3)
        #expect(!shell.canPlayWord(3, .you) && !shell.canPlayWord(3, .both) && shell.canPlayWord(3, .native))
        var played: [PlaybackSchedule] = []
        shell.onPlay = { played.append($0) }
        shell.replayWord()
        guard case .play(.model, _, _, _)? = played.last?.steps.first, played.last?.steps.count == 1 else {
            Issue.record("Native alone"); return
        }
    }

    @Test func aCardOneRowOpensItsWordInThePhrase() throws {
        let shell = try model("sounds-flags")
        guard case .flagged(let rows, _)? = shell.detail?.card.sounds else { Issue.record("no rows"); return }
        shell.openWord(rows[1].wordIndex)
        #expect(shell.wordPopover == 5)
    }
}
