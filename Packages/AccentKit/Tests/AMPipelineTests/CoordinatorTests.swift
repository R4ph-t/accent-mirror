// Spec 12: the coordinator's request identity, stale rejection and order of publication (§8.1–8.3).

import AMAlignment
import AMCore
import AMLibrary
import AMPipeline
import AMPlacement
import AMProsody
import AMVerdicts
import Foundation
import Testing

@MainActor @Suite("Analysis coordinator (spec 12)") struct CoordinatorTests {
    static func coordinator(
        _ world: PipelineFixtures.World, asrSeconds: Double? = nil, store: FakeTakeStore = FakeTakeStore()
    ) throws -> AnalysisCoordinator {
        let timestamper: any WordTimestamper = asrSeconds.map { SlowTimestamper(base: world.timings, seconds: $0) }
            ?? world.timings
        return AnalysisCoordinator(
            analyzer: try PipelineFixtures.analyzer(world, timestamper: timestamper), reference: world.reference,
            store: store)
    }

    static func submission(_ world: PipelineFixtures.World, voice: String = PipelineFixtures.modelItem)
        -> AnalysisSubmission
    {
        AnalysisSubmission(take: world.you, phrase: world.phrase, voice: PipelineFixtures.voice(voice))
    }

    /// The next `count` events.
    static func next(_ count: Int, of coordinator: AnalysisCoordinator) async -> [CoordinatorEvent] {
        var out: [CoordinatorEvent] = []
        for await event in coordinator.events {
            out.append(event)
            if out.count == count { break }
        }
        return out
    }

    @Test("a stale response is dropped for each invalidation reason", arguments: InvalidationReason.allCases)
    func staleDroppedOnInvalidation(reason: InvalidationReason) async throws {
        let world = try await PipelineFixtures.world()
        let store = FakeTakeStore()
        let coordinator = try Self.coordinator(world, asrSeconds: 0.5, store: store)
        let stale = coordinator.submit(Self.submission(world))
        coordinator.invalidate(reason)
        #expect(coordinator.current == nil)
        await coordinator.settle()
        #expect(coordinator.staleDropped == 1, "\(reason)")
        #expect(await store.saved.isEmpty)
        // The next event belongs to a later request: nothing of the stale one was published.
        let fresh = coordinator.submit(Self.submission(world))
        let events = await Self.next(1, of: coordinator)
        guard case .response(let response) = events.first else { Issue.record("expected a response"); return }
        #expect(response.requestID == fresh.id && response.requestID != stale.id)
        #expect(fresh.generation == stale.generation + 1)
    }

    @Test("a new submission cancels the one in flight; only the newer response is published")
    func newerRequestWins() async throws {
        let world = try await PipelineFixtures.world()
        let coordinator = try Self.coordinator(world, asrSeconds: 0.3)
        let first = coordinator.submit(Self.submission(world))
        let second = coordinator.submit(Self.submission(world, voice: PipelineFixtures.otherItem))
        let events = await Self.next(1, of: coordinator)
        guard case .response(let response) = events.first else { Issue.record("expected a response"); return }
        #expect(response.requestID == second.id)
        await coordinator.settle()
        #expect(coordinator.staleDropped == 1)
        #expect(first.id != second.id && second.generation == first.generation + 1)
    }

    @Test("a response whose inputs no longer match the current request is dropped")
    func changedInputsDropped() async throws {
        let world = try await PipelineFixtures.world()
        let coordinator = try Self.coordinator(world)
        coordinator.submit(Self.submission(world))
        // A transcript edit lands before the analysis reads the reference: its identity moves under the request.
        world.reference.bumpTranscriptRevision()
        await coordinator.settle()
        #expect(coordinator.staleDropped == 1)
    }

    @Test("the response is published first, then persistence updates for the same request")
    func responseBeforePersistence() async throws {
        let world = try await PipelineFixtures.world()
        let store = FakeTakeStore()
        let coordinator = try Self.coordinator(world, store: store)
        let request = coordinator.submit(Self.submission(world))
        let events = await Self.next(3, of: coordinator)
        guard case .response(let response) = events[0], case .analysed(let result) = response.outcome else {
            Issue.record("expected an analysed response first: \(events)")
            return
        }
        #expect(response.requestID == request.id)
        #expect(events[1] == .persistence(request.id, .pending))
        #expect(events[2] == .persistence(request.id, .saved(result.takeID)))
        let saved = await store.saved
        #expect(saved.count == 1)
        #expect(saved.first?.derived.map(\.level) == [.l0, .l1, .l2])
        #expect(saved.first?.audioSHA256 == world.you.sha256)
    }

    @Test("a failed save is reported after the response")
    func saveFailed() async throws {
        let world = try await PipelineFixtures.world()
        let coordinator = try Self.coordinator(world, store: FakeTakeStore(failing: .diskFull))
        let request = coordinator.submit(Self.submission(world))
        let events = await Self.next(3, of: coordinator)
        #expect(events.count == 3)
        if case .response = events[0] {} else { Issue.record("response first") }
        #expect(events[2] == .persistence(request.id, .saveFailed(.diskFull)))
    }

    @Test("a take problem is published, then notSaved(takeProblem); nothing is written")
    func takeProblemNotSaved() async throws {
        let world = try await PipelineFixtures.world()
        let store = FakeTakeStore()
        let coordinator = try Self.coordinator(world, store: store)
        let silent = TakeAudio(samples: [Float](repeating: 0, count: 48_000), recordedAt: PipelineFixtures.recordedAt)
        let request = coordinator.submit(AnalysisSubmission(
            take: silent, phrase: world.phrase, voice: PipelineFixtures.voice(PipelineFixtures.modelItem)))
        let events = await Self.next(2, of: coordinator)
        guard case .response(let response) = events[0] else { Issue.record("response first"); return }
        #expect(response.outcome == .takeProblem(.noSpeech))
        #expect(events[1] == .persistence(request.id, .notSaved(.takeProblem)))
        await coordinator.settle()
        #expect(await store.saved.isEmpty)
    }

    @Test("only analysed responses are offered for saving")
    func notSavedReasons() {
        #expect(AnalysisCoordinator.notSavedReason(of: .takeProblem(.tooQuiet)) == .takeProblem)
        #expect(AnalysisCoordinator.notSavedReason(of: .failed(.audioUnreadable)) == .failed)
        #expect(AnalysisCoordinator.notSavedReason(of: .cancelled) == .cancelled)
    }

    @Test("switching voice re-submits the take and recomputes L2 only")
    func switchVoice() async throws {
        let world = try await PipelineFixtures.world()
        let coordinator = try Self.coordinator(world)
        coordinator.submit(Self.submission(world))
        _ = await Self.next(3, of: coordinator)
        let before = await coordinator.analyzer.statistics
        let request = try #require(coordinator.switchVoice(to: PipelineFixtures.voice(PipelineFixtures.otherItem)))
        let events = await Self.next(1, of: coordinator)
        guard case .response(let response) = events.first else { Issue.record("expected a response"); return }
        #expect(response.requestID == request.id)
        #expect(response.identity.reference.recordingID == PipelineFixtures.voice(PipelineFixtures.otherItem))
        let after = await coordinator.analyzer.statistics
        #expect(after.l0Computed == before.l0Computed && after.l1Computed == before.l1Computed)
        #expect(after.l2Computed == before.l2Computed + 1)
    }
}
