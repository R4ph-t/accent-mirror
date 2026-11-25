// The selected input's volume (Designer addendum v3.5 I1): the Mac's own input volume, the CoreAudio volume scalar
// System Settings › Sound › Input sets, so it applies in every app. There is no in-app digital gain: it can't undo
// clipping at the converter, and a private gain would disagree with the level other apps hear. The element policy
// lives here, platform-neutral and tested with a fake; `CoreAudioVolumeScalars` (in `Live/`) is the Mac's backend.

import Foundation

/// What the Input popover can do with a device's volume.
public enum InputVolumeState: Sendable, Hashable {
    /// The device exposes a settable volume scalar (0…1).
    case settable(Double)
    /// The device has no settable volume ("This microphone sets its own level"), or it's gone.
    case fixed
}

/// Reads and sets an input device's volume. `InputVolume` over `CoreAudioVolumeScalars` on the Mac.
public protocol InputVolumeControl: Sendable {
    func state(of device: InputDevice.ID) -> InputVolumeState
    /// Sets the volume (clamped to 0…1). False when the device can't take it.
    @discardableResult func setVolume(_ volume: Double, of device: InputDevice.ID) -> Bool
}

/// One device's volume-scalar elements in the input scope: element 0 is the main (master) control, 1…n are the
/// channels. Every call is a property read or write; nothing here opens the input.
public protocol VolumeScalarElements: Sendable {
    /// The input channel count; nil when the device isn't there.
    func inputChannelCount(of device: InputDevice.ID) -> Int?
    /// The element has a volume scalar that can be set.
    func isSettable(device: InputDevice.ID, element: UInt32) -> Bool
    func scalar(device: InputDevice.ID, element: UInt32) -> Double?
    func setScalar(_ value: Double, device: InputDevice.ID, element: UInt32) -> Bool
}

/// The element policy: the main element when it's settable, otherwise every settable channel together (read as
/// their mean, set to the same value). With neither, the volume is `fixed`.
public struct InputVolume<Elements: VolumeScalarElements>: InputVolumeControl {
    public let elements: Elements

    public init(_ elements: Elements) {
        self.elements = elements
    }

    /// The elements the slider drives; empty when the device has no settable volume.
    public func controlledElements(of device: InputDevice.ID) -> [UInt32] {
        guard let channels = elements.inputChannelCount(of: device) else { return [] }
        if elements.isSettable(device: device, element: 0) { return [0] }
        guard channels > 0 else { return [] }
        return (1...UInt32(channels)).filter { elements.isSettable(device: device, element: $0) }
    }

    public func state(of device: InputDevice.ID) -> InputVolumeState {
        let values = controlledElements(of: device).compactMap { elements.scalar(device: device, element: $0) }
        guard !values.isEmpty else { return .fixed }
        return .settable(min(1, max(0, values.reduce(0, +) / Double(values.count))))
    }

    @discardableResult
    public func setVolume(_ volume: Double, of device: InputDevice.ID) -> Bool {
        let targets = controlledElements(of: device)
        guard !targets.isEmpty, volume.isFinite else { return false }
        let value = min(1, max(0, volume))
        return targets.map { elements.setScalar(value, device: device, element: $0) }.allSatisfy(\.self)
    }
}
