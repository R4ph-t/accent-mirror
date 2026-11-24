// Spec 22's guard, run as a package test until `make check` runs `scripts/check-no-tts-in-app.sh` itself: the app
// target and AccentKit's sources never reference the TTS tool, the speech synthesizer, ElevenLabs' host or its key.

import Foundation
import Testing

@Suite("No TTS in the app or AccentKit (spec 22)")
struct NoTTSInAppGuardTests {
    @Test("the repository passes the guard")
    func repositoryPasses() throws {
        // The root is passed, not found with git: the test VM's synced tree is not a git checkout.
        #expect(try Self.guardExit(root: Repo.root) == 0)
    }

    /// Each forbidden reference, planted in a scratch tree laid out like the repository, fails the guard.
    @Test("a planted reference fails the guard", arguments: [
        ("Packages/AccentKit/Sources/AMPipeline/Speak.swift", "let s = AVSpeechSynthesizer()"),
        ("Packages/AccentKit/Sources/AMCore/Host.swift", "let host = \"api.ElevenLabs.io\""),
        ("Packages/AccentKit/Sources/AMCore/Key.swift", "env[\"ELEVENLABS_API_KEY\"]"),
        ("Packages/AccentKit/Package.swift", ".package(path: \"../../tools/SynthRef\")"),
        ("AccentMirror/Shell/Voice.swift", "request.setValue(key, forHTTPHeaderField: \"xi-api-key\")"),
    ])
    func plantedReferenceFails(path: String, line: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clean = root.appendingPathComponent("Packages/AccentKit/Sources/AMCore/Clean.swift")
        try FileManager.default.createDirectory(at: clean.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("// A report label, not TTS code: syntheticReference elevenlabs\n".utf8).write(to: clean)
        #expect(try Self.guardExit(root: root) == 0)

        let planted = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: planted.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((line + "\n").utf8).write(to: planted)
        #expect(try Self.guardExit(root: root) == 1)
    }

    static func guardExit(root: URL?) throws -> Int32 {
        let process = Process()
        process.executableURL = Repo.url("scripts/check-no-tts-in-app.sh")
        process.arguments = root.map { ["--root", $0.path] } ?? []
        process.currentDirectoryURL = Repo.root
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
