// A `CaptureSource` that plays a recording into a take instead of the microphone (spec 14): every automated capture
// test runs on it, and spec 21's fixtures inject it. Its device list and permission are settable, so tests can
// unplug the input mid-take or deny access.

@preconcurrency import AVFAudio
import AMCore
import Foundation
import Synchronization

/// Plays fixed samples into a take through the same `CaptureSession` the microphone uses. The end of the recording
/// counts as Stop.
public final class FileCaptureSource: CaptureSource {
    /// How the samples reach the take.
    public enum Pacing: Sendable, Hashable {
        /// All at once, inside `start`: the take has ended when `start` returns.
        case immediate
        /// 10 ms of audio every 10 ms, like a microphone (UI fixtures).
        case realTime
        /// Only when the caller calls `advance(by:)` (tests that stop or cancel at an exact point).
        case manual
    }

    /// The one device a file source lists unless told otherwise.
    public static let fileDevice = InputDevice(id: "file", name: "Recording", isDefault: true)

    private struct State {
        var devices: [InputDevice]
        var authorization: MicAuthorization
        var session: CaptureSession?
        /// The next sample to feed.
        var position = 0
        var deviceWatchers: [UUID: AsyncStream<[InputDevice]>.Continuation] = [:]
    }

    /// 16 kHz mono Float32.
    public let samples: [Float]
    public let pacing: Pacing
    private let thresholds: Thresholds
    private let state: Mutex<State>

    public init(
        samples: [Float], pacing: Pacing = .immediate, devices: [InputDevice] = [fileDevice],
        authorization: MicAuthorization = .authorized, thresholds: Thresholds = .current
    ) {
        self.samples = samples
        self.pacing = pacing
        self.thresholds = thresholds
        state = Mutex(State(devices: devices, authorization: authorization))
    }

    /// Reads any audio file AVFAudio can open, converted to 16 kHz mono (the first channel). Nil when it can't be
    /// read.
    public convenience init?(
        contentsOf url: URL, pacing: Pacing = .immediate, devices: [InputDevice] = [fileDevice],
        authorization: MicAuthorization = .authorized, thresholds: Thresholds = .current
    ) {
        guard let samples = Self.read(url) else { return nil }
        self.init(
            samples: samples, pacing: pacing, devices: devices, authorization: authorization, thresholds: thresholds)
    }

    public func inputDevices() -> [InputDevice] { state.withLock { $0.devices } }

    public func authorization() -> MicAuthorization { state.withLock { $0.authorization } }

    public func deviceChanges() -> AsyncStream<[InputDevice]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [InputDevice].self)
        let id = UUID()
        let devices = state.withLock { state in
            state.deviceWatchers[id] = continuation
            return state.devices
        }
        continuation.yield(devices)
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.deviceWatchers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Changes the device list, as plugging or unplugging would. If the device in use is gone, the take ends with
    /// nothing kept.
    public func setDevices(_ devices: [InputDevice]) {
        let (lost, watchers) = state.withLock { state in
            state.devices = devices
            let lost = state.session.flatMap { session in
                devices.contains(where: { $0.id == session.device.id }) ? nil : session
            }
            return (lost, Array(state.deviceWatchers.values))
        }
        lost?.discard(.deviceLost)
        for watcher in watchers { watcher.yield(devices) }
    }

    /// Changes the permission, as System Settings would.
    public func setAuthorization(_ authorization: MicAuthorization) {
        state.withLock { $0.authorization = authorization }
    }

    public func start(device: InputDevice.ID?, lastSessionFloorDBFS: Double?) async throws(CaptureError)
        -> CaptureSession
    {
        let (devices, authorization) = state.withLock { ($0.devices, $0.authorization) }
        if let error = CaptureError.preflight(devices: devices, authorization: authorization) { throw error }
        if authorization == .notDetermined { setAuthorization(.authorized) }
        guard let input = InputDevice.resolve(device, in: devices) else { throw .noMicrophone }

        let session = CaptureSession(
            device: input, lastSessionFloorDBFS: lastSessionFloorDBFS, thresholds: thresholds)
        let previous = state.withLock { state in
            defer {
                state.session = session
                state.position = 0
            }
            return state.session
        }
        previous?.cancel()

        switch pacing {
        case .immediate:
            advance(by: .infinity)
        case .realTime:
            Task.detached { [weak self] in await self?.playInRealTime(session) }
        case .manual:
            break
        }
        return session
    }

    /// Feeds the next `seconds` of the recording into the current take, at once. Past the end of the recording the
    /// take stops (as Stop). No effect without a running take.
    public func advance(by seconds: Double) {
        let chunk = seconds.isFinite ? Int((seconds * SampleConverter.outputSampleRate).rounded()) : samples.count
        let next = state.withLock { state -> (CaptureSession, Range<Int>)? in
            guard let session = state.session, session.outcome == nil else { return nil }
            let end = min(samples.count, state.position + max(0, chunk))
            defer { state.position = end }
            return (session, state.position..<end)
        }
        guard let (session, range) = next else { return }
        session.feed(Array(samples[range]))
        if range.upperBound >= samples.count { session.stop() }
    }

    private func playInRealTime(_ session: CaptureSession) async {
        let clock = ContinuousClock()
        var deadline = clock.now
        while session.outcome == nil, isCurrent(session) {
            advance(by: 0.01)
            deadline += .milliseconds(10)
            try? await clock.sleep(until: deadline)
        }
    }

    private func isCurrent(_ session: CaptureSession) -> Bool {
        state.withLock { $0.session === session }
    }

    private static func read(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
            let converter = SampleConverter(from: file.processingFormat),
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384)
        else { return nil }
        var samples: [Float] = []
        while file.framePosition < file.length {
            do { try file.read(into: buffer) } catch { return nil }
            if buffer.frameLength == 0 { break }
            samples += converter.convert(buffer)
        }
        return samples + converter.finish()
    }
}
