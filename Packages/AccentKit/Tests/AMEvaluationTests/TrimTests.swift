import Foundation
import Testing
import AMEvaluation

@Suite("VCTK trim rule") struct TrimTests {
    static let rate = 16_000.0

    /// Quiet noise, then a tone of `speech` seconds starting at `onset`, in a clip of `total` seconds.
    static func clip(total: Double, onset: Double, speech: Double) -> [Float] {
        var generator = SeededGenerator(seed: 1)
        return (0..<Int(total * rate)).map { i in
            let t = Double(i) / rate
            let noise = Float(Double(generator.next() % 1000) / 1000 - 0.5) * 0.0004
            return t >= onset && t < onset + speech ? Float(0.2 * sin(2 * .pi * 200 * t)) + noise : noise
        }
    }

    @Test("Cuts at the first and last speech frame with 200 ms pre-roll and 300 ms tail") func keepsSpeech() throws {
        let outcome = TrimRule().apply(samples: Self.clip(total: 5, onset: 1.0, speech: 2.5), sampleRate: Self.rate)
        guard case .keep(let range) = outcome else { Issue.record("expected keep, got \(outcome)"); return }
        #expect(abs(Double(range.lowerBound) / Self.rate - 0.8) < 0.011)
        #expect(abs(Double(range.upperBound) / Self.rate - 3.8) < 0.011)
    }

    @Test("Clips outside 2–6 s are rejected and reported, never cut further") func rejectsOutOfRange() {
        guard case .outOfRange(let short) = TrimRule().apply(samples: Self.clip(total: 3, onset: 0.5, speech: 1.0), sampleRate: Self.rate)
        else { Issue.record("expected out of range"); return }
        #expect(abs(short - 1.5) < 0.02)
        guard case .outOfRange(let long) = TrimRule().apply(samples: Self.clip(total: 9, onset: 0.5, speech: 7.0), sampleRate: Self.rate)
        else { Issue.record("expected out of range"); return }
        #expect(long > 6)
        #expect(TrimRule().apply(samples: [Float](repeating: 0, count: 32_000), sampleRate: Self.rate) == .noSpeech)
    }

    @Test("48 kHz to 16 kHz keeps a 200 Hz tone and the length") func resample() throws {
        let source = (0..<48_000).map { Float(sin(2 * .pi * 200 * Double($0) / 48_000)) }
        let out = try AudioFiles.resample(source, from: 48_000, to: 16_000)
        #expect(out.count == 16_000)
        let expected = (0..<16_000).map { Float(sin(2 * .pi * 200 * Double($0) / 16_000)) }
        let error = zip(out[100..<15_900], expected[100..<15_900]).map { abs($0 - $1) }.max()!
        #expect(error < 0.01)
        #expect(throws: (any Error).self) { try AudioFiles.resample(source, from: 44_100, to: 16_000) }
    }
}
