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

/// The spec 23 decision under the CTO ruling of 2026-11-23 14:05: b2 (`ctc-w2v2b960-1`) is the aligner and b1 is a
/// diagnostic. The ship gate is downstream (`DownstreamGate`, synthetic and VCTK, both must pass); the 40 ms / 85%
/// bar is a reported target. b2 ships only when the gate passes and every prerequisite is met, and the flip is its
/// own later PR: this decision never changes the shipped aligner.
public enum ShipDecision {
    public struct Prerequisite: Codable, Sendable, Equatable {
        public var name: String
        public var status: String
        public var met: Bool

        public init(_ name: String, _ status: String, met: Bool) {
            self.name = name
            self.status = status
            self.met = met
        }
    }

    public struct Result: Codable, Sendable, Equatable {
        public var alignerOfRecord: String
        public var shippedAligner: String
        /// The downstream gate over both sets.
        public var gate: Outcome
        /// READY (gate passes, every prerequisite met; the flip is a separate PR), PENDING or FAIL.
        public var ship: String
        public var prerequisites: [Prerequisite]
        public var explanation: String
    }

    public static func decide(gates: [DownstreamGate], prerequisites: [Prerequisite], candidate: String,
                              shipped: String) -> Result {
        let gate = Outcome.combine(gates.map(\.outcome))
        let missing = prerequisites.filter { !$0.met }.map(\.name)
        let ship: String, explanation: String
        switch gate {
        case .fail:
            ship = "FAIL"
            explanation = "\(candidate) fails the downstream gate (\(gates.filter { $0.outcome == .fail }.map(\.set).joined(separator: ", "))): back to CTO, no retuning. `\(shipped)` stays shipped."
        case .notEvaluated:
            ship = "PENDING"
            explanation = "The downstream gate is NOT EVALUATED (\(gates.filter { $0.outcome == .notEvaluated }.map { "\($0.set): \($0.reason ?? "not run")" }.joined(separator: "; "))), which is not a pass. `\(shipped)` stays shipped."
        case .pass where missing.isEmpty:
            ship = "READY"
            explanation = "\(candidate) passes the downstream gate and every ship prerequisite. The ship flip is its own PR with Raph's OK; `\(shipped)` stays shipped here."
        case .pass:
            ship = "PENDING"
            explanation = "\(candidate) passes the downstream gate on both sets; ship PENDING on: \(missing.joined(separator: "; ")). `\(shipped)` stays shipped."
        }
        return Result(alignerOfRecord: candidate, shippedAligner: shipped, gate: gate, ship: ship,
                      prerequisites: prerequisites, explanation: explanation)
    }
}
