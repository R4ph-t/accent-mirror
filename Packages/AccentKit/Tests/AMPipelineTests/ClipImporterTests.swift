// Spec 17: the clip importer end to end. The clips are encoded in the test (AAC m4a, and an mp4 with a video track
// first) from the committed CC BY smoke set's VCTK p288 reading of prompt 018; nothing new is committed. Word timings
// are replayed through `FixtureTimestamper` from a folder written in the test: no ASR, no network, no microphone.

import AMAlignment
import AMCore
import AMLibrary
import AMPipeline
import Foundation
import Synchronization
import Testing

@MainActor @Suite("Clip import (spec 17)", .serialized) struct ClipImporterTests {
    final class Folder: Sendable {
        let url = FileManager.default.temporaryDirectory.appending(path: "ClipImporter-\(UUID().uuidString)")
        init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    /// Holds one clip's recognition until opened, ignoring cancellation, like a model that can't stop early.
    final class GatedTimestamper: WordTimestamper {
        let base: any WordTimestamper
        let gated: String
        private let gate = Mutex<(open: Bool, waiting: [CheckedContinuation<Void, Never>])>((false, []))
        init(_ base: any WordTimestamper, gated: String) {
            self.base = base
            self.gated = gated
        }
        var asrModelID: String { base.asrModelID }
        func open() {
            let waiting = gate.withLock { state in
                state.open = true
                defer { state.waiting = [] }
                return state.waiting
            }
            for continuation in waiting { continuation.resume() }
        }
        func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] {
            if request.clipID == gated {
                await withCheckedContinuation { continuation in
                    let open = gate.withLock { state in
                        if !state.open { state.waiting.append(continuation) }
                        return state.open
                    }
                    if open { continuation.resume() }
                }
            }
            return try await base.wordTimestamps(for: request)
        }
    }

    /// Counts the tagger's calls, answering one class for every word.
    final class CountingTagger: LexicalClassTagger {
        let answer: LexicalClass
        let calls = Atomic<Int>(0)
        init(_ answer: LexicalClass) { self.answer = answer }
        func lexicalClasses(in text: String, words: [Range<String.Index>]) -> [LexicalClass] {
            calls.add(1, ordering: .relaxed)
            return words.map { _ in answer }
        }
    }

    static let clipItem = "vctk-p288_018"
    static let takeItem = "vctk-p245_018"
    nonisolated static let createdAt = Date(timeIntervalSince1970: 1_795_000_000)

    /// One test's world: a temporary Application Support, the encoded clips, and the importer once timings exist.
    struct World {
        let folder: Folder
        let store: MyPhraseStore
        let takes: TakeStore
        let phrases: ImportedPhrases
        let importer: ClipImporter
        let timings: URL
        /// Which clip's recognition to hold, and the gate once the recogniser loads.
        let holder: GateHolder
    }

    /// The clip's samples (16 kHz mono) and its replayed words.
    static func source() throws -> (samples: [Float], words: [WordTimestamp], asrModelID: String) {
        let items = try PipelineFixtures.items()
        let timings = try PipelineFixtures.timings()
        let item = try #require(items[clipItem])
        let samples = try SmokePlacementGoldenTests.readMono(SmokePlacementGoldenTests.smoke.appending(path: item.audio))
        return (samples, try #require(timings.recording(for: clipItem)).words, timings.asrModelID)
    }

    /// The importer over a fresh folder. Its recogniser loads `timings` (written by `record`) on first use; `gated`
    /// holds that clip's recognition until opened.
    static func world(tagger: any LexicalClassTagger = NaturalLanguageTagger(), folder: Folder = Folder()) throws
        -> World
    {
        let timings = folder.url.appending(path: "timings")
        let asrModelID = try PipelineFixtures.timings().asrModelID
        let holder = GateHolder()
        let speech = SpeechModelHost(asrModelID: asrModelID) {
            let fixture = try FixtureTimestamper(directory: timings)
            return holder.wrap(fixture)
        }
        let analyzer = Analyzer(speech: speech, configuration: try .shipped())
        let selector = try PronunciationSelector.bundled(tagger: tagger)
        let root = folder.url.appending(path: "Accent Mirror")
        // The store's rebuilder comes from the phrases; it reads only the phrase and the analyzer, not the store.
        let phrases = ImportedPhrases(
            store: MyPhraseStore(root: root, rebuilder: placeholderRebuilder), selector: selector, analyzer: analyzer)
        let wired = MyPhraseStore(root: root, rebuilder: phrases.rebuilder)
        let wiredPhrases = ImportedPhrases(store: wired, selector: selector, analyzer: analyzer)
        let takes = TakeStore(
            root: root,
            recomputer: .pipeline(analyzer: analyzer, reference: wired) { wiredPhrases.input($0) })
        let importer = ClipImporter(phrases: wiredPhrases, takes: takes, now: { createdAt })
        return World(
            folder: folder, store: wired, takes: takes, phrases: wiredPhrases, importer: importer, timings: timings,
            holder: holder)
    }

    static let placeholderRebuilder = MyPhraseRebuilder(
        expectedKey: { _ in "" }, rebuild: { _, _ in throw InjectedError() })

    /// Where each world's gate lives (the recogniser is built lazily, after the test knows which clip to gate).
    final class GateHolder: Sendable {
        let gated = Mutex<String?>(nil)
        let made = Mutex<GatedTimestamper?>(nil)
        func wrap(_ base: FixtureTimestamper) -> any WordTimestamper {
            guard let clipID = gated.withLock({ $0 }) else { return base }
            let gate = GatedTimestamper(base, gated: clipID)
            made.withLock { $0 = gate }
            return gate
        }
    }

    /// Writes the replay folder: the clip's words for each selection (shifted to the selection, keyed by the
    /// selection audio's SHA-256) plus your take's words.
    static func record(_ world: World, proposal: ClipProposal, selections: [ClipSelection]) throws {
        let source = try source()
        let all = try PipelineFixtures.timings()
        var entries: [ReplayManifest.Entry] = []
        try FileManager.default.createDirectory(at: world.timings, withIntermediateDirectories: true)
        func write(_ recording: RecordedTimestamps) throws {
            let data = try JSONEncoder().encode(recording)
            let file = recording.clipID.prefix(24) + ".json"
            try data.write(to: world.timings.appending(path: String(file)))
            entries.append(ReplayManifest.Entry(clipID: recording.clipID, file: String(file), sha256: Digest.sha256(data)))
        }
        for selection in selections {
            let audio = proposal.audio(selection)
            let words = source.words
                .filter { $0.start >= selection.start - 0.05 && $0.end <= selection.end + 0.05 }
                .map {
                    WordTimestamp(
                        word: $0.word, start: max(0, $0.start - selection.start),
                        end: min(selection.duration, $0.end - selection.start), probability: $0.probability)
                }
            try write(RecordedTimestamps(
                clipID: audio.clipID, audioSHA256: audio.sha256, asrModelID: source.asrModelID,
                text: ClipImporterTests.text(words), words: words))
        }
        try write(try #require(all.recording(for: takeItem)))
        let manifest = ReplayManifest(asrModelID: source.asrModelID, attribution: "VCTK 0.92, CC BY 4.0", clips: entries)
        try JSONEncoder().encode(manifest).write(to: world.timings.appending(path: ReplayManifest.fileName))
    }

    static func text(_ words: [WordTimestamp]) -> String {
        words.map { $0.word.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    /// The clip encoded as `name` in the world's folder.
    static func encode(_ world: World, _ name: String, as container: ClipEncoding.Container, samples: [Float]? = nil)
        async throws -> URL
    {
        let url = world.folder.url.appending(path: name)
        try await ClipEncoding.write(samples ?? (try source().samples), to: url, as: container)
        return url
    }

    /// Low deterministic noise, so a stretch with no speech still has a floor (as a real file does).
    static func noise(seconds: Double, seed: UInt64) -> [Float] {
        var state = seed
        return (0..<Int(seconds * 16_000)).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Float(state >> 40) / Float(1 << 24) - 0.5) * 0.002
        }
    }

    // MARK: - Tests

    @Test("the m4a and mp4 clips become a phrase with a transcript, offline", arguments: [
        ("clip.m4a", ClipEncoding.Container.m4a), ("clip.mp4", ClipEncoding.Container.mp4WithVideo),
    ])
    func importsOffline(name: String, container: ClipEncoding.Container) async throws {
        URLProtocol.registerClass(NoNetworkProtocol.self)
        defer { URLProtocol.unregisterClass(NoNetworkProtocol.self) }
        let attemptsBefore = NoNetworkProtocol.attempts.withLock { $0 }
        let world = try Self.world()
        let url = try await Self.encode(world, name, as: container)
        let proposal = try await world.importer.propose(url)
        #expect(abs(proposal.duration - 4.6) < 0.2)
        #expect(proposal.fileName == name)
        #expect(!proposal.speechRegions.isEmpty)
        #expect(!proposal.waveform.isEmpty && proposal.waveform.allSatisfy { (0...1).contains($0) })
        let onset = try #require(proposal.speechRegions.first).start
        #expect(abs(proposal.defaultSelection.start - max(0, onset - 0.2)) < 0.011)
        #expect(proposal.defaultSelection.end == ClipSelectionSnap.down(proposal.duration))

        try Self.record(world, proposal: proposal, selections: [proposal.defaultSelection])
        let session = world.importer.session(proposal)
        await session.settle()
        #expect(session.transcriptionError == nil)
        #expect(session.transcript.hasPrefix("Aristotle thought that the rainbow"))
        let phrase = try await session.commit()

        #expect(phrase.text == session.transcript)
        #expect(phrase.subtitle == "My Phrases · From \(name)")
        #expect(phrase.transcriptRevision == 0)
        #expect(phrase.selection == proposal.defaultSelection)
        #expect(phrase.pronunciations.count == phraseTokens(phrase.text).count)
        #expect(world.store.phrases().map(\.id) == [phrase.id])
        let stored = try world.store.clip(phrase.id)
        let selected = proposal.audio(phrase.selection).samples
        #expect(stored.count == selected.count, "\(phrase.selection) \(proposal.duration)")
        // The stored reference is what the running code expects: reading it rebuilds nothing.
        let natives = try await world.store.natives(phrase: phrase.id)
        #expect(natives.count == 1)
        #expect(DerivedCoding.native(in: try #require(natives.first).analysis) != nil)
        #expect(await world.store.rebuilds.isEmpty)
        #expect(NoNetworkProtocol.attempts.withLock { $0 } == attemptsBefore, "no request was attempted")
    }

    @Test("an unreadable file is audioUnreadable; a selection with no speech is noSpeech")
    func twoErrors() async throws {
        let world = try Self.world()
        let broken = world.folder.url.appending(path: "broken.m4a")
        try Data("not audio at all".utf8).write(to: broken)
        for url in [broken, world.folder.url.appending(path: "missing.mp4")] {
            await #expect(throws: ClipImportError.audioUnreadable) { try await world.importer.propose(url) }
        }
        #expect(ClipImportError.audioUnreadable.operational == .audioUnreadable)

        let samples = Self.noise(seconds: 3, seed: 1) + (try Self.source().samples) + Self.noise(seconds: 1, seed: 2)
        let url = try await Self.encode(world, "padded.m4a", as: .m4a, samples: samples)
        let proposal = try await world.importer.propose(url)
        let silent = ClipSelection(start: 0.5, end: 2.5)
        #expect(!proposal.hasSpeech(in: silent))
        try Self.record(world, proposal: proposal, selections: [proposal.defaultSelection])
        let session = world.importer.session(proposal)
        await session.settle()
        try session.select(silent)
        await session.settle()
        #expect(session.transcriptionError == .noSpeech)
        await #expect(throws: ClipImportError.noSpeech) {
            try await world.importer.commit(proposal, selection: silent, transcript: "the rain")
        }
        await #expect(throws: ClipImportError.emptyTranscript) {
            try await world.importer.commit(proposal, selection: proposal.defaultSelection, transcript: "  ,  ")
        }
        #expect(world.store.phrases().isEmpty)
    }

    @Test("selections: 0.4 s and 15.1 s rejected, 0.5 s and 15 s accepted, snapped to 10 ms, inside the file")
    func selectionBounds() async throws {
        let world = try Self.world()
        let samples = Self.noise(seconds: 0.5, seed: 3) + (try Self.source().samples) + Self.noise(seconds: 12, seed: 4)
        let proposal = try await world.importer.propose(try await Self.encode(world, "long.m4a", as: .m4a, samples: samples))
        #expect(proposal.duration > 16)
        #expect(proposal.defaultSelection.duration <= 15 + 1e-9)

        #expect(throws: ClipImportError.invalidSelection(.tooShort)) {
            try proposal.validate(ClipSelection(start: 1, end: 1.4))
        }
        #expect(throws: ClipImportError.invalidSelection(.tooLong)) {
            try proposal.validate(ClipSelection(start: 0.5, end: 15.6))
        }
        #expect(try proposal.validate(ClipSelection(start: 1, end: 1.5)) == ClipSelection(start: 1, end: 1.5))
        #expect(try proposal.validate(ClipSelection(start: 0.5, end: 15.5)).duration == 15)
        // Snapped to 10 ms; length is judged after snapping.
        let snapped = try proposal.validate(ClipSelection(start: 0.123, end: 1.2345))
        #expect(abs(snapped.start - 0.12) < 1e-9 && abs(snapped.end - 1.23) < 1e-9)
        #expect(try proposal.validate(ClipSelection(start: 1.003, end: 1.497)).duration > 0.5 - 1e-9)
        #expect(throws: ClipImportError.invalidSelection(.outsideFile)) {
            try proposal.validate(ClipSelection(start: -0.1, end: 1))
        }
        #expect(throws: ClipImportError.invalidSelection(.outsideFile)) {
            try proposal.validate(ClipSelection(start: proposal.duration - 1, end: proposal.duration + 0.5))
        }
        // An invalid selection leaves the session as it was.
        try Self.record(world, proposal: proposal, selections: [proposal.defaultSelection])
        let session = world.importer.session(proposal)
        await session.settle()
        #expect(throws: ClipImportError.invalidSelection(.tooShort)) { try session.select(ClipSelection(start: 1, end: 1.4)) }
        #expect(session.selectionRevision == 0)
        #expect(session.selection == proposal.defaultSelection)
        await #expect(throws: ClipImportError.invalidSelection(.tooLong)) {
            try await world.importer.commit(proposal, selection: ClipSelection(start: 0, end: 15.1), transcript: "rain")
        }
    }

    @Test("a stale transcription is dropped: the result for an older selection never lands")
    func staleTranscriptionDropped() async throws {
        let world = try Self.world()
        let proposal = try await world.importer.propose(try await Self.encode(world, "clip.m4a", as: .m4a))
        let first = proposal.defaultSelection
        let second = try proposal.validate(ClipSelection(start: first.start, end: first.start + 1.5))
        try Self.record(world, proposal: proposal, selections: [first, second])
        let holder = world.holder
        holder.gated.withLock { $0 = proposal.audio(first).clipID }

        let session = world.importer.session(proposal)
        #expect(session.isTranscribing)
        try session.select(second)
        #expect(session.selectionRevision == 1)
        await session.settle()
        let secondText = session.transcript
        #expect(!secondText.isEmpty)
        #expect(!secondText.contains("rain."))
        // The first selection's result arrives late and is dropped.
        let gate = try #require(holder.made.withLock { $0 })
        gate.open()
        for _ in 0..<200 where session.staleDropped == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(session.staleDropped == 1)
        #expect(session.transcript == secondText)
    }

    @Test("typed text beats a late ASR result; closing drops the result in flight")
    func typedTextWins() async throws {
        let world = try Self.world()
        let proposal = try await world.importer.propose(try await Self.encode(world, "clip.m4a", as: .m4a))
        try Self.record(world, proposal: proposal, selections: [proposal.defaultSelection])
        let holder = world.holder
        holder.gated.withLock { $0 = proposal.audio(proposal.defaultSelection).clipID }

        let session = world.importer.session(proposal)
        // Let the recogniser load (and the gate exist) before typing.
        for _ in 0..<500 where holder.made.withLock({ $0 }) == nil { try await Task.sleep(for: .milliseconds(10)) }
        session.edit(transcript: "Aristotle thought")
        #expect(session.userEdited)
        try #require(holder.made.withLock { $0 }).open()
        await session.settle()
        #expect(!session.isTranscribing)
        #expect(session.transcript == "Aristotle thought")

        let closing = world.importer.session(proposal)
        closing.close()
        await closing.settle()
        #expect(closing.isClosed)
        #expect(closing.transcript.isEmpty)
    }

    @Test("reanalyze replaces the reference in place and marks a take that no longer aligns as unalignable")
    func reanalyzeMarksUnalignable() async throws {
        let world = try Self.world()
        let proposal = try await world.importer.propose(try await Self.encode(world, "clip.m4a", as: .m4a))
        try Self.record(world, proposal: proposal, selections: [proposal.defaultSelection])
        let original = "Aristotle thought that the rainbow was caused by reflection of the sun's rays by the rain."
        let phrase = try await world.importer.commit(proposal, selection: proposal.defaultSelection, transcript: original)

        // Your take of the same words, analysed against the clip and saved, as the coordinator would.
        let items = try PipelineFixtures.items()
        let you = try PipelineFixtures.take(try #require(items[Self.takeItem]))
        let input = try #require(world.phrases.input(phrase.id))
        let run = await world.phrases.analyzer.run(
            take: you, phrase: input, reference: world.store, voice: MyPhrase.recordingID)
        guard case .analysed(let result) = run.response.outcome else {
            Issue.record("expected your take to be analysed against the clip: \(run.response.outcome)")
            return
        }
        _ = try await world.takes.save(TakeRecord(
            takeID: result.takeID, phraseID: phrase.id, recording: MyPhrase.recordingID, recordedAt: you.recordedAt,
            audioSHA256: you.sha256, samples: you.samples, derived: run.derived, identity: run.response.identity))
        let take = TakeRef(phrase: phrase.id, id: result.takeID)
        let oldKey = try #require(try await world.store.natives(phrase: phrase.id).first).analysis.key

        // New wording the recordings don't say: the reference is recomputed in place, the take can't be realigned.
        let edited = "Aristotle thought that the sunset was caused by reflection of the moon's rays by the rain."
        let report = try await world.importer.reanalyze(phraseID: phrase.id, transcript: edited)
        #expect(report.unalignable == [take])
        #expect(report.phrase.transcriptRevision == 1)
        #expect(world.store.phrases().map(\.id) == [phrase.id])
        let stored = try #require(world.store.phrase(phrase.id))
        #expect(stored.text == edited && stored.transcriptRevision == 1)
        #expect(stored.createdAt == phrase.createdAt && stored.clipSHA256 == phrase.clipSHA256)
        let newKey = try #require(try await world.store.natives(phrase: phrase.id).first).analysis.key
        #expect(newKey != oldKey)
        #expect(await world.store.rebuilds.isEmpty)
        let takes = await world.takes.takes(for: phrase.id)
        #expect(takes.map(\.ref) == [take], "kept, and still counted")
        #expect(takes.first?.status == .unalignable(reason: "recorded for the old wording"))

        // Back to words the take says: realigned and comparable again.
        let back = try await world.importer.reanalyze(phraseID: phrase.id, transcript: original)
        #expect(back.realigned == [take])
        #expect(back.phrase.transcriptRevision == 2)
        #expect(await world.takes.takes(for: phrase.id).first?.status == .comparable)
        await #expect(throws: ClipImportError.phraseNotFound(PhraseID("my-none"))) {
            try await world.importer.reanalyze(phraseID: PhraseID("my-none"), transcript: original)
        }
    }

    @Test("the persisted pronunciation survives a relaunch: the tagger isn't asked again")
    func persistedPronunciationSurvivesRelaunch() async throws {
        let folder = Folder()
        let nounTagger = CountingTagger(.noun)
        let world = try Self.world(tagger: nounTagger, folder: folder)
        let proposal = try await world.importer.propose(try await Self.encode(world, "clip.m4a", as: .m4a))
        try Self.record(world, proposal: proposal, selections: [proposal.defaultSelection])
        // "record" is a stress-shift word: the tagger picks the noun (first-syllable stress) at import.
        let text = "Aristotle thought that the record was caused by reflection of the sun's rays by the rain."
        let phrase = try await world.importer.commit(proposal, selection: proposal.defaultSelection, transcript: text)
        #expect(nounTagger.calls.load(ordering: .relaxed) >= 1)
        let saved = try #require(phrase.pronunciations.first { $0.text == "record" })
        #expect(saved.chosenBy == "tagger")
        #expect(saved.arpabet?.contains("R EH1 K") == true)

        // Relaunch with a tagger that would say verb: the persisted noun stands, and the tagger is never called.
        let verbTagger = CountingTagger(.verb)
        let relaunched = try Self.world(tagger: verbTagger, folder: folder)
        let input = try #require(relaunched.phrases.input(phrase.id))
        let word = try #require(input.words.first { $0.text == "record" })
        #expect(word.pronunciation.arpabet == saved.arpabet)
        #expect(word.accepted == [0])
        #expect(verbTagger.calls.load(ordering: .relaxed) == 0)
        #expect(relaunched.store.phrase(phrase.id)?.pronunciations == phrase.pronunciations)
        // The re-run keeps it too, while the word is still "record" at that index.
        let report = try await relaunched.importer.reanalyze(phraseID: phrase.id, transcript: text)
        #expect(report.phrase.pronunciations.first { $0.text == "record" } == saved)
        #expect(verbTagger.calls.load(ordering: .relaxed) == 0)
    }
}

/// Snapping as the importer does it, for expectations.
enum ClipSelectionSnap {
    static func down(_ seconds: Double) -> Double { ((seconds / 0.01) + 1e-9).rounded(.down) * 0.01 }
}
