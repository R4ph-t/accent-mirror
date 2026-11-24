// The coordinator (spec 12, plan §8.1–8.3): one request in flight, stale responses dropped, and the response
// published before any persistence status for the same request. The app (spec 21) owns one; analysis runs in the
// `Analyzer` actor, never on the main actor.

import AMCore
import AMLibrary
import Foundation
import os

/// Why the coordinator drops the request in flight.
public enum InvalidationReason: String, Sendable, Hashable, CaseIterable {
    case newRecordingStarted, phraseSwitched, voiceSwitched, transcriptEditCommitted, importerSelectionChanged
    case importerClosed, appTerminating
}

/// What the coordinator publishes, in order: a request's response, then its persistence updates.
public enum CoordinatorEvent: Sendable, Hashable {
    case response(AnalysisResponse)
    case persistence(RequestID, PersistenceStatus)
}

/// What one request analyses.
public struct AnalysisSubmission: Sendable {
    public let take: TakeAudio
    public let phrase: PhraseInput
    public let voice: RecordingID

    public init(take: TakeAudio, phrase: PhraseInput, voice: RecordingID) {
        self.take = take
        self.phrase = phrase
        self.voice = voice
    }
}

@MainActor
public final class AnalysisCoordinator {
    public let analyzer: Analyzer
    public let reference: any ReferenceSet
    public let store: any TakePersisting
    /// Every response and persistence update, in publication order.
    public let events: AsyncStream<CoordinatorEvent>
    private let continuation: AsyncStream<CoordinatorEvent>.Continuation

    /// The current request: its ID and what it analyses. Cleared by `invalidate`; a new `submit` replaces it.
    public private(set) var current: (request: AnalysisRequest, submission: AnalysisSubmission)?
    /// The last submission, kept after `invalidate` so a voice switch can re-submit its take.
    private var lastSubmission: AnalysisSubmission?
    /// Responses dropped as stale (tests, diagnostics).
    public private(set) var staleDropped = 0
    private var generation = 0
    private var task: Task<Void, Never>?
    /// The last save, so a new request's saving never overtakes an older one's.
    private var saving: Task<Void, Never>?

    static let signposter = OSSignposter(subsystem: "AccentMirror", category: "Coordinator")

    public init(analyzer: Analyzer, reference: any ReferenceSet, store: any TakePersisting) {
        self.analyzer = analyzer
        self.reference = reference
        self.store = store
        (events, continuation) = AsyncStream.makeStream(of: CoordinatorEvent.self)
    }

    /// Issues a request with a new `RequestID` and the next generation, cancelling the one in flight.
    @discardableResult
    public func submit(_ submission: AnalysisSubmission) -> AnalysisRequest {
        task?.cancel()
        generation += 1
        let inputs = AnalysisInputs(
            takeAudioSHA256: submission.take.sha256,
            reference: reference.identity(phrase: submission.phrase.id, voice: submission.voice))
        let request = AnalysisRequest(generation: generation, inputs: inputs, config: analyzer.config)
        current = (request, submission)
        lastSubmission = submission
        let analyzer = self.analyzer
        let reference = self.reference
        task = Task { [weak self] in
            let run = await analyzer.run(
                take: submission.take, phrase: submission.phrase, reference: reference, voice: submission.voice,
                requestID: request.id)
            self?.receive(run, for: submission, cancelled: Task.isCancelled)
        }
        return request
    }

    /// Switches the reference voice for the current take: cancels the request in flight and re-submits the same take
    /// and phrase. L0 and L1 come from the analyzer's cache, so only L2 is recomputed.
    @discardableResult
    public func switchVoice(to voice: RecordingID) -> AnalysisRequest? {
        guard let submission = lastSubmission else { return nil }
        invalidate(.voiceSwitched)
        return submit(AnalysisSubmission(take: submission.take, phrase: submission.phrase, voice: voice))
    }

    /// Cancels the request in flight and clears it: its response, whenever it comes, is dropped.
    public func invalidate(_ reason: InvalidationReason) {
        task?.cancel()
        current = nil
        Self.signposter.emitEvent("invalidate", "\(reason.rawValue)")
    }

    /// Waits for the request in flight and any save (tests and app termination).
    public func settle() async {
        await task?.value
        await saving?.value
    }

    /// Delivers `run` only if it answers the current request with the current inputs and wasn't cancelled.
    private func receive(_ run: Analyzer.Run, for submission: AnalysisSubmission, cancelled: Bool) {
        let response = run.response
        guard !cancelled, let current, current.request.id == response.requestID,
            AnalysisInputs(takeAudioSHA256: response.identity.takeAudioSHA256, reference: response.identity.reference)
                == current.request.inputs
        else {
            staleDropped += 1
            Self.signposter.emitEvent("stale-dropped", "\(response.requestID.description)")
            return
        }
        continuation.yield(.response(response))
        let id = response.requestID
        if let reason = Self.notSavedReason(of: response.outcome) {
            continuation.yield(.persistence(id, .notSaved(reason)))
            return
        }
        guard case .analysed(let result) = response.outcome else { return }
        continuation.yield(.persistence(id, .pending))
        let record = TakeRecord(
            takeID: result.takeID, phraseID: result.phraseID, recording: submission.voice,
            recordedAt: result.recordedAt, audioSHA256: submission.take.sha256, samples: submission.take.samples,
            derived: run.derived, identity: response.identity)
        let store = self.store
        let previous = saving
        saving = Task { [continuation] in
            await previous?.value
            let status: PersistenceStatus
            do throws(StorageError) {
                let saved = try await store.save(record)
                status = saved.pruneFailure.map { .savedPruneFailed(saved.id, $0) } ?? .saved(saved.id)
            } catch {
                status = .saveFailed(error)
            }
            continuation.yield(.persistence(id, status))
        }
    }

    /// Only `analysed` responses are offered for saving (§8.3).
    public nonisolated static func notSavedReason(of outcome: AnalysisOutcome) -> NotSavedReason? {
        switch outcome {
        case .analysed: nil
        case .takeProblem: .takeProblem
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }
}
