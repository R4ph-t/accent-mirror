import Foundation
import Testing
import AMCore
import AMPitch
@testable import AMWarp

/// Pure tones back to back, at 16 kHz.
func tones(_ parts: [(hz: Double, seconds: Double)]) -> [Float] {
    var out: [Float] = []
    for part in parts {
        let n = Int(part.seconds * 16_000)
        out += (0..<n).map { Float(0.3 * sin(2 * Double.pi * part.hz * Double($0) / 16_000)) }
    }
    return out
}

/// One present word over the whole take, with anchors at its edges only.
func wholeTakeWarp(model: Double, you: Double, timing: TimingLevel) throws -> TimeWarp {
    let alignment = try WordAlignment(pairs: [.present(phrase: WordIndex(0), you: r(0, you))])
    return try TimeWarp(
        alignment: alignment, model: [TimedWord(range: r(0, model), timing: timing)],
        you: [WordIndex(0): TimedWord(range: r(0, you), timing: timing)], timing: .good)
}

@Suite("DTW") struct DTWTests {
    static let modelAudio = tones([(300, 0.25), (600, 0.25), (450, 0.25), (900, 0.25)])
    static let yourAudio = tones([(300, 0.15), (600, 0.45), (450, 0.20), (900, 0.20)])

    @Test("DTW maps time inside a Poor segment: tone boundaries line up") func recoversWarp() throws {
        let warp = try wholeTakeWarp(model: 1.0, you: 1.0, timing: .poor)
        let refined = try warp.refined(
            model: FrameFeatures(samples: Self.modelAudio, sampleRate: 16_000),
            you: FrameFeatures(samples: Self.yourAudio, sampleRate: 16_000))
        #expect(refined.refinements[0] != nil)
        for (model, you) in [(0.25, 0.15), (0.50, 0.60), (0.75, 0.80)] {
            let mapped = try #require(refined.toYou(model))
            #expect(abs(mapped - you) < 0.03, "toYou(\(model)) = \(mapped), expected \(you)")
        }
    }

    @Test("DTW changes no syllable output and sets timing to Rough") func leavesSyllablesAlone() throws {
        let alignment = Scene.alignment
        var model = Scene.model
        model[2] = word(1.00, 1.30, syllables: 3, timing: .poor)
        let you = Scene.you
        let syllablesBefore = model.map(\.syllables)
        let warp = try TimeWarp(alignment: alignment, model: model, you: you, timing: .good)
        #expect(warp.anchorTiming[3] == .poor && warp.anchorTiming[0] == .good)

        let refined = try warp.refined(
            model: FrameFeatures(samples: tones([(300, 1.2), (500, 1.0)]), sampleRate: 16_000),
            you: FrameFeatures(samples: tones([(300, 1.6), (500, 1.2)]), sampleRate: 16_000))
        #expect(refined.refinements.keys.sorted() == [3])
        #expect(refined.map == warp.map)
        #expect(refined.comparableCoverage == warp.comparableCoverage)
        #expect(refined.anchorTiming == warp.anchorTiming)
        #expect(refined.modelWords == warp.modelWords)
        #expect(you == Scene.you && model.map(\.syllables) == syllablesBefore)
        #expect(refined.timing == .rough)
        // Gaps still hold after refinement.
        #expect(refined.toYou(0.75) == nil && refined.toModel(1.15) == nil)
    }

    @Test("Good anchors: no DTW, timing kept") func goodAnchorsUntouched() throws {
        let warp = try wholeTakeWarp(model: 1.0, you: 1.0, timing: .good)
        let refined = try warp.refined(
            model: FrameFeatures(samples: Self.modelAudio, sampleRate: 16_000),
            you: FrameFeatures(samples: Self.yourAudio, sampleRate: 16_000))
        #expect(refined == warp)
        #expect(refined.timing == .good)
    }

    @Test("A cancelled task stops DTW with CancellationError") func cancellation() async throws {
        let a = FrameFeatures(samples: tones([(300, 3.0)]), sampleRate: 16_000).frames
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DTW.path(a, a)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Features: 13 MFCCs plus log-energy every 10 ms over 25 ms windows") func featureShape() {
        let features = FrameFeatures(samples: tones([(440, 1.0)]), sampleRate: 16_000)
        #expect(features.frames.count == 1 + (16_000 - 400) / 160)
        #expect(features.frames.allSatisfy { $0.count == 14 })
    }

    @Test("Benchmark: features and DTW for a 3 s take within 150 ms") func benchmark() throws {
        let model = tones([(220, 0.5), (330, 0.7), (440, 0.6), (550, 0.6), (660, 0.6)])
        let you = tones([(220, 0.7), (330, 0.5), (440, 0.7), (550, 0.5), (660, 0.6)])
        let warp = try wholeTakeWarp(model: 3.0, you: 3.0, timing: .poor)
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            _ = try warp.refined(
                model: FrameFeatures(samples: model, sampleRate: 16_000),
                you: FrameFeatures(samples: you, sampleRate: 16_000))
        }
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("AMWarp DTW benchmark: 3 s take, MFCC + DTW in \(String(format: "%.1f", ms)) ms (budget 150 ms)")
        #expect(ms <= 150)
    }
}

@Suite("Native band") struct NativeBandTests {
    /// A flat line at `st` from `start` for `frames` frames.
    static func flat(_ st: Double, start: Double = 0, frames: Int = 100) -> [PitchSegment] {
        [PitchSegment(start: start, frames: Array(repeating: PitchFrame(semitones: st, voiced: true), count: frames))]
    }

    static func identity(_ seconds: Double = 1.0) throws -> TimeWarp {
        try wholeTakeWarp(model: seconds, you: seconds, timing: .good)
    }

    @Test("One take: ±1.5 st around the model") func singleTake() throws {
        let model = [PitchSegment(start: 0.2, frames: (0..<50).map { PitchFrame(semitones: Double($0) / 10, voiced: true) })]
        let band = try NativeBand(selected: NativeVoice(sha256: "a", pitch: model), others: [], testTake: "t")
        #expect(band.points.count == 50)
        for (k, p) in band.points.enumerated() {
            #expect(abs(p.time - (0.2 + Double(k) * 0.01)) < 1e-9)
            #expect(abs(p.lower - (Double(k) / 10 - 1.5)) < 1e-9 && abs(p.upper - (Double(k) / 10 + 1.5)) < 1e-9)
        }
    }

    @Test("Several takes: P10–P90 per frame") func percentiles() throws {
        let warp = try Self.identity()
        let others = (1...10).map {
            WarpedVoice(voice: NativeVoice(sha256: "h\($0)", pitch: Self.flat(Double($0))), ontoSelected: warp)
        }
        let band = try NativeBand(selected: NativeVoice(sha256: "h0", pitch: Self.flat(0)), others: others, testTake: nil)
        // Values 0…10: P10 = 1, P90 = 9.
        #expect(band.points.count == 100)
        #expect(band.points.allSatisfy { abs($0.lower - 1) < 1e-9 && abs($0.upper - 9) < 1e-9 })
        #expect(band.takeHashes == (0...10).map { "h\($0)" }.sorted())
        #expect(band.nativeSetHash == SHA256Digest.hex(of: Data(band.takeHashes.joined(separator: "\n").utf8)))
    }

    @Test("A voice switch re-times the band onto the new voice") func voiceSwitch() throws {
        // Voice A says the word in 1 s, voice B in 2 s; each pitch line is flat over its own word.
        let a = NativeVoice(sha256: "A", pitch: Self.flat(0, frames: 100))
        let b = NativeVoice(sha256: "B", pitch: Self.flat(2, frames: 200))
        let bOntoA = try wholeTakeWarp(model: 1.0, you: 2.0, timing: .good)
        let aOntoB = try wholeTakeWarp(model: 2.0, you: 1.0, timing: .good)
        let onA = try NativeBand(selected: a, others: [WarpedVoice(voice: b, ontoSelected: bOntoA)], testTake: nil)
        let onB = try NativeBand(selected: b, others: [WarpedVoice(voice: a, ontoSelected: aOntoB)], testTake: nil)
        #expect(onA.points.last!.time < 1.0 && onA.points.last!.time >= 0.98)
        #expect(onB.points.last!.time < 2.0 && onB.points.last!.time >= 1.98)
        #expect(onB.points.count == 2 * onA.points.count)
        // Same native set, same hash, whichever voice is selected.
        #expect(onA.nativeSetHash == onB.nativeSetHash)
        // Two takes at 0 and 2 st: P10 = 0.2, P90 = 1.8 on both timelines.
        for p in onA.points + onB.points { #expect(abs(p.lower - 0.2) < 1e-9 && abs(p.upper - 1.8) < 1e-9) }
    }

    @Test("The builder rejects a test take that is in the native set") func rejectsTestSpeaker() throws {
        let warp = try Self.identity()
        let others = [WarpedVoice(voice: NativeVoice(sha256: "test", pitch: Self.flat(1)), ontoSelected: warp)]
        #expect(throws: NativeBand.BuildError.testTakeInNativeSet("test")) {
            try NativeBand(selected: NativeVoice(sha256: "model", pitch: Self.flat(0)), others: others, testTake: "test")
        }
        #expect(throws: NativeBand.BuildError.testTakeInNativeSet("model")) {
            try NativeBand(selected: NativeVoice(sha256: "model", pitch: Self.flat(0)), others: [], testTake: "model")
        }
    }

    @Test("Band coverage: share of your comparable voiced frames inside the band") func coverage() throws {
        let warp = try Scene.warp()
        let band = try NativeBand(
            selected: NativeVoice(sha256: "m", pitch: Self.flat(0, frames: 250)), others: [], testTake: "you")
        // Your line on model time: 0 st (inside) up to 1.2 s, then 5 st (outside), with a bridged frame at 0.2 s.
        var frames = (0..<200).map { k in PitchFrame(semitones: k < 120 ? 0 : 5, voiced: k != 20) }
        frames[20] = PitchFrame(semitones: 9, voiced: false)
        let line = [PitchSegment(start: 0, frames: frames)]
        // Comparable frames: a (0.10–0.50, 40 frames, one bridged), c (1.00–1.30, 30), e (1.80–2.00, 20).
        // Inside: a's 39 voiced plus c's 1.00–1.20 (20). Outside: c's 1.20–1.30 (10) and e's 20.
        let share = try #require(band.coverage(of: line, warp: warp))
        #expect(abs(share - 59.0 / 89.0) < 1e-9)
        #expect(band.coverage(of: [], warp: warp) == nil)
    }
}
