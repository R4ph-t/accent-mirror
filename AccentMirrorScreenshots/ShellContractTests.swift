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

    // MARK: Round 3, Addendum r3 and the 12:19 batch

    /// B6: your unstressed bars use the final2 values in both themes.
    @Test func yourUnstressedBarTokensAreTheFinal2Values() {
        func rgba(_ c: Color) -> [Int] {
            let r = c.resolve(in: EnvironmentValues())
            return [r.red, r.green, r.blue, r.opacity].map { Int(($0 * 255).rounded()) }
        }
        #expect(rgba(Palette.light.stripBarYou) == rgba(Color(.sRGB, red: 28 / 255, green: 26 / 255, blue: 23 / 255, opacity: 0.50)))
        #expect(rgba(Palette.dark.stripBarYou) == rgba(Color(.sRGB, red: 247 / 255, green: 244 / 255, blue: 238 / 255, opacity: 0.58)))
    }

    /// B3 (§10): in a card-1 sentence the mistake is only bold caps in mistake blue. The sentence carries no
    /// triangle or underline glyph; those belong to strip labels (`ClusterLabel.Style.mistake`).
    @Test func cardSentenceMistakeIsCapsOnly() throws {
        let row = try card("result-feedback").rows.first { $0.sentence.contains { $0.role == .mistake } }
        let mistakes = row?.sentence.filter { $0.role == .mistake }.map(\.text)
        #expect(mistakes == ["PHO"])
        #expect(row?.sentence.plain.contains { "\u{25B2}\u{25B4}\u{26A0}".contains($0) } == false)
    }

    /// Every `rows-*` fixture: one per diff-row kind it demonstrates (round 4 adds `rows-contrast`).
    private static let rowFixtures = [
        "rows-contrast", "rows-final-direction-higher", "rows-final-direction-lower", "rows-range", "rows-too-much-contrast",
    ]

    @Test func theRowFixturesAreTheFiveWeExpect() throws {
        #expect(try library.allNames().filter { $0.hasPrefix("rows-") } == Self.rowFixtures)
    }

    /// B11 / 12:19 a: each row fixture draws its own take, not the close-match one, and no two share one.
    @Test func rowFixturesUseTheirOwnTake() throws {
        var takes: [String] = []
        for name in Self.rowFixtures {
            let take = try #require(try library.load(name).fixture.take, "\(name)")
            #expect(take != "photography-take04-close", "\(name)")
            takes.append(take)
        }
        #expect(Set(takes).count == Self.rowFixtures.count)
    }

    /// Round 4, Designer answer 3: each row fixture carries exactly one row, so its take shows one difference.
    @Test(arguments: [
        ("rows-range", "Use more of your voice range. Your pitch stays flatter than the model's."),
        ("rows-contrast", "Make HAR and LOOKS stronger. Right now they sound like the syllables around them."),
        ("rows-final-direction-higher", "End higher, the way the model does."),
        ("rows-final-direction-lower", "End lower, the way the model does."),
        ("rows-too-much-contrast", "You can soften HAR and LOOKS a little. The model doesn't push them as hard."),
    ])
    func rowFixtureCarriesOneRow(_ name: String, _ sentence: String) throws {
        #expect(try library.load(name).fixture.analysis?.verdict?.rows?.count == 1, "\(name)")
        #expect(try sentences(name) == [sentence])
    }

    private func take(_ id: String) throws -> TakeFixture {
        let url = library.root.appendingPathComponent("takes").appendingPathComponent(id + ".json")
        return try JSONDecoder().decode(TakeFixture.self, from: Data(contentsOf: url))
    }

    private func prominences(_ take: TakeFixture) -> [String: Double] {
        Dictionary(take.words.flatMap(\.syllables).map { ($0.text, $0.prominence) }, uniquingKeysWith: { a, _ in a })
    }

    private func pitch(_ take: TakeFixture) -> [Double] { take.pitch.flatMap(\.points).map(\.st) }

    /// Round 4: a photography row take differs from the close-match take only in its own dimension, so the
    /// charts show one difference: the bars named by the row, or your pitch line, never both.
    @Test func rowTakesChangeOnlyTheirOwnDimension() throws {
        let close = try take("photography-take04-close")
        let stressed: Set<String> = ["tog", "har", "looks"]
        func changedBars(_ name: String) throws -> Set<String> {
            let mine = prominences(try #require(try library.load(name).take))
            return Set(prominences(close).keys.filter { mine[$0] != prominences(close)[$0] })
        }
        func pitchChanged(_ name: String) throws -> Bool {
            zip(pitch(try #require(try library.load(name).take)), pitch(close)).contains { abs($0 - $1) > 0.01 }
        }
        // Lines only.
        for name in ["rows-range", "rows-final-direction-lower"] {
            #expect(try changedBars(name).isEmpty, "\(name)")
            #expect(try pitchChanged(name), "\(name)")
        }
        // Bars only. Contrast changes only the named stressed bars; too much contrast also lowers their
        // unstressed neighbours (r4 C4) and brings the small syllables it doesn't name to native's relative height
        // (r5 D2), never anything else.
        #expect(try changedBars("rows-contrast") == ["har", "looks"])
        #expect(try changedBars("rows-too-much-contrast")
            .isSubset(of: stressed.union(["is", "der", "it", "pho", "ra", "phy", "than"])))
        for name in ["rows-contrast", "rows-too-much-contrast"] { #expect(try !pitchChanged(name), "\(name)") }
        let weak = prominences(try #require(try library.load("rows-contrast").take))
        let strong = prominences(try #require(try library.load("rows-too-much-contrast").take))
        for word in ["har", "looks"] {
            #expect(weak[word]! < prominences(close)[word]!)
            #expect(strong[word]! > prominences(close)[word]!)
        }
    }

    /// r4 C1: the native question rise dips low at the start of LOOKS, then rises in a curve that gets steeper
    /// (concave up) through the last 60% or so of the word, ends near the TOG peak at 85–90% of the plot height,
    /// flattens slightly at the very end and stays inside the plot. No straight ramp, no kink before LOOKS.
    private func questionRiseHasTheR4Shape(_ loaded: LoadedFixture) throws {
        let band = loaded.phrase.band.flatMap(\.points)
        let range = loaded.phrase.rangeSemitones
        let looks = try #require(loaded.phrase.words.last)
        let inLooks = band.filter { $0.t >= looks.start }
        let dip = try #require(inLooks.min { $0.st < $1.st })
        // The dip sits in the first quarter of LOOKS and is the lowest point since HARDER's peak.
        #expect(dip.t <= looks.start + 0.25 * (looks.end - looks.start))
        #expect(band.filter { $0.t > 0.6 }.allSatisfy { $0.st >= dip.st })
        // Ends at 85–90% of the plot height (bottom −range, top +range), near the TOG peak, inside the plot.
        let height = { (st: Double) in (st + range) / (2 * range) }
        let end = try #require(band.last)
        #expect((0.85...0.90).contains(height(end.st)))
        let tog = try #require(band.filter { $0.t < 0.3 }.max { $0.st < $1.st })
        #expect(abs(height(end.st) - height(tog.st)) < 0.08)
        #expect(band.allSatisfy { abs($0.st) + $0.half < range })
        // Concave up from the dip until the last span, which flattens.
        let rise = band.filter { $0.t >= dip.t }
        let slopes = zip(rise, rise.dropFirst()).map { ($1.st - $0.st) / ($1.t - $0.t) }
        #expect(slopes.count >= 5)
        let climbing = slopes.dropLast(2)
        #expect(zip(climbing, climbing.dropFirst()).allSatisfy { $1 >= $0 }, "concave up: \(slopes)")
        #expect(slopes.last! < slopes[slopes.count - 2] && slopes.last! > 0, "flattens at the end")
        #expect(slopes.max()! > 3 * slopes.first { $0 > 0 }!, "a curve, not a straight ramp")
        // From HARDER's last point down to the dip the descent only eases: no kink before LOOKS.
        let fall = band.filter { $0.t >= 0.585 && $0.t <= dip.t }
        let fallSlopes = zip(fall, fall.dropFirst()).map { ($1.st - $0.st) / ($1.t - $0.t) }
        #expect(fallSlopes.allSatisfy { $0 < 0 })
        #expect(zip(fallSlopes, fallSlopes.dropFirst()).allSatisfy { $1 >= $0 }, "no kink: \(fallSlopes)")
    }

    /// The unstressed neighbours of the syllables a too-much-contrast row names that are lighter in your take than
    /// the row's 2× rule allows next to native (r4 C4): the strip's "light neighbours".
    private func lightNeighbours(_ loaded: LoadedFixture) throws -> Set<String> {
        guard let row = loaded.fixture.analysis?.verdict?.rows?.first(where: { $0.kind == .tooMuchContrast }),
              let take = loaded.take
        else { return [] }
        let native = loaded.phrase.words.flatMap(\.syllables)
        let mine = take.words.flatMap(\.syllables)
        guard native.count == mine.count else { return [] }
        let named = Set((row.targets ?? []).map { $0.lowercased() })
        var neighbours: Set<String> = []
        for index in mine.indices where named.contains(mine[index].text.lowercased()) {
            for other in [index - 1, index + 1] where mine.indices.contains(other) && !native[other].stressed {
                let nativeRatio = native[other].prominence / native[index].prominence
                let mineRatio = mine[other].prominence / mine[index].prominence
                if mineRatio <= nativeRatio / 2 + 1e-9 { neighbours.insert(mine[other].text.lowercased()) }
            }
        }
        return neighbours
    }

    /// r4 C4 and r5 D2: the too-much-contrast strip shows more contrast than the model, and nothing else.
    /// - Named syllables stand at full height.
    /// - Each unstressed neighbour of a named syllable is at most half as tall relative to it as the native's
    ///   neighbour is to the native's (the row's 2× rule): a light neighbour.
    /// - Every other syllable keeps native's relative height (±10%; TOG to 1%), except one a reduction row in the
    ///   same take names, which may be heavier (`feedback-too-much-contrast-last`: ra, phy and than; pho is not
    ///   named, so it stays at native's height).
    @Test(arguments: ["rows-too-much-contrast", "feedback-too-much-contrast-last"])
    func tooMuchContrastStripShowsMoreContrast(_ name: String) throws {
        let loaded = try library.load(name)
        let native = loaded.phrase.words.flatMap(\.syllables).map { (text: $0.text.lowercased(), prominence: $0.prominence) }
        let mine = try #require(loaded.take).words.flatMap(\.syllables).map { (text: $0.text.lowercased(), prominence: $0.prominence) }
        #expect(native.map(\.text) == mine.map(\.text))
        let rows = loaded.fixture.analysis?.verdict?.rows ?? []
        let row = try #require(rows.first { $0.kind == .tooMuchContrast })
        let named = Set((row.targets ?? []).map { $0.lowercased() })
        let reductionNamed = Set(rows.filter { $0.kind == .reduction }.flatMap { $0.targets ?? [] }.map { $0.lowercased() })
        let nativeMax = native.map(\.prominence).max()!, mineMax = mine.map(\.prominence).max()!
        let stressed = Set(loaded.phrase.words.flatMap(\.syllables).filter(\.stressed).map { $0.text.lowercased() })
        var neighbours: Set<String> = []
        for (index, syllable) in mine.enumerated() where named.contains(syllable.text) {
            for other in [index - 1, index + 1] where mine.indices.contains(other) && !stressed.contains(mine[other].text) {
                neighbours.insert(mine[other].text)
                let nativeRatio = native[other].prominence / native[index].prominence
                let mineRatio = mine[other].prominence / mine[index].prominence
                #expect(mineRatio <= nativeRatio / 2 + 1e-9, "\(mine[other].text) next to \(syllable.text)")
            }
        }
        #expect(neighbours == ["is", "der", "it"])
        #expect(try lightNeighbours(loaded) == neighbours)
        for (index, syllable) in mine.enumerated() {
            let nativeRelative = native[index].prominence / nativeMax
            let mineRelative = syllable.prominence / mineMax
            if named.contains(syllable.text) {
                #expect(syllable.prominence == mineMax, "\(syllable.text) at full height")
            } else if neighbours.contains(syllable.text) {
                continue
            } else if stressed.contains(syllable.text) {
                #expect(abs(mineRelative - nativeRelative) < 0.01, "\(syllable.text) keeps native's relative height")
            } else if reductionNamed.contains(syllable.text) {
                #expect(mineRelative >= nativeRelative, "\(syllable.text) is named by the reduction row: never lighter")
            } else {
                #expect(abs(mineRelative / nativeRelative - 1) <= 0.10,
                        "\(syllable.text) isn't named: native's relative height (\(mineRelative) vs \(nativeRelative))")
            }
        }
        if name == "rows-too-much-contrast" {
            #expect(reductionNamed.isEmpty)
        } else {
            #expect(reductionNamed == ["ra", "phy", "than"])
            let pho = try #require(mine.firstIndex { $0.text == "pho" })
            #expect(abs((mine[pho].prominence / mineMax) / (native[pho].prominence / nativeMax) - 1) <= 0.10)
        }
    }

    /// r5 D2: a syllable that is a light neighbour in a too-much-contrast row is never named in a reduction row,
    /// in any fixture. `feedback-too-much-contrast-last` reads "ra, phy, than." with no "der".
    @Test func lightNeighboursAreNeverNamedAsTooHeavy() throws {
        var checked = 0
        for name in try library.allNames() {
            let loaded = try library.load(name)
            let light = try lightNeighbours(loaded)
            guard !light.isEmpty else { continue }
            checked += 1
            let reduction = (loaded.fixture.analysis?.verdict?.rows ?? []).filter { $0.kind == .reduction }
            let reductionNamed = Set(reduction.flatMap { $0.targets ?? [] }.map { $0.lowercased() })
            #expect(reductionNamed.isDisjoint(with: light), "\(name): \(reductionNamed.intersection(light))")
        }
        #expect(checked >= 2)
        let rows = try sentences("feedback-too-much-contrast-last")
        #expect(rows.first == "Keep the small syllables short and light: ra, phy, than.")
        #expect(!rows.joined().contains("der"))
    }

    /// Round 4, Designer answer 1: "End higher" sits on a question whose native really rises at the end, and
    /// your ending falls; "End lower" on the statement, whose native falls while yours rises.
    @Test func finalDirectionTakesMatchTheirRow() throws {
        func ending(_ points: [Double]) -> Double { points[points.count - 1] - points[points.count - 3] }
        let higher = try library.load("rows-final-direction-higher")
        #expect(higher.phrase.text == "Is photography harder than it looks?")
        #expect(higher.fixture.sidebar?.selectedPhraseID == higher.phrase.id)
        #expect(ending(pitch(try #require(higher.take))) < -3)
        try questionRiseHasTheR4Shape(higher)
        let words = try #require(higher.take).words.compactMap(\.expected)
        #expect(words == higher.phrase.words.map { $0.text.lowercased().trimmingCharacters(in: .punctuationCharacters) })

        let lower = try library.load("rows-final-direction-lower")
        #expect(ending(lower.phrase.band.flatMap(\.points).map(\.st)) < -3)
        #expect(ending(pitch(try #require(lower.take))) > 3)
    }

    /// Round 4, Designer answer 2: too much contrast names every syllable that's over, joined like the other rows.
    @Test(arguments: [
        (["HAR"], "You can soften HAR a little. The model doesn't push it as hard."),
        (["HAR", "LOOKS"], "You can soften HAR and LOOKS a little. The model doesn't push them as hard."),
        (["TOG", "HAR", "LOOKS"], "You can soften TOG, HAR and LOOKS a little. The model doesn't push them as hard."),
    ])
    func tooMuchContrastNamesEverySyllable(_ targets: [String], _ sentence: String) {
        let row = Copy.row(DiffRow(kind: .tooMuchContrast, targets: targets))
        #expect(row.plain == sentence)
        #expect(row.filter { $0.role == .stressed }.map(\.text) == targets)
    }

    /// Row order: too much contrast comes last whatever order the result lists the rows in
    /// (`feedback-too-much-contrast-last`), and drops out when three rows come before it.
    @Test func tooMuchContrastComesLastAndOnlyWithRoom() throws {
        let rows = try card("feedback-too-much-contrast-last").rows.map(\.sentence.plain)
        #expect(rows.count == 2)
        #expect(rows.first?.hasPrefix("Keep the small syllables short and light") == true)
        #expect(rows.last?.hasPrefix("You can soften HAR and LOOKS") == true)
        let full = ShellPresenter.orderedRows([
            DiffRow(kind: .tooMuchContrast, targets: ["HAR"]), DiffRow(kind: .range),
            DiffRow(kind: .reduction, targets: ["ra"]), DiffRow(kind: .finalDirection, direction: "lower"),
        ])
        #expect(full.map(\.kind) == [.reduction, .range, .finalDirection])
    }

    /// B11 / 12:19 b: targetWordsMissing names words of the fixture's own phrase, and the take has a missing
    /// slot for exactly those words.
    @Test func missingWordsComeFromThePhraseAndMatchTheSlots() throws {
        let expected = [
            "inc-targetWordsMissing-one": ["harder"],
            "inc-targetWordsMissing-two": ["harder", "looks"],
        ]
        for name in try library.allNames() where name.hasPrefix("inc-targetWordsMissing") {
            let loaded = try library.load(name)
            let words = loaded.fixture.analysis?.verdict?.inconclusive?.words ?? []
            if let want = expected[name] { #expect(words == want, "\(name)") }
            let phraseWords = Set(loaded.phrase.words.map { $0.text.lowercased().trimmingCharacters(in: .punctuationCharacters) })
            #expect(!words.isEmpty && words.allSatisfy(phraseWords.contains), "\(name)")
            guard case .bars(_, let slots, _) = ShellPresenter.strip(loaded).you else { Issue.record("\(name)"); continue }
            #expect(slots.map(\.expected) == words, "\(name)")
            #expect(ShellPresenter.pitch(loaded).message == nil, "\(name) still has pitch to show")
        }
    }

    // MARK: Round 3, 12:19 batch c: final-direction icons

    @Test func finalDirectionIconFollowsTheDirection() throws {
        let higher = try card("rows-final-direction-higher").rows.first { $0.sentence.plain.hasPrefix("End higher") }
        #expect(higher?.icon == "arrow.up.right")
        let lower = try card("rows-final-direction-lower").rows.first { $0.sentence.plain.hasPrefix("End lower") }
        #expect(lower?.icon == "arrow.down.right")
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
