import AMCore
import Foundation

/// Spec 23's gate for one aligner: spec 03's unpadded bar on starts and on ends, pooled and for every speaker.
public struct BoundaryBar: Codable, Sendable, Equatable {
    public var starts: Outcome
    public var ends: Outcome
    /// Speakers whose starts or ends miss the bar.
    public var failingSpeakers: [String]
    public var perSpeaker: Outcome
    public var outcome: Outcome

    public init(_ accuracy: AccuracyResult) {
        starts = accuracy.starts.outcome
        ends = accuracy.ends.outcome
        failingSpeakers = accuracy.perSpeaker
            .filter { Outcome.combine([$0.starts.outcome, $0.ends.outcome]) != .pass }.map(\.key)
        perSpeaker = accuracy.perSpeaker.isEmpty ? .notEvaluated : (failingSpeakers.isEmpty ? .pass : .fail)
        outcome = Outcome.combine([starts, ends, perSpeaker])
    }
}

/// b1's extra gate (spec 23): snapping ends with intensity must not couple syllable duration to intensity. On spec
/// 02's unmodified-control and sham-control pairs, Δr = r_snap − r_whisper, where r is the Pearson correlation of
/// syllable duration with mean intensity. PASS only when the bootstrap 95% CI of Δr has its lower bound ≤ 0.
public struct CorrelationGate: Codable, Sendable, Equatable {
    /// One syllable measured twice, with the same proportional split of each aligner's word span.
    public struct Syllable: Sendable, Equatable {
        public var clipID: String
        public var whisper: (durationS: Double, meanIntensityDB: Double)
        public var snapped: (durationS: Double, meanIntensityDB: Double)

        public init(clipID: String, whisper: (Double, Double), snapped: (Double, Double)) {
            self.clipID = clipID
            self.whisper = whisper
            self.snapped = snapped
        }

        public static func == (a: Syllable, b: Syllable) -> Bool {
            a.clipID == b.clipID && a.whisper == b.whisper && a.snapped == b.snapped
        }
    }

    public var outcome: Outcome
    /// Why the gate is NOT EVALUATED, when it is.
    public var reason: String?
    public var syllables: Int
    public var clips: Int
    public var rWhisper: Double?
    public var rSnapped: Double?
    public var deltaR: Double?
    public var ciLower: Double?
    public var ciUpper: Double?
    public var resamples: Int
    public var seed: UInt64

    public static func notEvaluated(_ reason: String, resamples: Int = Int(Thresholds.current.agreement.bootstrapResamples),
                                    seed: UInt64) -> CorrelationGate {
        CorrelationGate(outcome: .notEvaluated, reason: reason, syllables: 0, clips: 0, rWhisper: nil, rSnapped: nil,
                        deltaR: nil, ciLower: nil, ciUpper: nil, resamples: resamples, seed: seed)
    }

    /// Δr and its percentile bootstrap CI, resampling clips with replacement (a clip's syllables move together).
    public static func evaluate(_ syllables: [Syllable],
                                resamples: Int = Int(Thresholds.current.agreement.bootstrapResamples),
                                seed: UInt64) -> CorrelationGate {
        let byClip = Dictionary(grouping: syllables, by: \.clipID).sorted { $0.key < $1.key }.map(\.value)
        func deltaR(_ group: [Syllable]) -> (Double, Double, Double)? {
            guard let w = pearson(group.map { ($0.whisper.durationS, $0.whisper.meanIntensityDB) }),
                  let s = pearson(group.map { ($0.snapped.durationS, $0.snapped.meanIntensityDB) })
            else { return nil }
            return (w, s, s - w)
        }
        guard byClip.count >= 2, let (rW, rS, dR) = deltaR(syllables) else {
            return notEvaluated("fewer than two clips with a defined correlation", resamples: resamples, seed: seed)
        }
        var rng = SeededGenerator(seed: seed)
        var deltas: [Double] = []
        deltas.reserveCapacity(resamples)
        for _ in 0..<resamples {
            let sample = (0..<byClip.count).flatMap { _ in byClip[Int.random(in: 0..<byClip.count, using: &rng)] }
            if let (_, _, d) = deltaR(sample) { deltas.append(d) }
        }
        let lower = Statistics.percentile(deltas, 2.5)
        let upper = Statistics.percentile(deltas, 97.5)
        return CorrelationGate(
            outcome: lower.map { $0 <= 0 ? .pass : .fail } ?? .notEvaluated, reason: nil,
            syllables: syllables.count, clips: byClip.count, rWhisper: rW, rSnapped: rS, deltaR: dR,
            ciLower: lower, ciUpper: upper, resamples: resamples, seed: seed)
    }

    /// Pearson's r; nil with fewer than 3 points or no variance on a side.
    public static func pearson(_ points: [(Double, Double)]) -> Double? {
        guard points.count >= 3 else { return nil }
        let n = Double(points.count)
        let mx = points.reduce(0) { $0 + $1.0 } / n, my = points.reduce(0) { $0 + $1.1 } / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (x, y) in points {
            sxy += (x - mx) * (y - my)
            sxx += (x - mx) * (x - mx)
            syy += (y - my) * (y - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }
}

/// SplitMix64: a small seeded generator, so a bootstrap is reproducible from the seed in the report.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The spec 23 decision: b1 ships if it passes the bar on both sides and the correlation gate; otherwise b2 ships if
/// it was built and passes the bar; otherwise nothing ships (`whisper` stays) and the report is FAIL.
public enum BoundaryDecision {
    public struct Result: Codable, Sendable, Equatable {
        public var shippedAligner: String
        public var outcome: Outcome
        public var b1: Outcome
        /// nil when b2 was not built.
        public var b2: Outcome?
        public var explanation: String
    }

    public static func decide(b1Bar: Outcome, b1Correlation: Outcome, b2Bar: Outcome?,
                              b1ID: String, b2ID: String, fallbackID: String) -> Result {
        let b1 = Outcome.combine([b1Bar, b1Correlation])
        if b1 == .pass {
            return Result(shippedAligner: b1ID, outcome: .pass, b1: b1, b2: b2Bar,
                          explanation: "\(b1ID) passes the unpadded bar on both sides and the correlation gate.")
        }
        let why = b1Bar != .pass
            ? "\(b1ID) misses the unpadded bar (\(b1Bar.rawValue))"
            : "\(b1ID) passes the bar but the correlation gate is \(b1Correlation.rawValue), which is not a pass"
        guard let b2Bar else {
            return Result(shippedAligner: fallbackID, outcome: .fail, b1: b1, b2: nil,
                          explanation: "\(why); \(b2ID) was not built. Nothing ships: \(fallbackID) stays.")
        }
        if b2Bar == .pass {
            return Result(shippedAligner: b2ID, outcome: .pass, b1: b1, b2: b2Bar,
                          explanation: "\(why); \(b2ID) passes the unpadded bar on both sides.")
        }
        return Result(shippedAligner: fallbackID, outcome: .fail, b1: b1, b2: b2Bar,
                      explanation: "\(why); \(b2ID) misses it too (\(b2Bar.rawValue)). Nothing ships: \(fallbackID) stays.")
    }
}
