import Testing
@testable import AccentMirror

/// Designer addendum v3.5 through the presenter and the shell (app-hosted: the test VM runs it, never the host or
/// CI). The popover's rules and mic check are tested unhosted in `AccentMirrorTests/AddendumV35Tests`.
@MainActor
@Suite("Addendum v3.5 contract")
struct AddendumV35ContractTests {
    let library = FixtureLibrary(bundle: Bundle(for: ShellModel.self))!

    @Test func tierBIsTheFirstQuietLineWithInput() throws {
        let card = ShellPresenter.card(try library.load("result-clipped"))
        #expect(card.rows.first?.trailing == .playBoth)
        #expect(card.quietLine?.plain == "Your take clipped. Lower the input volume and try another take.")
        #expect(card.quietLineInput)
    }

    @Test func tierAKeepsTheTakeProblemWithInputThenTryAgain() throws {
        let loaded = try library.load("tp-clipped")
        let card = ShellPresenter.card(loaded)
        #expect(card.rows.first?.trailing == .inputThenButton("Try Again"))
        #expect(card.rows.first?.sentence.plain
                == "That take was too loud and distorted. Move back a little or lower the input level.")
        #expect(ShellPresenter.toolbar(for: loaded).takeMenu == .lastTryNotSaved, "not saved")
        guard case .takeProblem(_, let shape, let caption) = ShellPresenter.strip(loaded).you else {
            Issue.record("your row")
            return
        }
        #expect(shape == .clipped && caption == "Too loud to measure")
    }

    @Test func noOtherQuietLineOffersInput() throws {
        for name in try library.allNames() where name != "result-clipped" {
            #expect(!ShellPresenter.card(try library.load(name)).quietLineInput, "\(name)")
        }
    }

    @Test(arguments: ["input-popover", "input-popover-no-volume", "input-popover-too-loud"])
    func popoverFixturesOpenThePopover(_ name: String) throws {
        let model = ShellModel(fixture: try library.load(name))
        #expect(model.inputPopover != nil)
        model.apply(try library.load("result"))
        #expect(model.inputPopover == nil, "Samples ▸ to another state closes it")
    }

    @Test func popoverStaysPinnedInsideTheNarrowestDetailPane() {
        // 960 pt window, sidebar and inspector open: the detail pane is 440 pt wide.
        let pane = Metrics.minimumWindow.width - Metrics.sidebarWidth - Metrics.inspectorWidth
        #expect(pane - InputPopoverMetrics.trailing - InputPopoverMetrics.width >= Metrics.outer)
        #expect(InputPopoverMetrics.width == 300)
    }
}
