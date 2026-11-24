// Spec 12: the analyzer end to end on replayed word timings (no ASR, no network, no microphone).

import AMAlignment
import AMCore
import AMLibrary
@testable import AMPipeline
import AMPitch
import Foundation
import Synchronization
import Testing

@Suite("Analyzer (spec 12)") struct AnalyzerTests {
    static let golden = SmokePlacementGoldenTests.root.appendingPathComponent("fixtures/pipeline/analysis-golden.json")

    @Test("a fixture take and a fixture reference give the committed AnalysisResult JSON")
    func endToEndGolden() async throws {
        let world = try await PipelineFixtures.world()
        let analyzer = try PipelineFixtures.analyzer(world)
        let response = await analyzer.analyse(
            take: world.you, phrase: world.phrase, reference: world.reference,
            voice: PipelineFixtures.voice(PipelineFixtures.modelItem))
        guard case .analysed(let result) = response.outcome else {
            Issue.record("expected an analysed outcome, got \(response.outcome)")
            return
        }
        #expect(result.identity == response.identity)
        #expect(result.takeID == world.you.takeID)
        #expect(!result.nativeBand.isEmpty, "the band has points")
        // Both sides go through the same canonicalisation (a re-parsed number can print differently).
        let json = try CanonicalJSON.canonicalize(CanonicalJSON.encode(result))
        if ProcessInfo.processInfo.environment["AM_RECORD_PIPELINE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(
                at: Self.golden.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (json + Data("\n".utf8)).write(to: Self.golden)
            Issue.record("recorded \(Self.golden.path); unset AM_RECORD_PIPELINE_GOLDEN and rerun")
            return
        }
        // The file is the canonical bytes plus a newline. Not re-canonicalised: parsing and re-printing a number can
        // change its last digit.
        var committed = try Data(contentsOf: Self.golden)
        if committed.last == UInt8(ascii: "\n") { committed.removeLast() }
        #expect(json == committed, "the result differs from fixtures/pipeline/analysis-golden.json")
        if json != committed, let dir = ProcessInfo.processInfo.environment["AM_GOLDEN_DIFF_DIR"] {
            try json.write(to: URL(fileURLWithPath: dir).appendingPathComponent("analysis-actual.json"))
        }
        let decoded = try CanonicalJSON.decoder().decode(AnalysisResult.self, from: committed)
        #expect(decoded.verdict == result.verdict && decoded.identity == result.identity, "the golden decodes")
    }

    @Test("a voice switch recomputes L2 only: no ASR, pitch, L0 or L1 work on your take")
    func voiceSwitchRecomputesL2Only() async throws {
        let world = try await PipelineFixtures.world()
        let asr = CountingTimestamper(world.timings)
        let pitch = CountingPitchTracker(PYINTracker())
        let analyzer = try PipelineFixtures.analyzer(world, timestamper: asr, pitch: pitch)
        let first = await analyzer.analyse(
            take: world.you, phrase: world.phrase, reference: world.reference,
            voice: PipelineFixtures.voice(PipelineFixtures.modelItem))
        let before = await analyzer.statistics
        #expect(asr.calls == 1 && pitch.calls == 1)
        let second = await analyzer.analyse(
            take: world.you, phrase: world.phrase, reference: world.reference,
            voice: PipelineFixtures.voice(PipelineFixtures.otherItem))
        let after = await analyzer.statistics
        #expect(asr.calls == 1, "no ASR on a voice switch")
        #expect(pitch.calls == 1, "no pitch on a voice switch")
        #expect(after.l0Computed == before.l0Computed && after.l1Computed == before.l1Computed)
        #expect(after.l2Computed == before.l2Computed + 1)
        #expect(after.l0Hits == before.l0Hits + 1 && after.l1Hits == before.l1Hits + 1)
        #expect(first.identity.reference.recordingID != second.identity.reference.recordingID)
        if case .analysed(let result) = second.outcome {
            #expect(result.identity.reference.recordingID == PipelineFixtures.voice(PipelineFixtures.otherItem))
        } else {
            Issue.record("the switched voice gave \(second.outcome)")
        }
    }

    static let injected: [OperationalError] = [
        .modelUnavailable(.notInstalled), .modelUnavailable(.checksumMismatch), .modelUnavailable(.loadFailed),
        .inferenceFailed(stage: .compare), .referenceCacheCorrupt(RecordingID("injected")), .audioUnreadable,
    ]

    @Test("each OperationalError injected at each stage is surfaced as itself; any other error names the stage",
          arguments: Stage.allCases)
    func operationalErrorsSurfaceAsThemselves(stage: Stage) async throws {
        let world = try await PipelineFixtures.world()
        for error in Self.injected + [nil] {
            let analyzer = try PipelineFixtures.analyzer(world) { running in
                guard running == stage else { return }
                if let error { throw OperationalFailure(error) }
                throw InjectedError()
            }
            let response = await analyzer.analyse(
                take: world.you, phrase: world.phrase, reference: world.reference,
                voice: PipelineFixtures.voice(PipelineFixtures.modelItem))
            #expect(response.outcome == .failed(error ?? .inferenceFailed(stage: stage)), "\(stage), \(String(describing: error))")
        }
    }

    @Test("unreadable audio is audioUnreadable; a silent take is a take problem, not a failure")
    func audioProblems() async throws {
        let world = try await PipelineFixtures.world()
        let analyzer = try PipelineFixtures.analyzer(world)
        let voice = PipelineFixtures.voice(PipelineFixtures.modelItem)
        let broken = TakeAudio(samples: [0, .nan, 0], recordedAt: PipelineFixtures.recordedAt)
        #expect(await analyzer.analyse(take: broken, phrase: world.phrase, reference: world.reference, voice: voice)
            .outcome == .failed(.audioUnreadable))
        let silent = TakeAudio(samples: [Float](repeating: 0, count: 48_000), recordedAt: PipelineFixtures.recordedAt)
        #expect(await analyzer.analyse(take: silent, phrase: world.phrase, reference: world.reference, voice: voice)
            .outcome == .takeProblem(.noSpeech))
    }

    @Test("a corrupt reference record triggers one silent rebuild; only a second failure is reported")
    func referenceRebuildOnce() async throws {
        let world = try await PipelineFixtures.world()
        let model = PipelineFixtures.voice(PipelineFixtures.modelItem)
        world.reference.corrupt(model, reads: 1)
        let healed = await (try PipelineFixtures.analyzer(world)).analyse(
            take: world.you, phrase: world.phrase, reference: world.reference, voice: model)
        if case .analysed = healed.outcome {} else { Issue.record("one corrupt read heals: \(healed.outcome)") }
        #expect(world.reference.rebuilds == [model])

        world.reference.corrupt(model, reads: 100)
        let broken = await (try PipelineFixtures.analyzer(world)).analyse(
            take: world.you, phrase: world.phrase, reference: world.reference, voice: model)
        #expect(broken.outcome == .failed(.referenceCacheCorrupt(model)))
        #expect(world.reference.rebuilds == [model, model], "one rebuild per request, then reported")
    }

    /// One cancelled request: the cancel is armed from the stage hook when `stage` starts, fired from a high-QoS GCD
    /// timer at `delay` after the request started and at least `intoStage` after `stage` starts, and the return is timed inside
    /// the analysis task. A busy cooperative pool (the suites run in parallel) moves neither time (as in #53).
    struct CancelAttempt {
        let response: AnalysisResponse
        /// Return minus cancel; nil when the cancel never fired.
        let elapsed: Duration?
    }

    static func cancelled(
        at stage: Stage, after delay: Duration, intoStage: Duration = .zero, take: TakeAudio, world: PipelineFixtures.World, host: SpeechModelHost
    ) async throws -> CancelAttempt {
        let task = Mutex<Task<(AnalysisResponse, ContinuousClock.Instant), Never>?>(nil)
        let cancelledAt = Mutex<ContinuousClock.Instant?>(nil)
        let submitted = ContinuousClock.now
        var configuration = try Analyzer.Configuration.shipped()
        configuration.beforeStage = { running in
            guard running == stage else { return }
            let wait = max(intoStage, delay - submitted.duration(to: .now))
            DispatchQueue.global(qos: .userInteractive).asyncAfter(
                deadline: .now() + .nanoseconds(Int(wait.components.attoseconds / 1_000_000_000 + wait.components.seconds * 1_000_000_000))
            ) {
                cancelledAt.withLock { $0 = .now }
                task.withLock { $0 }?.cancel()
            }
        }
        let analyzer = Analyzer(speech: host, configuration: configuration)
        let running = Task(priority: .high) {
            let response = await analyzer.analyse(
                take: take, phrase: world.phrase, reference: world.reference,
                voice: PipelineFixtures.voice(PipelineFixtures.modelItem))
            return (response, ContinuousClock.now)
        }
        task.withLock { $0 = running }
        let (response, returned) = await running.value
        return CancelAttempt(response: response, elapsed: cancelledAt.withLock { $0 }.map { $0.duration(to: returned) })
    }

    @Test("cancel 100 ms into a request, during ASR: .cancelled within about 300 ms, the model stays loaded",
          .timeLimit(.minutes(2)))
    func cancelDuringASR() async throws {
        let world = try await PipelineFixtures.world()
        // A 30 s decode, so the cancel always lands inside ASR however slow the stages before it are.
        let slow = SlowTimestamper(base: world.timings, seconds: 30)
        let host = SpeechModelHost(asrModelID: slow.asrModelID) { slow }
        let attempt = try await Self.cancelled(
            at: .recogniseWords, after: .milliseconds(100), take: world.you, world: world, host: host)
        let elapsed = try #require(attempt.elapsed)
        print("cancel during ASR: answered \(elapsed) after the cancel")
        #expect(attempt.response.outcome == .cancelled)
        #expect(elapsed < .milliseconds(300))
        #expect(await host.isLoaded, "a cancel never tears the model down")
        #expect(await host.loadAttempts == 1)
    }

    @Test("cancel outside ASR (pitch on a long take) is seen within one stage", .timeLimit(.minutes(2)))
    func cancelOutsideASR() async throws {
        let world = try await PipelineFixtures.world()
        // On a loaded runner pitch on a long take can finish before the cancel lands; that attempt proves nothing and
        // is retried with a longer take, up to three times (as in #53).
        var copies = 7
        for _ in 0..<3 {
            let long = TakeAudio(
                samples: Array(repeating: world.you.samples, count: copies).flatMap { $0 }, clipID: world.you.clipID,
                recordedAt: PipelineFixtures.recordedAt)
            let attempt = try await Self.cancelled(
                at: .trackPitch, after: .zero, intoStage: .milliseconds(20), take: long, world: world, host: SpeechModelHost(ready: world.timings))
            guard let elapsed = attempt.elapsed, attempt.response.outcome == .cancelled, elapsed > .zero else {
                copies *= 2
                continue
            }
            print("cancel outside ASR: answered \(elapsed) after the cancel (target ≤ 50 ms on the Mac)")
            #expect(elapsed < .milliseconds(300))
            return
        }
        Issue.record("in three attempts the cancel never landed while pitch was running")
    }

    @Test("per-stage times without ASR; the non-ASR stages fit the generous 500 ms budget")
    func latencyWithoutASR() async throws {
        let world = try await PipelineFixtures.world(prompt: "002")
        // The fastest of three runs on fresh analyzers: the package tests run in parallel, and contention isn't the
        // pipeline's latency.
        var best: Analyzer.Run?
        for _ in 0..<3 {
            let analyzer = try PipelineFixtures.analyzer(world)
            let run = await Task(priority: .high) {
                await analyzer.run(
                    take: world.you, phrase: world.phrase, reference: world.reference,
                    voice: PipelineFixtures.voice(PipelineFixtures.modelItem))
            }.value
            if case .analysed = run.response.outcome {} else { Issue.record("expected analysed: \(run.response.outcome)") }
            if best.map({ Self.nonASR($0) > Self.nonASR(run) }) ?? true { best = run }
        }
        let run = try #require(best)
        for stage in Stage.allCases {
            print("latency \(String(format: "%.1f", world.you.duration)) s take: \(stage.rawValue) \(String(format: "%.1f", (run.timings[stage] ?? 0) * 1000)) ms")
        }
        print("latency: non-ASR stages \(String(format: "%.1f", Self.nonASR(run) * 1000)) ms (budget 500 ms)")
        #expect(Self.nonASR(run) < 0.5)
    }

    static func nonASR(_ run: Analyzer.Run) -> Double {
        run.timings.filter { $0.key != .recogniseWords }.values.reduce(0, +)
    }
}

/// Fails every request: the pipeline must never reach for the network (CTO decision 2).
final class NoNetworkProtocol: URLProtocol, @unchecked Sendable {
    // @unchecked: URLProtocol is an Objective-C class the system instantiates; this subclass adds no state of its
    // own. The request counter is a static `Mutex`.
    static let attempts = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool {
        attempts.withLock { $0 += 1 }
        return true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

@Suite("No network (CTO decision 2)", .serialized) struct NoNetworkTests {
    @Test("the full pipeline runs with every request failing, opens no connection, and still gets a result")
    func fullPipelineWithoutNetwork() async throws {
        URLProtocol.registerClass(NoNetworkProtocol.self)
        defer { URLProtocol.unregisterClass(NoNetworkProtocol.self) }
        NoNetworkProtocol.attempts.withLock { $0 = 0 }
        let world = try await PipelineFixtures.world()
        let analyzer = try PipelineFixtures.analyzer(world)
        let response = await analyzer.analyse(
            take: world.you, phrase: world.phrase, reference: world.reference,
            voice: PipelineFixtures.voice(PipelineFixtures.modelItem))
        if case .analysed = response.outcome {} else { Issue.record("expected a result: \(response.outcome)") }
        #expect(NoNetworkProtocol.attempts.withLock { $0 } == 0, "no request was attempted")
        // A missing model is notInstalled, never a download.
        let missing = SpeechModelHost.whisperKit(
            folder: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("no-such-model-\(UUID())"),
            manifest: try ModelManifest(contentsOf: SmokePlacementGoldenTests.root.appendingPathComponent(
                "Resources/Models/openai_whisper-base.en/manifest.json")))
        do {
            _ = try await missing.timestamper()
            Issue.record("a missing model must not load")
        } catch {
            #expect(error == ModelUnavailable(.notInstalled))
        }
        #expect(NoNetworkProtocol.attempts.withLock { $0 } == 0, "a missing model downloads nothing")
    }
}

@Suite("Speech model host (spec 12)") struct SpeechModelHostTests {
    enum Load: Sendable { case fail(any Error & Sendable), succeed }

    static func host(_ plan: [Load]) -> SpeechModelHost {
        let attempts = Mutex(0)
        let timestamper = try! PipelineFixtures.timings()
        return SpeechModelHost(asrModelID: timestamper.asrModelID) {
            let n = attempts.withLock { n in
                defer { n += 1 }
                return n
            }
            switch plan[min(n, plan.count - 1)] {
            case .fail(let error): throw error
            case .succeed: return timestamper
            }
        }
    }

    @Test("a failed load is reported; the next request retries once; a second failure is reported and sticks")
    func retryOnce() async throws {
        let host = Self.host([.fail(ModelVerificationError.mismatch(path: "x", expected: "a", actual: "b"))])
        for expectedAttempts in [1, 2, 2, 2] {
            do {
                _ = try await host.timestamper()
                Issue.record("the load must fail")
            } catch {
                #expect(error == ModelUnavailable(.checksumMismatch))
            }
            #expect(await host.loadAttempts == expectedAttempts)
        }
    }

    @Test("a load that fails once then succeeds serves the next request")
    func retrySucceeds() async throws {
        let host = Self.host([.fail(InjectedError()), .succeed])
        await #expect(throws: ModelUnavailable(.loadFailed)) { try await host.timestamper() }
        _ = try await host.timestamper()
        #expect(await host.isLoaded)
        #expect(await host.loadAttempts == 2)
    }

    @Test("load failures map onto ModelFailure")
    func failureMapping() {
        #expect(SpeechModelHost.failure(of: ModelVerificationError.missing(path: "x")) == .notInstalled)
        #expect(SpeechModelHost.failure(of: 
            ModelVerificationError.manifestInconsistent(computed: "a", recorded: "b")) == .checksumMismatch)
        #expect(SpeechModelHost.failure(of: ModelUnavailable(.notInstalled)) == .notInstalled)
        #expect(SpeechModelHost.failure(of: InjectedError()) == .loadFailed)
    }

    @Test("a request made while the model loads waits for it (Open question 1)")
    func requestWaitsForLoad() async throws {
        let timings = try PipelineFixtures.timings()
        let host = SpeechModelHost(asrModelID: timings.asrModelID) {
            try await Task.sleep(for: .milliseconds(150))
            return timings
        }
        await host.prepare()
        _ = try await host.timestamper()
        #expect(await host.loadAttempts == 1)
    }

    @Test("an analysis with the model unavailable fails as modelUnavailable")
    func analysisReportsModelUnavailable() async throws {
        let world = try await PipelineFixtures.world()
        let analyzer = Analyzer(
            speech: Self.host([.fail(ModelUnavailable(.notInstalled))]), configuration: try .shipped())
        let response = await analyzer.analyse(
            take: world.you, phrase: world.phrase, reference: world.reference,
            voice: PipelineFixtures.voice(PipelineFixtures.modelItem))
        #expect(response.outcome == .failed(.modelUnavailable(.notInstalled)))
    }
}

@Suite("Derived records (spec 12)") struct DerivedRecordTests {
    @Test("L0, L1 and L2 round-trip through their records; a different key reads as a miss")
    func roundTrip() async throws {
        let world = try await PipelineFixtures.world()
        let analyzer = try PipelineFixtures.analyzer(world)
        let run = await analyzer.run(
            take: world.you, phrase: world.phrase, reference: world.reference,
            voice: PipelineFixtures.voice(PipelineFixtures.modelItem))
        #expect(run.derived.map(\.level) == [.l0, .l1, .l2])
        let l0 = try #require(run.derived.first)
        let decoded = try #require(DerivedCoding.value(L0Analysis.self, in: l0, key: l0.key))
        #expect(try DerivedCoding.record(decoded) == l0)
        #expect(DerivedCoding.value(L0Analysis.self, in: l0, key: "another") == nil)
        let l2 = try #require(run.derived.last)
        #expect(DerivedCoding.value(L2Analysis.self, in: l2, key: l2.key)?.outcome == run.response.outcome)
    }
}
