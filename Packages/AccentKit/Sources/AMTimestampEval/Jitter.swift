import Foundation

/// Spec 11 §4b's aligner-independent jitter test: the oracle's own word spans with both edges of each word moved by
/// an independent offset drawn uniformly from [−R, +R]. Measures only; it reads no threshold and decides nothing.
///
/// Fully specified, so a run depends only on the seed, the clip ID, R and the spans, never on clip order or threads:
/// - generator: SplitMix64 (Steele, Lea and Flood 2014), its state started at `seed XOR FNV-1a 64(UTF-8 of
///   "<clipID>#<R in ms>")`;
/// - draws: per word in phrase order, the start's offset then the end's; a draw is `(next() >> 11) · 2⁻⁵³`, in [0, 1),
///   mapped to `(2u − 1) · R`;
/// - clamping: each edge to the clip [0, duration] and to the neighbouring words' oracle edges (start ≥ the previous
///   word's oracle end, end ≤ the next word's oracle start; where the oracle words already overlap, to the oracle edge
///   itself);
/// - a jittered span shorter than `minimumMs` keeps the oracle span and is counted as kept.
public enum Jitter {
    public struct SplitMix64: Sendable {
        public private(set) var state: UInt64

        public init(state: UInt64) { self.state = state }

        public mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// Uniform in [0, 1), 53 bits.
        public mutating func unit() -> Double { Double(next() >> 11) * 0x1.0p-53 }
    }

    /// FNV-1a, 64 bits, over the string's UTF-8 bytes.
    public static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    public static func generator(seed: UInt64, clipID: String, radiusMs: Int) -> SplitMix64 {
        SplitMix64(state: seed ^ fnv1a64("\(clipID)#\(radiusMs)"))
    }

    public struct Span: Sendable, Equatable {
        public var start: Double
        public var end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }
    }

    /// One word's jittered span, or its oracle span when the jittered one was too short (`kept`).
    public struct Moved: Sendable, Equatable {
        public var span: Span
        public var kept: Bool
    }

    /// - Parameters:
    ///   - oracle: the comparable words' oracle spans (s), in phrase order.
    ///   - duration: the clip's length (s).
    public static func jitter(_ oracle: [Span], duration: Double, radiusMs: Int, seed: UInt64, clipID: String,
                              minimumMs: Double = 20) -> [Moved] {
        var random = generator(seed: seed, clipID: clipID, radiusMs: radiusMs)
        let radius = Double(radiusMs) / 1000
        return oracle.indices.map { index in
            let word = oracle[index]
            let startOffset = (2 * random.unit() - 1) * radius
            let endOffset = (2 * random.unit() - 1) * radius
            let lower = index > 0 ? min(word.start, max(0, oracle[index - 1].end)) : min(word.start, 0)
            let upper = index + 1 < oracle.count ? max(word.end, min(duration, oracle[index + 1].start))
                                                 : max(word.end, duration)
            let start = min(max(word.start + startOffset, max(lower, 0)), duration)
            let end = max(min(word.end + endOffset, min(upper, duration)), 0)
            guard (end - start) * 1000 >= minimumMs else { return Moved(span: word, kept: true) }
            return Moved(span: Span(start: start, end: end), kept: false)
        }
    }
}
