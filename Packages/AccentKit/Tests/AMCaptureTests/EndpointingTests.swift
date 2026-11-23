// Spec 05 cases E1–E17 on synthetic buffers. Each case prints t_onset, t_detect and its outcome.

import AMCore
import Foundation
import Testing
@testable import AMCapture

/// What one endpointer run saw, frame by frame.
struct EndpointerRun {
    var events: [(time: Double, event: Endpointer.Event)] = []
    var floors: [(time: Double, dBFS: Double, settled: Bool)] = []
    var take: Take?
    var endpointer: Endpointer

    typealias Take = Endpointer.Take

    var onsets: [Onset] { events.compactMap { if case .onset(let onset) = $0.event { onset } else { nil } } }
    var retractions: [Onset] { events.compactMap { if case .retracted(let onset) = $0.event { onset } else { nil } } }
    var settlings: [(time: Double, dBFS: Double)] {
        events.compactMap { if case .floorSettled(let dBFS) = $0.event { ($0.time, dBFS) } else { nil } }
    }

    /// Feeds `signal` frame by frame (a short tail is dropped). Stops by hand or cancels when `elapsed` reaches the
    /// given time; otherwise runs until the endpointer ends the take or the signal runs out.
    init(_ signal: [Float], stopAt: Double? = nil, cancelAt: Double? = nil, lastSessionFloorDBFS: Double? = nil) {
        endpointer = Endpointer(sampleRate: Synth.sampleRate, lastSessionFloorDBFS: lastSessionFloorDBFS)
        let length = endpointer.frameLength
        var start = 0
        while start + length <= signal.count, endpointer.state == .listening {
            if let stopAt, endpointer.elapsed >= stopAt - 1e-9 {
                take = endpointer.stop()
                return
            }
            if let cancelAt, endpointer.elapsed >= cancelAt - 1e-9 {
                endpointer.cancel()
                return
            }
            for event in endpointer.process(frame: Array(signal[start..<start + length])) {
                events.append((endpointer.elapsed, event))
                if case .ended(let ended) = event { take = ended }
            }
            floors.append((endpointer.elapsed, endpointer.noiseFloorDBFS, endpointer.isNoiseFloorSettled))
            start += length
        }
    }
}

/// Frame RMS (dBFS) of `signal` in 10 ms frames, for checking what a synthetic input is.
func frameLevels(_ signal: [Float]) -> [Double] {
    stride(from: 0, to: signal.count - 159, by: 160).map { start in
        let frame = signal[start..<start + 160]
        let power = frame.reduce(0.0) { $0 + Double($1) * Double($1) } / 160
        return 10 * log10(max(power, 1e-12))
    }
}

func spread(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    func at(_ p: Double) -> Double { sorted[Int((p * Double(sorted.count - 1)).rounded())] }
    return at(0.9) - at(0.1)
}

func report(_ name: String, _ onsets: [Onset], _ outcome: String) {
    let times = onsets.isEmpty
        ? "t_onset=none t_detect=none"
        : onsets.map { String(format: "t_onset=%.3f t_detect=%.3f", $0.time, $0.detectedAt) }.joined(separator: "; ")
    print("\(name): \(times) outcome=\(outcome)")
}

func describe(_ take: Endpointer.Take?) -> String {
    take.map { String(format: "%@ at %.3f s", $0.reason.rawValue, $0.endTime) } ?? "listening"
}

func describe(_ problem: TakeProblem?) -> String { problem?.rawValue ?? "ok" }

@Suite("Endpointing and take quality (spec 05)") struct EndpointingTests {
    // MARK: Onset and the noise floor

    @Test("E1 Immediate speech: onset at t = 0, floor not polluted") func e1ImmediateSpeech() throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 1), Synth.speech(seconds: 2, peakDBFS: -25), at: 0)
        let run = EndpointerRun(signal)
        let onset = try #require(run.onsets.first)
        report("E1", run.onsets, describe(run.take))
        #expect(abs(onset.time - 0) <= 0.020)
        #expect(onset.detectedAt - 0 <= 0.110)
        #expect(onset.detectedAt - onset.time <= 0.100 + 1e-9)
        for floor in run.floors { #expect(floor.dBFS <= -55, "floor \(floor.dBFS) at \(floor.time) s") }
        #expect(run.retractions.isEmpty)
        #expect(run.take?.reason == .endOfSpeech)
    }

    @Test("E2 Quiet speech: detected, then tooQuiet") func e2QuietSpeech() throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 3, dBFS: -65, seed: 2), Synth.speech(seconds: 1.5, peakDBFS: -45), at: 0.5)
        let analysis = TakeAnalysis(samples: signal)
        let onset = try #require(analysis.onsets.first)
        report("E2", analysis.onsets, describe(analysis.problem))
        #expect(abs(onset.time - 0.5) <= 0.020)
        #expect(onset.detectedAt - 0.5 <= 0.110)
        #expect(analysis.problem == .tooQuiet)
        #expect(TakeQuality.check(samples: signal) == .tooQuiet)
    }

    @Test("E3 Very quiet voiced: tooQuiet through the voiced rule, not noSpeech") func e3VeryQuietVoiced() {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 3, dBFS: -65, seed: 3), Synth.speech(seconds: 1.5, peakDBFS: -58), at: 0.5)
        let analysis = TakeAnalysis(samples: signal)
        report("E3", analysis.onsets, describe(analysis.problem))
        #expect(analysis.onsets.isEmpty)
        #expect(analysis.speechSeconds < Thresholds.current.capture.noSpeechS)
        #expect(analysis.voicedSeconds >= Thresholds.current.capture.noSpeechVoicedS)
        #expect(TakeQuality.check(samples: signal) == .tooQuiet)
    }

    @Test("E4 Noise only: pink noise at −50 dBFS is noSpeech") func e4NoiseOnly() {
        let signal = Synth.pinkNoise(seconds: 3, dBFS: -50, seed: 4)
        let analysis = TakeAnalysis(samples: signal)
        let run = EndpointerRun(signal)
        report("E4", analysis.onsets, describe(analysis.problem))
        #expect(analysis.onsets.isEmpty)
        #expect(run.take == nil)
        #expect(TakeQuality.check(samples: signal) == .noSpeech)
    }

    @Test("E5 Changing noise: no false onset, speech detected, endpoint 1.2 s after it") func e5ChangingNoise() throws {
        let noise = Synth.whiteNoise(seconds: 3, dBFS: -65, seed: 5) + Synth.whiteNoise(seconds: 7, dBFS: -45, seed: 55)
        let signal = Synth.mix(noise, Synth.speech(seconds: 1.5, peakDBFS: -30), at: 6.0)
        let run = EndpointerRun(signal)
        let take = try #require(run.take)
        let onset = try #require(run.onsets.first)
        report("E5", run.onsets, describe(take))
        #expect(run.onsets.allSatisfy { $0.time >= 6.0 - 0.020 }, "an onset fired on the noise alone")
        #expect(abs(onset.time - 6.0) <= 0.020)
        #expect(onset.detectedAt - 6.0 <= 0.110)
        #expect(take.reason == .endOfSpeech)
        #expect(abs(take.endTime - (7.5 + 1.2)) <= 0.020)
    }

    @Test("E6 Click: a 100 ms broadband burst creates no onset") func e6Click() {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 2.5, dBFS: -60, seed: 6), Synth.whiteNoise(seconds: 0.1, dBFS: -20, seed: 66),
            at: 1.0)
        let run = EndpointerRun(signal)
        report("E6", run.onsets, describe(run.take))
        #expect(run.onsets.isEmpty)
        #expect(run.take == nil)
    }

    // MARK: Ending a take

    @Test("E7 Manual stop mid-speech: ends at 2.0 s with no wait") func e7ManualStopMidSpeech() throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 7), Synth.speech(seconds: 2.5, peakDBFS: -25), at: 0.5)
        let run = EndpointerRun(signal, stopAt: 2.0)
        let take = try #require(run.take)
        let onset = try #require(take.onsets.first)
        report("E7", take.onsets, describe(take))
        #expect(abs(onset.time - 0.5) <= 0.020)
        #expect(onset.detectedAt - 0.5 <= 0.110)
        #expect(take.reason == .manualStop)
        #expect(abs(take.endTime - 2.0) < 1e-9)
    }

    @Test("E8 Manual stop in trailing silence: ends at once") func e8ManualStopInTrailingSilence() throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 8), Synth.speech(seconds: 1, peakDBFS: -25), at: 0.5)
        let run = EndpointerRun(signal, stopAt: 2.0)
        let take = try #require(run.take)
        let onset = try #require(take.onsets.first)
        report("E8", take.onsets, describe(take))
        #expect(abs(onset.time - 0.5) <= 0.020)
        #expect(onset.detectedAt - 0.5 <= 0.110)
        #expect(take.reason == .manualStop)
        #expect(abs(take.endTime - 2.0) < 1e-9)
    }

    @Test("E9 Inner pause: 1.0 s continues, 1.3 s endpoints at the 1.2 s mark") func e9InnerPause() throws {
        var signal = Synth.whiteNoise(seconds: 7, dBFS: -60, seed: 9)
        for start in [0.5, 2.5, 4.8] { signal = Synth.mix(signal, Synth.speech(seconds: 1, peakDBFS: -25), at: start) }
        let run = EndpointerRun(signal)
        let take = try #require(run.take)
        report("E9", take.onsets, describe(take))
        #expect(take.onsets.count == 2)
        #expect(abs(take.onsets[0].time - 0.5) <= 0.020 && take.onsets[0].detectedAt - 0.5 <= 0.110)
        #expect(abs(take.onsets[1].time - 2.5) <= 0.020 && take.onsets[1].detectedAt - 2.5 <= 0.110)
        #expect(take.reason == .endOfSpeech)
        #expect(abs(take.endTime - (3.5 + 1.2)) <= 0.020)
    }

    @Test("E10 Cap: 25 s of continuous speech stops at 20.0 s") func e10Cap() throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 25, dBFS: -60, seed: 10), Synth.speech(seconds: 25, peakDBFS: -25), at: 0)
        let run = EndpointerRun(signal)
        let take = try #require(run.take)
        let onset = try #require(take.onsets.first)
        report("E10", take.onsets, describe(take))
        #expect(abs(onset.time) <= 0.020 && onset.detectedAt <= 0.110)
        #expect(take.reason == .recordingCap)
        #expect(abs(take.endTime - 20.0) <= 0.010)
    }

    @Test("E11 Cancel: no outcome, nothing kept") func e11Cancel() throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 3, dBFS: -60, seed: 11), Synth.speech(seconds: 2, peakDBFS: -25), at: 0.5)
        var run = EndpointerRun(signal, cancelAt: 1.5)
        let onset = try #require(run.onsets.first)
        report("E11", run.onsets, "\(run.endpointer.state)")
        #expect(abs(onset.time - 0.5) <= 0.020 && onset.detectedAt - 0.5 <= 0.110)
        #expect(run.endpointer.state == .cancelled)
        #expect(run.take == nil)
        #expect(run.endpointer.stop() == nil)
        #expect(run.endpointer.process(frame: [Float](repeating: 0, count: run.endpointer.frameLength)).isEmpty)
    }

    // MARK: Take quality

    @Test("E12 Several problems: clipped and 0.3 s of speech is tooShort") func e12SeveralProblems() throws {
        let burst = Synth.clip(Synth.speech(seconds: 0.3, peakDBFS: -6), gainDB: 12)
        let signal = Synth.mix(Synth.whiteNoise(seconds: 2, dBFS: -60, seed: 12), burst, at: 0.5)
        let analysis = TakeAnalysis(samples: signal)
        let onset = try #require(analysis.onsets.first)
        report("E12", analysis.onsets, describe(analysis.problem))
        #expect(abs(onset.time - 0.5) <= 0.020 && onset.detectedAt - 0.5 <= 0.110)
        #expect(analysis.problems == [.tooShort, .clipped])
        #expect(TakeQuality.check(samples: signal) == .tooShort)
    }

    @Test("Clipped speech of normal length is clipped") func clippedSpeech() throws {
        let burst = Synth.clip(Synth.speech(seconds: 1.5, peakDBFS: -6), gainDB: 12)
        let signal = Synth.mix(Synth.whiteNoise(seconds: 3, dBFS: -60, seed: 120), burst, at: 0.5)
        let analysis = TakeAnalysis(samples: signal)
        report("Clipped", analysis.onsets, describe(analysis.problem))
        #expect(TakeQuality.check(samples: signal) == .clipped)
    }

    @Test("Clean speech of normal length has no problem") func cleanSpeech() {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 3, dBFS: -60, seed: 121), Synth.speech(seconds: 1.5, peakDBFS: -20), at: 0.5)
        let analysis = TakeAnalysis(samples: signal)
        report("Clean", analysis.onsets, describe(analysis.problem))
        #expect(TakeQuality.check(samples: signal) == nil)
    }

    // MARK: Provisional floor, retraction and pre-roll

    @Test("E13 Unvoiced burst: no onset, no false endpoint") func e13UnvoicedBurst() {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 3, dBFS: -65, seed: 13), Synth.whiteNoise(seconds: 0.15, dBFS: -40, seed: 133),
            at: 0.025)
        let run = EndpointerRun(signal)
        let voiced = ACFVoicing().voicedFrames(samples: signal, sampleRate: Synth.sampleRate)
        report("E13", run.onsets, describe(run.take))
        #expect(!voiced.prefix(20).contains(true), "the burst must not read as voiced")
        #expect(run.onsets.isEmpty)
        #expect(run.take == nil)
        #expect(run.endpointer.isNoiseFloorSettled)
        #expect(run.endpointer.noiseFloorDBFS <= -60)
    }

    @Test("E14 Voiced hum retracted: provisional onset, settles at 2.0 s, retracted, noSpeech")
    func e14VoicedHum() throws {
        let hum = Synth.hum(seconds: 3, dBFS: -48)
        #expect(spread(frameLevels(hum)) < 2)
        let run = EndpointerRun(hum)
        let onset = try #require(run.onsets.first)
        let settled = try #require(run.settlings.first)
        report("E14", run.onsets, describe(TakeQuality.check(samples: hum)))
        #expect(onset.provisional)
        #expect(abs(onset.time) <= 0.020 && onset.detectedAt <= 0.110)
        #expect(abs(settled.time - 2.0) < 1e-9)
        #expect(abs(settled.dBFS - -48.5) <= 1.0)
        #expect(run.retractions == [onset])
        #expect(TakeQuality.check(samples: hum) == .noSpeech)
    }

    @Test("E14 variant: speech over the hum from 2.5 s gives a kept onset at 2.5 s") func e14HumThenSpeech() throws {
        let signal = Synth.mix(Synth.hum(seconds: 6, dBFS: -48), Synth.speech(seconds: 1.5, peakDBFS: -30), at: 2.5)
        let run = EndpointerRun(signal)
        let take = try #require(run.take)
        let onset = try #require(take.onsets.first)
        report("E14 variant", take.onsets, describe(take))
        #expect(take.onsets.count >= 1)
        #expect(!onset.provisional)
        #expect(abs(onset.time - 2.5) <= 0.020)
        #expect(onset.detectedAt - 2.5 <= 0.110)
        #expect(take.reason == .endOfSpeech)
    }

    @Test("E15 Early speech: provisional, not stationary, not retracted, kept") func e15EarlySpeech() throws {
        let speech = Synth.speech(seconds: 1.5, peakDBFS: -25, depthDB: 14)
        #expect(spread(frameLevels(speech)) > 10)
        let signal = Synth.mix(Synth.whiteNoise(seconds: 3, dBFS: -60, seed: 15), speech, at: 0.15)
        let run = EndpointerRun(signal)
        let take = try #require(run.take)
        let onset = try #require(take.onsets.first)
        report("E15", take.onsets, describe(take))
        #expect(onset.provisional)
        #expect(abs(onset.time - 0.15) <= 0.020)
        #expect(onset.detectedAt - 0.15 <= 0.110)
        #expect(run.retractions.isEmpty)
        #expect(run.endpointer.isNoiseFloorSettled)
    }

    @Test("E16 Pre-roll: kept audio has 200 ms before t_onset") func e16PreRoll() throws {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 3, dBFS: -60, seed: 16), Synth.speech(seconds: 1, peakDBFS: -25), at: 0.8)
        let run = EndpointerRun(signal)
        let take = try #require(run.take)
        let onset = try #require(take.onsets.first)
        report("E16", take.onsets, describe(take))
        #expect(abs(onset.time - 0.8) <= 0.020 && onset.detectedAt - 0.8 <= 0.110)
        #expect(abs(take.audioStartTime - (onset.time - 0.2)) < 1e-9)
        let start = Synth.samples(take.audioStartTime)
        #expect(take.audio.count == Synth.samples(take.endTime) - start)
        #expect(Array(take.audio.prefix(Synth.samples(0.2))) == Array(signal[start..<start + Synth.samples(0.2)]))
    }

    @Test("E17 Quiet vowel: ACFVoicing marks it voiced; the take is tooQuiet") func e17QuietVowel() {
        let vowel = Synth.speech(seconds: 0.8, peakDBFS: -55, depthDB: 0)
        let signal = Synth.mix(Synth.whiteNoise(seconds: 2, dBFS: -65, seed: 17), vowel, at: 0.5)
        let voiced = ACFVoicing().voicedFrames(samples: signal, sampleRate: Synth.sampleRate)
        let analysis = TakeAnalysis(samples: signal)
        report("E17", analysis.onsets, describe(analysis.problem))
        // Frames wholly inside the vowel, once the 40 ms window has filled with it.
        let inside = voiced[54..<130]
        #expect(Double(inside.filter { $0 }.count) / Double(inside.count) >= 0.9)
        #expect(!voiced[5..<45].contains(true), "the noise before the vowel must not read as voiced")
        #expect(TakeQuality.check(samples: signal) == .tooQuiet)
    }

    // MARK: Contract details

    @Test("ACFVoicing is the acf-1 VoicingSource, one decision per 10 ms frame") func acfVoicingContract() {
        let voicing: any VoicingSource = ACFVoicing()
        #expect(voicing.id == "acf-1")
        let signal = Synth.whiteNoise(seconds: 1.005, dBFS: -60, seed: 18)
        #expect(voicing.voicedFrames(samples: signal, sampleRate: Synth.sampleRate).count == 101)
        #expect(voicing.voicedFrames(samples: [], sampleRate: Synth.sampleRate).isEmpty)
    }

    @Test("the provisional floor is the last-session floor when the caller passes one") func lastSessionFloor() {
        let endpointer = Endpointer(lastSessionFloorDBFS: -52)
        #expect(endpointer.noiseFloorDBFS == -52)
        #expect(!endpointer.isNoiseFloorSettled)
        #expect(Endpointer().noiseFloorDBFS == Thresholds.current.capture.provisionalFloorDBFS)
    }

    @Test("speech under 0.3 s never arms the endpoint") func shortSpeechDoesNotArm() {
        let signal = Synth.mix(
            Synth.whiteNoise(seconds: 4, dBFS: -60, seed: 19), Synth.speech(seconds: 0.2, peakDBFS: -25), at: 0.5)
        let run = EndpointerRun(signal)
        report("Short", run.onsets, describe(run.take))
        #expect(!run.onsets.isEmpty)
        #expect(run.take == nil)
    }
}
