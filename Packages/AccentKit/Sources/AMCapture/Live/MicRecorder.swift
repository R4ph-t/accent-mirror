// The Mac's microphone as a `CaptureSource` (spec 14). The only file that uses AVFoundation's capture APIs and Core
// Audio's device properties; compiled out on iOS (iOS capture is Milestone 2). CI never instantiates it: every test
// runs on `FileCaptureSource`, and `scripts/capture-check.sh` is the hand check.

#if os(macOS)

    @preconcurrency import AVFoundation
    import AMCore
    import CoreAudio
    import Foundation
    import Synchronization
    import os

    /// Records takes from an input device with `AVAudioEngine`: an input tap converted to 16 kHz mono Float32 and fed
    /// to a `CaptureSession` (endpoint, cap, pre-roll, level and envelope streams). Opens the input only for a take,
    /// and releases it as soon as the take ends. One take at a time: starting another cancels the one running.
    public final class MicRecorder: CaptureSource {
        private struct Take {
            let session: CaptureSession
            let engine: AVAudioEngine
            let observers: [any NSObjectProtocol]
            /// How many times this take's input has been reopened after the system reconfigured it.
            let reopens: Int
        }

        /// Reopens allowed per take before a reconfiguration ends it as `deviceLost`. A Continuity microphone (an
        /// iPhone) reconfigures once or twice as its route settles just after it opens; one that keeps doing it is
        /// not usable.
        static let maxReopens = 3
        static let log = Logger(subsystem: "AccentMirror", category: "Capture")

        private let thresholds: Thresholds
        /// The running take's engine and observers. Only touched under the lock.
        private let current = Mutex<UncheckedBox<Take>?>(nil)
        /// Reopens run here, one at a time, off the notification's thread.
        private let reopenQueue = DispatchQueue(label: "AccentMirror.MicRecorder.reopen", qos: .userInitiated)

        public init(thresholds: Thresholds = .current) {
            self.thresholds = thresholds
        }

        // MARK: Devices and permission

        public func inputDevices() -> [InputDevice] {
            let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
            var seen = Set<String>()
            return Self.discovery().devices.compactMap { device in
                guard seen.insert(device.uniqueID).inserted else { return nil }
                return InputDevice(id: device.uniqueID, name: device.localizedName, isDefault: device.uniqueID == defaultID)
            }
        }

        public func deviceChanges() -> AsyncStream<[InputDevice]> {
            let (stream, continuation) = AsyncStream.makeStream(of: [InputDevice].self)
            continuation.yield(inputDevices())
            let center = NotificationCenter.default
            let notify = Self.deviceListObserver(self, continuation)
            let tokens = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification].map {
                center.addObserver(forName: $0, object: nil, queue: nil, using: notify)
            }
            let defaultChanged = DefaultInputListener { notify(Notification(name: .init("defaultInputChanged"))) }
            let held = UncheckedBox((tokens, defaultChanged))
            continuation.onTermination = { _ in
                for token in held.value.0 { center.removeObserver(token) }
                held.value.1.remove()
            }
            return stream
        }

        public func authorization() -> MicAuthorization {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: .notDetermined
            case .authorized: .authorized
            case .denied: .denied
            case .restricted: .restricted
            @unknown default: .denied
            }
        }

        // MARK: Taking

        public func start(device: InputDevice.ID?, lastSessionFloorDBFS: Double?) async throws(CaptureError)
            -> CaptureSession
        {
            let startedAt = ContinuousClock.now
            let devices = inputDevices()
            if let error = CaptureError.preflight(devices: devices, authorization: authorization()) { throw error }
            if authorization() == .notDetermined {
                guard await AVCaptureDevice.requestAccess(for: .audio) else { throw .micDenied }
            }
            guard let input = InputDevice.resolve(device, in: devices) else { throw .noMicrophone }
            current.withLock { $0 }?.value.session.cancel()

            let session = CaptureSession(
                device: input, lastSessionFloorDBFS: lastSessionFloorDBFS, thresholds: thresholds,
                startedAt: startedAt, onEnd: { [weak self] in self?.release() })
            // AVAudioEngine follows the system default unless its input unit is pointed at another device.
            let engine = try Self.openEngine(on: input.isDefault ? nil : input.id, feeding: session)

            let observers = lossObservers(engine: engine, deviceID: input.id, session: session)
            current.withLock {
                $0 = UncheckedBox(Take(session: session, engine: engine, observers: observers, reopens: 0))
            }
            do {
                engine.prepare()
                try engine.start()
            } catch {
                session.discard(.cancelled)
                throw .inputFailed(String(describing: error))
            }
            // The device may have gone between the observers and `current`: release() found nothing to release then.
            if session.outcome != nil { release() }
            return session
        }

        /// Stops the engine and drops the observers once a take has ended. Asynchronous, because the session can end
        /// from inside the tap block, where the engine must not be stopped.
        private func release() {
            guard let take = current.withLock({ box -> UncheckedBox<Take>? in
                guard let take = box, take.value.session.outcome != nil else { return nil }
                box = nil
                return take
            }) else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                take.value.engine.inputNode.removeTap(onBus: 0)
                take.value.engine.stop()
                for observer in take.value.observers { NotificationCenter.default.removeObserver(observer) }
            }
        }

        /// A fresh engine whose input tap feeds `session`, not started yet. `deviceID` nil follows the system default.
        private static func openEngine(
            on deviceID: InputDevice.ID?, feeding session: CaptureSession
        ) throws(CaptureError) -> AVAudioEngine {
            let engine = AVAudioEngine()
            if let deviceID {
                guard select(deviceID, on: engine) else { throw .noMicrophone }
            }
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard let converter = SampleConverter(from: format) else { throw .noMicrophone }
            let tap = tapBlock(TapPipe(converter: converter, session: session))
            // 50 ms per callback: the meter and live bars stay smooth; the endpointer still sees every 10 ms frame.
            engine.inputNode.installTap(
                onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate * 0.05), format: format, block: tap)
            return engine
        }

        /// Ends the take with nothing kept when its device disappears, and reopens the input when the system
        /// reconfigures it.
        private func lossObservers(
            engine: AVAudioEngine, deviceID: String, session: CaptureSession
        ) -> [any NSObjectProtocol] {
            let center = NotificationCenter.default
            let disconnected = center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil,
                using: Self.deviceLostObserver(deviceID: deviceID, session: session))
            // The engine stops when its input's sample rate or channel count changes. A Continuity microphone (an
            // iPhone) does that as its route settles just after the input opens, and the system default moving can
            // do it too, so the take reopens its device rather than ending.
            let reconfigured = center.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil,
                using: Self.reconfiguredObserver(self, engine: engine))
            return [disconnected, reconfigured]
        }

        private func scheduleReopen(after engine: AVAudioEngine) {
            let held = UncheckedBox(engine)
            reopenQueue.async { [weak self] in self?.reopen(after: held.value) }
        }

        /// Reopens the running take's device on a fresh engine after the system reconfigured `old`, keeping the take
        /// (the few milliseconds in between are not heard). The take ends as `deviceLost` when the device is gone or
        /// won't start, or after `maxReopens`.
        private func reopen(after old: AVAudioEngine) {
            guard
                let take = current.withLock({ box -> UncheckedBox<Take>? in
                    guard let take = box, take.value.engine === old, take.value.session.outcome == nil else {
                        return nil
                    }
                    return take
                })?.value
            else { return }
            let session = take.session
            old.inputNode.removeTap(onBus: 0)
            old.stop()
            for observer in take.observers { NotificationCenter.default.removeObserver(observer) }
            guard take.reopens < Self.maxReopens else {
                Self.log.error("input reconfigured \(take.reopens + 1, privacy: .public) times; take ends as deviceLost")
                session.discard(.deviceLost)
                return
            }

            let engine: AVAudioEngine
            do {
                // Pinned to the take's device by UID, so the take stays where it started even when the system
                // default has moved (macOS can switch it to an iPhone as that connects).
                engine = try Self.openEngine(on: session.device.id, feeding: session)
                engine.prepare()
                try engine.start()
            } catch {
                Self.log.error("reopening the input failed: \(String(describing: error), privacy: .public)")
                session.discard(.deviceLost)
                return
            }
            let observers = lossObservers(engine: engine, deviceID: session.device.id, session: session)
            let stored = current.withLock { box -> Bool in
                guard let running = box, running.value.engine === old else { return false }
                box = UncheckedBox(
                    Take(session: session, engine: engine, observers: observers, reopens: take.reopens + 1))
                return true
            }
            guard stored else {
                // The take ended, or another one started, while the input reopened.
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
                for observer in observers { NotificationCenter.default.removeObserver(observer) }
                return
            }
            Self.log.notice("input reconfigured; reopened it (\(take.reopens + 1, privacy: .public) of \(Self.maxReopens, privacy: .public))")
            // The take may have ended after the check above: release() found the old engine then, not this one.
            if session.outcome != nil { release() }
        }

        // These build closures outside any isolation, so the audio and notification threads may call them.

        private nonisolated static func tapBlock(_ pipe: TapPipe) -> AVAudioNodeTapBlock {
            { buffer, _ in pipe.handle(buffer) }
        }

        private nonisolated static func reconfiguredObserver(
            _ recorder: MicRecorder, engine: AVAudioEngine
        ) -> @Sendable (Notification) -> Void {
            let held = UncheckedBox(engine)
            return { [weak recorder] _ in recorder?.scheduleReopen(after: held.value) }
        }

        private nonisolated static func deviceLostObserver(deviceID: String, session: CaptureSession)
            -> @Sendable (Notification) -> Void
        {
            { notification in
                guard let device = notification.object as? AVCaptureDevice, device.uniqueID == deviceID else { return }
                session.discard(.deviceLost)
            }
        }

        private nonisolated static func deviceListObserver(
            _ recorder: MicRecorder, _ continuation: AsyncStream<[InputDevice]>.Continuation
        ) -> @Sendable (Notification) -> Void {
            { [weak recorder] _ in
                guard let recorder else { return }
                continuation.yield(recorder.inputDevices())
            }
        }

        private static func discovery() -> AVCaptureDevice.DiscoverySession {
            AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        }

        /// Points the engine's input unit at the device with Core Audio UID `uid`. False when the device is gone.
        private static func select(_ uid: String, on engine: AVAudioEngine) -> Bool {
            var deviceID = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var cfUID = uid as CFString
            let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), uidPointer,
                    &size, &deviceID)
            }
            guard status == noErr, deviceID != kAudioObjectUnknown, let unit = engine.inputNode.audioUnit else {
                return false
            }
            return AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr
        }
    }

    /// Carries tap buffers to the session. The tap block runs on one audio thread at a time, so the converter's state
    /// is never shared.
    private final class TapPipe: @unchecked Sendable {
        private let converter: SampleConverter
        private let session: CaptureSession

        init(converter: SampleConverter, session: CaptureSession) {
            self.converter = converter
            self.session = session
        }

        func handle(_ buffer: AVAudioPCMBuffer) {
            guard session.outcome == nil else { return }
            session.feed(converter.convert(buffer))
        }
    }

    /// Calls back when the system default input changes, so the Input pop-up's "default" mark follows it.
    private final class DefaultInputListener: @unchecked Sendable {
        private var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        private let block: AudioObjectPropertyListenerBlock

        init(_ changed: @escaping @Sendable () -> Void) {
            block = { _, _ in changed() }
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, block)
        }

        func remove() {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, block)
        }
    }

    /// Holds a value that isn't Sendable but is only touched under a lock or on one thread.
    private final class UncheckedBox<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

#endif
