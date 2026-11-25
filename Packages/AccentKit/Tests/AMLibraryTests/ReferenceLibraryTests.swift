// Spec 15: the starter manifest and the reference library. The bundled manifest is read from the source tree; the
// rebuild and cache behaviour runs on a small bundle written to a temporary folder, with a fake rebuilder.

import AMCore
import AMLibrary
import Foundation
import Testing

/// The repository's `Resources/Starter`.
let starterFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/Starter")

@Suite("Bundled starter manifest") struct BundledManifestTests {
    @Test("The bundled manifest decodes, validates and every file matches its SHA-256")
    func bundledManifestLoads() throws {
        let manifest = try StarterManifest.load(from: starterFolder)
        #expect(manifest.problems().isEmpty)
        #expect(!manifest.phrases.isEmpty)
        for phrase in manifest.phrases {
            #expect(!phrase.targets.isEmpty, "\(phrase.id) has no target")
            #expect(phrase.recording(phrase.headlineVoice) != nil, "\(phrase.id) headline is not one of its recordings")
            #expect(phrase.headlineVoice.rawValue.hasPrefix("p311_"), "\(phrase.id) default voice should be p311")
        }
    }

    @Test("Four packs in CPO's order; Noun and Verb Pairs is empty (coming soon)")
    func packsInOrder() throws {
        let manifest = try StarterManifest.load(from: starterFolder, checkFiles: false)
        #expect(manifest.packs.map(\.title) == ["Stress Shifts", "Noun and Verb Pairs", "Compound Nouns", "Weak Forms"])
        #expect(manifest.packs[1].phrases.isEmpty)
        #expect(manifest.packs.filter { $0.phrases.isEmpty }.map(\.id) == ["noun-verb-pairs"])
    }

    @Test("Every recording carries its attribution; p225 is English, Southern England, F; never p315")
    func recordingsAttributed() throws {
        let manifest = try StarterManifest.load(from: starterFolder, checkFiles: false)
        let recordings = manifest.phrases.flatMap(\.recordings)
        for r in recordings {
            #expect(r.corpus == "VCTK 0.92")
            #expect(r.licence == "CC BY 4.0")
            #expect(r.sourceURL.hasPrefix("https://"))
            #expect(r.audioSHA256.count == 64)
            #expect(!r.accent.isEmpty && !r.region.isEmpty && ["F", "M"].contains(r.gender))
            #expect(r.speaker != "p315" && r.speaker != "p280")
            let seconds = r.trimEnd - r.trimStart
            #expect(seconds >= 2 && seconds <= 6, "\(r.id) is \(seconds) s")
        }
        let p225 = try #require(recordings.first { $0.speaker == "p225" })
        #expect((p225.accent, p225.region, p225.gender) == ("English", "Southern England", "F"))
        // p225 has no 015. The default voice is p311 (v3.3).
        if let phrase = manifest.phrase(PhraseID("vctk-015")) {
            #expect(phrase.headlineVoice == RecordingID("p311_015"))
            #expect(!phrase.recordings.contains { $0.speaker == "p225" })
        }
    }
}

@Suite("Manifest validation") struct ManifestValidationTests {
    @Test("Unknown phrase in a pack, a phrase in no pack and zero targets are named")
    func structuralProblems() {
        let fixture = LibraryFixture.manifest(targets: [], packPhrases: [PhraseID("p-x")])
        let problems = fixture.problems()
        #expect(problems.contains(.noTargets(LibraryFixture.phrase)))
        #expect(problems.contains(.unknownPhrase(pack: "pack", phrase: PhraseID("p-x"))))
        #expect(problems.contains(.phraseInNoPack(LibraryFixture.phrase)))
    }

    @Test("A missing file and a SHA-256 mismatch are named")
    func fileProblems() throws {
        let fixture = try LibraryFixture()
        try FileManager.default.removeItem(at: fixture.bundle.appending(path: "timings/p/v.json"))
        try Data("changed".utf8).write(to: fixture.bundle.appending(path: "audio/p/v.flac"))
        let problems = fixture.manifest.fileProblems(in: fixture.bundle)
        #expect(problems.contains(.missingFile("timings/p/v.json")))
        #expect(problems.contains { if case .shaMismatch(let path, _, _) = $0 { path == "audio/p/v.flac" } else { false } })
        #expect(throws: StarterManifest.Problem.self) {
            try StarterManifest.load(from: fixture.bundle)
        }
    }

    @Test("A zero-phrase pack loads")
    func zeroPhrasePackLoads() throws {
        let fixture = try LibraryFixture()
        let manifest = try StarterManifest.load(from: fixture.bundle)
        #expect(manifest.packs.map(\.phrases.count) == [1, 0])
        let library = try ReferenceLibrary(bundle: fixture.bundle, caches: fixture.caches, rebuilder: fixture.rebuilder())
        #expect(library.manifest.packs.last?.phrases.isEmpty == true)
    }
}

@Suite("Reference library") struct ReferenceLibraryTests {
    @Test("A current bundled analysis is read as is: no rebuild, nothing written")
    func currentIdentityReadsBundle() async throws {
        let fixture = try LibraryFixture()
        let library = try ReferenceLibrary(bundle: fixture.bundle, caches: fixture.caches, rebuilder: fixture.rebuilder())
        let natives = try await library.natives(phrase: LibraryFixture.phrase)
        #expect(natives.map(\.analysis.key) == ["key-1"])
        #expect(natives.first?.audioSHA256 == fixture.manifest.phrases[0].recordings[0].audioSHA256)
        #expect(await library.rebuilds.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.caches.path))
    }

    @Test("A stale identity rebuilds into Caches and never writes the bundle")
    func staleIdentityRebuildsIntoCaches() async throws {
        let fixture = try LibraryFixture()
        let before = try fixture.bundleSnapshot()
        try fixture.makeBundleReadOnly()
        defer { fixture.makeBundleWritable() }
        let library = try ReferenceLibrary(
            bundle: fixture.bundle, caches: fixture.caches, rebuilder: fixture.rebuilder(expectedKey: "key-2"))
        let natives = try await library.natives(phrase: LibraryFixture.phrase)
        #expect(natives.map(\.analysis.key) == ["key-2"])
        #expect(await library.rebuilds == [LibraryFixture.recording: 1])
        let cached = library.cacheURL(LibraryFixture.recording, phrase: LibraryFixture.phrase)
        #expect(cached.path.hasPrefix(fixture.caches.path))
        #expect(FileManager.default.fileExists(atPath: cached.path))
        #expect(try fixture.bundleSnapshot() == before)
        // The next read comes from the cache: no second rebuild.
        _ = try await library.natives(phrase: LibraryFixture.phrase)
        #expect(await library.rebuilds == [LibraryFixture.recording: 1])
    }

    @Test("A corrupt cache is rebuilt once and then used")
    func corruptCacheRebuildsOnce() async throws {
        let fixture = try LibraryFixture()
        let library = try ReferenceLibrary(bundle: fixture.bundle, caches: fixture.caches, rebuilder: fixture.rebuilder())
        try fixture.writeCorruptCache(library)
        let loaded = try await library.loadNatives(phrase: LibraryFixture.phrase, decode: LibraryFixture.decode)
        #expect(loaded == ["ok"])
        #expect(await library.rebuilds == [LibraryFixture.recording: 1])
    }

    @Test("A corrupt cache whose rebuild is corrupt too: one rebuild, then referenceCacheCorrupt")
    func corruptTwiceIsReported() async throws {
        let fixture = try LibraryFixture()
        let library = try ReferenceLibrary(
            bundle: fixture.bundle, caches: fixture.caches, rebuilder: fixture.rebuilder(rebuiltBytes: Data("{".utf8)))
        try fixture.writeCorruptCache(library)
        await #expect(throws: ReferenceLoadError.referenceCacheCorrupt(LibraryFixture.recording)) {
            try await library.loadNatives(phrase: LibraryFixture.phrase, decode: LibraryFixture.decode)
        }
        #expect(await library.rebuilds == [LibraryFixture.recording: 1])
        #expect(ReferenceLoadError.referenceCacheCorrupt(LibraryFixture.recording).operational
            == .referenceCacheCorrupt(LibraryFixture.recording))
    }

    @Test("A failing rebuild is referenceCacheCorrupt")
    func failingRebuildIsReported() async throws {
        let fixture = try LibraryFixture()
        let library = try ReferenceLibrary(
            bundle: fixture.bundle, caches: fixture.caches, rebuilder: fixture.rebuilder(expectedKey: "key-2", fails: true))
        await #expect(throws: ReferenceLoadError.referenceCacheCorrupt(LibraryFixture.recording)) {
            try await library.loadNatives(phrase: LibraryFixture.phrase, decode: LibraryFixture.decode)
        }
    }

    @Test("Identity: the recording's SHA-256, the phrase's override and target hashes, the native-set hash")
    func identity() throws {
        let fixture = try LibraryFixture()
        let library = try ReferenceLibrary(bundle: fixture.bundle, caches: fixture.caches, rebuilder: fixture.rebuilder())
        let identity = library.identity(phrase: LibraryFixture.phrase, voice: LibraryFixture.recording)
        let recording = fixture.manifest.phrases[0].recordings[0]
        #expect(identity.recordingSHA256 == recording.audioSHA256)
        #expect(identity.nativeSetHash == SHA256Digest.hex(of: Data(recording.audioSHA256.utf8)))
        #expect(identity.targetsHash == (try CanonicalJSON.sha256([1])))
        #expect(identity.pronunciationOverridesHash == (try CanonicalJSON.sha256([1: "K AH0 N"])))
    }
}

/// A one-phrase, one-recording bundle in a temporary folder, plus a pack with no phrases.
struct LibraryFixture {
    static let phrase = PhraseID("p")
    static let recording = RecordingID("v")
    static let goodBytes = Data(#"{"ok":true}"#.utf8)

    let root: URL
    let bundle: URL
    let caches: URL
    let manifest: StarterManifest

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "am-library-\(UUID().uuidString)")
        bundle = root.appending(path: "Bundle/Starter")
        caches = root.appending(path: "Caches/Starter")
        let files = ["audio/p/v.flac": Data("flac".utf8), "timings/p/v.json": Data("{}".utf8), "analysis/p/v.json": Self.goodBytes]
        for (path, data) in files {
            let url = bundle.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        manifest = Self.manifest(
            targets: [1], packPhrases: [Self.phrase],
            sha: { SHA256Digest.hex(of: files[$0]!) })
        try manifest.encoded().write(to: bundle.appending(path: StarterManifest.fileName))
    }

    static func manifest(
        targets: [Int], packPhrases: [PhraseID], sha: (String) -> String = { _ in String(repeating: "0", count: 64) }
    ) -> StarterManifest {
        let recording = StarterManifest.Recording(
            id: recording, speaker: "v", accent: "English", region: "Somewhere", gender: "F", corpus: "VCTK 0.92",
            licence: "CC BY 4.0", sourceURL: "https://example.org", utteranceID: "v_001", sourceFile: "v_001.flac",
            trimStart: 0, trimEnd: 3, audio: "audio/p/v.flac", audioSHA256: sha("audio/p/v.flac"),
            timings: "timings/p/v.json", timingsSHA256: sha("timings/p/v.json"), analysis: "analysis/p/v.json",
            analysisSHA256: sha("analysis/p/v.json"), analysisKey: "key-1")
        return StarterManifest(
            asrModelID: "model",
            packs: [
                StarterManifest.Pack(id: "pack", title: "Pack", phrases: packPhrases),
                StarterManifest.Pack(id: "empty", title: "Coming soon", phrases: []),
            ],
            phrases: [StarterManifest.Phrase(
                id: phrase, text: "we can go", targets: targets, pronunciations: [1: "K AH0 N"], headlineVoice: recording.id,
                recordings: [recording])])
    }

    /// A fake rebuilder: the running code's key is `expectedKey`; a rebuild returns `rebuiltBytes` under that key.
    func rebuilder(expectedKey: String = "key-1", rebuiltBytes: Data = goodBytes, fails: Bool = false) -> ReferenceRebuilder {
        ReferenceRebuilder(
            expectedKey: { _ in expectedKey },
            rebuild: { source in
                #expect(source.audio.path.hasPrefix(bundle.path))
                if fails { throw CocoaError(.fileReadCorruptFile) }
                return DerivedRecord(level: .l1, key: expectedKey, bytes: rebuiltBytes)
            })
    }

    /// The pipeline's role in the test: a record is good when its bytes are `{"ok":true}`.
    static func decode(_ recording: NativeRecording) -> String? {
        struct OK: Decodable { let ok: Bool }
        return (try? JSONDecoder().decode(OK.self, from: recording.analysis.bytes))?.ok == true ? "ok" : nil
    }

    func writeCorruptCache(_ library: ReferenceLibrary) throws {
        let url = library.cacheURL(Self.recording, phrase: Self.phrase)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a record".utf8).write(to: url)
    }

    /// Every file under the bundle with its contents.
    func bundleSnapshot() throws -> [String: Data] {
        var snapshot: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            snapshot[url.path] = try Data(contentsOf: url)
        }
        return snapshot
    }

    /// Makes the bundle folder tree read-only, as the app bundle is.
    func makeBundleReadOnly() throws { try setPermissions(0o555) }
    func makeBundleWritable() { try? setPermissions(0o755) }

    private func setPermissions(_ mode: Int) throws {
        let enumerator = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isDirectoryKey])
        var folders = [bundle]
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { folders.append(url) }
        }
        for folder in folders { try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: folder.path) }
    }
}
