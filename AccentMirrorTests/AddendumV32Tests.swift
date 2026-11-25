import AMCore
import AMLibrary
import CoreText
import Foundation
import SwiftUI
import Testing

// Designer addenda v3.2 (W2–W5) and v3.3 (default voice p311). Unhosted: committed fixtures, the bundled manifest
// and font files, and the UI-free rules. No window, no microphone, no network.

private let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let library = FixtureLibrary(root: repo.appending(path: "AccentMirror/Resources/Fixtures", directoryHint: .isDirectory))
private let starterFolder = repo.appending(path: "Resources/Starter", directoryHint: .isDirectory)
private let geistFolder = repo.appending(path: "AccentMirror/Resources/Fonts/Geist", directoryHint: .isDirectory)

// MARK: - W2 fixtures

struct V32FixtureTests {
    @Test(arguments: ["recording-level", "recording-too-loud", "voice-popup-open"])
    func newFixturesDecodeAndAreListed(_ name: String) throws {
        #expect(try library.allNames().contains(name), "Samples ▸ lists \(name)")
        let loaded = try library.load(name)
        #expect(loaded.fixture.name == name)
    }

    @Test func recordingLevelIsMidAndNotLoud() throws {
        let level = try #require(try library.load("recording-level").fixture.recording?.level)
        #expect(level.rmsDBFS > -60 && level.rmsDBFS < -1, "part way along −60…0 dBFS")
        #expect(level.peakDBFS >= level.rmsDBFS && level.peakDBFS < -1)
        #expect(!level.tooLoud)
    }

    @Test func recordingTooLoudIsAClippingFrame() throws {
        let level = try #require(try library.load("recording-too-loud").fixture.recording?.level)
        #expect(level.tooLoud)
        #expect(level.peakDBFS >= -1, "a peak at −1 dBFS or more is what makes it too loud (E5)")
    }

    /// `recording` is aligned with `recording-level`: the meter is part of recording, not an extra state.
    @Test func recordingMatchesRecordingLevel() throws {
        let recording = try library.load("recording").fixture
        let level = try library.load("recording-level").fixture
        #expect(recording.recording?.level == level.recording?.level)
        #expect(recording.recording?.level != nil)
        #expect(recording.phase == .recording && level.phase == .recording)
        #expect(recording.take == level.take && recording.recording?.elapsed == level.recording?.elapsed)
    }

    /// A fixture without a frame draws no meter, as outside a live take.
    @Test func olderRecordingFixturesHaveNoMeterFrame() throws {
        #expect(try library.load("recording-live-2000ms").fixture.recording?.level == nil)
    }

    @Test func levelDecodesWithoutTooLoud() throws {
        let level = try JSONDecoder().decode(LevelReading.self, from: Data(#"{"rmsDBFS": -30, "peakDBFS": -20}"#.utf8))
        #expect(level == LevelReading(rmsDBFS: -30, peakDBFS: -20, tooLoud: false))
    }

    /// v3.2 W2 with v3.3 X2–X3: the empty phrase, the closed button "Iowa · p311", rows "{region} ({accent})" in
    /// manifest order with "p311 · M" tags, p311 checked.
    @Test func voicePopupOpenShowsP311Checked() throws {
        let fixture = try library.load("voice-popup-open").fixture
        #expect(fixture.phase == .empty && fixture.take == nil && fixture.savedTakes.isEmpty)
        #expect(fixture.inspectorOpen == true)
        let model = try #require(fixture.modelRecording)
        #expect(model.open == true)
        #expect([model.voice, model.region].compactMap { $0 }.joined(separator: " \u{00B7} ") == "Iowa \u{00B7} p311")
        let selected = try #require(model.selected)
        #expect(model.voices[selected] == "Iowa (American)")
        #expect(model.tags?[selected] == "p311 \u{00B7} M")
        #expect(fixture.subtitle == "Stress Shifts \u{00B7} Native speaker from Iowa, VCTK")
    }

    /// The pop-up's rows match what the live app builds from the manifest, in its order.
    @Test func voicePopupRowsMatchTheManifest() throws {
        let manifest = try StarterManifest.load(from: starterFolder, checkFiles: false)
        let phrase = try #require(manifest.phrases.first)
        let model = try #require(try library.load("voice-popup-open").fixture.modelRecording)
        #expect(model.voices == phrase.recordings.map(LivePresenter.voiceRow))
        #expect(model.tags == phrase.recordings.map(LivePresenter.voiceTag))
        #expect(model.selected == phrase.recordings.firstIndex { $0.id == phrase.headlineVoice })
    }

    /// v3.3 X3 (with #82's format): a default install's `empty` and `inspector-open` show the closed button
    /// "Iowa · p311" and credit "p311 · Iowa", then the VCTK licence line; `voice-popup-open` matches them.
    @Test(arguments: ["empty", "inspector-open", "voice-popup-open"])
    func defaultInstallCreditsP311(_ name: String) throws {
        let model = try #require(try library.load(name).fixture.modelRecording)
        #expect(model.voice == "Iowa \u{00B7} p311" && model.region == nil)
        #expect(model.attribution == "p311 \u{00B7} Iowa\nVCTK 0.92 \u{00B7} CC BY 4.0")
    }
}

// MARK: - W3 Geist Medium

struct GeistMediumTests {
    @Test func bundledMediumIsTheGeist500Cut() throws {
        let url = geistFolder.appending(path: "Geist-Medium.ttf")
        let descriptors = try #require(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
        let descriptor = try #require(descriptors.first)
        #expect(CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String == BundledFonts.geistMedium)
        #expect(CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String == "Geist")
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let os2 = try #require(CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?)
        // usWeightClass, big-endian at byte 4 of the OS/2 table.
        #expect(UInt16(os2[4]) << 8 | UInt16(os2[5]) == 500)
    }

    @Test func mediumRolesUseGeistMediumNeverTheSystemFace() {
        #expect(BundledFonts.allPostScriptNames.contains(BundledFonts.geistMedium))
        #expect(TypeRole.bodyMedium.fontName == "Geist-Medium" && TypeRole.bodyMedium.size == 13)
        #expect(TypeRole.smallMedium.fontName == "Geist-Medium" && TypeRole.smallMedium.size == 12)
    }

    /// Ghost buttons, Play Both and "Too loud" read the medium roles, and nothing sets a system weight on Geist.
    @Test func mediumLabelsUseTheRoles() throws {
        let card = try String(contentsOf: repo.appending(path: "AccentMirror/Cards/CardOneView.swift"), encoding: .utf8)
        let toolbar = try String(contentsOf: repo.appending(path: "AccentMirror/Toolbar/ToolbarView.swift"), encoding: .utf8)
        #expect(card.contains("Text(Copy.tooLoud)\n                            .typeRole(.smallMedium)"))
        #expect(card.contains("Text(Copy.playBoth)\n                            .typeRole(.bodyMedium)"))
        #expect(toolbar.contains("TextMeasure.width(title, role: .bodyMedium)"))
        #expect(!card.contains(".font.weight("), "a weight modifier on a Geist role falls back to synthesis")
    }

    @Test func licenceSitsNextToTheFont() throws {
        let licence = try String(contentsOf: geistFolder.appending(path: "OFL.txt"), encoding: .utf8)
        #expect(licence.contains("SIL OPEN FONT LICENSE"))
    }
}

// MARK: - W5 highlight token and the label box

struct HighlightTests {
    private func rgba(_ color: Color) -> [Int] {
        let r = color.resolve(in: EnvironmentValues())
        return [r.red, r.green, r.blue, r.opacity].map { Int(($0 * 255).rounded()) }
    }

    /// highlight.hover / highlight.loop: text.primary at 5% / 9% (light) and 6% / 11% (dark).
    @Test func tokenValues() {
        #expect(rgba(Palette.light.highlightHover) == [0x1C, 0x1A, 0x17, 13])
        #expect(rgba(Palette.light.highlightLoop) == [0x1C, 0x1A, 0x17, 23])
        #expect(rgba(Palette.dark.highlightHover) == [0xF2, 0xEF, 0xE9, 15])
        #expect(rgba(Palette.dark.highlightLoop) == [0xF2, 0xEF, 0xE9, 28])
        #expect(rgba(Palette.light.textPrimary).prefix(3) == rgba(Palette.light.highlightHover).prefix(3))
        #expect(rgba(Palette.dark.textPrimary).prefix(3) == rgba(Palette.dark.highlightLoop).prefix(3))
    }

    /// The E4 outline's ink: text.secondary #6B665D light is v3.2's figure; the token table's light value is the
    /// Addendum A2 #69645C, so this only checks dark, where both agree.
    @Test func outlineInkDark() {
        #expect(rgba(Palette.dark.textSecondary) == [0xA3, 0x9D, 0x93, 255])
    }

    @Test func boxIsFourPointsOutsideTheWordsLabels() throws {
        let box = try #require(HighlightGeometry.box([(center: 40, width: 20), (center: 80, width: 30)]))
        #expect(box.minX == 26 && box.maxX == 99)
        #expect(box.height == 24, "16 pt label line plus 4 pt above and below fills the label row")
    }

    @Test func noLabelsNoBox() {
        #expect(HighlightGeometry.box([]) == nil)
    }
}

// MARK: - v3.3 subtitle (the default and the explicit-pick rules are DefaultVoiceTests, from #82)

@MainActor
struct V33SubtitleTests {
    @Test func p311Subtitle() throws {
        let manifest = try StarterManifest.load(from: starterFolder, checkFiles: false)
        let phrase = try #require(manifest.phrases.first)
        let live = LivePhrase(phrase: phrase, packTitle: "Stress Shifts", voice: phrase.headlineVoice)
        #expect(LivePresenter.subtitle(live) == "Stress Shifts \u{00B7} Native speaker from Iowa, VCTK")
    }
}
