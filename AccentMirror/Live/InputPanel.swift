import AMCapture
import Foundation

// The Input popover (Designer addendum v3.5 I1–I6), UI-free: what it shows (`InputPopoverState`) and when it listens
// (`InputPanel`). The unhosted `AccentMirrorTests` compile this file and drive `InputPanel` with a fake volume
// control and a fake level monitor: no microphone, no Core Audio, no window.

/// What the popover draws. A fixture freezes one (`input-popover`, …); the live app's `InputPanel` publishes it.
struct InputPopoverState: Equatable, Sendable {
    struct Device: Equatable, Sendable {
        var id: String
        var name: String
    }

    enum Volume: Equatable, Sendable {
        /// The device's Mac input volume, 0…1.
        case settable(Double)
        /// "This microphone sets its own level": the slider is drawn disabled.
        case fixed
    }

    /// v2 §11.1's copy, reused (I6).
    enum Notice: String, Equatable, Sendable, Decodable {
        case micDenied, noMicrophone
    }

    /// The listed inputs, after "System Default".
    var devices: [Device]
    /// The chosen input; nil is "System Default" (the default).
    var selected: String?
    var volume: Volume
    var notice: Notice?
    var isRecording: Bool
    /// A fixture's frozen meter frame; nil reads the live meter.
    var level: LevelReading?

    /// The device pop-up: disabled while recording ("Stop recording to change the microphone") or with no microphone.
    var deviceMenuEnabled: Bool { notice != .noMicrophone && !isRecording }
    /// The volume stays enabled while recording, so the level can come down mid-take (I3).
    var sliderEnabled: Bool { notice != .noMicrophone && volume != .fixed }
    /// The slider's position. A fixed-level device is drawn full: it isn't turned down.
    var sliderValue: Double {
        if case .settable(let value) = volume { value } else { 1 }
    }
    /// "This microphone sets its own level" and "Sound Settings…" under the disabled slider.
    var showsFixedNote: Bool { notice != .noMicrophone && volume == .fixed }
    /// The meter and its hint; not with a notice (permission denied: nothing listens; no microphone).
    var showsMeter: Bool { notice == nil }
    /// The popover's own mic check runs: no notice and no take (during a take the meter shows the take's levels).
    var listens: Bool { notice == nil && !isRecording }
}

/// The popover's state and its mic check in the live app (I3): the input is opened only while the popover is open
/// and nothing records, and released as soon as either changes. No idle monitoring.
@MainActor
final class InputPanel {
    private(set) var isOpen = false
    private(set) var state: InputPopoverState
    /// Called with the state to draw whenever it changes; nil when the popover closes.
    var onChange: (@MainActor (InputPopoverState?) -> Void)?
    /// The mic check's levels (10 ms frames).
    var onLevel: (@MainActor (InputLevel) -> Void)?
    /// The mic check stopped (closed, a take started, the device changed, or the input ended by itself).
    var onStopListening: (@MainActor () -> Void)?
    /// The input ended by itself (permission refused, device gone): the app re-reads permission and devices.
    var onListeningEnded: (@MainActor () -> Void)?

    private let volume: any InputVolumeControl
    private let monitor: any InputLevelMonitor
    private var devices: [InputDevice] = []
    private var requested: InputDevice.ID?
    private var authorization: MicAuthorization = .notDetermined
    private var isRecording = false
    /// The listening task and the device it listens to (nil key: the system default).
    private var listening: (task: Task<Void, Never>, device: InputDevice.ID?, generation: Int)?
    private var generation = 0
    /// The device whose input ended by itself: not reopened until something changes.
    private var ended: InputDevice.ID??

    init(volume: any InputVolumeControl, monitor: any InputLevelMonitor) {
        self.volume = volume
        self.monitor = monitor
        state = InputPopoverState(devices: [], selected: nil, volume: .fixed, notice: .noMicrophone, isRecording: false)
    }

    /// The device a take (and the volume slider) uses now.
    var resolvedDevice: InputDevice? { InputDevice.resolve(requested, in: devices) }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        ended = nil
        sync()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        sync()
    }

    func toggle() {
        isOpen ? close() : open()
    }

    /// The app's inputs, the chosen one (nil: System Default), permission and whether a take is recording.
    func update(devices: [InputDevice], requested: InputDevice.ID?, authorization: MicAuthorization, isRecording: Bool) {
        if devices != self.devices || requested != self.requested || authorization != self.authorization {
            ended = nil
        }
        self.devices = devices
        self.requested = requested
        self.authorization = authorization
        self.isRecording = isRecording
        sync()
    }

    /// The slider moved: the Mac's input volume for the device in use (I1), then read back.
    func setVolume(_ value: Double) {
        guard state.sliderEnabled, let device = resolvedDevice else { return }
        volume.setVolume(value, of: device.id)
        sync()
    }

    /// Re-reads the volume (it may have moved in System Settings).
    func refresh() {
        sync()
    }

    private func sync() {
        state = Self.state(devices: devices, requested: requested, authorization: authorization,
                           isRecording: isRecording, volume: resolvedDevice.map { volume.state(of: $0.id) } ?? .fixed)
        let wanted: InputDevice.ID?? = isOpen && state.listens && resolvedDevice != nil ? .some(requested) : nil
        if let current = listening, wanted == nil || wanted! != current.device {
            stopListening()
        }
        if listening == nil, let device = wanted, ended == nil || ended! != device {
            startListening(device)
        }
        onChange?(isOpen ? state : nil)
    }

    nonisolated static func state(devices: [InputDevice], requested: InputDevice.ID?, authorization: MicAuthorization,
                      isRecording: Bool, volume: InputVolumeState) -> InputPopoverState {
        let notice: InputPopoverState.Notice? = if devices.isEmpty {
            .noMicrophone
        } else if authorization == .denied || authorization == .restricted {
            .micDenied
        } else {
            nil
        }
        let shown: InputPopoverState.Volume = if case .settable(let value) = volume { .settable(value) } else { .fixed }
        // A remembered device that's unplugged reads as System Default until it's back.
        let selected = requested.flatMap { id in devices.contains { $0.id == id } ? id : nil }
        return InputPopoverState(devices: devices.map { .init(id: $0.id, name: $0.name) }, selected: selected,
                                 volume: shown, notice: notice, isRecording: isRecording)
    }

    private func startListening(_ device: InputDevice.ID?) {
        generation += 1
        let mine = generation
        let stream = monitor.levels(device: device)
        let task = Task { @MainActor [weak self] in
            for await level in stream {
                guard !Task.isCancelled else { break }
                self?.onLevel?(level)
            }
            guard !Task.isCancelled, let self, self.listening?.generation == mine else { return }
            // The input ended by itself: don't reopen it until something changes.
            self.listening = nil
            self.ended = .some(device)
            self.onStopListening?()
            self.onListeningEnded?()
        }
        listening = (task, device, mine)
    }

    private func stopListening() {
        listening?.task.cancel()
        listening = nil
        onStopListening?()
    }

    /// True while the mic check holds the input (tests).
    var isListening: Bool { listening != nil }
}

extension InputPopoverState {
    /// A fixture's `inputPopover` block; `isRecording` follows the fixture's phase.
    init(fixture: InputPopoverFixture, isRecording: Bool) {
        let names = fixture.devices ?? []
        let list = names.enumerated().map { Device(id: "fixture-\($0.offset)", name: $0.element) }
        devices = list
        selected = fixture.device.flatMap { name in list.first { $0.name == name }?.id }
        volume = fixture.volume.map { .settable(min(1, max(0, $0))) } ?? .fixed
        notice = fixture.notice
        self.isRecording = isRecording
        level = fixture.level
    }
}
