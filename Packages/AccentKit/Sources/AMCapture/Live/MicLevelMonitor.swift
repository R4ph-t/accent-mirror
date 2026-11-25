// The Input popover's mic check on the Mac (Designer addendum v3.5 I3): an input tap measured into 10 ms levels for
// the meter and nothing else. No sample is kept, written or analysed. The input opens when the popover asks and is
// released as soon as the popover stops listening (or a take starts).

#if os(macOS)

    @preconcurrency import AVFoundation
    import AudioToolbox
    import CoreAudio
    import Foundation

    public final class MicLevelMonitor: InputLevelMonitor {
        public init() {}

        public func levels(device: InputDevice.ID?) -> AsyncStream<InputLevel> {
            let (stream, continuation) = AsyncStream.makeStream(
                of: InputLevel.self, bufferingPolicy: .bufferingNewest(32))
            let queue = DispatchQueue(label: "AccentMirror.MicLevelMonitor", qos: .userInitiated)
            let listener = Listener(continuation: continuation, queue: queue)
            continuation.onTermination = { _ in queue.async { listener.stop() } }
            Task.detached(priority: .userInitiated) {
                guard await Self.authorized(),
                      let input = InputDevice.resolve(device, in: MicRecorder().inputDevices())
                else {
                    continuation.finish()
                    return
                }
                queue.async { listener.start(input) }
            }
            return stream
        }

        /// Asks once if never asked (the system's own prompt; opening the popover is the user's action).
        private static func authorized() async -> Bool {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return true
            case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
            default: return false
            }
        }
    }

    /// One listening session. Only touched on its serial queue, except the tap, which owns its `MeterTap`.
    private final class Listener: @unchecked Sendable {
        private let continuation: AsyncStream<InputLevel>.Continuation
        private let queue: DispatchQueue
        private var engine: AVAudioEngine?
        private var observer: (any NSObjectProtocol)?
        private var stopped = false

        init(continuation: AsyncStream<InputLevel>.Continuation, queue: DispatchQueue) {
            self.continuation = continuation
            self.queue = queue
        }

        func start(_ input: InputDevice) {
            guard !stopped else { return }
            let engine = AVAudioEngine()
            if !input.isDefault {
                guard let id = CoreAudioVolumeScalars.deviceID(uid: input.id), let unit = engine.inputNode.audioUnit
                else { return fail() }
                var deviceID = id
                let status = AudioUnitSetProperty(
                    unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID,
                    UInt32(MemoryLayout<AudioDeviceID>.size))
                guard status == noErr else { return fail() }
            }
            self.engine = engine
            guard install(on: engine) else { return fail() }
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.queue.async { self.reconfigure() }
            }
            do {
                engine.prepare()
                try engine.start()
            } catch {
                fail()
            }
        }

        /// The device's format changed, or its switch completed after start: re-tap at the new format and keep going.
        private func reconfigure() {
            guard !stopped, let engine else { return }
            engine.inputNode.removeTap(onBus: 0)
            guard install(on: engine) else { return fail() }
            if !engine.isRunning {
                do {
                    engine.prepare()
                    try engine.start()
                } catch {
                    fail()
                }
            }
        }

        private func install(on engine: AVAudioEngine) -> Bool {
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0, let tap = MeterTap(format: format, continuation: continuation)
            else { return false }
            engine.inputNode.installTap(
                onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate * 0.05), format: format,
                block: Self.tapBlock(tap))
            return true
        }

        private nonisolated static func tapBlock(_ tap: MeterTap) -> AVAudioNodeTapBlock {
            { buffer, _ in tap.handle(buffer) }
        }

        func stop() {
            stopped = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
        }

        private func fail() {
            stop()
            continuation.finish()
        }
    }

    /// Converts tap buffers to 16 kHz mono and yields their 10 ms levels. The tap block runs on one audio thread at a
    /// time, and a reconfigured engine gets a new `MeterTap`.
    private final class MeterTap: @unchecked Sendable {
        private let converter: SampleConverter
        private var frames = LevelFrames()
        private let continuation: AsyncStream<InputLevel>.Continuation

        init?(format: AVAudioFormat, continuation: AsyncStream<InputLevel>.Continuation) {
            guard let converter = SampleConverter(from: format) else { return nil }
            self.converter = converter
            self.continuation = continuation
        }

        func handle(_ buffer: AVAudioPCMBuffer) {
            let samples = converter.convert(buffer)
            guard !samples.isEmpty else { return }
            for level in frames.feed(samples) { continuation.yield(level) }
        }
    }

#endif
