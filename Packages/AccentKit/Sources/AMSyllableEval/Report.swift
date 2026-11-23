import AMCapture
import AMCore
import AMTimestampEval
import Foundation

/// The spec 07 real-speech report: `docs/agreement/reports/syllable-boundaries-<configDigest8>.{json,md}`.
public struct SyllableBoundaryReport: Codable, Sendable {
    /// Why the real-speech lines aren't evaluated yet (spec 07 Open question 0).
    public static let waitingOnSpec23 = "waiting on spec 23"

    public struct Identity: Codable, Sendable {
        public var config: ConfigIdentity
        public var configCanonicalJSON: String
        public var configDigest: String
        public var configDigestRecipe: String
        public var evaluatedCommit: String
        public var cleanTree: Bool
        /// Spec 02's §6.6 identity header, when spec 02 has shipped it; until then, why it's absent.
        public var agreementHeader: String

        public init(config: ConfigIdentity, evaluatedCommit: String, cleanTree: Bool) throws {
            let record = try ConfigDigestRecord(config: config)
            self.config = config
            configCanonicalJSON = record.canonicalJSON
            configDigest = record.sha256
            configDigestRecipe = ConfigDigestRecord.recipe
            self.evaluatedCommit = evaluatedCommit
            self.cleanTree = cleanTree
            agreementHeader = "not present: spec 02's §6.6 header is not on main yet"
        }
    }

    /// The pinned MFA reference (spec 03's `scripts/setup-mfa.sh`).
    public struct Reference: Codable, Sendable {
        public var aligner = "Montreal Forced Aligner 3.4.4"
        public var acousticModel = "english_mfa v3.1.0"
        public var dictionary = "english_mfa v3.1.0"
        public var syllabifier = "spec 06 Syllabifier on the segmenter's pronunciation, matched by phone position"
        public var clips = "spec 02's 12 held-out VCTK speakers"
        public init() {}
    }

    public struct Line: Codable, Sendable {
        public var name: String
        public var bar: String
        public var status: GateStatus
        public var value: String?
        public var note: String?
    }

    public var identity: Identity
    public var reference = Reference()
    public var evaluation: BoundaryEvaluation?
    public var lines: [Line]
    /// PASS only when every line passes; FAIL when any fails; otherwise NOT EVALUATED (never a pass).
    public var status: GateStatus

    /// `evaluation` is nil until spec 23 ships and MFA and spec 02's clips are available.
    public init(identity: Identity, evaluation: BoundaryEvaluation?, notEvaluatedReason: String = waitingOnSpec23,
                bars: Thresholds.SyllableBoundaries = Thresholds.current.syllableBoundaries) {
        self.identity = identity
        self.evaluation = evaluation
        let waiting = "NOT EVALUATED (\(notEvaluatedReason))"
        func line(_ name: String, _ bar: String, _ status: GateStatus?, _ value: String?) -> Line {
            Line(name: name, bar: bar, status: status ?? .notEvaluated, value: value,
                 note: status == nil || status == .notEvaluated ? waiting : nil)
        }
        lines = [
            line("speechocean762 recall (spec 02 set)", "spec 02 / §6.7", nil, nil),
            line("VCTK false positives (spec 02 set)", "spec 02 / §6.7", nil, nil),
            line("MFA syllable boundaries: median error", "≤ \(Self.number(bars.medianErrorMaxMs)) ms",
                 evaluation?.median, evaluation?.medianErrorMs.map { "\(Self.number($0)) ms" }),
            line("MFA syllable boundaries: within \(Self.number(bars.withinToleranceMs)) ms",
                 "≥ \(Self.number(bars.withinToleranceShareMin * 100))%", evaluation?.withinTolerance,
                 evaluation?.withinToleranceShare.map { "\(Self.number($0 * 100))%" }),
            line("Calibration: low-confidence syllables have larger error", "median(low) > median(medium, high)",
                 evaluation?.calibration,
                 evaluation.flatMap { evaluation in
                     guard let low = evaluation.medianErrorLowMs, let rest = evaluation.medianErrorMediumOrHighMs
                     else { return nil }
                     return "\(Self.number(low)) ms vs \(Self.number(rest)) ms"
                 }),
        ]
        if lines.contains(where: { $0.status == .fail }) {
            status = .fail
        } else if lines.allSatisfy({ $0.status == .pass }) {
            status = .pass
        } else {
            status = .notEvaluated
        }
    }

    public var fileStem: String { "syllable-boundaries-\(identity.configDigest.prefix(8))" }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    public func markdown() -> String {
        var out = [
            "# Syllable boundaries (spec 07)", "",
            "Status: **\(status.rawValue)**. NOT EVALUATED is not a pass; a FAIL goes to CTO.", "",
            "## Identity", "",
            "- configDigest: `\(identity.configDigest)`",
            "- algorithmVersion \(identity.config.algorithmVersion), thresholdsVersion \(identity.config.thresholdsVersion), "
                + "contractVersion \(identity.config.contractVersion)",
            "- voicing `\(identity.config.voicingID)`, ASR `\(identity.config.asrModelID)`, pitch `\(identity.config.pitchTrackerID)`",
            "- commit `\(identity.evaluatedCommit)`\(identity.cleanTree ? "" : " (dirty tree)")",
            "- spec 02 identity header: \(identity.agreementHeader)",
            "- recompute the digest: `\(identity.configDigestRecipe)`", "",
            "## Reference", "",
            "- \(reference.aligner), acoustic model \(reference.acousticModel), dictionary \(reference.dictionary)",
            "- syllables: \(reference.syllabifier)",
            "- clips: \(reference.clips)", "",
            "## Lines", "",
            "| Check | Bar | Value | Status |",
            "|---|---|---|---|",
        ]
        for line in lines {
            out.append("| \(line.name) | \(line.bar) | \(line.value ?? "–") | \(line.note ?? line.status.rawValue) |")
        }
        if let evaluation {
            out += ["", "Boundaries compared: \(evaluation.count)."]
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

extension ConfigIdentity {
    /// Spec 07's identity: AMCore's current versions, the voicing the pipeline wires (spec 05's `ACFVoicing`), and
    /// the explicit placeholder `none` for ASR (word boundaries are injected) and pitch (spec 08 adds peak F0).
    public static let syllableSegmentation = ConfigIdentity(
        asrModelID: "none", pitchTrackerID: "none", voicingID: ACFVoicing.voicingID)
}
