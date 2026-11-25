import AMCapture
import Foundation
import Synchronization
import Testing

// Designer addendum v3.5: the Input popover's fixtures and rules, its mic check (driven with a fake level monitor and
// a fake volume control), the clipped quiet line, and the shortcut correction. Unhosted: no window, no microphone,
// no Core Audio, no network.

private let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let library = FixtureLibrary(root: repo.appending(path: "AccentMirror/Resources/Fixtures", directoryHint: .isDirectory))

// MARK: - Fixtures (I7)

struct V35FixtureTests {
    @Test(arguments: ["input-popover", "input-popover-no-volume", "input-popover-too-loud", "result-clipped"])
    func newFixturesDecodeAndAreListed(_ name: String) throws {
        #expect(try library.allNames().contains(name), "Samples ▸ lists \(name)")
        #expect(try library.load(name).fixture.name == name)
    }

    private func popover(_ name: String) throws -> InputPopoverState {
        let fixture = try library.load(name).fixture
        let block = try #require(fixture.inputPopover, "\(name) draws the popover open")
        return InputPopoverState(fixture: block, isRecording: fixture.phase == .recording)
    }

    @Test func inputPopoverIsSystemDefaultWithAVolumeAndAMidLevel() throws {
        let state = try popover("input-popover")
        #expect(state.selected == nil, "System Default")
        #expect(state.volume == .settable(0.7))
        #expect(state.sliderEnabled && !state.showsFixedNote && state.showsMeter && state.deviceMenuEnabled)
        let level = try #require(state.level)
        #expect(level.rmsDBFS > -60 && level.rmsDBFS < -1 && !level.tooLoud)
    }

    @Test func noVolumeDisablesTheSliderAndKeepsTheMeter() throws {
        let state = try popover("input-popover-no-volume")
        #expect(state.volume == .fixed)
        #expect(!state.sliderEnabled && state.showsFixedNote)
        #expect(state.showsMeter && state.deviceMenuEnabled)
        #expect(state.devices.first { $0.id == state.selected }?.name == "USB Microphone")
    }

    @Test func tooLoudIsAClippingFrame() throws {
        let level = try #require(try popover("input-popover-too-loud").level)
        #expect(level.tooLoud && level.peakDBFS >= -1)
    }

    @Test func resultClippedIsASavedResultWithTheClippedLine() throws {
        let loaded = try library.load("result-clipped")
        let analysis = try #require(loaded.fixture.analysis)
        #expect(analysis.clipped == true && analysis.takeProblems == nil, "tier B: measured and saved")
        #expect(loaded.take?.number == 3)
        #expect(ResultQuietLine.first(clipped: true, comparableCoverage: analysis.comparableCoverage,
                                      minimumCoverage: 0.7, timing: analysis.timing, insertions: []) == .clipped)
    }

    @Test func otherFixturesHaveNoPopoverAndNoClipping() throws {
        for name in try library.allNames() where !name.hasPrefix("input-popover") && name != "result-clipped" {
            let fixture = try library.load(name).fixture
            #expect(fixture.inputPopover == nil && fixture.analysis?.clipped == nil, "\(name)")
        }
    }
}

// MARK: - Quiet line order (I4 tier B)

struct ClippedQuietLineTests {
    @Test func clippedComesFirst() {
        #expect(ResultQuietLine.first(clipped: true, comparableCoverage: 0.2, minimumCoverage: 0.7, timing: .rough,
                                      insertions: ["so"]) == .clipped)
        #expect(ResultQuietLine.first(clipped: false, comparableCoverage: 0.2, minimumCoverage: 0.7, timing: .rough,
                                      insertions: ["so"]) == .lowCoverage)
        #expect(ResultQuietLine.first(comparableCoverage: 0.9, minimumCoverage: 0.7, timing: .good, insertions: []) == nil)
    }
}

// MARK: - Popover rules (I1, I3, I6)

struct InputPopoverStateTests {
    private let mic = InputDevice(id: "mbp", name: "MacBook Pro Microphone", isDefault: true)
    private let usb = InputDevice(id: "usb", name: "USB Microphone", isDefault: false)

    private func state(devices: [InputDevice]? = nil, requested: String? = nil, authorization: MicAuthorization = .authorized,
                       recording: Bool = false, volume: InputVolumeState = .settable(0.5)) -> InputPopoverState {
        InputPanel.state(devices: devices ?? [mic, usb], requested: requested, authorization: authorization,
                         isRecording: recording, volume: volume)
    }

    @Test func recordingKeepsTheVolumeAndLocksTheMicrophone() {
        let recording = state(recording: true)
        #expect(!recording.deviceMenuEnabled, "Stop recording to change the microphone")
        #expect(recording.sliderEnabled, "the level can come down mid-take")
        #expect(recording.showsMeter && !recording.listens, "the take's own levels, not a second listener")
    }

    @Test func deniedShowsTheNoticeAndNeverListens() {
        for authorization in [MicAuthorization.denied, .restricted] {
            let denied = state(authorization: authorization)
            #expect(denied.notice == .micDenied)
            #expect(!denied.showsMeter && !denied.listens)
            #expect(denied.deviceMenuEnabled && denied.sliderEnabled, "the controls stay visible and usable")
        }
    }

    @Test func noMicrophoneDisablesEverything() {
        let none = state(devices: [], volume: .fixed)
        #expect(none.notice == .noMicrophone)
        #expect(!none.deviceMenuEnabled && !none.sliderEnabled && !none.showsMeter && !none.showsFixedNote)
    }

    @Test func notYetAskedListensSoOpeningCanAsk() {
        #expect(state(authorization: .notDetermined).listens)
    }

    @Test func aFixedLevelDeviceShowsTheNote() {
        let fixed = state(requested: "usb", volume: .fixed)
        #expect(!fixed.sliderEnabled && fixed.showsFixedNote && fixed.sliderValue == 1)
        #expect(fixed.selected == "usb")
    }

    @Test func anUnpluggedChoiceReadsAsSystemDefault() {
        #expect(state(requested: "gone").selected == nil)
    }
}

// MARK: - The mic check (I3): only while open, never while recording

private final class FakeMonitor: InputLevelMonitor, Sendable {
    let starts = Mutex<[String?]>([])
    let terminations = Mutex(0)
    var started: [String?] { starts.withLock { $0 } }
    var ended: Int { terminations.withLock { $0 } }
    private let continuations = Mutex<[AsyncStream<InputLevel>.Continuation]>([])

    func levels(device: InputDevice.ID?) -> AsyncStream<InputLevel> {
        let (stream, continuation) = AsyncStream.makeStream(of: InputLevel.self)
        continuation.onTermination = { [terminations] _ in terminations.withLock { $0 += 1 } }
        starts.withLock { $0.append(device) }
        continuations.withLock { $0.append(continuation) }
        return stream
    }

    func yield(_ level: InputLevel) { continuations.withLock { $0.last?.yield(level) } }
    func endLast() { continuations.withLock { $0.last?.finish() } }
}

private final class FakeVolume: InputVolumeControl, Sendable {
    let values = Mutex<[String: Double]>(["mbp": 0.5])
    func value(_ device: String) -> Double? { values.withLock { $0[device] } }

    func state(of device: InputDevice.ID) -> InputVolumeState {
        values.withLock { $0[device] }.map { .settable($0) } ?? .fixed
    }

    func setVolume(_ volume: Double, of device: InputDevice.ID) -> Bool {
        values.withLock { values in
            guard values[device] != nil else { return false }
            values[device] = volume
            return true
        }
    }
}

/// Yields to the main actor until `condition` holds (the listening task runs there); fails after ~2 s.
@MainActor
private func until(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

@MainActor
struct InputPanelTests {
    private let mic = InputDevice(id: "mbp", name: "MacBook Pro Microphone", isDefault: true)
    private let usb = InputDevice(id: "usb", name: "USB Microphone", isDefault: false)

    private func panel() -> (InputPanel, FakeMonitor, FakeVolume) {
        let monitor = FakeMonitor()
        let volume = FakeVolume()
        let panel = InputPanel(volume: volume, monitor: monitor)
        panel.update(devices: [mic, usb], requested: nil, authorization: .authorized, isRecording: false)
        return (panel, monitor, volume)
    }

    @Test func nothingListensUntilThePopoverOpens() {
        let (panel, monitor, _) = panel()
        panel.update(devices: [mic, usb], requested: "usb", authorization: .authorized, isRecording: false)
        #expect(monitor.started.isEmpty, "no idle monitoring")
        #expect(!panel.isListening)
    }

    @Test func openingListensToTheChosenInputAndClosingReleasesIt() async {
        let (panel, monitor, _) = panel()
        var shown: [InputPopoverState?] = []
        panel.onChange = { shown.append($0) }
        var levels: [InputLevel] = []
        panel.onLevel = { levels.append($0) }
        panel.open()
        #expect(monitor.started == [nil], "System Default")
        #expect(shown.last??.volume == .settable(0.5))
        monitor.yield(InputLevel(time: 0.01, rmsDBFS: -30, peakDBFS: -24))
        await until { levels.count == 1 }
        panel.close()
        #expect(!panel.isListening)
        #expect(shown.last! == nil)
        await until { monitor.ended == 1 }
    }

    @Test func aTakeStopsTheMicCheckAndItResumesAfter() async {
        let (panel, monitor, _) = panel()
        panel.open()
        panel.update(devices: [mic, usb], requested: nil, authorization: .authorized, isRecording: true)
        #expect(!panel.isListening && panel.state.isRecording)
        await until { monitor.ended == 1 }
        panel.update(devices: [mic, usb], requested: nil, authorization: .authorized, isRecording: false)
        #expect(panel.isListening)
        #expect(monitor.started.count == 2)
    }

    @Test func choosingAnotherInputListensToIt() async {
        let (panel, monitor, _) = panel()
        panel.open()
        panel.update(devices: [mic, usb], requested: "usb", authorization: .authorized, isRecording: false)
        #expect(monitor.started == [nil, "usb"])
        await until { monitor.ended == 1 }
        #expect(panel.state.selected == "usb")
    }

    @Test func deniedNeverListens() {
        let (panel, monitor, _) = panel()
        panel.update(devices: [mic, usb], requested: nil, authorization: .denied, isRecording: false)
        panel.open()
        #expect(monitor.started.isEmpty)
        #expect(panel.state.notice == .micDenied)
    }

    @Test func anInputThatEndsByItselfIsNotReopenedUntilSomethingChanges() async {
        let (panel, monitor, _) = panel()
        var ended = 0
        panel.onListeningEnded = { ended += 1 }
        panel.open()
        monitor.endLast()
        await until { ended == 1 }
        #expect(!panel.isListening)
        panel.refresh()
        #expect(monitor.started.count == 1, "no restart loop")
        panel.close()
        panel.open()
        #expect(monitor.started.count == 2, "reopening the popover tries again")
    }

    @Test func theSliderSetsTheMacVolumeOfTheInputInUse() {
        let (panel, _, volume) = panel()
        panel.open()
        panel.setVolume(0.25)
        #expect(volume.value("mbp") == 0.25)
        #expect(panel.state.volume == .settable(0.25))
        panel.update(devices: [mic, usb], requested: "usb", authorization: .authorized, isRecording: false)
        #expect(panel.state.volume == .fixed)
        panel.setVolume(0.9)
        #expect(volume.value("usb") == nil, "a fixed-level device isn't written")
    }
}

// MARK: - Shortcut correction (I5): no shortcut for Input…, and never ⌥⌘M

struct InputShortcutTests {
    @Test func noInputShortcutAndNoOptionCommandM() {
        #expect(!MenuTable.commands.contains { $0.key == "m" })
        #expect(!MenuCommand.Action.allCases.map(\.rawValue).contains { $0.lowercased().contains("input") })
    }
}
