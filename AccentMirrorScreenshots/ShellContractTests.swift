import CoreText
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

    // MARK: Designer review of PR #4 (fixes 1, 2, 4, 6) and inferenceFailed copy

    /// Your strip labels that carry the mistake marker, as (word syllable text, upper-cased).
    private func markedSyllables(_ loaded: LoadedFixture) -> [String] {
        guard case .bars(let clusters, _, let showsLabels) = ShellPresenter.strip(loaded).you, showsLabels else { return [] }
        return clusters.compactMap { $0.label?.style == .mistake ? $0.label?.text : nil }
    }

    /// The syllable card 1 names after "not", when it shows a placement row.
    private func placementHeardSyllable(_ loaded: LoadedFixture) -> String? {
        guard let verdict = loaded.fixture.analysis?.verdict, verdict.kind == .feedback else { return nil }
        let row = ShellPresenter.orderedRows(verdict.rows ?? []).first { $0.kind == .placement }
        guard let row, let syllables = row.syllables, let heard = row.heardIndex else { return nil }
        return syllables[heard].uppercased()
    }

    /// §8, §13 item 5: the marker shows only with a placement row (stress outside the accepted set at high
    /// confidence), and only on the syllable named after "not". Checked on every fixture.
    @Test func mistakeMarkerOnlyWithAPlacementRow() throws {
        for name in try library.allNames() {
            let loaded = try library.load(name)
            let marked = markedSyllables(loaded)
            if let heard = placementHeardSyllable(loaded), loaded.take?.alignment == .aligned,
               ShellPresenter.firstTakeProblem(loaded) == nil {
                #expect(marked == [heard], "\(name)")
            } else {
                #expect(marked.isEmpty, "\(name) shows the mistake marker without a placement row")
            }
        }
    }

    /// The same rule on the fixture data itself, so a fixture never carries strip data from another state:
    /// a take drawn with labels has a `mistake` syllable only when its state has a placement row.
    @Test func fixtureDataMarksOnlyPlacementStates() throws {
        for name in try library.allNames() {
            let loaded = try library.load(name)
            guard case .bars(_, _, true) = ShellPresenter.strip(loaded).you, let take = loaded.take else { continue }
            let raw = take.words.flatMap(\.syllables).filter { $0.label == .mistake }.map { $0.text.uppercased() }
            #expect(raw == (placementHeardSyllable(loaded).map { [$0] } ?? []), "\(name)")
        }
    }

    @Test func inconclusiveAndNoClearDifferenceNeverShowTheMarker() throws {
        for name in try library.allNames() where name.hasPrefix("inc-") || name.hasPrefix("ncd-") {
            #expect(markedSyllables(try library.load(name)).isEmpty, "\(name)")
        }
        // Low confidence: no Lime peak in photography either (the stress wasn't clear).
        let low = try library.load("inc-requiredMeasureUnavailable-lowConfidence")
        guard case .bars(let clusters, _, _) = ShellPresenter.strip(low).you else { Issue.record("no bars"); return }
        #expect(clusters.prefix(4).allSatisfy { $0.fill != .stressed })
    }

    /// Fix 2: every noClearDifference result has its equal.circle row first; quiet lines sit under it.
    @Test func noClearDifferenceAlwaysHasItsRow() throws {
        for name in try library.allNames() where name.hasPrefix("ncd-") {
            let card = try card(name)
            #expect(card.rows.count == 1, "\(name)")
            #expect(card.rows.first?.icon == "equal.circle", "\(name)")
            #expect(card.rows.first?.iconIsMistake == false, "\(name)")
        }
        let insertions = try card("ncd-insertionsPresent")
        #expect(insertions.rows.map(\.sentence.plain) == ["No clear difference in stress or rhythm."])
        #expect(insertions.infoLines.map(\.plain) == ["You added \u{201C}so\u{201D}. It's left out of the comparison."])
        #expect(insertions.infoLines.first?.contains { $0.role == .heard && $0.text == "\u{201C}so\u{201D}" } == true)
        #expect(try sentences("ncd-nonTargetWordsIncomplete") == ["No clear difference in stress or rhythm."])
    }

    /// Fix 3: your unstressed bars use their own darker token; the native row and heard-only words never do.
    @Test func yourUnstressedBarsUseTheirOwnTone() throws {
        let loaded = try library.load("result-feedback")
        let strip = ShellPresenter.strip(loaded)
        #expect(!strip.native.contains { $0.fill == .yours })
        guard case .bars(let clusters, _, _) = strip.you else { Issue.record("no bars"); return }
        #expect(clusters.contains { $0.fill == .yours })
        #expect(clusters.allSatisfy { $0.fill != .neutral })
        let inserted = try library.load("feedback-insertions")
        guard case .bars(let withInsertion, _, _) = ShellPresenter.strip(inserted).you else { Issue.record("no bars"); return }
        #expect(withInsertion.first { $0.label?.text == "+ so" }?.fill == .neutral)
    }

    @Test(arguments: [Palette.light, Palette.dark])
    func yourBarsAreDarkerThanTheNativeRow(_ p: Palette) {
        let you = p.stripBarYou.resolve(in: EnvironmentValues())
        let native = p.stripBar.resolve(in: EnvironmentValues())
        #expect(you.opacity > native.opacity + 0.2)
    }

    /// Fixes 4 and 6 (§7.1, A7): a take problem with audio draws the take grouped by syllable, shaped and
    /// captioned by the problem, and the menu reads LAST TRY · NOT SAVED; without audio it's the placeholder.
    @Test func takeProblemsYourRowAndTakeMenu() throws {
        func you(_ name: String) throws -> StripPresentation.YouRow { ShellPresenter.strip(try library.load(name)).you }
        guard case .takeProblem(let quiet, .nearSilent, Copy.tooQuietToMeasure?) = try you("tooQuiet") else {
            Issue.record("tooQuiet"); return
        }
        #expect(quiet.count > 4 && quiet.allSatisfy { $0.fill == .neutral && $0.label == nil })
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

    // MARK: Round 3, Designer answer 1: the noClearDifference sentence

    private static let ncdSentences: [NoClearDifferenceReason: String] = [
        .pitchShapeBelowClose: "No clear difference in stress or rhythm. Your pitch moves a little differently from the model's, but not in one place we can point to.",
        .optionalMeasuresUnavailable: "No clear difference in stress or rhythm. Some pitch measures couldn't be taken on this take.",
        .mediumConfidenceOnly: "Nothing stood out clearly enough to point at. Try another take to check.",
        .timingRough: "No clear difference, but the timing match was rough, so small differences may be hidden.",
    ]

    /// Each §13 item 1 reason on its own gives its full sentence, with or without quiet-line reasons beside it.
    @Test(arguments: [
        NoClearDifferenceReason.pitchShapeBelowClose, .optionalMeasuresUnavailable, .mediumConfidenceOnly, .timingRough,
    ])
    func noClearDifferenceReasonOnItsOwn(_ reason: NoClearDifferenceReason) {
        let expected = Self.ncdSentences[reason]
        #expect(Copy.noClearDifference([reason]).plain == expected)
        #expect(Copy.noClearDifference([.insertionsPresent, reason, .nonTargetWordsIncomplete]).plain == expected)
    }

    /// Several §13 item 1 reasons: the first in §13 order wins, whatever order the result lists them in.
    @Test func noClearDifferenceFirstApplicableReasonWins() {
        #expect(Copy.noClearDifference([.timingRough, .pitchShapeBelowClose]).plain == Self.ncdSentences[.pitchShapeBelowClose])
        #expect(Copy.noClearDifference([.timingRough, .mediumConfidenceOnly, .optionalMeasuresUnavailable]).plain ==
            Self.ncdSentences[.optionalMeasuresUnavailable])
        #expect(Copy.noClearDifference([.timingRough, .mediumConfidenceOnly]).plain == Self.ncdSentences[.mediumConfidenceOnly])
        #expect(Copy.noClearDifference(NoClearDifferenceReason.allCases.reversed()).plain ==
            Self.ncdSentences[.pitchShapeBelowClose])
    }

    /// No §13 item 1 reason: the bare sentence, and the A6 quiet line (if any) sits under it.
    @Test func noClearDifferenceBareSentenceOnlyWhenNoReasonApplies() {
        let bare = "No clear difference in stress or rhythm."
        #expect(Copy.noClearDifference([]).plain == bare)
        #expect(Copy.noClearDifference([.insertionsPresent]).plain == bare)
        #expect(Copy.noClearDifference([.nonTargetWordsIncomplete]).plain == bare)
        #expect(Copy.noClearDifference([.nonTargetWordsIncomplete, .insertionsPresent]).plain == bare)
    }

    /// The ncd fixtures follow the same rule end to end.
    @Test func noClearDifferenceFixturesUseTheirReasonSentence() throws {
        #expect(try sentences("ncd-pitchShapeBelowClose") == [Self.ncdSentences[.pitchShapeBelowClose]!])
        #expect(try sentences("ncd-optionalMeasuresUnavailable") == [Self.ncdSentences[.optionalMeasuresUnavailable]!])
        #expect(try sentences("ncd-mediumConfidenceOnly") == [Self.ncdSentences[.mediumConfidenceOnly]!])
        #expect(try sentences("ncd-timingRough") == [Self.ncdSentences[.timingRough]!])
    }

    @Test func noVoicedFramesKeepsItsMessage() throws {
        #expect(ShellPresenter.pitch(try library.load("noVoicedFrames")).message == "No pitch to show for this take")
    }

    @Test(arguments: [
        (OperationalError.Stage.findingWords, "finding your words"),
        (.measuringPitch, "measuring your pitch"),
        (.measuringStress, "measuring stress"),
        (.comparing, "comparing with the model"),
    ])
    func inferenceFailedNamesTheStage(_ stage: OperationalError.Stage, _ words: String) {
        let sentence = Copy.inferenceFailed(stage)
        #expect(sentence == "Something went wrong inside Accent Mirror while \(words). This isn't about your take.")
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
}
