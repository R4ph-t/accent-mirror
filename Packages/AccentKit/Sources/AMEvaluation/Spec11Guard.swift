// Spec 11 §4, §4a, §4b and §4c: the anti-inconclusive guard, read from `am-timestamps spec11-guard`'s JSON. That tool
// only measures (spec 07's `WordVerdict`s under an oracle and a candidate, spec 23's harness unchanged); the limits
// live here, from `Thresholds.wordBoundaries` and `Thresholds.agreement`, so no gate value is in the tool.

import AMCore
import Foundation

/// `am-timestamps spec11-guard`'s output (format 1). Decoding only; unknown keys are ignored.
public struct GuardRun: Sendable, Hashable, Codable {
    public struct Bucket: Sendable, Hashable, Codable {
        public let bucket: String
        public let words: Int
        public let differing: Int
        public let oracleInconclusive: Int
        public let candidateInconclusive: Int
    }

    public struct Bin: Sendable, Hashable, Codable {
        public let bin: String
        public let words: Int
        public let differing: Int
    }

    public struct Transitions: Sendable, Hashable, Codable {
        public let decidedToDecided: Int
        public let involvingInconclusive: Int
    }

    public struct InconclusiveSplit: Sendable, Hashable, Codable {
        public let oracle: Int
        public let candidate: Int
        public let candidateGateBypassed: Int
        public let gatedWords: Int
    }

    public struct Comparison: Sendable, Hashable, Codable {
        public let id: String
        public let candidate: String
        public let status: String
        public let reason: String?
        public let words: Int
        public let differing: Int
        public let oracleInconclusive: Int
        public let candidateInconclusive: Int
        public let parts: [String: Int]
        public let onlyCue: [String: Int]
        public let bySyllables: [Bucket]
        public let transitions: Transitions
        public let boundaryError: [Bin]
        public let keptUnjittered: Int
        public let inconclusiveSplit: InconclusiveSplit?

        public var evaluated: Bool { status == "evaluated" && words > 0 }
    }

    public struct GuardSet: Sendable, Hashable, Codable {
        public let set: String
        public let oracle: String
        public let status: String
        public let reason: String?
        public let clips: Int
        public let clipsSkipped: [String]
        public let substituted: Int
        public let deleted: Int
        public let comparisons: [Comparison]

        public func comparison(_ id: String) -> Comparison? { comparisons.first { $0.id == id } }
    }

    public let formatVersion: Int
    public let thresholdsLabel: String
    public let seed: UInt64
    public let asrModelID: String?
    public let ctcModel: String?
    public let sets: [GuardSet]

    public func set(_ name: String) -> GuardSet? { sets.first { $0.set == name } }
}

/// Rounded to a millionth, so a share of exactly 0.02 isn't pushed over a bar by floating point (as spec 23's gate).
func microunit(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }

/// One guard check: n, value, limit, interval and MET / NOT MET (NOT EVALUATED is never met).
public struct GuardCheck: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case met = "MET"
        case notMet = "NOT MET"
        case notEvaluated = "NOT EVALUATED"
        /// A syllable group under the CTO's minimum: printed, not gated.
        case reportedSmall = "reported (n < 30)"
        case reported = "REPORTED"
    }

    public let name: String
    public let set: String
    public let n: Int
    public let value: Double?
    public let limit: Double?
    public let status: Status
    public let interval: Interval?
    public let detail: String

    public var line: String {
        let v = value.map { String(format: "%.4f", $0) } ?? "–"
        let l = limit.map { String(format: "≤ %.2f", $0) } ?? "no limit"
        let i = interval.map { String(format: " [%.4f, %.4f] Wilson 95%%", $0.lower, $0.upper) } ?? ""
        return "\(name), \(set): n=\(n) value \(v)\(i) (\(l)): \(status.rawValue)\(detail.isEmpty ? "" : "; \(detail)")"
    }
}

/// The guard's conditions on one scope, from a `GuardRun`.
public struct GuardEvaluation: Sendable {
    public enum Scope: Sendable { case tuning, heldOut }

    /// A syllable group with fewer words is reported, not gated (CTO, 2026-11-24). Not a tunable number.
    public static let minimumGatedGroupWords = 30
    /// The syllable groups the gaming guard gates (Open question 4: 2 and 3 separately).
    public static let gatedBuckets = ["2", "3"]

    public let run: GuardRun
    public let scope: Scope
    public let thresholds: Thresholds

    public init(run: GuardRun, scope: Scope, thresholds: Thresholds = .current) {
        self.run = run
        self.scope = scope
        self.thresholds = thresholds
    }

    var diffMax: Double { thresholds.wordBoundaries.verdictDiffMax }
    var riseMax: Double { thresholds.wordBoundaries.inconclusiveRiseMaxPoints }

    /// The VCTK set of this scope.
    public var vctk: GuardRun.GuardSet? { run.sets.first { $0.set != "synthetic" } }
    public var synthetic: GuardRun.GuardSet? { run.set("synthetic") }

    /// Share of comparable words whose verdicts differ (anything↔inconclusive included).
    public func flips(_ comparison: GuardRun.Comparison?, set: String, name: String) -> GuardCheck {
        guard let c = comparison, c.evaluated else {
            return GuardCheck(name: name, set: set, n: comparison?.words ?? 0, value: nil, limit: diffMax,
                              status: .notEvaluated, interval: nil, detail: comparison?.reason ?? "not run")
        }
        let share = Double(c.differing) / Double(c.words)
        return GuardCheck(
            name: name, set: set, n: c.words, value: share, limit: diffMax,
            status: microunit(share) <= diffMax ? .met : .notMet,
            interval: Statistics.wilson(successes: c.differing, n: c.words),
            detail: "\(c.differing) of \(c.words) words")
    }

    /// The overall inconclusive rise of a comparison, in points (as shares).
    public func rise(_ comparison: GuardRun.Comparison?, set: String, name: String) -> GuardCheck {
        guard let c = comparison, c.evaluated else {
            return GuardCheck(name: name, set: set, n: 0, value: nil, limit: riseMax, status: .notEvaluated,
                              interval: nil, detail: comparison?.reason ?? "not run")
        }
        let o = Double(c.oracleInconclusive) / Double(c.words)
        let k = Double(c.candidateInconclusive) / Double(c.words)
        let rise = microunit(k - o)
        return GuardCheck(
            name: name, set: set, n: c.words, value: rise, limit: riseMax, status: rise <= riseMax ? .met : .notMet,
            interval: nil, detail: String(format: "inconclusive %.1f%% → %.1f%%", o * 100, k * 100))
    }

    /// The gaming guard: per syllable group (1, 2, 3, 4+) the inconclusive rise over the oracle, with n and both Wilson
    /// intervals. Groups 2 and 3 with n ≥ 30 are gated at ≤ 2 points; the rest are reported.
    public func groups(_ comparison: GuardRun.Comparison?, set: String, name: String) -> [GuardCheck] {
        guard let c = comparison, c.evaluated else {
            return Self.gatedBuckets.map {
                GuardCheck(name: "\(name), \($0)-syllable inconclusive rise", set: set, n: 0, value: nil, limit: riseMax,
                           status: .notEvaluated, interval: nil, detail: comparison?.reason ?? "not run")
            }
        }
        return c.bySyllables.map { b in
            let gated = Self.gatedBuckets.contains(b.bucket)
            let o = b.words == 0 ? 0 : Double(b.oracleInconclusive) / Double(b.words)
            let k = b.words == 0 ? 0 : Double(b.candidateInconclusive) / Double(b.words)
            let rise = microunit(k - o)
            let wo = Statistics.wilson(successes: b.oracleInconclusive, n: max(b.words, 1))
            let wc = Statistics.wilson(successes: b.candidateInconclusive, n: max(b.words, 1))
            let status: GuardCheck.Status =
                !gated ? .reported
                : b.words < Self.minimumGatedGroupWords ? .reportedSmall
                : rise <= riseMax ? .met : .notMet
            return GuardCheck(
                name: "\(name), \(b.bucket)-syllable inconclusive rise", set: set, n: b.words, value: rise,
                limit: gated ? riseMax : nil, status: status, interval: nil,
                detail: String(format: "oracle %d/%d [%.3f, %.3f], candidate %d/%d [%.3f, %.3f]; flips %d/%d",
                               b.oracleInconclusive, b.words, wo.lower, wo.upper, b.candidateInconclusive, b.words,
                               wc.lower, wc.upper, b.differing, b.words))
        }
    }

    /// The multi-syllable groups whose flips §4b gates at ±40 ms (CTO, 2026-11-24 12:53).
    public static let flipGatedBuckets = ["2", "3", "4+"]

    /// Flips per multi-syllable group (2, 3, 4+): gated at ≤ 2% with n ≥ 30, else `reported (n < 30)`.
    public func groupFlips(_ comparison: GuardRun.Comparison?, set: String, name: String) -> [GuardCheck] {
        guard let c = comparison, c.evaluated else {
            return Self.flipGatedBuckets.map {
                GuardCheck(name: "\(name), \($0)-syllable flips", set: set, n: 0, value: nil, limit: diffMax,
                           status: .notEvaluated, interval: nil, detail: comparison?.reason ?? "not run")
            }
        }
        return Self.flipGatedBuckets.map { bucket in
            guard let b = c.bySyllables.first(where: { $0.bucket == bucket }), b.words > 0 else {
                return GuardCheck(name: "\(name), \(bucket)-syllable flips", set: set, n: 0, value: nil, limit: diffMax,
                                  status: .reportedSmall, interval: nil, detail: "no words")
            }
            let share = Double(b.differing) / Double(b.words)
            return GuardCheck(
                name: "\(name), \(bucket)-syllable flips", set: set, n: b.words, value: share, limit: diffMax,
                status: b.words < Self.minimumGatedGroupWords ? .reportedSmall : microunit(share) <= diffMax ? .met : .notMet,
                interval: Statistics.wilson(successes: b.differing, n: b.words),
                detail: "\(b.differing) of \(b.words) words")
        }
    }

    /// All checks of one comparison: flips (or only the rise), overall rise, groups.
    func checks(_ id: String, in set: GuardRun.GuardSet?, setName: String, name: String, gateRise: Bool,
                groupFlipsGated: Bool = false) -> [GuardCheck] {
        let c = set?.comparison(id)
        var out = [flips(c, set: setName, name: name)]
        if groupFlipsGated { out += groupFlips(c, set: setName, name: name) }
        let r = rise(c, set: setName, name: "\(name), inconclusive rise")
        out.append(gateRise ? r : GuardCheck(name: r.name, set: r.set, n: r.n, value: r.value, limit: nil,
                                             status: r.status == .notEvaluated ? .notEvaluated : .reported,
                                             interval: nil, detail: r.detail))
        out += groups(c, set: setName, name: name)
        return out
    }

    /// Whether a list of checks is met: every gated check MET (reported ones don't count; NOT EVALUATED fails).
    public static func met(_ checks: [GuardCheck]) -> Bool {
        checks.allSatisfy { [.met, .reported, .reportedSmall].contains($0.status) }
            && checks.contains { $0.status == .met }
    }

    // MARK: Tuning scope (§4c during tuning: b2 vs MFA and ±40 ms jitter on the VCTK tuning speakers)

    public var tuningChecks: [GuardCheck] {
        let name = vctk?.set ?? "vctk-tuning"
        return checks("b2", in: vctk, setName: name, name: "b2 vs MFA", gateRise: true)
            + checks("jitter-40", in: vctk, setName: name, name: "jitter ±40 ms", gateRise: false, groupFlipsGated: true)
    }

    public var tuningConditionsMet: Bool { Self.met(tuningChecks) }

    // MARK: Held-out scope (the release's four conditions)

    /// Condition 1: the TTS-vs-MFA control on the synthetic set (≤ 2% flips, gaming guard).
    public var condition1: [GuardCheck] {
        checks("control", in: synthetic, setName: "synthetic", name: "TTS-vs-MFA control", gateRise: false)
    }

    /// Condition 3: b2 vs oracle on each set (≤ 2% flips and ≤ 2 points of rise, gaming guard).
    public var condition3: [GuardCheck] {
        checks("b2", in: synthetic, setName: "synthetic", name: "b2 vs oracle", gateRise: true)
            + checks("b2", in: vctk, setName: vctk?.set ?? "vctk", name: "b2 vs oracle", gateRise: true)
    }

    /// Condition 4: ±40 ms jitter on each set, ≤ 2% flips pooled and in each multi-syllable group with n ≥ 30, plus
    /// the gaming guard.
    public var condition4: [GuardCheck] {
        checks("jitter-40", in: synthetic, setName: "synthetic", name: "jitter ±40 ms", gateRise: false,
               groupFlipsGated: true)
            + checks("jitter-40", in: vctk, setName: vctk?.set ?? "vctk", name: "jitter ±40 ms", gateRise: false,
                     groupFlipsGated: true)
    }

    /// ±20 and ±80 ms: reported only.
    public var jitterReported: [GuardCheck] {
        ["jitter-20", "jitter-80"].flatMap { id in
            [synthetic, vctk].compactMap { $0 }.map { set in
                let check = flips(set.comparison(id), set: set.set, name: "jitter ±\(id.dropFirst(7)) ms")
                return GuardCheck(name: check.name, set: check.set, n: check.n, value: check.value, limit: nil,
                                  status: check.status == .notEvaluated ? .notEvaluated : .reported,
                                  interval: check.interval, detail: check.detail)
            }
        }
    }

    public var lines: [String] {
        switch scope {
        case .tuning: tuningChecks.map(\.line) + ["guard on tuning data: \(tuningConditionsMet ? "MET" : "NOT MET")"]
        case .heldOut: (condition1 + condition3 + condition4 + jitterReported).map(\.line)
        }
    }
}
