import AMAlignment
import AMCore
import Foundation

/// The spec 23 word-boundary report (`docs/agreement/reports/word-boundaries-<configDigest8>.{json,md}`): every
/// aligner on spec 03's clips and baseline, side by side, with spec 03's identity header.
public struct WordBoundaryReport: Codable, Sendable {
    public static let suite = "word-boundaries"

    /// Counts of the rule that set each boundary (dsp-snap-1 only; spec 23, Open question 2).
    public struct RuleCounts: Codable, Sendable, Equatable {
        public var starts: [String: Int]
        public var ends: [String: Int]

        public init(starts: [String: Int], ends: [String: Int]) {
            self.starts = starts
            self.ends = ends
        }
    }

    /// Where an aligner's refined boundaries are recorded for CI replay.
    public struct Replay: Codable, Sendable, Equatable {
        public var folder: String
        public var recordingsSHA256: String
        /// The run's boundaries equal the recorded ones.
        public var matchesRecording: Bool?

        public init(folder: String, recordingsSHA256: String, matchesRecording: Bool?) {
            self.folder = folder
            self.recordingsSHA256 = recordingsSHA256
            self.matchesRecording = matchesRecording
        }
    }

    public struct Aligner: Codable, Sendable {
        public var id: String
        public var config: ConfigIdentity
        public var configDigest: String
        public var accuracy: AccuracyResult
        public var bar: BoundaryBar
        /// Refinement time per clip, after the first (warm), in ms.
        public var latency: TimestampReport.Timing.Summary
        public var rules: RuleCounts?
        public var replay: Replay?
        /// Comparable boundaries the aligner moved, of all comparable boundaries.
        public var movedShare: Double?

        public init(id: String, config: ConfigIdentity, configDigest: String, accuracy: AccuracyResult,
                    latency: TimestampReport.Timing.Summary, rules: RuleCounts?, replay: Replay?, movedShare: Double?) {
            self.id = id
            self.config = config
            self.configDigest = configDigest
            self.accuracy = accuracy
            self.bar = BoundaryBar(accuracy)
            self.latency = latency
            self.rules = rules
            self.replay = replay
            self.movedShare = movedShare
        }
    }

    public var generatedAt: Date
    public var identity: TimestampReport.Identity
    public var asrModelID: String
    /// Where the Whisper words came from (spec 03's committed replay of WhisperKit base.en).
    public var whisperSource: String
    public var baseline: WordBaseline.Aligner?
    public var corpus: TimestampReport.Corpus
    public var gate: TimestampGate
    public var thresholds: Thresholds.WordBoundaries
    public var aligners: [Aligner]
    public var correlation: CorrelationGate
    /// §6.7's ≤ 2% placement-diff rule: needs specs 08 and 10, checked in spec 11's agreement run.
    public var placementRule: String
    public var decision: BoundaryDecision.Result
    public var notes: [String]

    public init(generatedAt: Date, identity: TimestampReport.Identity, asrModelID: String, whisperSource: String,
                baseline: WordBaseline.Aligner?, corpus: TimestampReport.Corpus, aligners: [Aligner],
                correlation: CorrelationGate, decision: BoundaryDecision.Result, notes: [String]) {
        self.generatedAt = generatedAt
        self.identity = identity
        self.asrModelID = asrModelID
        self.whisperSource = whisperSource
        self.baseline = baseline
        self.corpus = corpus
        self.gate = .plan
        self.thresholds = Thresholds.current.wordBoundaries
        self.aligners = aligners
        self.correlation = correlation
        self.placementRule = "PENDING: checked in spec 11's agreement run with `aligner` in the identity (needs specs 08 and 10)"
        self.decision = decision
        self.notes = notes
    }

    public var baseName: String { "\(Self.suite)-\(identity.configDigest.prefix(8))" }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self) + Data("\n".utf8)
    }

    public func markdown() -> String {
        var md: [String] = []
        md.append("# Word-boundary refinement (spec 23): \(decision.outcome.rawValue)")
        md.append("")
        md.append("Generated \(ISO8601DateFormatter().string(from: generatedAt)). Refined WhisperKit word boundaries against the MFA word baseline\(baseline.map { " (\($0.name) \($0.version), \($0.acousticModel))" } ?? "") on \(corpus.clips) VCTK 0.92 clips. **No stress claims.**")
        md.append("")
        md.append("## Decision")
        md.append("")
        md.append("\(decision.explanation) Shipped aligner: `\(decision.shippedAligner)`.")
        md.append("")
        md.append("| Line | \(aligners.map { "`\($0.id)`" }.joined(separator: " | ")) |")
        md.append("|---|\(aligners.map { _ in "---" }.joined(separator: "|"))|")
        func row(_ title: String, _ value: (Aligner) -> String) {
            md.append("| \(title) | \(aligners.map(value).joined(separator: " | ")) |")
        }
        row("Starts: median error (≤ \(ms(gate.medianErrorMaxMs)))") { "\(ms($0.accuracy.starts.stats.medianErrorMs)) \($0.accuracy.starts.medianOutcome.rawValue)" }
        row("Starts: within \(ms(gate.toleranceMs)) (≥ \(pct(gate.minShareWithinTolerance)))") { "\(pct($0.accuracy.starts.stats.shareWithinTolerance)) \($0.accuracy.starts.shareOutcome.rawValue)" }
        row("Ends: median error (≤ \(ms(gate.medianErrorMaxMs)))") { "\(ms($0.accuracy.ends.stats.medianErrorMs)) \($0.accuracy.ends.medianOutcome.rawValue)" }
        row("Ends: within \(ms(gate.toleranceMs)) (≥ \(pct(gate.minShareWithinTolerance)))") { "\(pct($0.accuracy.ends.stats.shareWithinTolerance)) \($0.accuracy.ends.shareOutcome.rawValue)" }
        row("Every speaker, both sides") { $0.bar.failingSpeakers.isEmpty ? "all pass" : "\($0.bar.failingSpeakers.count) of \($0.accuracy.perSpeaker.count) miss" }
        row("Comparable boundaries per side") { "\($0.accuracy.starts.stats.boundaries)" }
        row("Mean signed start / end (negative: early)") { "\(signedMs($0.accuracy.meanSignedStartMs)) / \(signedMs($0.accuracy.meanSignedEndMs))" }
        row("Boundaries moved") { pct($0.movedShare) }
        row("Refinement per clip: median / p90 / max") { "\(ms($0.latency.medianMs)) / \(ms($0.latency.p90Ms)) / \(ms($0.latency.maxMs))" }
        row("**Unpadded bar**") { "**\($0.bar.outcome.rawValue)**" }
        md.append("")
        md.append("- Correlation gate (b1 only, spec 02's control pairs): **\(correlation.outcome.rawValue)**\(correlation.reason.map { ". \($0)" } ?? "")")
        if let delta = correlation.deltaR {
            md.append("  - r_whisper \(num(correlation.rWhisper)), r_snap \(num(correlation.rSnapped)), Δr \(num(delta)), 95% CI [\(num(correlation.ciLower)), \(num(correlation.ciUpper))]; \(correlation.syllables) syllables in \(correlation.clips) clips")
        }
        md.append("  - Bootstrap: \(correlation.resamples) resamples over clips, seed \(correlation.seed)")
        md.append("- ≤ 2% placement-diff rule (§6.7): \(placementRule)")
        md.append("")
        md.append("Under the bar, or not evaluated: this report goes to CTO. Thresholds are not changed to pass.")
        md.append("")
        md.append("## Identity (plan §6.6)")
        md.append("")
        md.append("- `configDigest` (the shipped aligner's identity): `\(identity.configDigest)`")
        md.append("- `sourceTreeHash`: `\(identity.sourceTreeHash)`")
        md.append("- Evaluated commit: `\(identity.evaluatedCommit)`; clean tree: \(identity.cleanTree ? "yes" : "no")")
        md.append("- `ConfigIdentity`: algorithmVersion \(identity.config.algorithmVersion), thresholdsVersion \(identity.config.thresholdsVersion), contractVersion \(identity.config.contractVersion), asrModelID `\(identity.config.asrModelID)`, pitchTrackerID `\(identity.config.pitchTrackerID)`, voicingID `\(identity.config.voicingID)`, aligner `\(identity.config.aligner)`")
        for aligner in aligners {
            md.append("  - `\(aligner.id)`: configDigest `\(aligner.configDigest)` (pitchTrackerID `\(aligner.config.pitchTrackerID)`)")
        }
        md.append("- Corpus manifest hash: `\(identity.corpusManifestHash)`")
        if let labelHash = identity.labelHash {
            md.append("- Label (baseline) hash: `\(labelHash)` (`\(identity.labelFile ?? "")`)")
        }
        let tc = identity.toolchain
        md.append("- Toolchain: \(tc.xcode); \(tc.swift); macOS \(tc.macOS); \(tc.hardware)")
        md.append("- Whisper words: \(whisperSource); asrModelID `\(asrModelID)`")
        md.append("- Thresholds: `wordBoundaries.snapWindowMs` \(num(thresholds.snapWindowMs)), `wordBoundaries.intensityDropDB` \(num(thresholds.intensityDropDB)) (spec default, untuned)")
        md.append("")
        md.append("Recompute by hand:")
        md.append("")
        md.append("```sh")
        md.append("# sourceTreeHash")
        md.append(identity.sourceTreeRecipe.replacingOccurrences(of: "<commit>", with: identity.evaluatedCommit))
        md.append("# configDigest: SHA-256 of identity.configCanonicalJSON in the JSON report (no trailing newline)")
        md.append(identity.configDigestRecipe.replacingOccurrences(of: "<report>", with: baseName))
        md.append("```")
        md.append("")
        md.append("## Corpus")
        md.append("")
        md.append("- \(corpus.name), archive SHA-256 `\(corpus.archiveSHA256 ?? "not pinned")`; \(corpus.clips) of \(corpus.specifiedClips) specified clips evaluated; voices \(corpus.speakers.joined(separator: ", "))")
        if !corpus.absentClips.isEmpty {
            md.append("- Not in the archive, so not evaluated: \(corpus.absentClips.joined(separator: ", "))")
        }
        md.append("- \(corpus.attribution)")
        for aligner in aligners {
            md.append("")
            md.append("## `\(aligner.id)`: per speaker (unpadded)")
            md.append("")
            md.append("| Speaker | n | Starts: median | Starts: within \(ms(gate.toleranceMs)) | Starts | Ends: median | Ends: within \(ms(gate.toleranceMs)) | Ends |")
            md.append("|---|---|---|---|---|---|---|---|")
            for s in aligner.accuracy.perSpeaker {
                md.append("| \(s.key) | \(s.starts.stats.boundaries) | \(ms(s.starts.stats.medianErrorMs)) | \(pct(s.starts.stats.shareWithinTolerance)) | \(s.starts.outcome.rawValue) | \(ms(s.ends.stats.medianErrorMs)) | \(pct(s.ends.stats.shareWithinTolerance)) | \(s.ends.outcome.rawValue) |")
            }
            if let rules = aligner.rules {
                md.append("")
                md.append("Rule that set each boundary (Open question 2: later offset for ends, earlier onset for starts), over all words:")
                md.append("")
                md.append("| Side | " + Self.ruleOrder.joined(separator: " | ") + " |")
                md.append("|---|" + Self.ruleOrder.map { _ in "---" }.joined(separator: "|") + "|")
                for (side, counts) in [("Starts", rules.starts), ("Ends", rules.ends)] {
                    let total = max(counts.values.reduce(0, +), 1)
                    md.append("| \(side) | " + Self.ruleOrder.map { "\(counts[$0] ?? 0) (\(pct(Double(counts[$0] ?? 0) / Double(total))))" }.joined(separator: " | ") + " |")
                }
            }
            if let replay = aligner.replay {
                md.append("")
                md.append("Recorded for CI replay: `\(replay.folder)`, recordingsSHA256 `\(replay.recordingsSHA256)`; this run matches the recording: \(replay.matchesRecording.map { $0 ? "yes" : "NO" } ?? "not checked")")
            }
        }
        if !notes.isEmpty {
            md.append("")
            md.append("## Notes")
            md.append("")
            for note in notes { md.append("- \(note)") }
        }
        return md.joined(separator: "\n")
    }

    private static let ruleOrder = ["voicing", "intensity", "tie", "unchanged"]
}

private func ms(_ value: Double?) -> String {
    value.map { String(format: "%.1f ms", $0) } ?? "–"
}

private func signedMs(_ value: Double?) -> String {
    value.map { String(format: "%+.1f ms", $0) } ?? "–"
}

private func pct(_ value: Double?) -> String {
    value.map { String(format: "%.1f%%", $0 * 100) } ?? "–"
}

private func num(_ value: Double?) -> String {
    value.map { String(format: "%g", $0) } ?? "–"
}
