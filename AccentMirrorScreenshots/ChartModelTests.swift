import Foundation
import Testing
@testable import AccentMirror

/// Spec 20: the charts' motion, resolved by `ChartModel` at fixed clock times. App-hosted (they read the bundled
/// fixtures and build `ShellModel`s), so they run in the test VM with `make test-ui-vm`. No window, no audio.
@MainActor
@Suite("Chart model")
struct ChartModelTests {
    let library = FixtureLibrary(bundle: Bundle(for: ShellModel.self))!

    /// A shell on `name` with its own defaults, so View ▸ Show Earlier Takes starts on (its default) whatever ran before.
    private func shell(_ name: String, reduceMotion: Bool = false) throws -> ShellModel {
        let loaded = try library.load(name)
        let defaults = try #require(UserDefaults(suiteName: "ChartModelTests-\(UUID().uuidString)"))
        let model = ShellModel(manifest: .stub, sidebar: .stub, toolbar: ShellPresenter.toolbar(for: loaded), defaults: defaults)
        model.reduceMotionOverride = reduceMotion
        model.apply(loaded)
        return model
    }

    private func charts(_ name: String, reduceMotion: Bool = false) throws -> (strip: StripChart, pitch: PitchChart) {
        try #require(try shell(name, reduceMotion: reduceMotion).charts(systemReduceMotion: false))
    }

    private func close(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
        guard let a else { return false }
        return abs(a - b) < tolerance
    }

    // MARK: Ease curves at fixed clock times

    @Test func easesAtFixedClockTimes() {
        let fade = ChartTransition(start: 0, duration: ChartMotion.highlightFade)
        #expect(fade.progress(at: 0, reduceMotion: false) == 0)
        #expect(close(fade.progress(at: 0.030, reduceMotion: false), 0.15625))
        #expect(close(fade.progress(at: 0.060, reduceMotion: false), 0.5))
        #expect(fade.progress(at: 0.120, reduceMotion: false) == 1)
        #expect(fade.progress(at: 0.500, reduceMotion: false) == 1)
        #expect(fade.isRunning(at: 0.119) && !fade.isRunning(at: 0.120))

        let ease = ChartTransition(start: 1, duration: ChartMotion.voiceSwitch)
        #expect(ease.progress(at: 1, reduceMotion: false) == 0)
        #expect(close(ease.progress(at: 1.075, reduceMotion: false), 0.5))
        #expect(ease.progress(at: 1.150, reduceMotion: false) == 1)
        #expect(ChartMotion.earlierTakeSaved == 0.150 && ChartMotion.earlierTakesToggle == 0.120)

        // Reduce Motion: every change is already done.
        #expect(fade.progress(at: 0, reduceMotion: true) == 1)
        #expect(ease.progress(at: 1, reduceMotion: true) == 1)
    }

    @Test func hoverAndLoopBoxesFadeInOver120ms() throws {
        let hover = try #require(try charts("label-hover").strip.highlight)
        #expect(hover.word == 0 && hover.strength == .hover && hover.opacity == 1)
        #expect(close(ChartModel.fade(since: 0, 0.06, false), 0.5))
        #expect(ChartModel.fade(since: 0, 0, true) == 1)

        let loop = try charts("word-loop")
        #expect(loop.strip.highlight == ChartHighlight(word: 2, strength: .loop, opacity: 1))
        #expect(loop.pitch.highlight?.word == 2)
        #expect(loop.strip.header == .looping("harder"))
    }

    // MARK: Earlier takes

    @Test func ghostSelectionKeepsThreePreviousAlignedTakesAndTheMenuPreviewAlone() throws {
        let take02 = try library.load("result").earlierTakes[0]
        let take01 = try library.load("result").earlierTakes[1]
        let unalignable = try #require(try library.load("unalignable").take)
        var older = take01
        older.number = 0
        var oldest = take01
        oldest.number = -1
        let lines = EarlierTakes.lines([take02, unalignable, take01, older, oldest], visible: true)
        #expect(lines.map(\.number) == [2, 1, 0])
        #expect(lines.map(\.opacity) == [0.30, 0.20, 0.12])
        #expect(EarlierTakes.lines([unalignable], visible: true).isEmpty)
        #expect(EarlierTakes.lines([take02], visible: false).isEmpty)

        let preview = try charts("ghosts-menu-preview").pitch.pitch.earlier
        #expect(preview.map(\.number) == [1])
        #expect(preview.map(\.opacity) == [0.30])
    }

    @Test func aSavedTakeFadesInOver150msAsTheOthersStepDown() throws {
        let ghosts = try charts("ghosts-saved-75ms").pitch.pitch.earlier
        #expect(ghosts.map(\.number) == [2, 1])
        #expect(close(ghosts[0].opacity, 0.15))
        #expect(close(ghosts[1].opacity, 0.25))
        // Reduce Motion: no fade.
        #expect(try charts("ghosts-saved-75ms", reduceMotion: true).pitch.pitch.earlier.map(\.opacity) == [0.30, 0.20])

        // The oldest drops out.
        let a = EarlierTakeLine(number: 3, opacity: 0.30, segments: [])
        let b = EarlierTakeLine(number: 2, opacity: 0.20, segments: [])
        let c = EarlierTakeLine(number: 1, opacity: 0.12, segments: [])
        let d = EarlierTakeLine(number: 4, opacity: 0.30, segments: [])
        let mid = GhostBlend.blend(from: [a, b, c], to: [d, EarlierTakeLine(number: 3, opacity: 0.20, segments: []),
                                                         EarlierTakeLine(number: 2, opacity: 0.12, segments: [])], progress: 0.5)
        #expect(mid.map(\.number) == [4, 3, 2, 1])
        #expect(close(mid[3].opacity, 0.06))
        #expect(GhostBlend.blend(from: [a, b, c], to: [d], progress: 1).map(\.number) == [4])
    }

    @Test func toggleFadesOver120msAndIsRemembered() throws {
        let off = try charts("ghosts-toggled-off-60ms").pitch.pitch.earlier
        #expect(off.map(\.number) == [2, 1])
        #expect(close(off[0].opacity, 0.15) && close(off[1].opacity, 0.10))
        #expect(try charts("ghosts-toggled-off-60ms", reduceMotion: true).pitch.pitch.earlier.isEmpty)

        let suite = "ChartModelTests-toggle-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let loaded = try library.load("result")
        let model = ShellModel(manifest: .stub, sidebar: .stub, toolbar: ShellPresenter.toolbar(for: loaded), defaults: defaults)
        model.apply(loaded)
        #expect(model.showEarlierTakes)
        model.toggleEarlierTakes()
        #expect(!model.showEarlierTakes)
        #expect(model.chartInputs.ghostTransition?.duration == ChartMotion.earlierTakesToggle)
        #expect(model.chartInputs.ghostsBefore.map(\.number) == [2, 1])
        #expect(model.detail?.pitch.earlier.isEmpty == true)
        #expect(!EarlierTakesPreference(defaults: try #require(UserDefaults(suiteName: suite))).isOn)
    }

    // MARK: Playhead

    @Test func playheadPlayingTheModel() throws {
        let charts = try charts("playback-model")
        let placement = try #require(charts.strip.playhead)
        #expect(close(placement.native, 0.15))
        #expect(close(charts.pitch.playhead, 0.15))
        // On your row through TimeWarp.toYou, inside "photography".
        let you = try #require(placement.you)
        #expect(you > 0.003 && you < 0.403)
        #expect(charts.strip.header == .playing(.model))
    }

    @Test func playheadPlayingYourTake() throws {
        let charts = try charts("playback-you")
        let placement = try #require(charts.strip.playhead)
        #expect(close(placement.you, 0.17))
        let model = try #require(placement.native)
        #expect(model > 0.003 && model < 0.379)
        #expect(close(charts.pitch.playhead, model))
        #expect(charts.strip.header == .playing(.you))
    }

    /// Across a youOnly stretch (the inserted "so") the native row has no playhead and the pitch playhead holds at the
    /// gap edge: the end of "is" on model time.
    @Test func playheadHoldsAtTheGapEdgeAcrossAnInsertion() throws {
        let charts = try charts("playback-you-gap")
        let placement = try #require(charts.strip.playhead)
        #expect(close(placement.you, 0.47))
        #expect(placement.native == nil)
        #expect(close(charts.pitch.playhead, 0.444))

        let map = try #require(ShellModel.timeMap(try library.load("playback-you-gap")))
        #expect(map.toModel(0.47) == nil)
        #expect(map.toModel(0.55) != nil)
    }

    @Test func playheadKeepsMovingWithReduceMotion() throws {
        #expect(close(try charts("playback-model", reduceMotion: true).pitch.playhead, 0.15))
    }

    // MARK: Syllable being played

    @Test func playedSyllableIsOutlinedOnBothRows() throws {
        let model = try charts("playing-syllable-model").strip
        let native = try #require(model.playing.native)
        let you = try #require(model.playing.you)
        #expect(model.strip.native[native].label?.text == "HAR")
        #expect(model.strip.yourClusters[you].label?.text == "har")

        let yours = try charts("playing-syllable-you").strip
        #expect(yours.playing.you.flatMap { yours.strip.yourClusters[$0].label?.text } == "har")
        #expect(yours.playing.native.flatMap { yours.strip.native[$0].label?.text } == "HAR")
    }

    // MARK: Axis

    @Test func axisGrowsIn6StStepsUpTo24AndNeverShrinks() throws {
        #expect(PitchAxis.range(needed: 2, floor: 0) == 6)
        #expect(PitchAxis.range(needed: 9.15, floor: 12) == 12)
        #expect(PitchAxis.range(needed: 13, floor: 12) == 18)
        #expect(PitchAxis.range(needed: 3, floor: 18) == 18)
        #expect(PitchAxis.range(needed: 40, floor: 0) == 24)

        // Within a phrase, across takes: a wide take grows the axis, a narrow one after it keeps it.
        let model = try shell("result")
        var wide = try library.load("result")
        wide.take?.pitch[0].points[2].st = 15
        model.apply(wide)
        #expect(model.detail?.pitch.rangeSemitones == 18)
        model.apply(try library.load("result"))
        #expect(model.detail?.pitch.rangeSemitones == 18)
    }

    // MARK: Live recording strip

    @Test func liveBarsFoldInOnlyNewSamplesAndCompressPastTheModel() throws {
        let syllables = [StripCluster(start: 0.1, end: 0.6, prominence: 1, label: nil, dot: false, seed: 3, tooltip: nil)]
        let full = RecordingEnvelope.synthetic(syllables: syllables, takeSeconds: 2, elapsed: 1.5)
        var live = EnvelopeBins()
        for count in stride(from: 10, through: full.rms.count, by: 10) {
            live.update(RecordingEnvelope(rms: Array(full.rms.prefix(count))), plotWidth: 600, modelSeconds: 2)
        }
        #expect(live.rebuilds == 1)
        #expect(live.heights == EnvelopeBins.binned(full, plotWidth: 600, modelSeconds: 2).heights)
        // 1.5 s of a 2 s model: three quarters of the 200 bins.
        #expect(live.heights.count == 150)

        #expect(RecordingScale.playhead(elapsed: 0.5, modelSeconds: 2) == 0.25)
        #expect(RecordingScale.playhead(elapsed: 19.5, modelSeconds: 2) == 1)
        let long = RecordingEnvelope.synthetic(syllables: syllables, takeSeconds: 2, elapsed: 19.5)
        #expect(EnvelopeBins.binned(long, plotWidth: 600, modelSeconds: 2).heights.count <= 200)
    }

    @Test func recordingFixturesFeedTheEnvelope() throws {
        for (name, seconds) in [("recording-live-500ms", 0.5), ("recording-live-2000ms", 2.0), ("recording-live-19500ms", 19.5)] {
            guard case .recording(let envelope) = try charts(name).strip.strip.you else { Issue.record(name); continue }
            #expect(close(envelope.elapsed, seconds), "\(name)")
            #expect(try charts(name).pitch.pitch.you.isEmpty, "\(name): no live pitch")
        }
    }

    // MARK: Voice switch

    @Test func voiceSwitchKeepsTheOldDrawingThenEasesOnto150ms() throws {
        let pending = try shell("voice-switch-pending")
        #expect(pending.toolbar.subtitle == .source("Stress Shifts \u{00B7} Native speaker p226, VCTK"))
        let p225 = try library.load("voice-switch-pending").phrase
        let p226 = try #require(try library.load("voice-switch-pending").chartPhrases["photography-p226"])
        let old = try #require(pending.charts(systemReduceMotion: false))
        #expect(old.strip.strip.native[1].start == p225.words[0].syllables[1].start)

        let mid = try charts("voice-switch-75ms")
        let a = p225.words[0].syllables[1].start, b = p226.words[0].syllables[1].start
        #expect(close(mid.strip.strip.native[1].start, (a + b) / 2))
        #expect(close(mid.pitch.pitch.band[0].points[2].t, (p225.band[0].points[2].t + p226.band[0].points[2].t) / 2))
        #expect(close(try charts("voice-switch-75ms", reduceMotion: true).strip.strip.native[1].start, b))

        let done = try charts("voice-switch-done")
        #expect(done.strip.strip.native[1].start == b)
        for name in ["voice-switch-pending", "voice-switch-75ms", "voice-switch-done"] {
            #expect(try charts(name).pitch.pitch.band.allSatisfy { $0.points.count > 1 }, "\(name): band drawn")
            #expect(!(try charts(name).pitch.pitch.band.isEmpty), "\(name): band drawn")
        }
    }

    // MARK: Fixtures

    @Test func everySpec20FixtureLoads() throws {
        let names = try library.allNames()
        for name in [
            "recording-live-500ms", "recording-live-2000ms", "recording-live-19500ms", "playback-model", "playback-you",
            "playback-you-gap", "ghosts-saved-75ms", "ghosts-toggled-off-60ms", "ghosts-menu-preview",
            "voice-switch-pending", "voice-switch-75ms", "voice-switch-done", "label-hover", "word-loop",
            "playing-syllable-model", "playing-syllable-you",
        ] {
            #expect(names.contains(name), "\(name)")
            #expect(try library.load(name).fixture.chart != nil, "\(name) drives the chart")
        }
    }
}
