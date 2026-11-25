// The Input popover's mic check (Designer addendum v3.5 I3): levels from the selected input while the popover is
// open and nothing is recording. Opening the popover is the user's reason to listen; there is no idle monitoring.
// `MicLevelMonitor` (in `Live/`) is the Mac's; tests use a fake.

import Accelerate
import Foundation

/// Listens to one input for the meter only: no samples are kept, nothing is recorded.
public protocol InputLevelMonitor: Sendable {
    /// One level per 10 ms frame from `device` (nil: the system default) until the consumer stops iterating, which
    /// releases the input. Asks for microphone permission first if it was never asked; finishes at once when access
    /// is denied or the input can't start.
    func levels(device: InputDevice.ID?) -> AsyncStream<InputLevel>
}

/// Cuts 16 kHz mono samples (any chunk size) into 10 ms frames and measures each as the recording meter does.
public struct LevelFrames: Sendable {
    public let sampleRate: Double
    private let frameLength: Int
    private var pending: [Float] = []
    private var frames = 0

    public init(sampleRate: Double = 16_000) {
        self.sampleRate = sampleRate
        frameLength = max(1, Int((sampleRate * 0.01).rounded()))
    }

    /// The levels of every whole frame `samples` completes; a partial frame waits for the next call.
    public mutating func feed(_ samples: [Float]) -> [InputLevel] {
        pending += samples
        var levels: [InputLevel] = []
        var start = 0
        while pending.count - start >= frameLength {
            let frame = pending[start..<start + frameLength]
            start += frameLength
            frames += 1
            let (rms, peak) = frame.withUnsafeBufferPointer { (vDSP.rootMeanSquare($0), vDSP.maximumMagnitude($0)) }
            levels.append(
                InputLevel(
                    time: Double(frames * frameLength) / sampleRate, rmsDBFS: InputLevel.clampedDBFS(rms),
                    peakDBFS: InputLevel.clampedDBFS(peak)))
        }
        pending.removeFirst(start)
        return levels
    }
}
