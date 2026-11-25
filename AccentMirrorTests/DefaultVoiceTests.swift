import AMCore
import AMLibrary
import Foundation
import Testing

/// Designer v3.3: new installs get p311; an explicit pick, including p225, is kept.
@Suite("Default voice p311") @MainActor struct DefaultVoiceTests {
    private func starter() throws -> StarterManifest {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Starter")
        return try StarterManifest.load(from: folder, checkFiles: false)
    }

    @Test("A new install, with no stored pick, uses the manifest headline p311")
    func newInstallUsesP311() throws {
        let manifest = try starter()
        for phrase in manifest.phrases {
            #expect(phrase.headlineVoice.rawValue.hasPrefix("p311_"), "\(phrase.id)")
            #expect(phrase.recording(phrase.headlineVoice)?.speaker == "p311")
        }
        let phrase = try #require(manifest.phrases.first)
        let defaults = UserDefaults(suiteName: "test.accentmirror.voice.\(UUID().uuidString)")!
        #expect(LiveSession.rememberedVoice(phrase, defaults: defaults) == phrase.headlineVoice)
    }

    @Test("An explicit pick, including p225, is kept")
    func explicitPickIsKept() throws {
        let manifest = try starter()
        let phrase = try #require(manifest.phrases.first { $0.recordings.contains { $0.speaker == "p225" } })
        let p225 = try #require(phrase.recordings.first { $0.speaker == "p225" })
        let defaults = UserDefaults(suiteName: "test.accentmirror.voice.\(UUID().uuidString)")!
        defaults.set(p225.id.rawValue, forKey: LiveSession.voiceKey(phrase.id))
        #expect(LiveSession.rememberedVoice(phrase, defaults: defaults) == p225.id)
        #expect(phrase.headlineVoice != p225.id)
    }

    @Test("The closed button is region · id; the inspector credits id · region")
    func closedButtonAndInspectorCredit() throws {
        let manifest = try starter()
        let phrase = try #require(manifest.phrases.first)
        let recording = try #require(phrase.recording(phrase.headlineVoice))
        #expect(recording.speaker == "p311")
        #expect(recording.region == "Iowa")
        #expect(recording.accent == "American")
        #expect(recording.gender == "M")
        #expect(LivePresenter.voiceTitle(recording) == "Iowa \u{00B7} p311")
        #expect(LivePresenter.voiceRow(recording) == "Iowa (American)")
        #expect(LivePresenter.voiceTag(recording) == "p311 \u{00B7} M")
        let credit = LivePresenter.inspectorCredit(recording)
        #expect(credit.hasPrefix("p311 \u{00B7} Iowa"))
        #expect(credit.contains("VCTK 0.92"))
        #expect(credit.contains("CC BY 4.0"))
    }
}
