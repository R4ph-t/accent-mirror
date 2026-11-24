import AMTimestampEval
import Testing

@Suite("Spec 11 jitter test")
struct JitterTests {
    typealias Span = Jitter.Span

    @Test("SplitMix64 and FNV-1a match their published reference values")
    func referenceValues() {
        var random = Jitter.SplitMix64(state: 1_234_567)
        #expect(random.next() == 6_457_827_717_110_365_317)
        #expect(random.next() == 3_203_168_211_198_807_973)
        #expect(Jitter.fnv1a64("") == 0xCBF2_9CE4_8422_2325)
        #expect(Jitter.fnv1a64("a") == 0xAF63_DC4C_8601_EC8C)
    }

    @Test("The same seed, clip and radius give the same spans; another clip or radius gives others")
    func deterministic() {
        let words = [Span(start: 0.1, end: 0.4), Span(start: 0.5, end: 0.9), Span(start: 1.0, end: 1.6)]
        let a = Jitter.jitter(words, duration: 2, radiusMs: 40, seed: 20_261_125, clipID: "p238_002")
        #expect(a == Jitter.jitter(words, duration: 2, radiusMs: 40, seed: 20_261_125, clipID: "p238_002"))
        #expect(a != Jitter.jitter(words, duration: 2, radiusMs: 40, seed: 20_261_125, clipID: "p238_003"))
        #expect(a != Jitter.jitter(words, duration: 2, radiusMs: 80, seed: 20_261_125, clipID: "p238_002"))
    }

    @Test("Each edge moves at most R and stays inside the clip and the neighbours' oracle edges")
    func clamped() {
        // Contiguous words, the first at the clip start and the last at its end: edges can only move inwards.
        let words = [Span(start: 0, end: 0.3), Span(start: 0.3, end: 0.7), Span(start: 0.7, end: 1.0)]
        for seed in UInt64(0)..<200 {
            let moved = Jitter.jitter(words, duration: 1, radiusMs: 80, seed: seed, clipID: "x")
            for (index, word) in moved.enumerated() where !word.kept {
                #expect(word.span.start >= words[index].start - 1e-12)
                #expect(word.span.end <= words[index].end + 1e-12)
                #expect(abs(word.span.start - words[index].start) <= 0.080 + 1e-12)
                #expect(abs(word.span.end - words[index].end) <= 0.080 + 1e-12)
                #expect(word.span.end - word.span.start >= 0.020)
            }
        }
    }

    @Test("Overlapping oracle words clamp to the word's own oracle edge")
    func overlap() {
        let words = [Span(start: 0.2, end: 0.6), Span(start: 0.5, end: 0.9)]
        for seed in UInt64(0)..<200 {
            let moved = Jitter.jitter(words, duration: 2, radiusMs: 80, seed: seed, clipID: "x")
            #expect(moved[0].span.end <= 0.6 + 1e-12)
            #expect(moved[1].span.start >= 0.5 - 1e-12)
        }
    }

    @Test("A span left shorter than 20 ms keeps the oracle span and is counted")
    func keptWhenTooShort() {
        let words = [Span(start: 0.5, end: 0.52)]
        let moved = Jitter.jitter(words, duration: 1, radiusMs: 80, seed: 1, clipID: "x")
        #expect(moved.count == 1)
        if moved[0].kept { #expect(moved[0].span == words[0]) }
        let all = (UInt64(0)..<100).map { Jitter.jitter(words, duration: 1, radiusMs: 80, seed: $0, clipID: "x")[0] }
        #expect(all.contains { $0.kept })
        #expect(all.allSatisfy { $0.kept ? $0.span == words[0] : $0.span.end - $0.span.start >= 0.020 })
    }

    @Test("Radius 0 leaves every span unchanged")
    func zeroRadius() {
        let words = [Span(start: 0.1, end: 0.4), Span(start: 0.5, end: 0.9)]
        let moved = Jitter.jitter(words, duration: 1, radiusMs: 0, seed: 7, clipID: "x")
        #expect(moved.map(\.span) == words)
        #expect(moved.allSatisfy { !$0.kept })
    }
}
