// Spec 17: My Phrases on disk. Every test works in its own temporary folder with a fake rebuilder standing in for
// `AMPipeline`; the clip samples are synthesised, nothing is committed.

import AMCore
import AMLibrary
import Foundation
import Synchronization
import Testing

@Suite("My Phrases store (spec 17)") struct MyPhraseStoreTests {
    final class Folder: Sendable {
        let url = FileManager.default.temporaryDirectory.appending(path: "MyPhraseStore-\(UUID().uuidString)")
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    /// A rebuilder whose expected key can move (an algorithm bump) and which counts its rebuilds.
    final class FakeRebuilder: Sendable {
        let key = Mutex("key-1")
        let rebuilt = Mutex(0)
        var rebuilder: MyPhraseRebuilder {
            MyPhraseRebuilder(
                expectedKey: { [self] _ in key.withLock { $0 } },
                rebuild: { [self] phrase, samples in
                    rebuilt.withLock { $0 += 1 }
                    return DerivedRecord(
                        level: .l1, key: key.withLock { $0 }, bytes: Data("\(phrase.id):\(samples.count)".utf8))
                })
        }
    }

    static let clip = (0..<8_000).map { Float(sin(Double($0) * 0.05)) * 0.4 }

    static func phrase(_ n: Int, text: String = "the rainbow was caused") -> MyPhrase {
        MyPhrase(
            id: PhraseID("my-\(n)"), text: text, sourceFileName: "clip-\(n).m4a",
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(n) * 60),
            selection: ClipSelection(start: 0.2, end: 0.7), clipSHA256: "sha-\(n)",
            pronunciations: [
                StoredPronunciation(word: 1, text: "rainbow", arpabet: "R EY1 N B OW2", expectedAmbiguous: false,
                                    chosenBy: "dictionary")
            ])
    }

    static func record(_ key: String = "key-1") -> DerivedRecord {
        DerivedRecord(level: .l1, key: key, bytes: Data("analysis".utf8))
    }

    @Test("a created phrase is listed newest first, with its clip, reference and subtitle; staging is empty")
    func createAndList() async throws {
        let folder = Folder()
        let store = MyPhraseStore(root: folder.url, rebuilder: FakeRebuilder().rebuilder)
        try await store.create(Self.phrase(1), clip: Self.clip, reference: Self.record())
        try await store.create(Self.phrase(2), clip: Self.clip, reference: Self.record())
        #expect(store.phrases().map(\.id) == [PhraseID("my-2"), PhraseID("my-1")])
        #expect(store.phrase(PhraseID("my-1"))?.subtitle == "My Phrases · From clip-1.m4a")
        #expect(try store.clip(PhraseID("my-1")) == Self.clip)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.folder(PhraseID("my-1")).path).sorted()
        #expect(files == ["clip.caf", "phrase.json", "reference.json"])
        let staging = folder.url.appending(path: "my-phrases/.staging")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty)

        let natives = try await store.natives(phrase: PhraseID("my-1"))
        #expect(natives.map(\.id) == [MyPhrase.recordingID])
        #expect(natives.first?.analysis == Self.record())
        #expect(natives.first?.audioSHA256 == "sha-1")
        #expect(store.identity(phrase: PhraseID("my-1"), voice: MyPhrase.recordingID) == Self.phrase(1).identity)
    }

    @Test("creating the same phrase twice fails without touching the first")
    func createIsExclusive() async throws {
        let folder = Folder()
        let store = MyPhraseStore(root: folder.url, rebuilder: FakeRebuilder().rebuilder)
        try await store.create(Self.phrase(1), clip: Self.clip, reference: Self.record())
        await #expect(throws: StorageError.self) {
            try await store.create(Self.phrase(1, text: "other words"), clip: [], reference: Self.record("x"))
        }
        #expect(store.phrase(PhraseID("my-1"))?.text == "the rainbow was caused")
    }

    @Test("an update replaces the reference and phrase.json in place, and survives a relaunch")
    func updateInPlace() async throws {
        let folder = Folder()
        let rebuilder = FakeRebuilder()
        let store = MyPhraseStore(root: folder.url, rebuilder: rebuilder.rebuilder)
        try await store.create(Self.phrase(1), clip: Self.clip, reference: Self.record())
        var edited = Self.phrase(1)
        edited.text = "the rainbow was made"
        edited.transcriptRevision = 1
        rebuilder.key.withLock { $0 = "key-2" }
        try await store.update(edited, reference: Self.record("key-2"))

        let relaunched = MyPhraseStore(root: folder.url, rebuilder: rebuilder.rebuilder)
        #expect(relaunched.phrases().map(\.id) == [PhraseID("my-1")])
        #expect(relaunched.phrase(PhraseID("my-1")) == edited)
        #expect(relaunched.phrase(PhraseID("my-1"))?.pronunciations == Self.phrase(1).pronunciations)
        #expect(try await relaunched.natives(phrase: PhraseID("my-1")).first?.analysis.key == "key-2")
        #expect(rebuilder.rebuilt.withLock { $0 } == 0)
        #expect(relaunched.identity(phrase: PhraseID("my-1"), voice: MyPhrase.recordingID).transcriptRevision == 1)
    }

    @Test("a reference keyed for other code is rebuilt from clip.caf and stored; a missing phrase updates nothing")
    func staleReferenceRebuilt() async throws {
        let folder = Folder()
        let rebuilder = FakeRebuilder()
        let store = MyPhraseStore(root: folder.url, rebuilder: rebuilder.rebuilder)
        try await store.create(Self.phrase(1), clip: Self.clip, reference: Self.record())
        rebuilder.key.withLock { $0 = "key-2" }
        let natives = try await store.natives(phrase: PhraseID("my-1"))
        #expect(natives.first?.analysis.key == "key-2")
        #expect(natives.first?.analysis.bytes == Data("my-1:\(Self.clip.count)".utf8))
        #expect(rebuilder.rebuilt.withLock { $0 } == 1)
        // Stored: the next read is a hit.
        _ = try await store.natives(phrase: PhraseID("my-1"))
        #expect(rebuilder.rebuilt.withLock { $0 } == 1)
        await #expect(throws: StorageError.self) { try await store.update(Self.phrase(9), reference: Self.record()) }
        #expect(store.phrase(PhraseID("my-9")) == nil)
    }

    @Test("a corrupt reference is cacheCorrupt; recovery deletes leftover staging folders")
    func corruptAndRecover() async throws {
        let folder = Folder()
        let store = MyPhraseStore(root: folder.url, rebuilder: FakeRebuilder().rebuilder)
        try await store.create(Self.phrase(1), clip: Self.clip, reference: Self.record())
        try Data("not json".utf8).write(to: store.folder(PhraseID("my-1")).appending(path: "reference.json"))
        await #expect(throws: ReferenceSetError.cacheCorrupt(MyPhrase.recordingID)) {
            try await store.natives(phrase: PhraseID("my-1"))
        }
        let leftover = folder.url.appending(path: "my-phrases/.staging/my-2")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        #expect(await store.recover() == 1)
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(store.phrases().map(\.id) == [PhraseID("my-1")])
    }

    @Test("the phrase library routes My Phrases to their store and lists them next to the starter packs")
    func phraseLibrary() async throws {
        let folder = Folder()
        let store = MyPhraseStore(root: folder.url, rebuilder: FakeRebuilder().rebuilder)
        try await store.create(Self.phrase(1), clip: Self.clip, reference: Self.record())
        let library = PhraseLibrary(starter: nil, myPhrases: store)
        #expect(library.packs.isEmpty)
        #expect(library.myPhraseList().map(\.id) == [PhraseID("my-1")])
        #expect(try await library.natives(phrase: PhraseID("my-1")).count == 1)
        #expect(library.identity(phrase: PhraseID("my-1"), voice: MyPhrase.recordingID) == Self.phrase(1).identity)
    }

    @Test("a take marked unalignable is comparable again after markComparable, across a relaunch")
    func markComparable() async throws {
        let fixture = try TakeStoreFixture()
        _ = try await fixture.store().save(fixture.record(1))
        try await fixture.store().markUnalignable(take: fixture.ref(1), reason: "recorded for the old wording")
        try await fixture.store().markComparable(take: fixture.ref(1))
        #expect(await fixture.store().takes(for: TakeStoreFixture.phrase).first?.status == .comparable)
        await #expect(throws: TakeStoreError.notFound(fixture.ref(2))) {
            try await fixture.store().markComparable(take: fixture.ref(2))
        }
    }
}
