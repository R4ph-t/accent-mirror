import AMAlignment
import AMCore
import Foundation

/// The spec 03 timestamp-feasibility report (`docs/agreement/reports/timestamp-feasibility-<configDigest8>.{json,md}`).
public struct TimestampReport: Codable, Sendable {
    public struct Toolchain: Codable, Sendable {
        public var xcode: String
        public var swift: String
        public var macOS: String
        public var hardware: String
        /// The CI runner image, when the run is on CI.
        public var runnerImage: String?

        public init(xcode: String, swift: String, macOS: String, hardware: String, runnerImage: String?) {
            self.xcode = xcode
            self.swift = swift
            self.macOS = macOS
            self.hardware = hardware
            self.runnerImage = runnerImage
        }
    }

    /// The plan §6.6 identity header.
    public struct Identity: Codable, Sendable {
        public var config: ConfigIdentity
        public var configCanonicalJSON: String
        public var configDigest: String
        public var configDigestRecipe: String
        public var corpusManifestHash: String
        public var corpusManifestRecipe: String
        /// SHA-256 of the committed baseline file; `nil` when there is no baseline.
        public var labelHash: String?
        public var labelFile: String?
        public var sourceTreeHash: String
        public var sourceTreeRecipe: String
        public var evaluatedCommit: String
        public var cleanTree: Bool
        public var toolchain: Toolchain

        public init(config: ConfigIdentity, configDigest: ConfigDigestRecord, corpusManifestHash: String,
                    labelHash: String?, labelFile: String?, sourceTreeHash: String, evaluatedCommit: String,
                    cleanTree: Bool, toolchain: Toolchain) {
            self.config = config
            self.configCanonicalJSON = configDigest.canonicalJSON
            self.configDigest = configDigest.sha256
            self.configDigestRecipe = ConfigDigestRecord.recipe
            self.corpusManifestHash = corpusManifestHash
            self.corpusManifestRecipe = CorpusHash.recipe
            self.labelHash = labelHash
            self.labelFile = labelFile
            self.sourceTreeHash = sourceTreeHash
            self.sourceTreeRecipe = SourceTree.recipe
            self.evaluatedCommit = evaluatedCommit
            self.cleanTree = cleanTree
            self.toolchain = toolchain
        }
    }

    public struct Model: Codable, Sendable {
        public var asrModelID: String
        public var modelSHA256: String
        public var whisperKitVersion: String
        public var whisperKitCommit: String
        public var sources: [ModelManifest.Source]
        public var files: [ModelManifest.File]
        public var decoding: String
        /// The model that would ship, given the warm budget (`tiny.en` is the fallback).
        public var shippingModel: String

        public init(manifest: ModelManifest, decoding: String, shippingModel: String) {
            asrModelID = manifest.asrModelID
            modelSHA256 = manifest.modelSHA256
            whisperKitVersion = manifest.whisperKit.version
            whisperKitCommit = manifest.whisperKit.commit
            sources = manifest.sources
            files = manifest.files
            self.decoding = decoding
            self.shippingModel = shippingModel
        }
    }

    public struct Corpus: Codable, Sendable {
        public var name: String
        public var archiveSHA256: String?
        /// Clips in the specified evaluation set (`fixtures/vctk/starter-clips.txt`).
        public var specifiedClips: Int
        /// Specified clips the archive does not contain; they are not evaluated.
        public var absentClips: [String]
        /// Clips evaluated.
        public var clips: Int
        public var speakers: [String]
        public var textIDs: [String]
        public var audio: String
        public var attribution: String

        public init(name: String, archiveSHA256: String?, specifiedClips: Int, absentClips: [String], clips: Int,
                    speakers: [String], textIDs: [String], audio: String, attribution: String) {
            self.name = name
            self.archiveSHA256 = archiveSHA256
            self.specifiedClips = specifiedClips
            self.absentClips = absentClips
            self.clips = clips
            self.speakers = speakers
            self.textIDs = textIDs
            self.audio = audio
            self.attribution = attribution
        }
    }

    public struct Timing: Codable, Sendable {
        public struct Summary: Codable, Sendable {
            public var count: Int
            public var medianMs: Double?
            public var p90Ms: Double?
            public var maxMs: Double?

            public init(_ values: [Double]) {
                count = values.count
                medianMs = Statistics.median(values)
                p90Ms = Statistics.percentile(values, 90)
                maxMs = values.max()
            }
        }

        public var verifyMs: Double
        public var loadMs: Double
        public var coldASRMs: Double?
        public var warmASR: Summary
        public var clipSeconds: Summary
        public var warmBudgetMs: Double
        /// PASS when the median warm ASR time is within the budget.
        public var budgetOutcome: Outcome

        public init(verifyMs: Double, loadMs: Double, asrMs: [Double], clipSeconds: [Double], budgetMs: Double) {
            self.verifyMs = verifyMs
            self.loadMs = loadMs
            coldASRMs = asrMs.first
            warmASR = Summary(Array(asrMs.dropFirst()))
            self.clipSeconds = Summary(clipSeconds)
            warmBudgetMs = budgetMs
            budgetOutcome = warmASR.medianMs.map { $0 <= budgetMs ? .pass : .fail } ?? .notEvaluated
        }
    }

    public struct Comparator: Codable, Sendable {
        public var name: String
        /// `present`, or `comparator not present` when its assets are not already installed (never downloaded).
        public var status: String
        public var locale: String
        public var coverage: Coverage?
        /// Raw spans (no padding), for information only: the comparator has no gate.
        public var raw: BoundaryStats?

        public init(name: String, status: String, locale: String, coverage: Coverage?, raw: BoundaryStats?) {
            self.name = name
            self.status = status
            self.locale = locale
            self.coverage = coverage
            self.raw = raw
        }
    }

    public struct Verdict: Codable, Sendable {
        public var medianError: Outcome
        public var shareWithinTolerance: Outcome
        public var calibration: Outcome
        public var warmBudget: Outcome
        public var overall: Outcome
    }

    public var suite: String
    public var generatedAt: String
    public var identity: Identity
    public var model: Model
    public var baseline: WordBaseline.Aligner?
    public var corpus: Corpus
    public var gate: TimestampGate
    public var accuracy: AccuracyResult?
    public var timing: Timing
    public var comparator: Comparator
    public var verdict: Verdict
    public var notes: [String]

    public static let suite = "timestamp-feasibility"

    public init(generatedAt: Date, identity: Identity, model: Model, baseline: WordBaseline.Aligner?, corpus: Corpus,
                gate: TimestampGate, accuracy: AccuracyResult?, timing: Timing, comparator: Comparator,
                notes: [String]) {
        suite = Self.suite
        self.generatedAt = generatedAt.formatted(.iso8601)
        self.identity = identity
        self.model = model
        self.baseline = baseline
        self.corpus = corpus
        self.gate = gate
        self.accuracy = accuracy
        self.timing = timing
        self.comparator = comparator
        let accuracyParts = accuracy.map { [$0.medianOutcome, $0.shareOutcome, $0.calibration.outcome] }
            ?? [.notEvaluated, .notEvaluated, .notEvaluated]
        verdict = Verdict(
            medianError: accuracyParts[0], shareWithinTolerance: accuracyParts[1], calibration: accuracyParts[2],
            warmBudget: timing.budgetOutcome, overall: Outcome.combine(accuracyParts + [timing.budgetOutcome]))
        self.notes = notes
    }

    /// `timestamp-feasibility-<first 8 hex of configDigest>`.
    public var baseName: String { "\(Self.suite)-\(identity.configDigest.prefix(8))" }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}

// MARK: - Markdown

extension TimestampReport {
    public func markdown() -> String {
        var md: [String] = []
        md.append("# Timestamp feasibility (spec 03): \(verdict.overall.rawValue)")
        md.append("")
        md.append("Generated \(generatedAt). WhisperKit word timings against \(baseline.map { "\($0.name) \($0.version)" } ?? "no baseline") on \(corpus.clips) \(corpus.name) clips. **No stress claims.**")
        md.append("")
        md.append("## Verdict")
        md.append("")
        md.append("| Line | Bar | Result | Outcome |")
        md.append("|---|---|---|---|")
        md.append("| Median boundary error (padded spans) | ≤ \(ms(gate.medianErrorMaxMs)) | \(ms(accuracy?.padded.medianErrorMs)) | \(verdict.medianError.rawValue) |")
        md.append("| Boundaries within \(ms(gate.toleranceMs)) (padded spans) | ≥ \(pct(gate.minShareWithinTolerance)) | \(pct(accuracy?.padded.shareWithinTolerance)) | \(verdict.shareWithinTolerance.rawValue) |")
        md.append("| Calibration: low-probability bin has more error than high | low > high | \(ms(accuracy?.calibration.low.meanAbsErrorMs)) vs \(ms(accuracy?.calibration.high.meanAbsErrorMs)) | \(verdict.calibration.rawValue) |")
        md.append("| Warm ASR, median over clips | ≤ \(ms(gate.asrWarmBudgetMs)) | \(ms(timing.warmASR.medianMs)) | \(verdict.warmBudget.rawValue) |")
        md.append("| **Overall** | | | **\(verdict.overall.rawValue)** |")
        md.append("")
        if verdict.overall != .pass {
            md.append("Under the bar, or not evaluated: this report goes to CTO. Thresholds are not changed to pass.")
            md.append("")
        }
        md.append("## Identity (plan §6.6)")
        md.append("")
        md.append("- `configDigest`: `\(identity.configDigest)`")
        md.append("- `sourceTreeHash`: `\(identity.sourceTreeHash)`")
        md.append("- Evaluated commit: `\(identity.evaluatedCommit)`; clean tree: \(identity.cleanTree ? "yes" : "**no (not a release report)**")")
        md.append("- `ConfigIdentity`: algorithmVersion \(identity.config.algorithmVersion), thresholdsVersion \(identity.config.thresholdsVersion), contractVersion \(identity.config.contractVersion), asrModelID `\(identity.config.asrModelID)`, pitchTrackerID `\(identity.config.pitchTrackerID)`, voicingID `\(identity.config.voicingID)`")
        md.append("- Corpus manifest hash: `\(identity.corpusManifestHash)`")
        md.append("- Label (baseline) hash: \(identity.labelHash.map { "`\($0)` (`\(identity.labelFile ?? "")`)" } ?? "none")")
        md.append("- Toolchain: \(identity.toolchain.xcode); \(identity.toolchain.swift); macOS \(identity.toolchain.macOS); \(identity.toolchain.hardware)\(identity.toolchain.runnerImage.map { "; runner \($0)" } ?? "")")
        md.append("")
        md.append("Recompute by hand:")
        md.append("")
        md.append("```sh")
        md.append("# sourceTreeHash")
        md.append(identity.sourceTreeRecipe.replacingOccurrences(of: "<commit>", with: identity.evaluatedCommit))
        md.append("# configDigest: SHA-256 of identity.configCanonicalJSON in the JSON report (no trailing newline)")
        md.append(identity.configDigestRecipe.replacingOccurrences(of: "<report>", with: baseName))
        md.append("# corpus manifest hash, in the VCTK cache folder")
        md.append(identity.corpusManifestRecipe)
        md.append("```")
        md.append("")
        md.append("## Model")
        md.append("")
        md.append("- `asrModelID`: `\(model.asrModelID)`; model SHA-256 `\(model.modelSHA256)`")
        md.append("- WhisperKit \(model.whisperKitVersion) (`\(model.whisperKitCommit)`), \(model.decoding)")
        for source in model.sources {
            md.append("- \(source.role): \(source.repo) at `\(source.commit)`\(source.folder.map { ", `\($0)/`" } ?? "") (\(source.license))")
        }
        md.append("- Model that would ship: `\(model.shippingModel)`")
        md.append("")
        md.append("<details><summary>File SHA-256s (\(model.files.count) files)</summary>")
        md.append("")
        for file in model.files { md.append("- `\(file.sha256)` `\(file.path)`") }
        md.append("")
        md.append("</details>")
        md.append("")
        md.append("## Baseline")
        md.append("")
        if let baseline {
            md.append("- \(baseline.name) \(baseline.version); acoustic model `\(baseline.acousticModel)` (SHA-256 `\(baseline.acousticModelSHA256)`); dictionary `\(baseline.dictionary)` (SHA-256 `\(baseline.dictionarySHA256)`)")
            md.append("- Command: `\(baseline.command)`")
        } else {
            md.append("No baseline: the forced aligner could not be run, so accuracy is NOT EVALUATED.")
        }
        md.append("")
        md.append("## Corpus")
        md.append("")
        md.append("- \(corpus.name), archive SHA-256 `\(corpus.archiveSHA256 ?? "not recorded")`; \(corpus.clips) of \(corpus.specifiedClips) specified clips evaluated; voices \(corpus.speakers.joined(separator: ", ")); texts \(corpus.textIDs.joined(separator: ", "))")
        if !corpus.absentClips.isEmpty {
            md.append("- Not in the archive, so not evaluated: \(corpus.absentClips.joined(separator: ", ")) (no substitutes chosen)")
        }
        md.append("- Audio: \(corpus.audio)")
        md.append("- \(corpus.attribution)")
        md.append("")
        if let accuracy {
            md.append("## Accuracy")
            md.append("")
            let c = accuracy.coverage
            md.append("Coverage: \(c.comparable) of \(c.phraseTokens) phrase tokens comparable (\(pct(c.comparableShare))); skipped: \(c.missingFromASROnly) missing from WhisperKit only, \(c.missingFromBaselineOnly) missing from the baseline only, \(c.missingFromBoth) missing from both. n = \(accuracy.padded.boundaries) comparable boundaries (starts and ends).")
            md.append("")
            md.append("| Spans | n | Median error | Within \(ms(gate.toleranceMs)) | Mean error |")
            md.append("|---|---|---|---|---|")
            md.append("| Padded ±\(ms(gate.spanPaddingMs)) (gate) | \(accuracy.padded.boundaries) | \(ms(accuracy.padded.medianErrorMs)) | \(pct(accuracy.padded.shareWithinTolerance)) | \(ms(accuracy.padded.meanErrorMs)) |")
            md.append("| Raw (information) | \(accuracy.raw.boundaries) | \(ms(accuracy.raw.medianErrorMs)) | \(pct(accuracy.raw.shareWithinTolerance)) | \(ms(accuracy.raw.meanErrorMs)) |")
            md.append("")
            md.append("Raw bias (information, ASR minus baseline; negative is early): starts \(signedMs(accuracy.rawMeanSignedStartMs)), ends \(signedMs(accuracy.rawMeanSignedEndMs)) on average.")
            md.append("")
            md.append("### Calibration")
            md.append("")
            md.append("Two bins split at the median word probability over comparable tokens (low: below it; high: at or above it).")
            md.append("")
            md.append("| Spans | Split | Low bin: words, p range, mean error | High bin: words, p range, mean error | Outcome |")
            md.append("|---|---|---|---|---|")
            for (label, cal) in [("Padded (gate)", accuracy.calibration), ("Raw (information)", accuracy.rawCalibration)] {
                md.append("| \(label) | \(num(cal.medianProbability)) | \(bin(cal.low)) | \(bin(cal.high)) | \(cal.outcome.rawValue) |")
            }
            md.append("")
            md.append("### Per voice (information, no gate)")
            md.append("")
            md.append(contentsOf: breakdownTable(accuracy.perVoice, title: "Voice"))
            md.append("")
            md.append("### Per phrase (information, no gate)")
            md.append("")
            md.append(contentsOf: breakdownTable(accuracy.perPhrase, title: "Text"))
            md.append("")
        }
        md.append("## Timing")
        md.append("")
        md.append("- Manifest verification (SHA-256 of every file): \(ms(timing.verifyMs))")
        md.append("- Model load and prewarm: \(ms(timing.loadMs))")
        md.append("- Cold ASR (first clip after load): \(ms(timing.coldASRMs))")
        md.append("- Warm ASR over \(timing.warmASR.count) clips: median \(ms(timing.warmASR.medianMs)), p90 \(ms(timing.warmASR.p90Ms)), max \(ms(timing.warmASR.maxMs))")
        md.append("- Budget: warm ASR ≤ \(ms(timing.warmBudgetMs)) (median): \(timing.budgetOutcome.rawValue)")
        md.append("- Clip length: median \(num(timing.clipSeconds.medianMs)) s, max \(num(timing.clipSeconds.maxMs)) s")
        md.append("")
        md.append("## Comparator: \(comparator.name)")
        md.append("")
        if let raw = comparator.raw, let coverage = comparator.coverage {
            md.append("Status: \(comparator.status) (\(comparator.locale)); information only, no gate. Coverage \(coverage.comparable) of \(coverage.phraseTokens) tokens; raw spans: n \(raw.boundaries), median \(ms(raw.medianErrorMs)), within \(ms(gate.toleranceMs)) \(pct(raw.shareWithinTolerance)), mean \(ms(raw.meanErrorMs)).")
        } else {
            md.append("Status: \(comparator.status) (\(comparator.locale)). Its assets are never downloaded or installed by this tool.")
        }
        md.append("")
        if !notes.isEmpty {
            md.append("## Notes")
            md.append("")
            md.append(contentsOf: notes.map { "- \($0)" })
            md.append("")
        }
        return md.joined(separator: "\n")
    }

    private func breakdownTable(_ rows: [Breakdown], title: String) -> [String] {
        ["| \(title) | n | Median (padded) | Within \(ms(gate.toleranceMs)) (padded) | Median (raw) | Within \(ms(gate.toleranceMs)) (raw) |",
         "|---|---|---|---|---|---|"]
            + rows.map {
                "| \($0.key) | \($0.padded.boundaries) | \(ms($0.padded.medianErrorMs)) | \(pct($0.padded.shareWithinTolerance)) | \(ms($0.raw.medianErrorMs)) | \(pct($0.raw.shareWithinTolerance)) |"
            }
    }

    private func bin(_ bin: CalibrationBin) -> String {
        "\(bin.words), \(num(bin.probabilityMin))–\(num(bin.probabilityMax)), \(ms(bin.meanAbsErrorMs))"
    }
}

private func ms(_ value: Double?) -> String {
    value.map { String(format: "%.1f ms", $0) } ?? "n/a"
}

private func signedMs(_ value: Double?) -> String {
    value.map { String(format: "%+.1f ms", $0) } ?? "n/a"
}

private func pct(_ value: Double?) -> String {
    value.map { String(format: "%.1f%%", $0 * 100) } ?? "n/a"
}

private func num(_ value: Double?) -> String {
    value.map { String(format: "%.3f", $0) } ?? "n/a"
}
