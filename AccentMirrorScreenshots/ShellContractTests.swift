import CoreText
import SwiftUI
import Testing
@testable import AccentMirror

/// Behaviour checks for the fixture-driven shell that need the app target (app-hosted, so they run in the test VM with
/// `make test-ui-vm`, never on the host or in CI): every fixture decodes, the presenter shows v3/v3.1 (spec 29), the
/// copy matches the written spec, and the tokens meet the contrast guardrails. The UI-free rules are also tested
/// unhosted in `AccentMirrorTests`.
@MainActor
@Suite("Shell contract")
struct ShellContractTests {
    let library = FixtureLibrary(bundle: Bundle(for: ShellModel.self))!

    @Test func everyFixtureDecodes() throws {
        let names = try library.allNames()
        #expect(names.count >= 40)
        for name in names { _ = try library.load(name) }
    }

    @Test func recordingToolbar() throws {
        let toolbar = ShellPresenter.toolbar(for: try library.load("recording"))
        #expect(toolbar.record == .stop)
        #expect(!toolbar.modelEnabled && !toolbar.youEnabled)
        #expect(toolbar.subtitle == .recording(elapsed: "0:02"))
    }

    @Test func bannersAreAboveTheCardsAndNeverWithATakeProblem() throws {
        let saveFailed = try library.load("op-saveFailed")
        #expect(ShellPresenter.banner(saveFailed.fixture)?.button == "Try Again Saving")
        let both = try library.load("op-error-wins-over-saveFailed")
        #expect(ShellPresenter.banner(both.fixture)?.sentence == "Accent Mirror couldn't read its copy of this native recording.")
        #expect(ShellPresenter.banner(try library.load("op-savedPruneFailed").fixture) == nil)
        #expect(ShellPresenter.banner(try library.load("cancelled").fixture) == nil)
        #expect(ShellPresenter.banner(try library.load("op-inferenceFailed").fixture)?.sentence ==
            "Accent Mirror ran into a problem while measuring your syllables. This isn't about your take.")
    }

    /// Fixes 4 and 6 (§7.1, A7): a take problem with audio draws the take grouped by syllable, shaped and
    /// captioned by the problem, and the menu reads LAST TRY · NOT SAVED; without audio it's the placeholder.
    @Test func takeProblemsYourRowAndTakeMenu() throws {
        func you(_ name: String) throws -> StripPresentation.YouRow { ShellPresenter.strip(try library.load(name)).you }
        guard case .takeProblem(let quiet, .nearSilent, Copy.tooQuietToMeasure?) = try you("tooQuiet") else {
            Issue.record("tooQuiet"); return
        }
        #expect(quiet.count > 4 && quiet.allSatisfy { $0.label == nil && !$0.dot })
        guard case .takeProblem(_, .clipped, "Too loud to measure"?) = try you("tp-clipped") else {
            Issue.record("tp-clipped"); return
        }
        // Round 3, Designer answer 3: too short and words don't match get the too-quiet treatment and a caption.
        guard case .takeProblem(_, .nearSilent, "Words didn't match the phrase"?) = try you("tp-wordsDontMatch") else {
            Issue.record("tp-wordsDontMatch"); return
        }
        guard case .takeProblem(_, .nearSilent, "Too short to measure"?) = try you("tp-tooShort") else {
            Issue.record("tp-tooShort"); return
        }

        let problemNames = try library.allNames().filter { $0.hasPrefix("tp-") } + ["tooQuiet"]
        for name in problemNames {
            let loaded = try library.load(name)
            let toolbar = ShellPresenter.toolbar(for: loaded)
            if loaded.take?.hasAudio == true {
                #expect(toolbar.takeMenu == .lastTryNotSaved, "\(name)")
                #expect(toolbar.youEnabled, "\(name)")
            } else {
                #expect(toolbar.takeMenu == .take(3), "\(name)")
                #expect(!toolbar.youEnabled, "\(name)")
                guard case .placeholder = ShellPresenter.strip(loaded).you else { Issue.record("\(name)"); continue }
            }
        }
    }

    @Test func noVoicedFramesKeepsItsMessage() throws {
        #expect(ShellPresenter.pitch(try library.load("noVoicedFrames")).message == "No pitch to show for this take")
    }

    @Test(arguments: [
        (OperationalError.Stage.findingWords, "finding your words"),
        (.measuringPitch, "measuring your pitch"),
        (.measuringStress, "measuring your syllables"),
        (.comparing, "lining your take up with the model"),
    ])
    func inferenceFailedNamesTheStage(_ stage: OperationalError.Stage, _ words: String) {
        let sentence = Copy.inferenceFailed(stage)
        #expect(sentence == "Accent Mirror ran into a problem while \(words). This isn't about your take.")
        #expect(!sentence.contains("\u{2026}") && !sentence.contains("..."))
        let banner = Copy.banner(OperationalError(kind: .inferenceFailed, stage: stage))
        #expect(banner.sentence == sentence && banner.button == "Retry")
    }

    // MARK: Fonts

    /// The italics are the real bundled faces, not a slanted copy or a system fallback.
    @Test func italicFacesAreBundled() {
        BundledFonts.register(from: Bundle(for: ShellModel.self))
        for name in [BundledFonts.geistItalic] {
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            #expect(CTFontCopyPostScriptName(font) as String == name)
            #expect(CTFontGetSymbolicTraits(font).contains(.traitItalic), "\(name)")
        }
    }

    /// Designer answer 4 (round 3): no Geist Mono italic is bundled, and mono labels stay upright.
    @Test func noMonoItalicIsBundled() throws {
        let geist = try #require(BundledFonts.fontsDirectory(in: Bundle(for: ShellModel.self)))
            .appendingPathComponent("Geist", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: geist.path)
        #expect(!files.contains { $0.hasPrefix("GeistMono-Italic") })
        #expect(!BundledFonts.allPostScriptNames.contains { $0.hasPrefix("GeistMono") && $0.hasSuffix("Italic") })
        #expect(TypeRole.mono.italicFontName == TypeRole.mono.fontName)
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

    // MARK: - Spec 29: v3/v3.1 show-don't-judge

    @Test(arguments: ["result", "result-not-scored", "result-no-verdict", "result-one-native", "inspector-open"])
    func resultShowsYourTakeWithTheResultRowAndPlayBoth(_ name: String) throws {
        let card = ShellPresenter.card(try library.load(name))
        #expect(card.title == "YOUR TAKE")
        #expect(card.rows.count == 1)
        #expect(card.rows.first?.icon == .overlay)
        #expect(card.rows.first?.trailing == .playBoth)
        #expect(card.rows.first?.sentence.plain ==
                "Your take is drawn over the model\u{2019}s. Play them back to back, then try another take.")
    }

    @Test func onlyTheFirstQuietLineShows() throws {
        func line(_ name: String) throws -> String? { ShellPresenter.card(try library.load(name)).quietLine?.plain }
        #expect(try line("result") == nil)
        #expect(try line("result-timing-rough") == "The timing match is rough, so syllables may not line up exactly.")
        #expect(try line("result-coverage-low") ==
                "Only part of your take lined up with the model, so some of it isn\u{2019}t drawn.")
        #expect(try line("result-insertions") == "You added \u{201C}so\u{201D}. It isn\u{2019}t drawn on the pitch chart.")
        #expect(try line("result-two-insertions") == "You added \u{201C}so\u{201D} and \u{201C}really\u{201D}.")
    }

    @Test func tooQuietIconIsSecondaryAndCopyIsV3() throws {
        let quiet = ShellPresenter.card(try library.load("tooQuiet"))
        #expect(quiet.title == "YOUR TAKE")
        #expect(quiet.rows.first?.icon == .symbol("speaker.wave.1"))
        #expect(ShellPresenter.card(try library.load("tp-tooShort")).rows.first?.sentence.plain ==
                "That take was too short to line up with the model. Say the whole phrase.")
        #expect(ShellPresenter.card(try library.load("unalignable")).rows.first?.sentence.plain ==
                "This take was recorded for the old wording, so it can't be lined up with the new one.")
        #expect(ShellPresenter.banner(try library.load("op-modelUnavailable").fixture)?.sentence ==
                "Accent Mirror couldn't load its speech model, so this take can't be shown. This isn't about your take.")
    }

    /// v3.1 V2–V3: the dot and bold caps on native context-resolved primaries only; your row lowercase and plain.
    @Test func dotsOnTheNativeRowOnlyAndYourLabelsArePlain() throws {
        let strip = ShellPresenter.strip(try library.load("result"))
        #expect(strip.native.filter(\.dot).compactMap(\.label?.text) == ["TOG", "HAR", "LOOKS"])
        #expect(strip.native.allSatisfy { $0.dot == ($0.label?.style == .caps) })
        guard case .bars(let yours, _, true) = strip.you else { Issue.record("no bars"); return }
        #expect(yours.allSatisfy { !$0.dot && $0.label?.style == .yours && $0.label?.text == $0.label?.text.lowercased() })
        #expect(!strip.connectors.isEmpty)
    }

    @Test func ambiguousWordHasNoDotNoCapsAndItsTooltip() throws {
        let strip = ShellPresenter.strip(try library.load("words-expectedAmbiguous"))
        let harder = strip.native.filter { ["har", "der"].contains($0.label?.text) }
        #expect(harder.count == 2)
        #expect(harder.allSatisfy { !$0.dot && $0.label?.style == .lower && $0.tooltip == "This word can be said more than one way." })
    }

    @Test func substitutedAndMissingWords() throws {
        guard case .bars(let clusters, _, _) = ShellPresenter.strip(try library.load("words-substituted")).you else {
            Issue.record("words-substituted"); return
        }
        #expect(clusters.contains { $0.tooltip?.hasPrefix("Heard \u{201C}") == true && $0.tooltip?.hasSuffix("\u{201D} here.") == true })
        guard case .bars(_, let slots, _) = ShellPresenter.strip(try library.load("words-missing")).you else {
            Issue.record("words-missing"); return
        }
        #expect(!slots.isEmpty)
        #expect(Copy.missingTooltip == "Not in your take.")
    }

    @Test func earlierTakesFollowTheToggle() throws {
        let result = try library.load("result")
        #expect(ShellPresenter.pitch(result, showEarlierTakes: true).earlier.map(\.opacity) == [0.30, 0.20])
        #expect(ShellPresenter.pitch(result, showEarlierTakes: false).earlier.isEmpty)
        #expect(ShellPresenter.pitch(try library.load("result-earlier-takes-off"), showEarlierTakes: true).earlier.isEmpty)
        #expect(ShellPresenter.pitch(try library.load("tooQuiet")).earlier.isEmpty)
    }

    @Test func inspectorShowsThisTakeAlignmentAndModelRecording() throws {
        let inspector = ShellPresenter.inspector(try library.load("inspector-open"))
        #expect(inspector.measures.map(\.name) == ["Length", "Syllables per s", "Pitch range", "Rhythm (nPVI)", "Ends"])
        #expect(inspector.measuresNote == "Native range is the spread across the 8 native voices for this phrase.")
        #expect(inspector.alignment == "Clear")
        #expect(inspector.model?.title == "p225 \u{00B7} Southern England")
        #expect(ShellPresenter.inspector(try library.load("result-timing-rough")).alignment == "Rough")
        #expect(ShellPresenter.inspector(try library.load("tooQuiet")).measures.isEmpty)
    }

    @Test func playingBothFixtureFreezesThePlayheadInYourHalf() throws {
        let model = ShellModel(fixture: try library.load("playing-both"))
        guard case .playing(.you, _) = model.playbackPhase else { Issue.record("\(String(describing: model.playbackPhase))"); return }
        model.stopPlaying()
        #expect(model.playbackPhase == nil)
    }
}
