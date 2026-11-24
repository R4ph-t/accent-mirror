// The clip importer (spec 17, first v2 §11): an audio or video file in, a My Phrases entry with its own native
// reference out, on device. No UI: the later import sheet (Designer Addendum r6 E1) drives a `ClipImportSession` and
// the Edit Transcript sheet (E2) calls `reanalyze(phraseID:transcript:)` once per Save.
//
//   propose(url)      decode (first audio track) → speech regions (spec 05) → waveform → default selection
//   session           selection changes bump `selectionRevision`; each settled selection is transcribed with the
//                     bundled model; an older revision's result is dropped, and typed text is never overwritten
//   commit            0.5–15 s, inside the file, snapped to 10 ms; a transcript with a word → the clip analysed as
//                     the phrase's reference → phrase.json, clip.caf, reference.json (staged, then one rename)
//   reanalyze         transcript revision bumped, the reference recomputed in place, then every stored take
//                     realigned through the take store; one that can't be is marked unalignable and kept

import AMAlignment
import AMCapture
import AMCore
import AMLibrary
import Foundation

/// What the importer shows before you choose: the file's length, where the speech is, and a waveform.
public struct ClipProposal: Sendable {
    /// The imported file's name (the phrase's subtitle). The file itself is never kept.
    public let fileName: String
    public let duration: Double
    /// Speech regions found by spec 05's detector, in seconds of the file.
    public let speechRegions: [ClipSelection]
    /// Peak level per bin over the whole file, 0–1 (`ClipImporter.waveformBins` bins, fewer for a short file).
    public let waveform: [Float]
    /// From the first speech onset minus 0.2 s, at most 15 s, snapped to 10 ms.
    public let defaultSelection: ClipSelection
    let clip: DecodedClip

    /// The selection's audio, as the importer transcribes and stores it.
    public func audio(_ selection: ClipSelection, recordedAt: Date = Date()) -> TakeAudio {
        let rate = DecodedClip.sampleRate
        let start = min(max(0, Int((selection.start * rate).rounded())), clip.samples.count)
        let end = min(max(start, Int((selection.end * rate).rounded())), clip.samples.count)
        return TakeAudio(samples: Array(clip.samples[start..<end]), recordedAt: recordedAt)
    }

    /// Whether any detected speech falls inside `selection`.
    public func hasSpeech(in selection: ClipSelection) -> Bool {
        speechRegions.contains { $0.start < selection.end && $0.end > selection.start }
    }

    /// `selection` snapped to 10 ms, or why it can't be used: under 0.5 s, over 15 s, or not inside the file.
    public func validate(_ selection: ClipSelection) throws(ClipImportError) -> ClipSelection {
        let tolerance = 1e-9
        guard selection.start.isFinite, selection.end.isFinite, selection.start >= -tolerance,
            selection.end <= duration + tolerance, selection.start < selection.end
        else { throw .invalidSelection(.outsideFile) }
        let start = max(0, ClipImporter.snap(selection.start))
        var end = ClipImporter.snap(selection.end)
        if end > duration { end = ClipImporter.snapDown(duration) }
        let length = end - start
        guard length >= ClipImporter.minimumSeconds - tolerance else { throw .invalidSelection(.tooShort) }
        guard length <= ClipImporter.maximumSeconds + tolerance else { throw .invalidSelection(.tooLong) }
        return ClipSelection(start: start, end: end)
    }
}

/// Why a selection can't be committed.
public enum SelectionProblem: String, Sendable, Hashable, CaseIterable {
    case tooShort, tooLong, outsideFile
}

public enum ClipImportError: Error, Sendable, Hashable {
    /// Designer v1 §8.2: the file can't be read (`OperationalError.audioUnreadable`).
    case audioUnreadable
    /// Designer v1 §8.2: no speech in the selection.
    case noSpeech
    case invalidSelection(SelectionProblem)
    /// The transcript has no word.
    case emptyTranscript
    case phraseNotFound(PhraseID)
    /// The clip couldn't be analysed (the model is missing, a stage failed).
    case analysisFailed(OperationalError)
    case storage(StorageError)
    /// Superseded by a later call, or the task was cancelled.
    case cancelled

    /// The operational error the case stands for, if any.
    public var operational: OperationalError? {
        switch self {
        case .audioUnreadable: .audioUnreadable
        case .analysisFailed(let error): error
        default: nil
        }
    }
}

/// What a transcript re-run did to the phrase's stored takes.
public struct ReanalysisReport: Sendable, Hashable {
    public let phrase: MyPhrase
    /// Takes realigned to the new wording.
    public var realigned: [TakeRef] = []
    /// Takes that couldn't be: marked unalignable, kept, still counted toward the 10.
    public var unalignable: [TakeRef] = []
    /// Takes left as they were because the store failed (retried by the next re-run or read).
    public var failed: [TakeRef] = []
}

@MainActor
public final class ClipImporter {
    /// Designer v1 §8: a selection of 0.5–15 s, snapped to 10 ms; the default starts 0.2 s before the first onset.
    public nonisolated static let minimumSeconds = 0.5
    public nonisolated static let maximumSeconds = 15.0
    public nonisolated static let snapSeconds = 0.01
    public nonisolated static let preRollSeconds = 0.2
    public nonisolated static let waveformBins = 400
    /// The reason a take that can't be realigned is marked with (plan §8.3).
    public nonisolated static let unalignableReason = "recorded for the old wording"

    public let phrases: ImportedPhrases
    public let takes: TakeStore
    /// The app's coordinator: closing the importer, changing the selection or committing a transcript invalidates
    /// its request in flight.
    public let coordinator: AnalysisCoordinator?
    private let now: @Sendable () -> Date
    /// Bumped per phrase by every re-run, so an older one never writes over a newer one.
    private var reanalyses: [PhraseID: Int] = [:]

    public init(
        phrases: ImportedPhrases, takes: TakeStore, coordinator: AnalysisCoordinator? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.phrases = phrases
        self.takes = takes
        self.coordinator = coordinator
        self.now = now
    }

    // MARK: - Propose

    /// Decodes `url` and finds its speech, off the main actor.
    public func propose(_ url: URL) async throws(ClipImportError) -> ClipProposal {
        try await Self.proposal(url)
    }

    /// A session over `proposal`, transcribing its default selection.
    public func session(_ proposal: ClipProposal) -> ClipImportSession {
        let session = ClipImportSession(importer: self, proposal: proposal)
        session.transcribeSelection()
        return session
    }

    nonisolated static func proposal(_ url: URL) async throws(ClipImportError) -> ClipProposal {
        let clip: DecodedClip
        do {
            clip = try await ClipDecoder.decode(url)
        } catch {
            throw .audioUnreadable
        }
        let analysis = TakeAnalysis(samples: clip.samples, sampleRate: DecodedClip.sampleRate)
        let duration = clip.duration
        let regions = analysis.speechRegions.map {
            ClipSelection(start: $0.lowerBound, end: min($0.upperBound, duration))
        }
        let start = snapDown(max(0, (regions.first?.start ?? 0) - preRollSeconds))
        let end = snapDown(min(duration, start + maximumSeconds))
        return ClipProposal(
            fileName: url.lastPathComponent, duration: duration, speechRegions: regions,
            waveform: waveform(clip.samples), defaultSelection: ClipSelection(start: start, end: end), clip: clip)
    }

    nonisolated static func snap(_ seconds: Double) -> Double { (seconds / snapSeconds).rounded() * snapSeconds }
    nonisolated static func snapDown(_ seconds: Double) -> Double {
        ((seconds / snapSeconds) + 1e-9).rounded(.down) * snapSeconds
    }

    nonisolated static func waveform(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let bins = min(waveformBins, samples.count)
        return (0..<bins).map { bin in
            let range = (bin * samples.count / bins)..<((bin + 1) * samples.count / bins)
            return min(1, samples[range].reduce(0) { max($0, abs($1)) })
        }
    }

    // MARK: - Transcribe

    /// The selection's words from the bundled model, as text. `noSpeech` when the detector found none there.
    func transcribe(_ proposal: ClipProposal, _ selection: ClipSelection) async -> Result<String, ClipImportError> {
        guard proposal.hasSpeech(in: selection) else { return .failure(.noSpeech) }
        let audio = proposal.audio(selection)
        let speech = phrases.analyzer.speech
        do {
            let timestamper: any WordTimestamper
            do throws(ModelUnavailable) {
                timestamper = try await speech.timestamper()
            } catch {
                return .failure(.analysisFailed(.modelUnavailable(error.failure)))
            }
            let words = try await timestamper.wordTimestamps(
                for: TimestampRequest(clipID: audio.clipID, samples: audio.samples))
            try Task.checkCancellation()
            return .success(Self.text(of: words))
        } catch {
            if Task.isCancelled || error is CancellationError { return .failure(.cancelled) }
            return .failure(.analysisFailed(.inferenceFailed(stage: .recogniseWords)))
        }
    }

    nonisolated static func text(of words: [WordTimestamp]) -> String {
        words.map { $0.word.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Commit

    /// Makes a My Phrases entry from `selection` of `proposal` with `transcript`.
    public func commit(_ proposal: ClipProposal, selection: ClipSelection, transcript: String)
        async throws(ClipImportError) -> MyPhrase
    {
        let selection = try proposal.validate(selection)
        let text = Self.clean(transcript)
        guard !phraseTokens(text).isEmpty else { throw .emptyTranscript }
        guard proposal.hasSpeech(in: selection) else { throw .noSpeech }
        let createdAt = now()
        let clip = proposal.audio(selection, recordedAt: createdAt)
        let id = MyPhrase.newID()
        let (reference, pronunciations) = try await analyse(clip, id: id, text: text, revision: 0, persisted: [])
        let phrase = MyPhrase(
            id: id, text: text, sourceFileName: proposal.fileName, createdAt: createdAt, selection: selection,
            clipSHA256: clip.sha256, pronunciations: pronunciations)
        do throws(StorageError) {
            try await phrases.store.create(phrase, clip: clip.samples, reference: reference)
        } catch {
            throw .storage(error)
        }
        return phrase
    }

    // MARK: - Re-run

    /// Commits an edited transcript: the revision bumped, the clip's reference recomputed in place, then every stored
    /// take of the phrase realigned through the take store. A take that can't be is marked unalignable and kept. A
    /// later call for the same phrase supersedes this one (`cancelled`).
    public func reanalyze(phraseID: PhraseID, transcript: String) async throws(ClipImportError) -> ReanalysisReport {
        guard let stored = phrases.store.phrase(phraseID) else { throw .phraseNotFound(phraseID) }
        let text = Self.clean(transcript)
        guard !phraseTokens(text).isEmpty else { throw .emptyTranscript }
        let generation = reanalyses[phraseID, default: 0] + 1
        reanalyses[phraseID] = generation
        if let coordinator, coordinator.current?.submission.phrase.id == phraseID {
            coordinator.invalidate(.transcriptEditCommitted)
        }
        let samples: [Float]
        do throws(StorageError) {
            samples = try phrases.store.clip(phraseID)
        } catch {
            throw .storage(error)
        }
        let clip = TakeAudio(samples: samples, sha256: stored.clipSHA256, recordedAt: stored.createdAt)
        let revision = stored.transcriptRevision + 1
        let (reference, pronunciations) = try await analyse(
            clip, id: phraseID, text: text, revision: revision, persisted: stored.pronunciations)
        guard reanalyses[phraseID] == generation else { throw .cancelled }
        var phrase = stored
        phrase.text = text
        phrase.transcriptRevision = revision
        phrase.pronunciations = pronunciations
        do throws(StorageError) {
            try await phrases.store.update(phrase, reference: reference)
        } catch {
            throw .storage(error)
        }

        var report = ReanalysisReport(phrase: phrase)
        for take in await takes.takes(for: phraseID) {
            guard reanalyses[phraseID] == generation, !Task.isCancelled else { throw .cancelled }
            do throws(TakeStoreError) {
                let comparison = try await takes.result(take: take.ref, voice: MyPhrase.recordingID)
                if Self.isAnalysed(comparison) {
                    try await takes.markComparable(take: take.ref)
                    report.realigned.append(take.ref)
                } else {
                    try await takes.markUnalignable(take: take.ref, reason: Self.unalignableReason)
                    report.unalignable.append(take.ref)
                }
            } catch {
                switch error {
                case .recomputeFailed:
                    if (try? await takes.markUnalignable(take: take.ref, reason: Self.unalignableReason)) != nil {
                        report.unalignable.append(take.ref)
                    } else {
                        report.failed.append(take.ref)
                    }
                case .notFound:
                    continue
                case .storage:
                    report.failed.append(take.ref)
                }
            }
        }
        return report
    }

    // MARK: - Shared

    private func analyse(
        _ clip: TakeAudio, id: PhraseID, text: String, revision: Int, persisted: [StoredPronunciation]
    ) async throws(ClipImportError) -> (DerivedRecord, [StoredPronunciation]) {
        do {
            return try await phrases.analyseClip(clip, id: id, text: text, revision: revision, persisted: persisted)
        } catch let failure as OperationalFailure {
            throw .analysisFailed(failure.error)
        } catch {
            if Task.isCancelled || error is CancellationError { throw .cancelled }
            throw .analysisFailed(.inferenceFailed(stage: .alignWords))
        }
    }

    /// Whether a stored comparison is an analysed result (a take problem such as words that don't match is not).
    nonisolated static func isAnalysed(_ record: DerivedRecord) -> Bool {
        guard let l2 = DerivedCoding.value(L2Analysis.self, in: record, key: record.key),
            case .analysed = l2.outcome
        else { return false }
        return true
    }

    nonisolated static func clean(_ transcript: String) -> String {
        transcript.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// One open importer: the file, the selection and the transcript as you edit them (the later sheet's model).
@MainActor
public final class ClipImportSession {
    public let proposal: ClipProposal
    public private(set) var selection: ClipSelection
    /// Bumped by every selection change; a transcription for an older revision is dropped.
    public private(set) var selectionRevision = 0
    public private(set) var transcript = ""
    /// Set once you type: a late recognition result never overwrites the text after that.
    public private(set) var userEdited = false
    /// Why the current selection has no recognised text (`noSpeech`, a missing model), if so.
    public private(set) var transcriptionError: ClipImportError?
    public private(set) var isClosed = false
    /// Results dropped because the selection had moved on or the importer had closed (tests, diagnostics).
    public private(set) var staleDropped = 0
    private let importer: ClipImporter
    private var task: Task<Void, Never>?

    init(importer: ClipImporter, proposal: ClipProposal) {
        self.importer = importer
        self.proposal = proposal
        selection = proposal.defaultSelection
    }

    /// True while the current selection is being transcribed.
    public var isTranscribing: Bool { task != nil }

    /// A settled selection: validated and snapped, the revision bumped, the request in flight invalidated, and the
    /// new selection transcribed. An invalid selection changes nothing.
    public func select(_ selection: ClipSelection) throws(ClipImportError) {
        let snapped = try proposal.validate(selection)
        self.selection = snapped
        selectionRevision += 1
        task?.cancel()
        importer.coordinator?.invalidate(.importerSelectionChanged)
        transcribeSelection()
    }

    /// What you typed. From now on a recognition result never replaces it.
    public func edit(transcript: String) {
        self.transcript = transcript
        userEdited = true
    }

    /// Closes the importer: the transcription in flight is cancelled and its result, if any, dropped.
    public func close() {
        isClosed = true
        task?.cancel()
        task = nil
        importer.coordinator?.invalidate(.importerClosed)
    }

    /// Commits the current selection and transcript (cancelling any transcription still running).
    public func commit() async throws(ClipImportError) -> MyPhrase {
        task?.cancel()
        task = nil
        return try await importer.commit(proposal, selection: selection, transcript: transcript)
    }

    /// Waits for the transcription in flight (tests).
    public func settle() async {
        while let running = task {
            await running.value
            if task == running { break }
        }
    }

    func transcribeSelection() {
        let revision = selectionRevision
        let selection = self.selection
        let proposal = self.proposal
        let importer = self.importer
        task = Task { [weak self] in
            let result = await importer.transcribe(proposal, selection)
            self?.deliver(result, revision: revision)
        }
    }

    /// Applies a transcription only if it answers the current selection of an open importer, and never over typed
    /// text.
    func deliver(_ result: Result<String, ClipImportError>, revision: Int) {
        guard !isClosed, revision == selectionRevision else {
            staleDropped += 1
            return
        }
        task = nil
        switch result {
        case .success(let text):
            transcriptionError = nil
            if !userEdited { transcript = text }
        case .failure(.cancelled):
            staleDropped += 1
        case .failure(let error):
            transcriptionError = error
        }
    }
}
