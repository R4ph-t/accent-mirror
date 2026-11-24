import Foundation
import Testing

// Spec 29 (v3/v3.1 show-don't-judge UI). Unhosted: these read the committed fixtures and sources and run the UI-free
// rules in `ResultLogic.swift`, so nothing opens a window.

private let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let library = FixtureLibrary(root: repo.appending(path: "AccentMirror/Resources/Fixtures", directoryHint: .isDirectory))

/// The decision procedure's coverage floor, read from `Thresholds.swift` so the test follows it.
private func minimumCoverage() throws -> Double {
    let text = try String(contentsOf: repo.appending(path: "Packages/AccentKit/Sources/AMCore/Thresholds.swift"), encoding: .utf8)
    let match = try #require(text.firstMatch(of: /minComparableCoverage = ([0-9.]+)/))
    return try #require(Double(match.1))
}

private func quietLine(_ name: String) throws -> ResultQuietLine? {
    let loaded = try library.load(name)
    let analysis = try #require(loaded.fixture.analysis)
    return ResultQuietLine.first(comparableCoverage: analysis.comparableCoverage, minimumCoverage: try minimumCoverage(),
                                 timing: analysis.timing, insertions: ResultQuietLine.insertedWords(loaded.take))
}

// MARK: - Fixtures (v3 §10, How to test 9)

struct V3FixtureTests {
    static let retired = [
        "result-feedback", "rough-timing-first", "rows-contrast", "rows-range", "rows-final-direction-higher",
        "rows-final-direction-lower", "rows-too-much-contrast", "feedback-too-much-contrast-last",
        "feedback-quiet-priority", "feedback-partial", "feedback-nonTargetWordsIncomplete", "close-all",
        "close-placement-only", "close-stress-rhythm", "placement-only-too-few-unstressed", "stress-match-p311",
        "stress-like-p311", "stress-differs-but-accepted", "stress-lowConfidence", "words-referenceAnomaly",
        "feedback-insertions", "feedback-two-insertions",
    ]

    static let added = [
        "result", "result-earlier-takes-off", "result-timing-rough", "result-coverage-low", "result-one-native",
        "playing-both", "stress-dot-short-bar", "result-insertions", "result-two-insertions",
    ]

    @Test func retiredFixturesAreGone() throws {
        let names = try library.allNames()
        for name in Self.retired { #expect(!names.contains(name), "\(name) is still in Samples") }
        #expect(!names.contains { $0.hasPrefix("inc-") || $0.hasPrefix("ncd-") })
    }

    @Test(arguments: added)
    func newFixturesExistAndDecode(_ name: String) throws {
        #expect(try library.allNames().contains(name))
        _ = try library.load(name)
    }

    @Test func resultHasTwoEarlierTakesAndTheToggleOffStateHidesThem() throws {
        #expect(try library.load("result").earlierTakes.count == 2)
        #expect(try library.load("result-earlier-takes-off").fixture.earlierTakesVisible == false)
    }

    @Test func noFixtureCarriesStressOrAMarker() throws {
        for folder in ["phrases", "takes", "states"] {
            let dir = repo.appending(path: "AccentMirror/Resources/Fixtures/\(folder)")
            for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                let text = try String(contentsOf: file, encoding: .utf8)
                #expect(!text.contains("\"mistake\"") && !text.contains("\"stressed\""), "\(file.lastPathComponent)")
                #expect(!text.contains("\"rows\"") && !text.contains("\"measures\""), "\(file.lastPathComponent)")
            }
        }
    }
}

// MARK: - Banned words and marks (v3 §5–6, v3.1 V4; How to test 2)

struct BannedWordTests {
    /// v3 §5 plus v3.1 V4.
    static let banned = [
        "wrong", "mistake", "correct", "better", "worse", "stronger", "softer", "soften", "should", "make",
        "close to the model", "no clear difference", "score", "target", "outside",
    ]

    /// Every Swift file a v1 string can come from: the views, the presenter, the copy and the result rules.
    static func sources() throws -> [URL] {
        let app = repo.appending(path: "AccentMirror")
        let enumerator = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// The string literals in a Swift file (single-line and multi-line), comments excluded.
    static func literals(_ text: String) -> [String] {
        var out: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var code = Substring(line)
            if let comment = code.range(of: "//"), !code[..<comment.lowerBound].contains("\"") { code = code[..<comment.lowerBound] }
            out += code.matches(of: /"((?:[^"\\]|\\.)*)"/).map { String($0.1) }
        }
        return out
    }

    @Test func noV1StringUsesABannedWord() throws {
        let files = try Self.sources()
        #expect(files.count > 20, "the scan must find the app's sources")
        for file in files {
            for literal in Self.literals(try String(contentsOf: file, encoding: .utf8)) {
                let lower = literal.lowercased()
                for word in Self.banned {
                    let hit = word.contains(" ") ? lower.contains(word)
                        : lower.firstMatch(of: try Regex("\\b\(word)")) != nil
                    #expect(!hit, "\(file.lastPathComponent): \"\(literal)\" uses \"\(word)\"")
                }
            }
        }
    }

    @Test func copyAndRulesCarryTheV3Sentences() throws {
        let copy = try String(contentsOf: repo.appending(path: "AccentMirror/Fixtures/Copy.swift"), encoding: .utf8)
        for sentence in [
            "Play them back to back, then try another take.",
            "Only part of your take lined up with the model, so some of it isn",
            "The timing match is rough, so syllables may not line up exactly.",
            "drawn on the pitch chart.",
            "That take was too short to line up with the model. Say the whole phrase.",
            "This take was recorded for the old wording, so it can't be lined up with the new one.",
            "so this take can't be shown. This isn't about your take.",
            "finding your words", "measuring your pitch", "measuring your syllables", "lining your take up with the model",
            "Result ready. Your take is drawn over the model",
            "This word can be said more than one way.", "Not in your take.", "Dictionary stress", "Native range",
            "Earlier takes", "Play the model, then your take", "Play Model, Then You", "Show Earlier Takes",
        ] {
            #expect(copy.contains(sentence), "Copy.swift lacks \"\(sentence)\"")
        }
    }

    /// `mistake` stays in the token file, reserved; no other file references it. No triangle, dotted underline or
    /// strike-through is drawn anywhere.
    @Test func noMistakeTokenTriangleUnderlineOrStrikeThrough() throws {
        for file in try Self.sources() where file.lastPathComponent != "Palette.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains(".mistake"), "\(file.lastPathComponent) references the mistake token")
            // The play glyph is a triangle by design; a marker triangle is an SF `triangle` symbol.
            #expect(!text.contains("\"triangle"), "\(file.lastPathComponent) draws a triangle")
            #expect(!text.contains("strikethrough") && !text.contains("DottedUnderline") && !text.contains(".underline"),
                    "\(file.lastPathComponent) strikes through or underlines")
        }
        let palette = try String(contentsOf: repo.appending(path: "AccentMirror/Design/Palette.swift"), encoding: .utf8)
        #expect(palette.contains("var mistake: Color"), "mistake stays reserved in the token file")
    }

    /// No red, yellow, amber, gold or purple is added: the token table is the only place colours live.
    @Test func noColourOutsideTheTokenTable() throws {
        for file in try Self.sources() where file.lastPathComponent != "Palette.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for colour in ["red", "yellow", "orange", "purple"] {
                #expect(text.firstMatch(of: try Regex("\\.\(colour)\\b")) == nil, "\(file.lastPathComponent) uses .\(colour)")
            }
            #expect(!text.contains("Color(hex") && !text.contains("Color(red"), "\(file.lastPathComponent) hard-codes a colour")
        }
    }
}

// MARK: - Dictionary-stress dot (v3.1 V2; How to test 4)

struct StressDotTests {
    private func dotted(_ phrase: PhraseFixture) -> [String] {
        phrase.words.flatMap { word in
            word.syllables.indices.filter { StressMarks.dottedSyllable(word) == $0 }.map { word.syllables[$0].text }
        }
    }

    @Test func resultDotsTheContextPrimaries() throws {
        #expect(dotted(try library.load("result").phrase) == ["tog", "har", "looks"])
    }

    @Test func ambiguousWordsGetNoDot() throws {
        let phrase = try library.load("words-expectedAmbiguous").phrase
        let harder = try #require(phrase.words.first { $0.text == "harder" })
        #expect(StressMarks.dottedSyllable(harder) == nil)
        #expect(StressMarks.isAmbiguous(harder))
        #expect(dotted(phrase) == ["tog", "looks"])
    }

    /// The dot follows `expectedStress` only: never bar height, and two primaries in one word is ambiguous.
    @Test func dotIgnoresBarsAndNeedsOnePrimary() throws {
        let json = #"""
        {"text": "record", "expectedStress": ["primary", "primary"], "start": 0, "end": 1,
         "syllables": [{"text": "re", "start": 0, "end": 0.5, "prominence": 1}, {"text": "cord", "start": 0.5, "end": 1, "prominence": 0.1}]}
        """#
        let word = try JSONDecoder().decode(NativeWord.self, from: Data(json.utf8))
        #expect(StressMarks.dottedSyllable(word) == nil)
        #expect(StressMarks.isAmbiguous(word))
    }

    @Test func shortBarFixtureDotsAShortFinalSyllableAndChangesNothingElse() throws {
        let short = try library.load("stress-dot-short-bar")
        let result = try library.load("result")
        let syllables = short.phrase.words.flatMap(\.syllables)
        let looks = try #require(syllables.last)
        #expect(looks.text == "looks")
        #expect(StressMarks.dottedSyllable(try #require(short.phrase.words.last)) == 0)
        let undottedTaller = short.phrase.words.flatMap { word in
            word.syllables.indices.filter { StressMarks.dottedSyllable(word) != $0 }.map { word.syllables[$0] }
        }.contains { $0.prominence > looks.prominence }
        #expect(undottedTaller, "an undotted syllable has taller bars than the dotted LOOKS")
        // Nothing else differs: the same take, analysis, dots and every other syllable.
        #expect(short.fixture.take == result.fixture.take)
        #expect(short.fixture.analysis?.describe == result.fixture.analysis?.describe)
        #expect(dotted(short.phrase) == dotted(result.phrase))
        let others = zip(syllables, result.phrase.words.flatMap(\.syllables)).dropLast()
        #expect(others.allSatisfy { $0.prominence == $1.prominence && $0.start == $1.start && $0.end == $1.end })
    }
}

// MARK: - Card 1's quiet line (v3 §3.1; How to test 8)

struct QuietLineTests {
    @Test func roughTimingWinsOverInsertions() throws {
        #expect(try quietLine("result-timing-rough") == .roughTiming)
        #expect(try ResultQuietLine.insertedWords(library.load("result-timing-rough").take) == ["so"])
    }

    @Test func coverageWinsOverEverything() throws {
        #expect(try quietLine("result-coverage-low") == .lowCoverage)
    }

    @Test func insertionsShowWhenNothingElseApplies() throws {
        #expect(try quietLine("result-insertions") == .insertions(["so"]))
        #expect(try quietLine("result-two-insertions") == .insertions(["so", "really"]))
    }

    @Test func cleanResultHasNoQuietLine() throws {
        #expect(try quietLine("result") == nil)
    }

    @Test func unknownCoverageIsNeverLow() {
        #expect(ResultQuietLine.first(comparableCoverage: nil, minimumCoverage: 0.7, timing: .good, insertions: []) == nil)
        #expect(ResultQuietLine.first(comparableCoverage: 0.7, minimumCoverage: 0.7, timing: .good, insertions: []) == nil)
    }
}

// MARK: - Earlier takes and ⇧⌘G (v3 §3.3; How to test 6)

struct EarlierTakesTests {
    @Test func resultDrawsTwoAtThirtyAndTwentyPercent() throws {
        let lines = EarlierTakes.lines(try library.load("result").earlierTakes, visible: true)
        #expect(lines.map(\.opacity) == [0.30, 0.20])
        #expect(lines.map(\.number) == [2, 1])
    }

    @Test func atMostThreeAndNeverUnalignable() throws {
        let aligned = try library.load("result").earlierTakes[0]
        let unalignable = try #require(try library.load("unalignable").take)
        let lines = EarlierTakes.lines([aligned, unalignable, aligned, aligned, aligned], visible: true)
        #expect(lines.map(\.opacity) == [0.30, 0.20, 0.12])
        #expect(EarlierTakes.lines([unalignable], visible: true).isEmpty)
    }

    @Test func hiddenDrawsNothingAndPreviewIsTheOnlyGhost() throws {
        let takes = try library.load("result").earlierTakes
        #expect(EarlierTakes.lines(takes, visible: false).isEmpty)
        #expect(EarlierTakes.preview(takes[1]).map(\.number) == [1])
    }

    @Test func showEarlierTakesIsOnByDefaultAndRemembered() throws {
        let suite = "AccentMirrorTests.EarlierTakes.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(EarlierTakesPreference(defaults: defaults).isOn)
        #expect(EarlierTakesPreference(defaults: defaults).toggle() == false)
        // Relaunch: a new reader of the same defaults still sees them hidden.
        let relaunched = try #require(UserDefaults(suiteName: suite))
        #expect(EarlierTakesPreference(defaults: relaunched).isOn == false)
        #expect(EarlierTakesPreference(defaults: relaunched).toggle() == true)
        #expect(EarlierTakesPreference(defaults: defaults).isOn)
    }
}

// MARK: - Play Both on an injected clock (v3 §3.1; How to test 5)

struct PlayBothTests {
    /// Equal up to floating-point noise from the clock arithmetic.
    private func near(_ a: PlaybackSchedule.Phase, _ b: PlaybackSchedule.Phase) -> Bool {
        switch (a, b) {
        case (.playing(let s1, let p1), .playing(let s2, let p2)): s1 == s2 && abs(p1 - p2) < 1e-9
        default: a == b
        }
    }

    @Test func modelThenPauseThenYou() {
        let clock = FrozenPlaybackClock(now: 100)
        let run = PlaybackRun(.both(model: 2.0, you: 2.5), clock: clock)
        #expect(near(run.phase, .playing(.model, progress: 0)))
        clock.now = 101
        #expect(near(run.phase, .playing(.model, progress: 0.5)))
        clock.now = 102.0
        #expect(run.phase == .pause)
        clock.now = 102.39
        #expect(run.phase == .pause)
        clock.now = 102.4
        #expect(near(run.phase, .playing(.you, progress: 0)))
        clock.now = 103.65
        #expect(near(run.phase, .playing(.you, progress: 0.5)))
        clock.now = 104.9
        #expect(run.phase == .finished)
        #expect(run.isFinished)
    }

    @Test func thePauseIsFourTenths() {
        #expect(PlaybackSchedule.pauseSeconds == 0.4)
        #expect(PlaybackSchedule.both(model: 1, you: 1).totalSeconds == 2.4)
    }

    @Test func escStopsAtOnce() {
        let clock = FrozenPlaybackClock(now: 0)
        let run = PlaybackRun(.both(model: 2, you: 2), clock: clock)
        clock.now = 0.5
        run.stop()
        #expect(run.phase == .finished)
        clock.now = 3
        #expect(run.phase == .finished)
    }

    @Test func modelAndYouAloneAreOneStep() {
        #expect(PlaybackSchedule.model(2).phase(at: 1) == .playing(.model, progress: 0.5))
        #expect(PlaybackSchedule.you(2).phase(at: 1) == .playing(.you, progress: 0.5))
        #expect(PlaybackSchedule.model(2).phase(at: 2) == .finished)
    }

    /// A label click loops the word's slices (model, 0.4 s, you, 0.4 s) until Esc; the playhead stays in the slice.
    @Test func labelLoopRepeatsUntilEsc() {
        let schedule = PlaybackSchedule.loop(model: (from: 0.2, to: 0.4, seconds: 1), you: (from: 0.5, to: 0.7, seconds: 1))
        #expect(schedule.totalSeconds == 2.8)
        #expect(near(schedule.phase(at: 0.5), .playing(.model, progress: 0.3)))
        #expect(schedule.phase(at: 1.2) == .pause)
        #expect(near(schedule.phase(at: 1.9), .playing(.you, progress: 0.6)))
        #expect(near(schedule.phase(at: 2.8 + 0.5), .playing(.model, progress: 0.3)), "it loops")
        let clock = FrozenPlaybackClock(now: 0)
        let run = PlaybackRun(schedule, clock: clock)
        clock.now = 100
        #expect(!run.isFinished)
        run.stop()
        #expect(run.isFinished)
        let modelOnly = PlaybackSchedule.loop(model: (from: 0, to: 0.5, seconds: 1), you: nil)
        #expect(modelOnly.steps.count == 2)
    }

    /// The `playing-both` fixture freezes the sequence with the playhead in your half.
    @Test func playingBothFixtureIsInYourHalf() throws {
        let frame = try #require(try library.load("playing-both").fixture.playBoth)
        let phase = PlaybackSchedule.both(model: frame.modelSeconds, you: frame.youSeconds).phase(at: frame.elapsed)
        guard case .playing(.you, let progress) = phase else {
            Issue.record("playing-both is not in your half: \(phase)")
            return
        }
        #expect(progress > 0 && progress < 1)
    }
}

// MARK: - Timing connectors (v3 §3.2, v3.1 V2)

struct ConnectorTests {
    @Test func everyMatchedSyllableHasOneAndDottedOnesStartUnderTheDot() throws {
        let loaded = try library.load("result")
        let connectors = TimingConnectors.connectors(phrase: loaded.phrase, take: try #require(loaded.take))
        #expect(connectors.count == loaded.phrase.words.flatMap(\.syllables).count)
        #expect(connectors.filter(\.fromDot).count == 3)
    }

    @Test func noConnectorForAMissingOrInsertedWord() throws {
        let missing = try library.load("words-missing")
        let take = try #require(missing.take)
        let lines = TimingConnectors.connectors(phrase: missing.phrase, take: take)
        let missingSyllables = take.words.filter { $0.kind == .missing }.compactMap { pair in
            missing.phrase.words.first { $0.text.lowercased().hasPrefix(pair.expected?.lowercased() ?? "-") }
        }.flatMap(\.syllables)
        #expect(!missingSyllables.isEmpty)
        for syllable in missingSyllables {
            #expect(!lines.contains { $0.native == (syllable.start + syllable.end) / 2 }, "a missing word has a connector")
        }

        let inserted = try library.load("result-insertions")
        let insertedTake = try #require(inserted.take)
        let insertedLines = TimingConnectors.connectors(phrase: inserted.phrase, take: insertedTake)
        let heard = insertedTake.words.filter { $0.kind == .inserted }.flatMap(\.syllables).map { ($0.start + $0.end) / 2 }
        #expect(!heard.isEmpty)
        #expect(!insertedLines.contains { heard.contains($0.you) }, "an inserted word has a connector")
    }
}

// MARK: - Inspector THIS TAKE (v3 §4, v3.1 V4; How to test 7)

struct ThisTakeTests {
    @Test func resultRowsReadAsInTheMockup() throws {
        let describe = try #require(try library.load("result").fixture.analysis?.describe)
        let rows = ThisTake.rows(describe)
        #expect(rows.map(\.name) == ["Length", "Syllables per s", "Pitch range", "Rhythm (nPVI)", "Ends"])
        #expect(rows.map(\.you) == ["2.4 s", "4.2", "4 st", "38", "rising"])
        #expect(rows.map(\.native) == ["1.9\u{2013}2.3 s", "4.3\u{2013}5.1", "6\u{2013}9 st", "52\u{2013}61", "5 falling, 3 rising"])
        #expect(rows[3].nameTooltip == "How much syllable lengths change from one syllable to the next.")
        #expect(ThisTake.note(describe) == "Native range is the spread across the 8 native voices for this phrase.")
        #expect(ThisTake.headers.native == "NATIVE RANGE")
    }

    @Test func oneNativeShowsThatTakesValues() throws {
        let describe = try #require(try library.load("result-one-native").fixture.analysis?.describe)
        let rows = ThisTake.rows(describe)
        #expect(rows.map(\.native) == ["2.1 s", "4.8", "7 st", "55", "falling"])
        #expect(ThisTake.note(describe) == nil)
    }

    /// A value outside the range is drawn like any other: the row has no field that could mark it.
    @Test func outsideTheRangeIsUnmarked() throws {
        let describe = try #require(try library.load("result").fixture.analysis?.describe)
        let length = ThisTake.rows(describe)[0]
        #expect(length.you == "2.4 s" && length.youTooltip == nil)
        #expect(Mirror(reflecting: length).children.map(\.label) ==
                ["name", "nameTooltip", "you", "youTooltip", "native", "nativeTooltip"])
    }

    @Test func missingValueIsADashWithItsReason() throws {
        let json = #"""
        {"you": {"lengthSeconds": {"value": 2}, "syllablesPerSecond": {"value": 4}, "pitchRangeSemitones": {"reason": "noVoicedFrames"},
                 "rhythmNPVI": {"reason": "tooFewSyllables"}},
         "native": {"voices": 2, "lengthSeconds": {"min": 1, "max": 2, "count": 2}, "syllablesPerSecond": {"min": 4, "max": 5, "count": 2},
                    "pitchRangeSemitones": {"min": 6, "max": 9, "count": 2}, "rhythmNPVI": {"min": 50, "max": 60, "count": 2},
                    "endingDirections": {"fall": 2}}}
        """#
        let rows = ThisTake.rows(try JSONDecoder().decode(Describe.self, from: Data(json.utf8)))
        #expect(rows[2].you == "\u{2014}" && rows[2].youTooltip == ThisTake.reason(.noVoicedFrames))
        #expect(rows[3].you == "\u{2014}" && rows[3].youTooltip == ThisTake.reason(.tooFewSyllables))
        #expect(rows[4].you == "\u{2014}" && rows[4].youTooltip != nil)
        #expect(rows[4].native == "2 falling")
    }

    @Test func alignmentReadsClearOrRough() {
        #expect(ThisTake.alignmentTitle == "ALIGNMENT")
        #expect(ThisTake.alignment(.good) == "Clear")
        #expect(ThisTake.alignment(.rough) == "Rough")
        #expect(ThisTake.alignmentNote == "how closely your syllables lined up")
    }
}
