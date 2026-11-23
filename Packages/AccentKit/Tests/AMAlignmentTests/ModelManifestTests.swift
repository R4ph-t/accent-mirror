import AMAlignment
import Foundation
import Testing

/// The repo root, found from this file's path (tests read committed fixtures, never the network).
let repoRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let baseEnManifestURL = repoRoot.appending(path: "Resources/Models/openai_whisper-base.en/manifest.json")

func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "AMAlignmentTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A manifest over two small files written into `folder`.
func smallManifest(in folder: URL) throws -> ModelManifest {
    let contents = ["model/weights.bin": Data([1, 2, 3, 4]), "tokenizer/tokenizer.json": Data("{}".utf8)]
    var files: [ModelManifest.File] = []
    for (path, data) in contents.sorted(by: { $0.key < $1.key }) {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        files.append(.init(path: path, size: data.count, sha256: Digest.sha256(data), url: "https://example.invalid/\(path)"))
    }
    var manifest = try ModelManifest(contentsOf: baseEnManifestURL)
    manifest.files = files
    manifest.modelSHA256 = Digest.listing(files.map { ($0.path, $0.sha256) })
    manifest.asrModelID = "test@0#\(manifest.modelSHA256.prefix(8))"
    return manifest
}

@Suite("Model manifest")
struct ModelManifestTests {
    @Test("The committed base.en manifest pins upstream commits and its digests agree")
    func committedManifestIsPinned() throws {
        let manifest = try ModelManifest(contentsOf: baseEnManifestURL)
        let commit = #/[0-9a-f]{40}/#
        #expect(manifest.model == "openai_whisper-base.en")
        #expect(Digest.listing(manifest.files.map { ($0.path, $0.sha256) }) == manifest.modelSHA256)
        let modelSource = try #require(manifest.sources.first { $0.role == "model" })
        #expect(manifest.asrModelID == "openai_whisper-base.en@\(modelSource.commit)#\(manifest.modelSHA256.prefix(8))")
        #expect(manifest.sources.allSatisfy { $0.commit.wholeMatch(of: commit) != nil })
        #expect(manifest.whisperKit.commit.wholeMatch(of: commit) != nil)
        for file in manifest.files {
            #expect(file.sha256.wholeMatch(of: #/[0-9a-f]{64}/#) != nil)
            #expect(file.url.contains("/resolve/") && !file.url.contains("/resolve/main/"), "\(file.url) is not pinned")
            #expect(manifest.sources.contains { file.url.contains("/resolve/\($0.commit)/") })
        }
        #expect(manifest.files.contains { $0.path == "tokenizer/tokenizer.json" })
    }

    @Test("A folder holding the pinned bytes verifies")
    func matchingFolderVerifies() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try smallManifest(in: folder).verify(folder: folder)
    }

    @Test("One changed byte fails verification and names the file")
    func tamperedFileFails() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest = try smallManifest(in: folder)
        try Data([1, 2, 3, 5]).write(to: folder.appending(path: "model/weights.bin"))
        #expect {
            try manifest.verify(folder: folder)
        } throws: { error in
            guard case ModelVerificationError.mismatch(let path, _, _) = error else { return false }
            return path == "model/weights.bin"
        }
    }

    @Test("A missing file fails verification")
    func missingFileFails() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest = try smallManifest(in: folder)
        try FileManager.default.removeItem(at: folder.appending(path: "tokenizer/tokenizer.json"))
        #expect(throws: ModelVerificationError.missing(path: "tokenizer/tokenizer.json")) {
            try manifest.verify(folder: folder)
        }
    }

    @Test("A manifest whose digests disagree with modelSHA256 is rejected")
    func inconsistentManifestFails() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var manifest = try smallManifest(in: folder)
        manifest.files[0].sha256 = String(repeating: "0", count: 64)
        #expect(throws: ModelVerificationError.self) { try manifest.verify(folder: folder) }
    }

    @Test("WhisperKit is never loaded from an unverified folder")
    func liveLoadRefusesUnverifiedFolder() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest = try ModelManifest(contentsOf: baseEnManifestURL)
        await #expect(throws: ModelVerificationError.self) {
            _ = try await WhisperKitTimestamper.load(manifest: manifest, folder: folder)
        }
    }
}
