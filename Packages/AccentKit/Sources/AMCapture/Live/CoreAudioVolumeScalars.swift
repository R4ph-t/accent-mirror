// The Mac's input volume (Designer addendum v3.5 I1): Core Audio's `kAudioDevicePropertyVolumeScalar` in the input
// scope, on the main element or each channel, the control System Settings › Sound › Input moves. Property reads and
// writes only: nothing here opens the input or touches samples. `InputVolume` holds the element policy.

#if os(macOS)

    import CoreAudio
    import Foundation

    public struct CoreAudioVolumeScalars: VolumeScalarElements {
        public init() {}

        public func inputChannelCount(of device: InputDevice.ID) -> Int? {
            guard let id = Self.deviceID(uid: device) else { return nil }
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
            let raw = UnsafeMutableRawPointer.allocate(
                byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { raw.deallocate() }
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
            let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
            return list.reduce(0) { $0 + Int($1.mNumberChannels) }
        }

        public func isSettable(device: InputDevice.ID, element: UInt32) -> Bool {
            guard let id = Self.deviceID(uid: device) else { return false }
            var address = Self.volume(element)
            guard AudioObjectHasProperty(id, &address) else { return false }
            var settable: DarwinBoolean = false
            return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
        }

        public func scalar(device: InputDevice.ID, element: UInt32) -> Double? {
            guard let id = Self.deviceID(uid: device) else { return nil }
            var address = Self.volume(element)
            guard AudioObjectHasProperty(id, &address) else { return nil }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
            return Double(value)
        }

        public func setScalar(_ value: Double, device: InputDevice.ID, element: UInt32) -> Bool {
            guard let id = Self.deviceID(uid: device) else { return false }
            var address = Self.volume(element)
            var scalar = Float32(value)
            return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
                == noErr
        }

        private static func volume(_ element: UInt32) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeInput, mElement: element)
        }

        /// The Core Audio device with UID `uid` (the `InputDevice.ID`); nil when it's gone.
        static func deviceID(uid: String) -> AudioObjectID? {
            var deviceID = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var cfUID = uid as CFString
            let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), pointer,
                    &size, &deviceID)
            }
            return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
        }
    }

#endif
