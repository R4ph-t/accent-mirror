// Spec 14's hand check (scripts/capture-check.sh): records one take from a microphone and prints the start latency,
// t_onset, the stop reason and the take's TakeAnalysis. Saves nothing. Never run by CI or the tests.
//
//   am-capture            one take from the default input
//   am-capture --device <id>
//   am-capture --list     the input devices, default marked

import AMCapture
import AMCore
import Foundation

#if os(macOS)

    func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    func seconds(_ value: Double?) -> String { value.map { String(format: "%.3f s", $0) } ?? "none" }

    let arguments = Array(CommandLine.arguments.dropFirst())
    let recorder = MicRecorder()

    if arguments.first == "--list" {
        let devices = recorder.inputDevices()
        if devices.isEmpty { print("no input devices (noMicrophone)") }
        for device in devices { print("\(device.isDefault ? "*" : " ") \(device.id)  \(device.name)") }
        exit(0)
    }

    var device: String?
    if arguments.first == "--device" {
        guard arguments.count == 2 else {
            print("usage: am-capture [--list | --device <id>]")
            exit(64)
        }
        device = arguments[1]
    }

    print("authorization: \(recorder.authorization())")
    let clock = ContinuousClock()
    let called = clock.now
    let session: CaptureSession
    do {
        session = try await recorder.start(device: device, lastSessionFloorDBFS: nil)
    } catch {
        // micDenied, noMicrophone or inputFailed(…)
        print("\(error)")
        exit(1)
    }
    let latency = milliseconds(clock.now - called)
    print(String(format: "start latency: %.1f ms (budget 100 ms)", latency))
    print("device: \(session.device.name)")
    print("Speak, then stay quiet: the take ends after 1.2 s of silence, or at 20 s.")

    let outcome = await session.result()
    guard let take = outcome.take else {
        print("outcome: \(outcome)")
        exit(1)
    }
    let analysis = take.analysis()
    print("t_onset: \(seconds(take.onsetTime))  t_detect: \(seconds(take.detectTime))")
    print("stop reason: \(take.stopReason.rawValue) at \(seconds(take.stopTime))")
    print("last speech: \(seconds(take.lastSpeechTime))  kept from: \(seconds(take.audioStartTime))")
    print("kept: \(take.samples.count) samples (\(seconds(Double(take.samples.count) / take.sampleRate)))")
    print("sha256: \(take.sha256)")
    print(String(format: "floor: %.1f dBFS", take.floorDBFS))
    print(
        "TakeAnalysis: speech \(seconds(analysis.speechSeconds)), voiced \(seconds(analysis.voicedSeconds)), "
            + "median \(analysis.speechMedianDBFS.map { String(format: "%.1f dBFS", $0) } ?? "none"), "
            + String(format: "clipped %.3f", analysis.clippedShare))
    print("problem: \(analysis.problem?.rawValue ?? "none")  (all: \(analysis.problems.map(\.rawValue)))")
    if latency > 100 { exit(2) }

#else

    print("am-capture: macOS only")

#endif
