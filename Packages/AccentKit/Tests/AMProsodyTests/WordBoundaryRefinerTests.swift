import Foundation
import Synchronization
import Testing
import AMAlignment
import AMCore
@testable import AMProsody

/// Synthetic takes: silence and voiced stretches (a 150 Hz harmonic complex), 16 kHz. No audio file is committed.
enum Take {
    static let sampleRate = 16_000.0

    /// `parts` are (seconds, voiced) in order.
    static func make(_ parts: [(Double, Bool)], f0: Double = 150) -> [Float] {
        var samples: [Float] = []
        var phase = 0.0
        let harmonics = (1...8).map { 1 / Double($0) }
        let norm = harmonics.reduce(0, +)
        for (seconds, voiced) in parts {
            for _ in 0..<Int((seconds * sampleRate).rounded()) {
                if voiced {
                    var value = 0.0
                    for (index, gain) in harmonics.enumerated() { value += gain * sin(Double(index + 1) * phase) }
                    samples.append(Float(value / norm) * 0.5)
                } else {
                    samples.append(0)
                }
                phase += 2 * Double.pi * f0 / sampleRate
            }
        }
        return samples
    }

    static func word(_ text: String, _ start: Double, _ end: Double, _ probability: Double = 0.9) -> WordTimestamp {
        WordTimestamp(word: text, start: start, end: end, probability: probability)
    }
}

/// A deterministic generator (SplitMix64), so the property test is reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func expectInvariants(_ refined: [WordTimestamp], _ original: [WordTimestamp], duration: Double,
                      sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(refined.map(\.word) == original.map(\.word), sourceLocation: sourceLocation)
    #expect(refined.map(\.probability) == original.map(\.probability), sourceLocation: sourceLocation)
    for (index, word) in refined.enumerated() {
        #expect(word.start >= 0 && word.end <= duration, "word \(index) outside the take", sourceLocation: sourceLocation)
        #expect(word.start <= word.end, "word \(index) ends before it starts", sourceLocation: sourceLocation)
        if index > 0 {
            #expect(word.start >= refined[index - 1].end, "word \(index) starts before the previous refined end",
                    sourceLocation: sourceLocation)
        }
    }
}

@Suite("WordBoundaryRefiner (spec 23)")
struct WordBoundaryRefinerTests {
    let snap = DSPSnapRefiner()

    @Test("dsp-snap-1 moves a Whisper end 120 ms early to within 20 ms of the true offset")
    func snapsEarlyEnd() async throws {
        // Word voiced 0.30–1.10 s; Whisper ends it at 0.98 s.
        let samples = Take.make([(0.3, false), (0.8, true), (0.5, false)])
        let truth = 1.10
        let refined = try await snap.refine([Take.word(" hello", 0.30, truth - 0.12)], samples: samples,
                                            sampleRate: Take.sampleRate)
        #expect(abs(refined[0].end - truth) <= 0.020, "end \(refined[0].end), truth \(truth)")
        #expect(abs(refined[0].start - 0.30) <= 0.020)
    }

    @Test("dsp-snap-1 moves a late start to the voicing onset")
    func snapsStart() async throws {
        let samples = Take.make([(0.4, false), (0.6, true), (0.4, false)])
        let refined = try await snap.refine([Take.word("a", 0.50, 1.0)], samples: samples, sampleRate: Take.sampleRate)
        #expect(abs(refined[0].start - 0.40) <= 0.020, "start \(refined[0].start)")
    }

    @Test("a boundary never passes the neighbouring word's refined boundary")
    func neighbourClamp() async throws {
        // Two words voiced 0.30–1.10 and 1.20–1.60; Whisper puts both early and back to back at 0.98.
        let samples = Take.make([(0.3, false), (0.8, true), (0.1, false), (0.4, true), (0.4, false)])
        let words = [Take.word("one", 0.30, 0.98), Take.word("two", 0.98, 1.50)]
        let refined = try await snap.refine(words, samples: samples, sampleRate: Take.sampleRate)
        #expect(abs(refined[0].end - 1.10) <= 0.020)
        #expect(refined[1].start >= refined[0].end)
        expectInvariants(refined, words, duration: Double(samples.count) / Take.sampleRate)
    }

    @Test("a boundary never leaves the take")
    func takeClamp() async throws {
        // Voicing runs to the last sample; Whisper's last end is 60 ms before it and its first start at 0.
        let samples = Take.make([(0.05, false), (0.6, true)])
        let duration = Double(samples.count) / Take.sampleRate
        let words = [Take.word("end", 0.0, duration - 0.06)]
        let refined = try await snap.refine(words, samples: samples, sampleRate: Take.sampleRate)
        expectInvariants(refined, words, duration: duration)
    }

    @Test("the clamps hold for random words over random takes", arguments: 0..<20)
    func clampsHoldRandomly(seed: UInt64) async throws {
        var rng = SplitMix64(state: seed)
        var parts: [(Double, Bool)] = []
        for index in 0..<Int.random(in: 2...8, using: &rng) {
            parts.append((Double.random(in: 0.02...0.5, using: &rng), index.isMultiple(of: 2)))
        }
        let samples = Take.make(parts)
        let duration = Double(samples.count) / Take.sampleRate
        var cuts = (0..<Int.random(in: 2...12, using: &rng)).map { _ in Double.random(in: 0...duration, using: &rng) }
        cuts.sort()
        let words = stride(from: 0, to: cuts.count - 1, by: 2).map { Take.word("w\($0)", cuts[$0], cuts[$0 + 1]) }
        for refiner in [snap as any WordBoundaryRefiner, WhisperOnly()] {
            let refined = try await refiner.refine(words, samples: samples, sampleRate: Take.sampleRate)
            expectInvariants(refined, words, duration: duration)
        }
    }

    @Test("with no offset or onset within ±150 ms, the boundaries are unchanged")
    func unchangedWithoutEdges() async throws {
        // Steady voicing from 0.2 to 2.2 s: no voicing edge and no 10 dB drop near 0.8 or 1.4.
        let samples = Take.make([(0.2, false), (2.0, true), (0.3, false)])
        let words = [Take.word("mid", 0.8, 1.4)]
        let snapped = try await snap.snap(words, samples: samples, sampleRate: Take.sampleRate)
        #expect(snapped.words == words)
        #expect(snapped.startRules == [.unchanged] && snapped.endRules == [.unchanged])
    }

    @Test("WhisperOnly returns the input unchanged") func whisperOnly() async throws {
        let words = [Take.word("a", 0.5, 0.2), Take.word("b", 0.1, 0.3)]
        #expect(try await WhisperOnly().refine(words, samples: [], sampleRate: Take.sampleRate) == words)
        #expect(WhisperOnly().id == "whisper" && snap.id == "dsp-snap-1")
    }

    @Test("a cancel 100 ms into a call returns CancellationError within about 300 ms")
    func cancellation() async throws {
        // Two minutes of speech-like audio, so the call is still running 100 ms in.
        let samples = Take.make(Array(repeating: [(0.4, true), (0.2, false)], count: 200).flatMap { $0 })
        let words = (0..<200).map { Take.word("w", Double($0) * 0.6, Double($0) * 0.6 + 0.3) }
        let refiner = snap
        let task = Task { try await refiner.refine(words, samples: samples, sampleRate: Take.sampleRate) }
        try await Task.sleep(for: .milliseconds(100))
        let clock = ContinuousClock()
        let cancelledAt = clock.now
        task.cancel()
        let result = await task.result
        let elapsed = cancelledAt.duration(to: clock.now)
        if case .failure(let error) = result {
            #expect(error is CancellationError)
        } else {
            Issue.record("the call finished with a result instead of CancellationError")
        }
        #expect(elapsed <= .milliseconds(300), "returned \(elapsed) after the cancel")
    }

    @Test("ConfigIdentity with a different aligner gives a different configDigest")
    func alignerInDigest() throws {
        let digests = try [WhisperOnly().id, snap.id, "ctc-w2v2b960-1"].map {
            try configDigest(ConfigIdentity(asrModelID: "a", pitchTrackerID: "pyin-1", voicingID: "acf-1", aligner: $0))
        }
        #expect(Set(digests).count == 3)
    }
}

extension WordBoundaryRefinerTests {
    /// The refined boundaries recorded for spec 03's clips (`scripts/eval-word-boundaries.sh --record`), replayed the way
    /// CI does: no audio, no model, no network.
    @Suite("WordBoundaryRefiner replay (spec 23)")
    struct Replay {
        static let timestamps = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "fixtures/timestamps")
        static let whisper = Self.timestamps.appending(path: "openai_whisper-base.en")

        @Test("the recorded refined boundaries replay with networking denied, and keep the refiner's invariants",
              arguments: ["dsp-snap-1", "ctc-w2v2b960-1"])
        func replayRecordedBoundaries(aligner: String) async throws {
            URLProtocol.registerClass(DenyNetwork.self)
            defer { URLProtocol.unregisterClass(DenyNetwork.self) }
            let before = openSockets()
            let original = try FixtureTimestamper(directory: Self.whisper)
            let refined = try FixtureTimestamper(directory: Self.timestamps.appending(path: "openai_whisper-base.en+\(aligner)"))
            #expect(refined.asrModelID == original.asrModelID)
            #expect(refined.clipIDs == original.clipIDs)
            var moved = 0
            for clipID in refined.clipIDs {
                let request = TimestampRequest(clipID: clipID, samples: [])
                let words = try await refined.wordTimestamps(for: request)
                let source = try await original.wordTimestamps(for: request)
                let lastEnd = max(source.map(\.end).max() ?? 0, words.map(\.end).max() ?? 0)
                expectInvariants(words, source, duration: lastEnd)
                moved += zip(words, source).count { $0.start != $1.start || $0.end != $1.end }
            }
            #expect(moved > 0, "\(aligner) moved no boundary at all")
            #expect(DenyNetwork.attempts.withLock { $0 } == 0)
            #expect(openSockets() == before)
        }

        @Test("the refiners run with networking denied and open no socket")
        func refinersOpenNoSocket() async throws {
            URLProtocol.registerClass(DenyNetwork.self)
            defer { URLProtocol.unregisterClass(DenyNetwork.self) }
            let before = openSockets()
            let samples = Take.make([(0.3, false), (0.8, true), (0.5, false)])
            let words = [Take.word("hello", 0.30, 0.98)]
            for refiner in [DSPSnapRefiner() as any WordBoundaryRefiner, WhisperOnly()] {
                _ = try await refiner.refine(words, samples: samples, sampleRate: Take.sampleRate)
            }
            #expect(DenyNetwork.attempts.withLock { $0 } == 0)
            #expect(openSockets() == before)
        }
    }
}

/// Fails every URL request and counts the attempts.
final class DenyNetwork: URLProtocol {
    static let attempts = Mutex(0)
    override class func canInit(with request: URLRequest) -> Bool {
        attempts.withLock { $0 += 1 }
        return true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

/// File descriptors of this process that are sockets.
func openSockets() -> Set<Int32> {
    var sockets: Set<Int32> = []
    for fd in 0..<getdtablesize() {
        var info = stat()
        if fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK { sockets.insert(fd) }
    }
    return sockets
}
