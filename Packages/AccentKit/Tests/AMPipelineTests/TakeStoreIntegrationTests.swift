// Spec 16 through the pipeline: the coordinator saving into a real `TakeStore` in a temporary folder, the recompute
// closure's keys agreeing with what `Analyzer.run` stores, and the ghosts' pitch. Replayed word timings, no ASR, no
// network, no microphone.

import AMCore
import AMLibrary
import AMPipeline
import AMPlacement
import AMProsody
import AMVerdicts
import Foundation
import Testing

@MainActor @Suite("Take store through the pipeline (spec 16)") struct TakeStoreIntegrationTests {
    final class Folder: Sendable {
        let url = FileManager.default.temporaryDirectory.appending(path: "TakeStoreIntegration-\(UUID().uuidString)")
        deinit { try? FileManager.default.removeItem(at: url) }
        var isEmpty: Bool { ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).isEmpty }
    }

    struct Setup {
        let world: PipelineFixtures.World
        let analyzer: Analyzer
        let store: TakeStore
        let coordinator: AnalysisCoordinator
    }

    static func setup(_ folder: Folder, beforeStage: (@Sendable (Stage) async throws -> Void)? = nil) async throws
        -> Setup
    {
        let world = try await PipelineFixtures.world()
        let analyzer = try PipelineFixtures.analyzer(world, beforeStage: beforeStage)
        let phrase = world.phrase
        let recomputer = TakeRecomputer.pipeline(analyzer: analyzer, reference: world.reference) {
            $0 == phrase.id ? phrase : nil
        }
        let store = TakeStore(root: folder.url, recomputer: recomputer)
        await store.recover()
        return Setup(
            world: world, analyzer: analyzer, store: store,
            coordinator: AnalysisCoordinator(analyzer: analyzer, reference: world.reference, store: store))
    }

    static func submission(_ world: PipelineFixtures.World, voice: String = PipelineFixtures.modelItem)
        -> AnalysisSubmission
    {
        AnalysisSubmission(take: world.you, phrase: world.phrase, voice: PipelineFixtures.voice(voice))
    }

    static func next(_ count: Int, of coordinator: AnalysisCoordinator) async -> [CoordinatorEvent] {
        var out: [CoordinatorEvent] = []
        for await event in coordinator.events {
            out.append(event)
            if out.count == count { break }
        }
        return out
    }

    @Test("An analysed take is saved, listed, and its stored comparison is served without a recompute")
    func analysedTakeSaved() async throws {
        let folder = Folder()
        let setup = try await Self.setup(folder)
        let request = setup.coordinator.submit(Self.submission(setup.world))
        let events = await Self.next(3, of: setup.coordinator)
        guard case .response(let response) = events[0], case .analysed(let result) = response.outcome else {
            Issue.record("expected an analysed response first: \(events)")
            return
        }
        #expect(events[2] == .persistence(request.id, .saved(result.takeID)))

        let takes = await setup.store.takes(for: setup.world.phrase.id)
        #expect(takes.map(\.id) == [result.takeID])
        #expect(takes.first?.number == 1)
        #expect(takes.first?.recordedAt == result.recordedAt)
        // The store's expected keys are the ones `run` gave the records: a read is a hit, not a recompute.
        let computed = await setup.analyzer.statistics.l2Computed
        let ref = try #require(takes.first?.ref)
        let voice = PipelineFixtures.voice(PipelineFixtures.modelItem)
        let l2 = try await setup.store.result(take: ref, voice: voice)
        #expect(l2.level == .l2)
        #expect(await setup.analyzer.statistics.l2Computed == computed)
        #expect(await setup.analyzer.statistics.l2Hits == 0)
    }

    @Test("A voice switch stores the new voice's comparison in the same take")
    func voiceSwitchStoresSecondComparison() async throws {
        let folder = Folder()
        let setup = try await Self.setup(folder)
        setup.coordinator.submit(Self.submission(setup.world))
        _ = await Self.next(3, of: setup.coordinator)
        let switched = try #require(setup.coordinator.switchVoice(to: PipelineFixtures.voice(PipelineFixtures.otherItem)))
        let events = await Self.next(3, of: setup.coordinator)
        guard case .persistence(_, .saved(let id)) = events.last else { Issue.record("\(events)"); return }
        #expect(events.allSatisfy {
            if case .persistence(let request, _) = $0 { request == switched.id } else { true }
        })
        let takes = await setup.store.takes(for: setup.world.phrase.id)
        #expect(takes.map(\.id) == [id])
        #expect(takes.first?.number == 1)
        #expect(takes.first?.voices == [
            PipelineFixtures.voice(PipelineFixtures.otherItem), PipelineFixtures.voice(PipelineFixtures.modelItem),
        ])
    }

    @Test("A take problem and a failed analysis are never written")
    func failedAndUnsavedNeverWritten() async throws {
        let folder = Folder()
        let setup = try await Self.setup(folder) { stage in
            if stage == .compare { throw InjectedError() }
        }
        // Too quiet (silence): a take problem.
        let silent = TakeAudio(samples: [Float](repeating: 0, count: 48_000), recordedAt: PipelineFixtures.recordedAt)
        let quiet = setup.coordinator.submit(AnalysisSubmission(
            take: silent, phrase: setup.world.phrase, voice: PipelineFixtures.voice(PipelineFixtures.modelItem)))
        var events = await Self.next(2, of: setup.coordinator)
        #expect(events[1] == .persistence(quiet.id, .notSaved(.takeProblem)))
        // A stage that fails.
        let failing = setup.coordinator.submit(Self.submission(setup.world))
        events = await Self.next(2, of: setup.coordinator)
        guard case .response(let response) = events[0], case .failed = response.outcome else {
            Issue.record("expected failed: \(events)")
            return
        }
        #expect(events[1] == .persistence(failing.id, .notSaved(.failed)))
        await setup.coordinator.settle()
        #expect(await setup.store.takes(for: setup.world.phrase.id).isEmpty)
        #expect(folder.isEmpty, "nothing written under the root")
    }

    @Test("Ghosts give the earlier takes' pitch on the model timeline")
    func ghostPitch() async throws {
        let folder = Folder()
        let setup = try await Self.setup(folder)
        setup.coordinator.submit(Self.submission(setup.world))
        _ = await Self.next(3, of: setup.coordinator)
        // A second take: the same recording, nudged so it's a different take.
        var samples = setup.world.you.samples
        samples[0] += 1e-4
        let second = TakeAudio(
            samples: samples, clipID: setup.world.you.clipID, recordedAt: PipelineFixtures.recordedAt + 60)
        setup.coordinator.submit(AnalysisSubmission(
            take: second, phrase: setup.world.phrase, voice: PipelineFixtures.voice(PipelineFixtures.modelItem)))
        _ = await Self.next(3, of: setup.coordinator)

        let takes = await setup.store.takes(for: setup.world.phrase.id)
        #expect(takes.map(\.number) == [2, 1])
        let ghosts = await setup.store.ghosts(
            before: takes[0].ref, voice: PipelineFixtures.voice(PipelineFixtures.modelItem))
        #expect(ghosts.map(\.take.number) == [1])
        let pitch = try #require(ghosts.first.flatMap(GhostPitch.init))
        #expect(!pitch.pitchOnModel.isEmpty)
    }
}
