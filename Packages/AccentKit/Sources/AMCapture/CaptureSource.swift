// Live capture's platform-neutral surface (spec 14): what a take source looks like, what it publishes and what it
// returns. The macOS microphone is one implementation (`MicRecorder`, in `Live/`); `FileCaptureSource` is the other,
// for tests and UI fixtures. Nothing here touches a microphone.

import AMCore
import CryptoKit
import Foundation

/// The input level of one 10 ms frame, for the recording meter (spec 21, Addendum r6 E5). Informational only.
public struct InputLevel: Sendable, Hashable {
    /// The end of the frame, in seconds from the start of the take.
    public let time: Double
    /// Frame RMS as 20·log10(rms), clamped to −60…0.
    public let rmsDBFS: Double
    /// Largest sample magnitude as 20·log10(|x|), clamped to −60…0. "Too loud" is `peakDBFS ≥ −1`.
    public let peakDBFS: Double

    public static let floorDBFS = -60.0

    public init(time: Double, rmsDBFS: Double, peakDBFS: Double) {
        self.time = time
        self.rmsDBFS = rmsDBFS
        self.peakDBFS = peakDBFS
    }

    /// 20·log10(`linear`) clamped to −60…0.
    static func clampedDBFS(_ linear: Float) -> Double {
        guard linear > 0 else { return floorDBFS }
        return min(max(20 * log10(Double(linear)), floorDBFS), 0)
    }
}

/// One 10 ms frame of the recording envelope, for the live strip (spec 20). Informational only.
public struct EnvelopeFrame: Sendable, Hashable {
    /// The end of the frame, in seconds from the start of the take.
    public let time: Double
    /// Frame RMS, linear (1 is a full-scale square wave). Not clamped.
    public let rms: Float

    public init(time: Double, rms: Float) {
        self.time = time
        self.rms = rms
    }
}

/// An audio input, for the inspector's Input pop-up.
public struct InputDevice: Sendable, Hashable, Identifiable {
    /// Stable across launches and reconnections (Core Audio's device UID on macOS).
    public let id: String
    public let name: String
    /// The system default input.
    public let isDefault: Bool

    public init(id: String, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }

    /// The device a take uses: the requested one while it is present, otherwise the system default, otherwise the
    /// first listed. Nil when there is no device at all.
    public static func resolve(_ requested: InputDevice.ID?, in devices: [InputDevice]) -> InputDevice? {
        if let requested, let device = devices.first(where: { $0.id == requested }) { return device }
        return devices.first(where: \.isDefault) ?? devices.first
    }
}

/// Microphone permission, as the system reports it.
public enum MicAuthorization: Sendable, Hashable {
    /// Never asked: `start` asks (the system's own prompt, no pre-prompt).
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Why a take could not start.
public enum CaptureError: Error, Sendable, Hashable {
    /// No input device.
    case noMicrophone
    /// Access is denied or restricted.
    case micDenied
    /// The system wouldn't start the input (the message is for logs, never shown as is).
    case inputFailed(String)

    /// The take problem the app shows, for the two the user can fix. Nil for `inputFailed`.
    public var takeProblem: TakeProblem? {
        switch self {
        case .noMicrophone: .noMicrophone
        case .micDenied: .micDenied
        case .inputFailed: nil
        }
    }
}

/// A finished take: the kept audio and the timestamps spec 12's L_stop / L_speech measurement reads. Times are
/// seconds from the start of the take (its first frame) unless they are clock instants.
public struct CapturedTake: Sendable, Hashable {
    /// 16 kHz mono Float32, from max(0, first kept `t_onset` − 0.2 s) to the stop (all of it with no kept onset).
    public let samples: [Float]
    public let sampleRate: Double
    /// SHA-256 of `samples` as little-endian Float32 bytes, lowercase hex.
    public let sha256: String
    /// Where `samples` starts.
    public let audioStartTime: Double
    /// Onsets that still count as speech, in order. The first gives `t_onset` and `t_detect`.
    public let onsets: [Onset]
    /// The end of the last speech frame; nil with no kept speech.
    public let lastSpeechTime: Double?
    /// Why and when the take stopped: the endpoint decision, the cap, or the manual stop.
    public let stopReason: Endpointer.EndReason
    public let stopTime: Double
    /// The stop on the continuous clock, taken when the decision was made: L_stop starts here.
    public let stoppedAt: ContinuousClock.Instant
    /// The noise floor at the end of the take (the next session's provisional floor).
    public let floorDBFS: Double

    /// `t_onset`: the first kept onset, backdated to its run's first frame.
    public var onsetTime: Double? { onsets.first?.time }
    /// `t_detect`: when the first kept onset fired.
    public var detectTime: Double? { onsets.first?.detectedAt }
    /// The last speech frame on the continuous clock: L_speech starts here.
    public var lastSpeechAt: ContinuousClock.Instant? {
        lastSpeechTime.map { stoppedAt - .seconds(stopTime - $0) }
    }

    init(_ take: Endpointer.Take, sampleRate: Double, stoppedAt: ContinuousClock.Instant) {
        samples = take.audio
        self.sampleRate = sampleRate
        sha256 = Self.digest(take.audio)
        audioStartTime = take.audioStartTime
        onsets = take.onsets
        lastSpeechTime = take.lastSpeechEndTime
        stopReason = take.reason
        stopTime = take.endTime
        self.stoppedAt = stoppedAt
        floorDBFS = take.floorDBFS
    }

    /// One batch pass of take quality over the kept audio (spec 05).
    public func analysis(lastSessionFloorDBFS: Double? = nil, thresholds: Thresholds = .current) -> TakeAnalysis {
        TakeAnalysis(
            samples: samples, sampleRate: sampleRate, lastSessionFloorDBFS: lastSessionFloorDBFS,
            thresholds: thresholds)
    }

    /// SHA-256 of `samples` as little-endian Float32 bytes (every Apple platform is little-endian), lowercase hex.
    public static func digest(_ samples: [Float]) -> String {
        let digest = samples.withUnsafeBytes { SHA256.hash(data: $0) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// How a take ended.
public enum CaptureOutcome: Sendable, Hashable {
    case recorded(CapturedTake)
    /// `cancel()` (Esc): nothing kept.
    case cancelled
    /// The input device went away (or the system reconfigured it) mid-take: nothing kept, like Esc. The next start
    /// reports `noMicrophone` when no device is left.
    case deviceLost

    public var take: CapturedTake? {
        if case .recorded(let take) = self { take } else { nil }
    }
}

/// Where takes come from. `MicRecorder` on macOS; `FileCaptureSource` in tests and fixtures.
public protocol CaptureSource: Sendable {
    /// Input devices now. Empty when there is none.
    func inputDevices() -> [InputDevice]
    /// The device list each time it changes (plugged, unplugged, new default), starting with the current one. Ends
    /// when the consumer stops iterating.
    func deviceChanges() -> AsyncStream<[InputDevice]>
    func authorization() -> MicAuthorization
    /// Starts a take on `device` (nil: the system default). Asks for permission first if it was never asked.
    func start(device: InputDevice.ID?, lastSessionFloorDBFS: Double?) async throws(CaptureError) -> CaptureSession
}

extension CaptureSource {
    /// Starts a take on the system default input with the default provisional floor.
    public func start() async throws(CaptureError) -> CaptureSession {
        try await start(device: nil, lastSessionFloorDBFS: nil)
    }

    /// What would stop a take from starting now, first in Designer's order: `noMicrophone`, then `micDenied`. Nil when
    /// Record can go ahead (including when permission was never asked).
    public func availability() -> TakeProblem? {
        CaptureError.preflight(devices: inputDevices(), authorization: authorization())?.takeProblem
    }
}

extension CaptureError {
    /// The shared start rule: no device first, then denied or restricted.
    static func preflight(devices: [InputDevice], authorization: MicAuthorization) -> CaptureError? {
        if devices.isEmpty { return .noMicrophone }
        switch authorization {
        case .denied, .restricted: return .micDenied
        case .authorized, .notDetermined: return nil
        }
    }
}
