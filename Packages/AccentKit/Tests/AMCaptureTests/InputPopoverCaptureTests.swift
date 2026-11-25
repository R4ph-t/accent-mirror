// Designer addendum v3.5: the input volume's element policy (behind `VolumeScalarElements`, with a fake), the clipping
// tiers, and the 10 ms level frames the popover's mic check measures. No microphone, no Core Audio, no window.

import AMCore
import Foundation
import Synchronization
import Testing
@testable import AMCapture

/// A device's input-scope volume elements, in memory.
private final class FakeElements: VolumeScalarElements, Sendable {
    struct Device {
        var channels: Int
        /// Element → (settable, value). Elements not listed have no volume scalar.
        var scalars: [UInt32: (settable: Bool, value: Double)]
    }

    private let devices: Mutex<[String: Device]>
    let writes = Mutex<[(device: String, element: UInt32, value: Double)]>([])
    var writtenElements: [UInt32] { writes.withLock { $0.map(\.element) } }

    init(_ devices: [String: Device]) {
        self.devices = Mutex(devices)
    }

    func inputChannelCount(of device: InputDevice.ID) -> Int? { devices.withLock { $0[device]?.channels } }

    func isSettable(device: InputDevice.ID, element: UInt32) -> Bool {
        devices.withLock { $0[device]?.scalars[element]?.settable ?? false }
    }

    func scalar(device: InputDevice.ID, element: UInt32) -> Double? {
        devices.withLock { $0[device]?.scalars[element]?.value }
    }

    func setScalar(_ value: Double, device: InputDevice.ID, element: UInt32) -> Bool {
        devices.withLock { devices in
            guard let scalar = devices[device]?.scalars[element], scalar.settable else { return false }
            devices[device]?.scalars[element] = (true, value)
            writes.withLock { $0.append((device, element, value)) }
            return true
        }
    }
}

@Suite("Input volume (v3.5 I1)") struct InputVolumeTests {
    @Test("a settable main element is the volume, and setting it writes element 0 only")
    func mainElement() {
        let fake = FakeElements(["mbp": .init(channels: 2, scalars: [0: (true, 0.7), 1: (true, 0.2), 2: (true, 0.2)])])
        let volume = InputVolume(fake)
        #expect(volume.state(of: "mbp") == .settable(0.7))
        #expect(volume.setVolume(0.4, of: "mbp"))
        #expect(volume.state(of: "mbp") == .settable(0.4))
        #expect(fake.writtenElements == [0])
    }

    @Test("without a main control, every settable channel moves together and reads as their mean")
    func perChannel() {
        let fake = FakeElements(["usb": .init(channels: 2, scalars: [1: (true, 0.4), 2: (true, 0.6)])])
        let volume = InputVolume(fake)
        #expect(volume.state(of: "usb") == .settable(0.5))
        #expect(volume.setVolume(0.8, of: "usb"))
        #expect(fake.writtenElements == [1, 2])
        #expect(volume.state(of: "usb") == .settable(0.8))
    }

    @Test("a read-only scalar, no scalar at all, or a missing device is fixed, and setting it fails")
    func fixed() {
        let fake = FakeElements([
            "dji": .init(channels: 1, scalars: [0: (false, 1.0)]),
            "iphone": .init(channels: 1, scalars: [:]),
        ])
        let volume = InputVolume(fake)
        for device in ["dji", "iphone", "gone"] {
            #expect(volume.state(of: device) == .fixed, "\(device)")
            #expect(!volume.setVolume(0.5, of: device), "\(device)")
        }
        #expect(fake.writtenElements.isEmpty)
    }

    @Test("values are clamped to 0…1 and a non-finite value is refused")
    func clamping() {
        let fake = FakeElements(["mbp": .init(channels: 1, scalars: [0: (true, 0.5)])])
        let volume = InputVolume(fake)
        #expect(volume.setVolume(1.4, of: "mbp"))
        #expect(volume.state(of: "mbp") == .settable(1))
        #expect(volume.setVolume(-0.2, of: "mbp"))
        #expect(volume.state(of: "mbp") == .settable(0))
        #expect(!volume.setVolume(.nan, of: "mbp"))
    }
}

@Suite("Clipping tiers (v3.5 I4)") struct ClippingTierTests {
    private let rate = 16_000.0

    /// A quiet tone with `loudMs` milliseconds at full scale starting at `atMs`.
    private func take(loudMs: Int, atMs: Int = 300, totalMs: Int = 1_000) -> [Float] {
        let n = Int(rate) * totalMs / 1_000
        var samples = (0..<n).map { Float(0.1 * sin(Double($0) * 2 * .pi * 220 / 16_000)) }
        let start = Int(rate) * atMs / 1_000
        for i in start..<min(n, start + Int(rate) * loudMs / 1_000) { samples[i] = i.isMultiple(of: 2) ? 0.99 : -0.99 }
        return samples
    }

    @Test("the take problem clipped is tier A: unmeasurable, not saved")
    func tierA() {
        #expect(ClippingTier.classify(takeProblem: .clipped, samples: take(loudMs: 0), sampleRate: rate) == .unmeasurable)
    }

    @Test("a measured take with a 50 ms run at −1 dBFS is tier B")
    func tierB() {
        #expect(ClippingTier.longestRunSeconds(take(loudMs: 50), sampleRate: rate) == 0.05)
        #expect(ClippingTier.classify(takeProblem: nil, samples: take(loudMs: 50), sampleRate: rate) == .clippedSaved)
        #expect(ClippingTier.classify(takeProblem: nil, samples: take(loudMs: 120), sampleRate: rate) == .clippedSaved)
    }

    @Test("shorter spikes, and separate spikes that add up, aren't announced")
    func shortSpikes() {
        #expect(ClippingTier.classify(takeProblem: nil, samples: take(loudMs: 40), sampleRate: rate) == .none)
        var twoSpikes = take(loudMs: 30, atMs: 200)
        let second = take(loudMs: 30, atMs: 600)
        for i in twoSpikes.indices where abs(second[i]) > 0.5 { twoSpikes[i] = second[i] }
        #expect(ClippingTier.longestRunSeconds(twoSpikes, sampleRate: rate) == 0.03)
        #expect(ClippingTier.classify(takeProblem: nil, samples: twoSpikes, sampleRate: rate) == .none)
    }

    @Test("−1 dBFS is the line: 0.89 doesn't count, 0.9 does")
    func threshold() {
        let below = [Float](repeating: 0.89, count: 1_600)
        let at = [Float](repeating: 0.9, count: 1_600)
        #expect(ClippingTier.longestRunSeconds(below, sampleRate: rate) == 0)
        #expect(ClippingTier.longestRunSeconds(at, sampleRate: rate) == 0.1)
    }

    @Test("another take problem says nothing about clipping")
    func otherProblem() {
        #expect(ClippingTier.classify(takeProblem: .tooShort, samples: take(loudMs: 200), sampleRate: rate) == .none)
    }
}

@Suite("Mic check levels (v3.5 I3)") struct LevelFramesTests {
    @Test("10 ms frames from any chunk size, measured like the recording meter")
    func frames() {
        var frames = LevelFrames()
        #expect(frames.feed([Float](repeating: 0.5, count: 100)).isEmpty, "a partial frame waits")
        let levels = frames.feed([Float](repeating: 0.5, count: 380))
        #expect(levels.count == 3)
        #expect(levels.map(\.time) == [0.01, 0.02, 0.03])
        let expected = 20 * log10(0.5)
        #expect(levels.allSatisfy { abs($0.rmsDBFS - expected) < 1e-4 && abs($0.peakDBFS - expected) < 1e-4 })
        let loud = frames.feed([Float](repeating: 1, count: 160))
        #expect(loud.first?.peakDBFS == 0)
        #expect(frames.feed([Float](repeating: 0, count: 160)).first?.rmsDBFS == InputLevel.floorDBFS)
    }
}
