// Spec 14 through the file-backed CaptureSource: the same CaptureSession the microphone feeds, with no microphone.
// Covers auto-stop at 1.2 s, the 20 s cap, cancel, the 200 ms pre-roll (E16), the problem order of a clipped short
// take, the stop timestamp, the level and envelope streams, permission, devices and a device lost mid-take.

@preconcurrency import AVFAudio
import AMCore
import CryptoKit
import Foundation
import Testing
@testable import AMCapture

private func collect<Element>(_ stream: AsyncStream<Element>) async -> [Element] {
    var values: [Element] = []
    for await value in stream { values.append(value) }
    return values
}

private func record(_ signal: [Float]) async throws -> CapturedTake {
    let session = try await FileCaptureSource(samples: signal).start()
    return try #require(await session.result().take)
}

private let usb = InputDevice(id: "usb", name: "USB Mic", isDefault: false)
private let builtIn = InputDevice(id: "built-in", name: "MacBook Pro Microphone", isDefault: true)

@Suite("Live capture (spec 14)") struct LiveCaptureTests {
    // MARK: Ending a take

    @Test("auto-stop: the take ends 1.2 s after the last speech") func autoStop() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 5, dBFS: -60, seed: 141), Synth.speech(seconds: 1, peakDBFS: -25), at: 0.5)
        let take = try await record(signal)
        let onset = try #require(take.onsetTime)
        let lastSpeech = try #require(take.lastSpeechTime)
        #expect(take.stopReason == .endOfSpeech)
        #expect(abs(onset - 0.5) <= 0.020)
        #expect(try #require(take.detectTime) - 0.5 <= 0.110)
        #expect(abs(lastSpeech - 1.5) <= 0.020)
        #expect(abs(take.stopTime - (lastSpeech + 1.2)) < 1e-9)
        #expect(abs(take.stopTime - 2.7) <= 0.020)
    }

    @Test("the 20 s cap: 25 s of speech stops at 20.0 s") func cap() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 25, dBFS: -60, seed: 142), Synth.speech(seconds: 25, peakDBFS: -25), at: 0)
        let take = try await record(signal)
        #expect(take.stopReason == .recordingCap)
        #expect(abs(take.stopTime - 20.0) <= 0.010)
        #expect(take.audioStartTime == 0)
        #expect(take.samples.count == Synth.samples(take.stopTime))
    }

    @Test("cancel returns nothing and releases every sample") func cancel() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 143), Synth.speech(seconds: 2, peakDBFS: -25), at: 0.5)
        let source = FileCaptureSource(samples: signal, pacing: .manual)
        let session = try await source.start()
        source.advance(by: 1.505)
        #expect(session.bufferedSampleCount == Synth.samples(1.505))
        session.cancel()
        #expect(await session.result() == .cancelled)
        #expect(session.bufferedSampleCount == 0)
        // Nothing revives it: no more frames, no stop.
        source.advance(by: 1)
        session.stop()
        #expect(session.outcome == .cancelled)
        #expect(!session.feed([Float](repeating: 0, count: 160)))
        #expect(session.bufferedSampleCount == 0)
        // The streams ended with the take.
        #expect(await collect(session.levels).count == 150)
        #expect(await collect(session.envelope).count == 150)
    }

    @Test("E16 pre-roll: the kept audio starts 200 ms before t_onset") func preRoll() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 144), Synth.speech(seconds: 1, peakDBFS: -25), at: 0.8)
        let take = try await record(signal)
        let onset = try #require(take.onsetTime)
        #expect(abs(onset - 0.8) <= 0.020)
        #expect(abs(take.audioStartTime - (onset - 0.2)) < 1e-9)
        let start = Synth.samples(take.audioStartTime)
        #expect(take.samples.count == Synth.samples(take.stopTime) - start)
        #expect(take.samples == Array(signal[start..<start + take.samples.count]))
    }

    @Test("pre-roll near the start: max(0, t_onset − 0.2 s)") func preRollClampsAtZero() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 145), Synth.speech(seconds: 1, peakDBFS: -25), at: 0.1)
        let take = try await record(signal)
        #expect(abs(try #require(take.onsetTime) - 0.1) <= 0.020)
        #expect(take.audioStartTime == 0)
        #expect(take.samples == Array(signal.prefix(take.samples.count)))
    }

    @Test("a take both clipped and too short reports tooShort first") func clippedAndShort() async throws {
        let burst = Synth.clip(Synth.speech(seconds: 0.3, peakDBFS: -6), gainDB: 12)
        let signal = Synth.mix(Synth.whiteNoise(seconds: 2, dBFS: -60, seed: 146), burst, at: 0.5)
        let take = try await record(signal)
        let analysis = take.analysis()
        #expect(analysis.problems == [.tooShort, .clipped])
        #expect(analysis.problem == .tooShort)
        #expect(TakeProblem.first(of: [.clipped, .tooShort]) == .tooShort)
    }

    // MARK: The stop timestamp

    @Test("manual stop: the stop timestamp is the moment stop() was called") func manualStopTimestamp() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 147), Synth.speech(seconds: 2.5, peakDBFS: -25), at: 0.5)
        let source = FileCaptureSource(samples: signal, pacing: .manual)
        let session = try await source.start()
        source.advance(by: 2.0)
        #expect(session.outcome == nil)
        let before = ContinuousClock.now
        session.stop()
        let after = ContinuousClock.now
        let take = try #require(await session.result().take)
        #expect(take.stopReason == .manualStop)
        #expect(abs(take.stopTime - 2.0) < 1e-9)
        #expect(take.stoppedAt >= before && take.stoppedAt <= after)
        #expect(take.stoppedAt >= session.startedAt)
        // Speech was still going: the last speech frame is the stop.
        #expect(abs(try #require(take.lastSpeechTime) - 2.0) < 1e-9)
        #expect(take.lastSpeechAt == take.stoppedAt)
    }

    @Test("endpoint: the stop timestamp is the endpoint decision, 1.2 s of audio after the last speech")
    func endpointTimestamp() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 148), Synth.speech(seconds: 1, peakDBFS: -25), at: 0.5)
        let source = FileCaptureSource(samples: signal, pacing: .manual)
        let session = try await source.start()
        source.advance(by: 2.6)
        #expect(session.outcome == nil)
        let before = ContinuousClock.now
        source.advance(by: 0.2)
        let after = ContinuousClock.now
        let take = try #require(session.outcome?.take)
        #expect(take.stopReason == .endOfSpeech)
        #expect(take.stoppedAt >= before && take.stoppedAt <= after)
        let lastSpeechAt = try #require(take.lastSpeechAt)
        #expect(take.stoppedAt - lastSpeechAt == .seconds(take.stopTime - (take.lastSpeechTime ?? 0)))
    }

    @Test("the end of the recording counts as Stop") func endOfFileStops() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 1.5, dBFS: -60, seed: 149), Synth.speech(seconds: 1, peakDBFS: -25), at: 0.3)
        let take = try await record(signal)
        #expect(take.stopReason == .manualStop)
        #expect(abs(take.stopTime - 1.5) < 1e-9)
    }

    // MARK: Samples, digest and streams

    @Test("the digest is SHA-256 of the samples as little-endian Float32") func digest() async throws {
        #expect(
            CapturedTake.digest([]) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let samples: [Float] = [0, 1, -0.5, 0.25]
        var bytes: [UInt8] = []
        for sample in samples { withUnsafeBytes(of: sample.bitPattern.littleEndian) { bytes += $0 } }
        let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(CapturedTake.digest(samples) == expected)

        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 150), Synth.speech(seconds: 1, peakDBFS: -25), at: 0.5)
        let take = try await record(signal)
        #expect(take.sha256 == CapturedTake.digest(take.samples))
        #expect(take.sampleRate == 16_000)
    }

    @Test("chunk size doesn't matter: odd-sized pushes give the same take") func chunking() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 151), Synth.speech(seconds: 1, peakDBFS: -25), at: 0.5)
        let whole = try await record(signal)
        let session = CaptureSession(device: builtIn, lastSessionFloorDBFS: nil, thresholds: .current)
        var start = 0
        while start < signal.count, session.feed(Array(signal[start..<min(start + 37, signal.count)])) { start += 37 }
        let chunked = try #require(session.outcome?.take)
        #expect(chunked.sha256 == whole.sha256)
        #expect(chunked.stopTime == whole.stopTime)
        #expect(chunked.onsets == whole.onsets)
        #expect(session.bufferedSampleCount == 0)
    }

    @Test("levels and envelope: one per 10 ms frame, clamped to −60…0, ending with the take") func streams() async throws {
        // 0.5 s of silence, then 0.5 s clipped at full scale, then 0.3 s at −20 dBFS RMS.
        let loud = Synth.clip(Synth.speech(seconds: 0.5, peakDBFS: -3, depthDB: 0), gainDB: 20)
        let signal = [Float](repeating: 0, count: Synth.samples(0.5)) + loud
            + Synth.whiteNoise(seconds: 0.3, dBFS: -20, seed: 152)
        let session = try await FileCaptureSource(samples: signal).start()
        let take = try #require(await session.result().take)
        let levels = await collect(session.levels)
        let envelope = await collect(session.envelope)
        let frames = Int((take.stopTime / 0.01).rounded())
        #expect(levels.count == frames)
        #expect(envelope.count == frames)
        #expect(abs(levels[0].time - 0.01) < 1e-9 && abs(levels[frames - 1].time - take.stopTime) < 1e-9)
        #expect(zip(levels, envelope).allSatisfy { $0.time == $1.time })
        #expect(levels.allSatisfy { (-60...0).contains($0.rmsDBFS) && (-60...0).contains($0.peakDBFS) })
        #expect(levels.allSatisfy { $0.peakDBFS >= $0.rmsDBFS })
        // Silence reads −60, not −120; the clipped stretch is "Too loud" (peak ≥ −1 dBFS); −20 dBFS reads −20.
        #expect(levels[10].rmsDBFS == -60 && levels[10].peakDBFS == -60 && envelope[10].rms == 0)
        #expect(levels[60..<95].allSatisfy { $0.peakDBFS >= -1 })
        #expect(abs(levels[110].rmsDBFS - -20) <= 1.5)
        #expect(abs(Double(envelope[110].rms) - pow(10, -20.0 / 20)) <= 0.02)
    }

    // MARK: Permission and devices

    @Test("no device: start throws noMicrophone") func noMicrophone() async {
        let source = FileCaptureSource(samples: [], devices: [])
        #expect(source.availability() == .noMicrophone)
        await #expect(throws: CaptureError.noMicrophone) { try await source.start() }
    }

    @Test("denied or restricted: start throws micDenied", arguments: [MicAuthorization.denied, .restricted])
    func micDenied(_ authorization: MicAuthorization) async {
        let source = FileCaptureSource(samples: [], authorization: authorization)
        #expect(source.availability() == .micDenied)
        await #expect(throws: CaptureError.micDenied) { try await source.start() }
    }

    @Test("no device and denied: noMicrophone comes first (Designer's order)") func noMicrophoneFirst() async {
        let source = FileCaptureSource(samples: [], devices: [], authorization: .denied)
        #expect(source.availability() == .noMicrophone)
        await #expect(throws: CaptureError.noMicrophone) { try await source.start() }
    }

    @Test("never asked: Record is available, and start asks") func notDetermined() async throws {
        let source = FileCaptureSource(samples: [Float](repeating: 0, count: 1600), authorization: .notDetermined)
        #expect(source.availability() == nil)
        _ = try await source.start()
        #expect(source.authorization() == .authorized)
    }

    @Test("capture errors map to take problems") func takeProblems() {
        #expect(CaptureError.noMicrophone.takeProblem == .noMicrophone)
        #expect(CaptureError.micDenied.takeProblem == .micDenied)
        #expect(CaptureError.inputFailed("busy").takeProblem == nil)
    }

    @Test("the device a take uses: the requested one, else the default, else the first") func resolve() {
        #expect(InputDevice.resolve("usb", in: [builtIn, usb]) == usb)
        #expect(InputDevice.resolve("gone", in: [usb, builtIn]) == builtIn)
        #expect(InputDevice.resolve(nil, in: [usb, builtIn]) == builtIn)
        #expect(InputDevice.resolve(nil, in: [usb]) == usb)
        #expect(InputDevice.resolve("usb", in: []) == nil)
    }

    @Test("the device list notifies on every change, starting with the current one") func deviceChanges() async {
        let source = FileCaptureSource(samples: [], devices: [builtIn])
        let changes = source.deviceChanges()
        source.setDevices([builtIn, usb])
        source.setDevices([])
        var seen: [[InputDevice]] = []
        for await devices in changes {
            seen.append(devices)
            if seen.count == 3 { break }
        }
        #expect(seen == [[builtIn], [builtIn, usb], []])
    }

    @Test("device removed mid-take: nothing kept, then noMicrophone") func deviceLost() async throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 153), Synth.speech(seconds: 2, peakDBFS: -25), at: 0.5)
        let source = FileCaptureSource(samples: signal, pacing: .manual, devices: [builtIn, usb])
        let session = try await source.start(device: "usb", lastSessionFloorDBFS: nil)
        #expect(session.device == usb)
        source.advance(by: 1)
        // Another device going away doesn't touch the take.
        source.setDevices([usb])
        #expect(session.outcome == nil)
        source.setDevices([])
        #expect(await session.result() == .deviceLost)
        #expect(session.bufferedSampleCount == 0)
        #expect(source.availability() == .noMicrophone)
        await #expect(throws: CaptureError.noMicrophone) { try await source.start() }
    }

    @Test("starting a new take cancels the one running") func restartCancels() async throws {
        let signal = Synth.whiteNoise(seconds: 3, dBFS: -60, seed: 154)
        let source = FileCaptureSource(samples: signal, pacing: .manual)
        let first = try await source.start()
        source.advance(by: 0.5)
        let second = try await source.start()
        #expect(await first.result() == .cancelled)
        #expect(second.outcome == nil)
        source.advance(by: 0.5)
        second.stop()
        let take = try #require(await second.result().take)
        #expect(abs(take.stopTime - 0.5) < 1e-9)
    }

    @Test("the provisional floor is the caller's last-session floor") func lastSessionFloor() async throws {
        let source = FileCaptureSource(samples: [Float](repeating: 0, count: 1600), pacing: .manual)
        let session = try await source.start(device: nil, lastSessionFloorDBFS: -52)
        session.stop()
        #expect(try #require(await session.result().take).floorDBFS == -52)
    }

    @Test("real-time pacing plays at about 10 ms per frame") func realTime() async throws {
        let source = FileCaptureSource(samples: Synth.whiteNoise(seconds: 0.3, dBFS: -60, seed: 155), pacing: .realTime)
        let session = try await source.start()
        let take = try #require(await session.result().take)
        #expect(take.stopReason == .manualStop)
        #expect(abs(take.stopTime - 0.3) < 1e-9)
        #expect(take.stoppedAt - session.startedAt >= .milliseconds(250))
    }

    // MARK: Files

    @Test("a 48 kHz stereo file reads as 16 kHz mono, first channel") func readsFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("am-capture-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let frames = 48_000
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        let left = try #require(buffer.floatChannelData?[0])
        let right = try #require(buffer.floatChannelData?[1])
        for index in 0..<frames {
            left[index] = Float(0.5 * sin(2 * .pi * 440 * Double(index) / 48_000))
            right[index] = 0
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let source = try #require(FileCaptureSource(contentsOf: url))
        #expect(abs(source.samples.count - 16_000) <= 16)
        // A 0.5-amplitude sine has RMS 0.354; the zeroed right channel would halve a mixdown.
        let middle = source.samples[4_000..<12_000]
        let rms = (middle.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(middle.count)).squareRoot()
        #expect(abs(rms - 0.5 / 2.0.squareRoot()) <= 0.01)
    }

    @Test("an unreadable file gives no source") func unreadableFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("am-capture-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not audio".utf8).write(to: url)
        #expect(FileCaptureSource(contentsOf: url) == nil)
    }
}
