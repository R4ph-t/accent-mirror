import Foundation
import Testing
import AMCore
@testable import AMPitch

/// Frames whose cell centre is at least `margin` from both ends of the signal.
private func interior(_ readings: [VoicedReading], duration: Double, margin: Double = 0.05) -> [VoicedReading] {
    readings.filter { $0.time >= margin && $0.time <= duration - margin }
}

private func track(_ samples: [Float]) async throws -> PitchTrack {
    try await PYINTracker().track(samples, sampleRate: Signals.sampleRate)
}

@Suite("PYINTracker")
struct PYINTrackerTests {
    @Test("records pyin-1 as its pitchTrackerID") func identifiesItself() {
        #expect(PYINTracker().id == "pyin-1")
        #expect(PYINTracker.trackerID == "pyin-1")
    }

    @Test("steady tones read within ±0.3 st of truth on voiced frames",
          arguments: [80.0, 150.0, 220.0, 400.0], [false, true])
    func steadyTones(hz: Double, harmonic: Bool) async throws {
        let duration = 1.0
        let samples = harmonic ? Signals.complex(hz, duration: duration) : Signals.sine(hz, duration: duration)
        let result = try await track(samples)
        let readings = result.voicedReadings
        let inner = interior(readings, duration: duration)
        #expect(inner.count >= 85, "only \(inner.count) of ~90 interior frames voiced at \(hz) Hz")
        for reading in readings {
            #expect(abs(semitoneError(reading.f0Hz, hz)) <= 0.3, "\(reading.f0Hz) Hz at \(reading.time) s for \(hz) Hz")
        }
    }

    @Test("1 s glides read within ±0.3 st of truth on voiced frames",
          arguments: [(120.0, 240.0), (400.0, 200.0), (80.0, 160.0), (180.0, 330.0)])
    func glides(from: Double, to: Double) async throws {
        let duration = 1.0
        let f0 = Signals.glideF0(from: from, to: to, duration: duration)
        let samples = Signals.tone(duration: duration, harmonics: Signals.speechHarmonics, f0: f0)
        let result = try await track(samples)
        let inner = interior(result.voicedReadings, duration: duration)
        #expect(inner.count >= 85)
        for reading in result.voicedReadings {
            #expect(abs(semitoneError(reading.f0Hz, f0(reading.time))) <= 0.3,
                    "\(reading.f0Hz) Hz at \(reading.time) s, truth \(f0(reading.time))")
        }
    }

    @Test("a 220 Hz tone reads as 0 st against a 220 Hz median") func toneReadsZeroAgainstItsMedian() async throws {
        let result = try await track(Signals.complex(220, duration: 1))
        let median = try #require(result.medianF0Hz)
        #expect(abs(semitoneError(median, 220)) <= 0.05)
        let voiced = result.allFrames.filter(\.voiced)
        #expect(!voiced.isEmpty)
        #expect(voiced.allSatisfy { abs($0.semitones) <= 0.1 })
        #expect(result.segments.count == 1)
    }

    @Test("vibrato (±1 st at 5.5 Hz) is followed within ±0.5 st") func vibrato() async throws {
        let f0 = Signals.vibratoF0(centre: 200, depth: 1, rate: 5.5)
        let result = try await track(Signals.tone(duration: 1, harmonics: Signals.speechHarmonics, f0: f0))
        // Interior frames only: at the ends the window is shifted inside the audio, up to 20 ms off the cell, which
        // matters at vibrato slopes (~35 st/s) but not for the spec's tones and glides above.
        let inner = interior(result.voicedReadings, duration: 1)
        #expect(inner.count >= 85)
        for reading in inner {
            #expect(abs(semitoneError(reading.f0Hz, f0(reading.time))) <= 0.5, "at \(reading.time) s")
        }
    }

    @Test("an octave trap (odd harmonics gone, so the signal repeats at twice F0) is repaired",
          arguments: [0.03, 0.06])
    func octaveTrap(trapSeconds: Double) async throws {
        let trap = 0.5..<(0.5 + trapSeconds)
        let samples = Signals.tone(
            duration: 1, harmonics: Signals.speechHarmonics,
            harmonicGain: { t, h in trap.contains(t) && !h.isMultiple(of: 2) ? 0 : 1 }) { _ in 220 }
        let result = try await track(samples)
        #expect(result.voicedReadings.count >= 90)
        for reading in result.voicedReadings {
            #expect(abs(semitoneError(reading.f0Hz, 220)) <= 1, "\(reading.f0Hz) Hz at \(reading.time) s")
        }
    }

    @Test("a 200 ms unvoiced gap is bridged with voiced = false") func shortGapIsBridged() async throws {
        let samples = Signals.complex(220, duration: 0.5) + Signals.silence(duration: 0.2)
            + Signals.complex(220, duration: 0.5)
        let result = try await track(samples)
        #expect(result.segments.count == 1)
        let frames = result.allFrames
        print("AMPitch 200 ms gap: \(frames.count(where: { !$0.voiced })) bridged frames")
        #expect(frames.contains { !$0.voiced })
        #expect(frames.allSatisfy { $0.semitones.isFinite && abs($0.semitones) <= 0.3 })
    }

    @Test("a 300 ms unvoiced gap splits the line") func longGapSplits() async throws {
        let samples = Signals.complex(220, duration: 0.5) + Signals.silence(duration: 0.3)
            + Signals.complex(220, duration: 0.5)
        let result = try await track(samples)
        #expect(result.segments.count == 2)
        let second = try #require(result.segments.last)
        print("AMPitch 300 ms gap: first segment ends at \(result.segments[0].start + Double(result.segments[0].frames.count) * result.hopSeconds) s, second starts at \(second.start) s")
        #expect(second.start >= 0.78 && second.start <= 0.84)
    }

    @Test("silence and pure noise give an empty track and a nil median",
          arguments: ["silence", "noise", "quiet noise", "no samples", "shorter than a hop"])
    func noVoicedFrames(kind: String) async throws {
        let samples: [Float] = switch kind {
        case "silence": Signals.silence(duration: 1)
        case "noise": Signals.noise(duration: 1)
        case "quiet noise": Signals.noise(duration: 1, amplitude: 0.001, seed: 7)
        case "no samples": []
        default: Signals.complex(220, duration: 0.005)
        }
        let result = try await track(samples)
        #expect(result.isEmpty)
        #expect(result.medianF0Hz == nil)
        #expect(result.segments.isEmpty)
        #expect(result.voicedFrameCount == 0)
    }

    @Test("a rate too low to search up to 500 Hz is refused", arguments: [0.0, -16_000, 800, .nan, .infinity])
    func unsupportedSampleRate(rate: Double) async {
        await #expect(throws: PitchTrackingError.self) {
            try await PYINTracker().track(Signals.silence(duration: 0.1), sampleRate: rate)
        }
    }
}

@Suite("PYINTracker cancellation")
struct PYINTrackerCancellationTests {
    @Test("a cancelled task stops within 50 frames and returns no partial track") func stopsWithinFiftyFrames() async {
        let samples = Signals.complex(150, duration: 5)
        let cancelAt = 123
        let task = Task { () -> (error: (any Error)?, analysedAfterCancel: Int) in
            var analysedAfterCancel = 0
            var cancelled = false
            do {
                _ = try await PYINTracker().track(samples, sampleRate: Signals.sampleRate) { frame in
                    if cancelled { analysedAfterCancel += 1 }
                    if frame == cancelAt {
                        withUnsafeCurrentTask { $0?.cancel() }
                        cancelled = true
                    }
                }
                return (nil, analysedAfterCancel)
            } catch {
                return (error, analysedAfterCancel)
            }
        }
        let (error, analysedAfterCancel) = await task.value
        #expect(error is CancellationError, "no partial track: the call must throw CancellationError")
        #expect(analysedAfterCancel <= 50)
    }

    @Test("a task cancelled before it starts throws CancellationError") func cancelledBeforeStart() async {
        let samples = Signals.complex(150, duration: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PYINTracker().track(samples, sampleRate: Signals.sampleRate)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@Suite("PYINTracker benchmark")
struct PYINTrackerBenchmark {
    /// v1 budget: 300 frames (a 3 s take) in ≤ 120 ms on an M1. CI only prints the time; set
    /// AM_PITCH_BENCH_GATE=1 to gate locally (use a release build: `swift test -c release`).
    @Test("3 s take: prints the time for 300 frames") func threeSecondTake() async throws {
        let samples = Signals.tone(
            duration: 3, harmonics: Signals.speechHarmonics,
            f0: Signals.glideF0(from: 110, to: 220, duration: 3))
        let tracker = PYINTracker()
        _ = try await tracker.track(samples, sampleRate: Signals.sampleRate)  // warm-up
        let clock = ContinuousClock()
        var best = Duration.seconds(10)
        for _ in 0..<5 {
            let elapsed = try await clock.measure { _ = try await tracker.track(samples, sampleRate: Signals.sampleRate) }
            best = min(best, elapsed)
        }
        let ms = Double(best.components.attoseconds) / 1e15 + Double(best.components.seconds) * 1000
        print("AMPitch benchmark: 300 frames in \(String(format: "%.1f", ms)) ms (budget 120 ms on M1)")
        if ProcessInfo.processInfo.environment["AM_PITCH_BENCH_GATE"] == "1" {
            #expect(ms <= 120)
        }
    }
}
