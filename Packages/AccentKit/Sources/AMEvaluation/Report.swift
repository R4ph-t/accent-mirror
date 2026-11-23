// Agreement reports (plan §6.6): the identity header, the metrics, the summary lines and the files they go to.
// `scripts/check-report-identity.sh` recomputes the hashes defined here; keep the two in step.

import Foundation
import AMCore

/// The hashes a report carries, defined once.
public enum ReportHashes {
    /// SHA-256 of the sorted file hashes: lowercase hex, sorted, one per line, each followed by a newline.
    public static func corpusManifestHash(fileHashes: some Sequence<String>) -> String {
        let lines = fileHashes.map { $0.lowercased() }.sorted()
        return SHA256Digest.hex(of: Data(lines.map { $0 + "\n" }.joined().utf8))
    }

    /// The path prefix `sourceTreeHash` ignores, so a report can be committed after the commit it evaluated.
    public static let reportsPrefix = "docs/agreement/reports/"

    /// `sourceTreeHash` from the output of `git ls-tree -r --full-tree <commit>`: every line whose path is under
    /// `docs/agreement/reports/` removed, the rest sorted by byte value, each followed by a newline, then SHA-256.
    public static func sourceTreeHash(lsTree output: String) -> String {
        let lines = output.split(separator: "\n").map(String.init).filter { line in
            guard let tab = line.firstIndex(of: "\t") else { return true }
            return !line[line.index(after: tab)...].hasPrefix(reportsPrefix)
        }
        let sorted = lines.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        return SHA256Digest.hex(of: Data(sorted.map { $0 + "\n" }.joined().utf8))
    }
}

/// Which synthetic reference a report used. Always `none` until spec 22.
public enum SyntheticReference: Sendable, Hashable, Codable, CustomStringConvertible {
    case none
    case elevenlabs
    case macPremiumFallback(reason: String)

    public var description: String {
        switch self {
        case .none: "none"
        case .elevenlabs: "elevenlabs"
        case .macPremiumFallback(let reason): "mac-premium-fallback (\(reason))"
        }
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        switch text {
        case "none": self = .none
        case "elevenlabs": self = .elevenlabs
        default:
            let prefix = "mac-premium-fallback ("
            guard text.hasPrefix(prefix), text.hasSuffix(")") else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            self = .macPremiumFallback(reason: String(text.dropFirst(prefix.count).dropLast()))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// The §6.6 identity header every report carries.
public struct ReportIdentity: Sendable, Hashable, Codable {
    public let config: ConfigIdentity
    public let configDigest: String
    public let corpusManifestHash: String
    public let labelHash: String
    public let splitManifestHash: String
    public let splitSeed: UInt64
    public let sourceTreeHash: String
    public let evaluatedCommit: String
    public let cleanTree: Bool
    public let xcodeVersion: String
    public let swiftVersion: String
    public let macOSVersion: String
    public let runnerImage: String
    public let syntheticReference: SyntheticReference

    public init(
        config: ConfigIdentity, configDigest: String, corpusManifestHash: String, labelHash: String,
        splitManifestHash: String, splitSeed: UInt64, sourceTreeHash: String, evaluatedCommit: String,
        cleanTree: Bool, xcodeVersion: String, swiftVersion: String, macOSVersion: String, runnerImage: String,
        syntheticReference: SyntheticReference = .none
    ) {
        self.config = config
        self.configDigest = configDigest
        self.corpusManifestHash = corpusManifestHash
        self.labelHash = labelHash
        self.splitManifestHash = splitManifestHash
        self.splitSeed = splitSeed
        self.sourceTreeHash = sourceTreeHash
        self.evaluatedCommit = evaluatedCommit
        self.cleanTree = cleanTree
        self.xcodeVersion = xcodeVersion
        self.swiftVersion = swiftVersion
        self.macOSVersion = macOSVersion
        self.runnerImage = runnerImage
        self.syntheticReference = syntheticReference
    }
}

/// One agreement report.
public struct AgreementReport: Sendable, Hashable, Codable {
    /// The limitation every report states (rev 4).
    public static let limitation =
        "The shipped config's L2 recall is never measured on unseen speakers; the only L2 recall number is the CV "
        + "estimate of the tuning procedure."

    public let suite: String
    /// ISO 8601, UTC.
    public let generatedAt: String
    /// A release report must come from a clean tree.
    public let release: Bool
    public let identity: ReportIdentity
    public let metrics: [MetricResult]
    /// Per fold: its `configDigest`, recorded once, with every path's results under it.
    public let folds: FoldRunRecord?
    public let summary: ReleaseSummary
    /// `summary.lines` as written, so a report check can read the overall lines without the Swift types.
    public let summaryLines: [String]
    /// The VCTK positive set's status for this report (nil when the suite has no positive set).
    public let positiveSet: PositiveSetStatus?
    public let notes: [String]
    public let limitations: [String]

    public init(
        suite: String, generatedAt: Date, release: Bool, identity: ReportIdentity, metrics: [MetricResult],
        folds: FoldRunRecord? = nil, summary: ReleaseSummary, notes: [String] = []
    ) {
        self.suite = suite
        self.generatedAt = ISO8601DateFormatter().string(from: generatedAt)
        self.release = release
        self.identity = identity
        self.metrics = metrics
        self.folds = folds
        self.summary = summary
        self.summaryLines = summary.lines
        self.positiveSet = summary.positiveSet
        self.notes = notes
        self.limitations = [Self.limitation]
    }

    /// `<suite>-<configDigest8>`.
    public var baseName: String { "\(suite)-\(identity.configDigest.prefix(8))" }

    public var markdown: String {
        let id = identity
        var out = "# Agreement report: \(suite)\n\n"
        out += "| Identity | Value |\n|---|---|\n"
        let rows: [(String, String)] = [
            ("Generated", generatedAt), ("Release report", release ? "yes" : "no"),
            ("configDigest", id.configDigest),
            ("ConfigIdentity", "algorithm \(id.config.algorithmVersion), thresholds \(id.config.thresholdsVersion), contract \(id.config.contractVersion), ASR \(id.config.asrModelID), pitch \(id.config.pitchTrackerID), voicing \(id.config.voicingID)"),
            ("Corpus manifest hash", id.corpusManifestHash), ("Label hash", id.labelHash),
            ("Split manifest hash", id.splitManifestHash), ("Split seed", String(id.splitSeed)),
            ("sourceTreeHash", id.sourceTreeHash), ("Evaluated commit", id.evaluatedCommit),
            ("Clean tree", id.cleanTree ? "yes" : "no"), ("Xcode", id.xcodeVersion), ("Swift", id.swiftVersion),
            ("macOS", id.macOSVersion), ("Runner image", id.runnerImage),
            ("syntheticReference", id.syntheticReference.description),
        ]
        for (name, value) in rows { out += "| \(name) | `\(value)` |\n" }
        for layer in ValidationLayer.allCases {
            let lines = metrics.filter { $0.layer == layer }
            guard !lines.isEmpty else { continue }
            out += "\n## \(layer.label)\n\n"
            out += "| Metric | n | Value | Gate | Status | Interval | Worst speaker | Worst phrase |\n"
            out += "|---|---|---|---|---|---|---|---|\n"
            for m in lines {
                let value = m.value.map { String(format: "%.4f", $0) } ?? "–"
                let gate = m.gate.map { "\($0.direction == .atLeast ? "≥" : "≤") \($0.bound) (`\($0.key)`)" } ?? "–"
                let intervals = m.intervals.map { String(format: "[%.4f, %.4f] ", $0.lower, $0.upper) + $0.label }
                    .joined(separator: "; ")
                let worstSpeaker = m.worstSpeaker.map { String(format: "%@ %.4f (n=%d)", $0.id, $0.value, $0.n) } ?? "–"
                let worstPhrase = m.worstPhrase.map { String(format: "%@ %.4f (n=%d)", $0.id, $0.value, $0.n) } ?? "–"
                out += "| \(m.name) | \(m.n) | \(value) | \(gate) | \(m.status.text) | \(intervals.isEmpty ? "–" : intervals) | \(worstSpeaker) | \(worstPhrase) |\n"
            }
        }
        if let folds {
            out += "\n## Folds (one config per fold, every path under it)\n\n| Fold | configDigest | Held-out speakers | Paths |\n|---|---|---|---|\n"
            for fold in folds.folds {
                out += "| \(fold.index) | `\(fold.configDigest.prefix(16))…` | \(fold.heldOutSpeakers.count) | \(fold.results.keys.sorted().joined(separator: ", ")) |\n"
            }
            for (path, pooled) in folds.pooled.sorted(by: { $0.key < $1.key }) {
                out += "\nPooled out-of-fold recall, \(path): \(pooled.hits) / \(pooled.n)"
            }
            for c in folds.comparisons {
                out += "\nPaired per word, \(c.first) vs \(c.second): \(c.firstWins) wins, \(c.secondWins) losses, McNemar p = \(String(format: "%.4f", c.pValue))"
            }
            out += "\n"
        }
        if !notes.isEmpty { out += "\n## Notes\n\n" + notes.map { "- \($0)\n" }.joined() }
        out += "\n## Limitations\n\n" + limitations.map { "- \($0)\n" }.joined()
        out += "\n## Summary\n\n" + summary.lines.map { "    \($0)\n" }.joined()
        return out
    }
}

public enum ReportWriter {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case dirtyTreeRelease

        public var description: String { "a dirty tree cannot write a release report: commit or stash first" }
    }

    /// `docs/agreement/reports/` under the repository root.
    public static func directory(repositoryRoot: URL) -> URL {
        repositoryRoot.appendingPathComponent(ReportHashes.reportsPrefix, isDirectory: true)
    }

    /// Writes `<suite>-<configDigest8>.json` and `.md`. Refuses a release report from a dirty tree.
    @discardableResult
    public static func write(_ report: AgreementReport, to directory: URL) throws -> (json: URL, markdown: URL) {
        if report.release && !report.identity.cleanTree { throw Failure.dirtyTreeRelease }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = directory.appendingPathComponent(report.baseName + ".json")
        let markdown = directory.appendingPathComponent(report.baseName + ".md")
        try encoder.encode(report).write(to: json, options: .atomic)
        try Data(report.markdown.utf8).write(to: markdown, options: .atomic)
        return (json, markdown)
    }
}
