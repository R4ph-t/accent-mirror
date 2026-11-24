// One take in progress (spec 14), shared by every `CaptureSource`: the source pushes 16 kHz mono samples in any
// chunk size, and the session cuts them into 10 ms frames, feeds spec 05's streaming `Endpointer`, publishes the
// level and envelope streams, and ends the take on the endpoint, the cap, `stop()`, `cancel()` or a lost device.

import Accelerate
import AMCore
import Foundation
import Synchronization

/// A take being recorded. Thread-safe: the source feeds it from its audio thread while the app stops or cancels it
/// from anywhere.
public final class CaptureSession: Sendable {
    /// One value per 10 ms frame, while the take runs. Finishes when it ends.
    public let levels: AsyncStream<InputLevel>
    /// One value per 10 ms frame, while the take runs. Finishes when it ends.
    public let envelope: AsyncStream<EnvelopeFrame>
    /// When the take started, on the continuous clock.
    public let startedAt: ContinuousClock.Instant
    /// The device the take records from.
    public let device: InputDevice

    private struct State {
        var endpointer: Endpointer
        /// Samples waiting to fill the next frame.
        var pending: [Float] = []
        var outcome: CaptureOutcome?
        var waiters: [CheckedContinuation<CaptureOutcome, Never>] = []
    }

    private let state: Mutex<State>
    private let sampleRate: Double
    private let frameLength: Int
    private let levelSink: AsyncStream<InputLevel>.Continuation
    private let envelopeSink: AsyncStream<EnvelopeFrame>.Continuation
    /// Called once when the take ends, however it ends, outside the lock (the source releases its input here).
    private let onEnd: @Sendable () -> Void

    init(
        device: InputDevice, sampleRate: Double = 16_000, lastSessionFloorDBFS: Double?, thresholds: Thresholds,
        startedAt: ContinuousClock.Instant = .now, onEnd: @escaping @Sendable () -> Void = {}
    ) {
        let endpointer = Endpointer(
            sampleRate: sampleRate, lastSessionFloorDBFS: lastSessionFloorDBFS, thresholds: thresholds)
        self.device = device
        self.sampleRate = sampleRate
        self.startedAt = startedAt
        self.onEnd = onEnd
        frameLength = endpointer.frameLength
        state = Mutex(State(endpointer: endpointer))
        // Unbounded is bounded in practice: the cap ends the take after 2,000 frames.
        (levels, levelSink) = AsyncStream.makeStream(of: InputLevel.self)
        (envelope, envelopeSink) = AsyncStream.makeStream(of: EnvelopeFrame.self)
    }

    /// The outcome, once the take has ended; nil while it runs.
    public var outcome: CaptureOutcome? { state.withLock { $0.outcome } }

    /// Waits for the take to end.
    public func result() async -> CaptureOutcome {
        await withCheckedContinuation { continuation in
            let outcome = state.withLock { state -> CaptureOutcome? in
                if let outcome = state.outcome { return outcome }
                state.waiters.append(continuation)
                return nil
            }
            if let outcome { continuation.resume(returning: outcome) }
        }
    }

    /// Ends the take now, keeping what was heard (Stop). No effect once it has ended.
    public func stop() {
        finish { state in state.endpointer.stop().map { self.recorded($0) } }
    }

    /// Ends the take and drops every sample (Esc). No effect once it has ended.
    public func cancel() {
        discard(.cancelled)
    }

    /// Ends the take with nothing kept, for `cancelled` or `deviceLost`.
    func discard(_ outcome: CaptureOutcome) {
        finish { state in
            state.endpointer.cancel()
            return outcome
        }
    }

    /// Feeds samples from the source (16 kHz mono, any count). Returns false once the take has ended, so the source
    /// can stop feeding. A partial frame waits for the next call; it is dropped when the take ends.
    @discardableResult
    func feed(_ samples: [Float]) -> Bool {
        var ended = false
        let wasRunning = finish { state in
            state.pending += samples
            var start = 0
            defer { state.pending.removeFirst(min(start, state.pending.count)) }
            while state.pending.count - start >= frameLength {
                let frame = Array(state.pending[start..<start + frameLength])
                start += frameLength
                let time = state.endpointer.elapsed + Double(frameLength) / sampleRate
                publish(frame, at: time)
                for case .ended(let take) in state.endpointer.process(frame: frame) {
                    ended = true
                    return recorded(take)
                }
            }
            return nil
        }
        return wasRunning && !ended
    }

    /// Samples the session still holds (the endpointer's buffer and the partial frame), for the release check.
    var bufferedSampleCount: Int {
        state.withLock { $0.endpointer.bufferedSampleCount + $0.pending.count }
    }

    private func recorded(_ take: Endpointer.Take) -> CaptureOutcome {
        .recorded(CapturedTake(take, sampleRate: sampleRate, stoppedAt: .now))
    }

    private func publish(_ frame: [Float], at time: Double) {
        let rms = vDSP.rootMeanSquare(frame)
        let peak = vDSP.maximumMagnitude(frame)
        levelSink.yield(
            InputLevel(
                time: time, rmsDBFS: InputLevel.clampedDBFS(rms), peakDBFS: InputLevel.clampedDBFS(peak)))
        envelopeSink.yield(EnvelopeFrame(time: time, rms: rms))
    }

    /// Runs `body` under the lock while the take is running; when it returns an outcome, the take ends with it: the
    /// buffers are dropped, the streams finish, waiters resume and the source is told, all once. Returns whether the
    /// take was running when called (`body` doesn't run otherwise).
    @discardableResult
    private func finish(_ body: (inout State) -> CaptureOutcome?) -> Bool {
        typealias Ended = (outcome: CaptureOutcome, waiters: [CheckedContinuation<CaptureOutcome, Never>])
        let (wasRunning, ended) = state.withLock { state -> (Bool, Ended?) in
            guard state.outcome == nil else { return (false, nil) }
            guard let outcome = body(&state) else { return (true, nil) }
            state.outcome = outcome
            state.pending = []
            let waiters = state.waiters
            state.waiters = []
            return (true, (outcome, waiters))
        }
        if let ended {
            levelSink.finish()
            envelopeSink.finish()
            for waiter in ended.waiters { waiter.resume(returning: ended.outcome) }
            onEnd()
        }
        return wasRunning
    }
}
