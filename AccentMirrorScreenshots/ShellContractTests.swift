import SwiftUI
import Testing
@testable import AccentMirror

/// Behaviour checks for the fixture-driven shell that need the app target (so they run locally with
/// `make screenshots`, not in CI): every fixture decodes, the copy matches the written spec, and the tokens meet
/// the contrast guardrails.
@MainActor
@Suite("Shell contract")
struct ShellContractTests {
    let library = FixtureLibrary(bundle: Bundle(for: ShellModel.self))!

    private func card(_ name: String) throws -> CardPresentation {
        ShellPresenter.card(try library.load(name))
    }

    private func sentences(_ name: String) throws -> [String] {
        try card(name).rows.map(\.sentence.plain)
    }

    @Test func everyFixtureDecodes() throws {
        let names = try library.allNames()
        #expect(names.count >= 53)
        for name in names { _ = try library.load(name) }
    }

    @Test func primaryStates() throws {
        #expect(try sentences("empty") == ["Listen to the model, then press Space to record your take."])
        #expect(try sentences("recording") == ["Recording. Press Space when you\u{2019}re done."])
        #expect(try sentences("result-feedback") == [
            "Stress TOG, not PHO: phoTOGraphy.",
            "Make HAR and LOOKS stronger. Right now they sound like the syllables around them.",
            "Keep the small syllables short and light: ra, phy, der, than.",
        ])
        let quiet = try card("tooQuiet")
        #expect(quiet.title == "YOUR TAKE")
        #expect(quiet.rows.first?.iconIsMistake == true)
        #expect(ShellPresenter.toolbar(for: try library.load("tooQuiet")).takeMenu == .lastTryNotSaved)
        #expect(ShellPresenter.toolbar(for: try library.load("tooQuiet")).youEnabled)
    }

    @Test func recordingToolbar() throws {
        let toolbar = ShellPresenter.toolbar(for: try library.load("recording"))
        #expect(toolbar.record == .stop)
        #expect(!toolbar.modelEnabled && !toolbar.youEnabled)
        #expect(toolbar.subtitle == .recording(elapsed: "0:02"))
    }

    @Test func closeNamesOnlyEvaluatedDimensions() throws {
        #expect(try sentences("close-all") == ["Close to the model. Stress, rhythm and pitch shape all match."])
        #expect(try sentences("close-stress-rhythm") == ["Close to the model. Stress and rhythm match."])
        #expect(try sentences("close-placement-only") == ["Close to the model. Stress is in the right place."])
        #expect(try card("close-placement-only").infoLines.map(\.plain) == [
            "This phrase gets stress placement feedback only: one word with two syllables has nothing else to compare.",
        ])
    }

    @Test func onlyTheMostSpecificQuietLineShows() throws {
        #expect(try card("feedback-quiet-priority").infoLines.map(\.plain) == [
            "You added \u{201C}so\u{201D}. It's left out of the comparison.",
        ])
        #expect(try card("feedback-two-insertions").infoLines.map(\.plain) == ["You added \u{201C}so\u{201D} and \u{201C}really\u{201D}."])
        #expect(try card("feedback-partial").infoLines.map(\.plain) == ["Feedback covers 6 of 8 words."])
        let notes = ShellPresenter.inspector(try library.load("feedback-quiet-priority")).first { $0.title == "NOTES" }
        #expect(notes?.lines.count == 3)
    }

    @Test func roughTimingComesFirstAndRowsCapAtThree() throws {
        let rows = try sentences("rough-timing-first")
        #expect(rows.count == 3)
        #expect(rows.first == "The timing match for this take is rough, so syllable lengths may be off.")
    }

    @Test func inconclusiveAndNoClearDifferenceCopy() throws {
        #expect(try sentences("inc-comparableCoverageLow") == [
            "Only part of your take lined up with the model (about 55%). Say the whole phrase in one go.",
        ])
        #expect(try card("inc-noApplicableStressMeasure").rows.first?.trailing == CardRow.Trailing.none)
        #expect(try sentences("ncd-mediumConfidenceOnly") == ["Nothing stood out clearly enough to point at. Try another take to check."])
        #expect(try card("ncd-pitchShapeBelowClose").title == "WHAT TO CHANGE")
    }

    @Test func bannersAreAboveTheCardsAndNeverWithATakeProblem() throws {
        let saveFailed = try library.load("op-saveFailed")
        #expect(ShellPresenter.banner(saveFailed.fixture)?.button == "Try Again Saving")
        let both = try library.load("op-error-wins-over-saveFailed")
        #expect(ShellPresenter.banner(both.fixture)?.sentence == "Accent Mirror couldn't read its copy of this native recording.")
        #expect(ShellPresenter.banner(try library.load("op-savedPruneFailed").fixture) == nil)
        #expect(ShellPresenter.banner(try library.load("cancelled").fixture) == nil)
        #expect(ShellPresenter.banner(try library.load("op-inferenceFailed").fixture)?.sentence ==
            "Something went wrong inside Accent Mirror while measuring stress. This isn't about your take.")
    }

    @Test func placementNamesTheNearestVoiceAndNeverSaysWrong() throws {
        #expect(try sentences("stress-like-p311").first == "Stress TOG, not PHO: phoTOGraphy, like p311 says it.")
        for name in try library.allNames() {
            let text = try card(name).rows.map(\.sentence.plain).joined(separator: " ")
            #expect(!text.lowercased().contains("wrong"), "\(name)")
        }
    }

    @Test func comingSoonIsDrivenByAnEmptyPack() {
        #expect(LibraryManifest.stub.packs.filter(\.isComingSoon).map(\.id) == ["noun-verb-pairs"])
    }

    // MARK: Contrast guardrails (spec 18)

    private func luminance(_ color: Color) -> Double {
        let r = color.resolve(in: EnvironmentValues())
        // Color.Resolved components are linear sRGB.
        return 0.2126 * Double(r.linearRed) + 0.7152 * Double(r.linearGreen) + 0.0722 * Double(r.linearBlue)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test(arguments: [Palette.light, Palette.dark])
    func textMeetsContrast(_ p: Palette) {
        for surface in [p.surfaceBase, p.surfaceCard, p.surfaceSidebar] {
            #expect(contrast(p.textPrimary, surface) >= 4.5)
            #expect(contrast(p.textSecondary, surface) >= 4.5)
        }
        #expect(contrast(p.limeText, p.surfaceCard) >= 4.5)
        #expect(contrast(p.limeText, p.surfaceBase) >= 4.5)
        #expect(contrast(p.limeSidebarText, p.surfaceSidebar) >= 4.5)
        #expect(contrast(p.onLime, p.buttonA) >= 4.5)
        #expect(contrast(p.onLime, p.buttonB) >= 4.5)
        #expect(contrast(p.mistake, p.surfaceCard) >= 4.5)
    }

    @Test func increaseContrastHidesGrainAndStepsText() {
        let p = Palette.resolve(.light, increaseContrast: true, reduceTransparency: false)
        #expect(!p.showsGrain && !p.showsPitchTexture && p.hairlineIsThick)
        #expect(p.textTertiary == Palette.light.textSecondary)
        #expect(!Palette.resolve(.dark, increaseContrast: false, reduceTransparency: true).showsGrain)
    }
}
