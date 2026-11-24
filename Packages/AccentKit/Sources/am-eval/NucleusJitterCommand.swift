// Spec 25 §5 acceptance 1: `am-eval nucleus-jitter --span <run> --nucleus <run> [--write-report] [--summary <file>]`.
// Reads two `am-timestamps spec11-guard --rows jitter` runs, prints acceptance 1 per set (pooled and per group at ±20 /
// ±40 / ±80 ms with n and Wilson intervals, `.span` beside `.nucleus`, the inconclusive rise per group, the budget and
// the near-edge diagnostic) and ends `Nucleus jitter: MET` or `NOT MET (stop; proposal written)`. With
// `--write-report` it writes docs/agreement/reports/nucleus-jitter-<configDigest8>.{json,md}.

import AMAlignment
import AMCore
import AMEvaluation
import Foundation

func nucleusJitter(_ args: Arguments, root: URL) async throws -> Int32 {
    let decoder = JSONDecoder()
    let span = try decoder.decode(GuardRun.self, from: Data(contentsOf: try args.url("span")))
    let nucleus = try decoder.decode(GuardRun.self, from: Data(contentsOf: try args.url("nucleus")))
    let sets = try NucleusJitter.sets(span: span, nucleus: nucleus)
    let thresholds = Thresholds.current
    let checks = NucleusJitter.gatedChecks(sets, thresholds: thresholds)
    let met = NucleusJitter.met(checks)
    let proposal = met ? nil : try await nucleusJitterProposal(sets, root: root)

    let identity = try reportIdentity(
        root: root, corpusManifestHash: "", labelHash: "", splitPath: "fixtures/splits/vctk.json", splitSeed: nucleus.seed)
    let report = NucleusJitterReport(
        generatedAt: ISO8601DateFormatter().string(from: Date()), identity: identity,
        shippedMeasurement: thresholds.prominence.measurement.name, nucleus: thresholds.nucleus, seed: nucleus.seed,
        asrModelID: nucleus.asrModelID, sets: sets, thresholds: thresholds, proposal: proposal)

    let markdown = nucleusJitterMarkdown(report)
    print(markdown)
    if args.flag("write-report") {
        let directory = root.appendingPathComponent(ReportHashes.reportsPrefix)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try (encoder.encode(report) + Data("\n".utf8))
            .write(to: directory.appendingPathComponent(report.baseName + ".json"))
        try markdown.write(to: directory.appendingPathComponent(report.baseName + ".md"), atomically: true, encoding: .utf8)
        print("nucleus-jitter: wrote \(ReportHashes.reportsPrefix)\(report.baseName).{json,md}"
              + (identity.cleanTree ? "" : " (dirty tree: not a report of record)"))
    }
    if let path = args.value("summary") {
        try nucleusJitterSummary(report).write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        print("nucleus-jitter: summary → \(path)")
    }
    print(met ? "Nucleus jitter: MET" : "Nucleus jitter: NOT MET (stop; proposal written)")
    return met ? 0 : 2
}

// MARK: - Text

private func pct(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0 * 100) } ?? "–" }

private func wilson(_ k: Int, _ n: Int) -> String {
    guard n > 0 else { return "–" }
    let i = Statistics.wilson(successes: k, n: n)
    return String(format: "[%.1f, %.1f]", i.lower * 100, i.upper * 100)
}

/// One row per group at one radius: n, flips, rate, Wilson, inconclusive oracle → jittered and the rise.
private func groupRows(_ c: GuardRun.Comparison?) -> [(label: String, n: Int, flips: Int, rate: String, interval: String,
                                                      inconclusive: String)] {
    guard let c, c.evaluated else { return [] }
    let pooled = (label: "pooled", n: c.words, flips: c.differing,
                  rate: pct(Double(c.differing) / Double(c.words)), interval: wilson(c.differing, c.words),
                  inconclusive: rise(c.oracleInconclusive, c.candidateInconclusive, c.words))
    return [pooled] + c.bySyllables.map { b in
        (label: b.bucket, n: b.words, flips: b.differing,
         rate: b.words == 0 ? "–" : pct(Double(b.differing) / Double(b.words)), interval: wilson(b.differing, b.words),
         inconclusive: rise(b.oracleInconclusive, b.candidateInconclusive, b.words))
    }
}

private func rise(_ oracle: Int, _ candidate: Int, _ n: Int) -> String {
    guard n > 0 else { return "–" }
    let o = Double(oracle) / Double(n), k = Double(candidate) / Double(n)
    return String(format: "%.1f%% → %.1f%% (%+.1f pt)", o * 100, k * 100, (k - o) * 100)
}

/// The ±40 ms table of one set: groups down, `.span` and `.nucleus` across.
private func table40(_ set: NucleusJitter.Set) -> String {
    let s = groupRows(set.comparison(NucleusJitter.gatedID, measurement: .span))
    let n = groupRows(set.comparison(NucleusJitter.gatedID, measurement: .nucleus))
    var out = "| Group | n | .span flips | .span Wilson 95% | .nucleus flips | .nucleus Wilson 95% | .nucleus inconclusive (oracle → ±40) |\n"
    out += "|---|---|---|---|---|---|---|\n"
    for (index, row) in n.enumerated() {
        let before = index < s.count ? s[index] : nil
        out += "| \(row.label) | \(row.n) | \(before.map { "\($0.flips) (\($0.rate))" } ?? "–") | \(before?.interval ?? "–") "
            + "| \(row.flips) (\(row.rate)) | \(row.interval) | \(row.inconclusive) |\n"
    }
    return out
}

func nucleusJitterMarkdown(_ report: NucleusJitterReport) -> String {
    let id = report.identity
    var out = "# Nucleus jitter (spec 25 acceptance 1): \(report.outcome)\n\n"
    out += "Spec 11 §4b's oracle-boundary jitter test, `.nucleus` measurement with `.span` beside it (the before column). "
        + "Oracle word boundaries: TTS markers on the synthetic set, MFA on the held-out VCTK speakers. Both edges of "
        + "every comparable word moved by an independent uniform offset in ±R (seed \(report.seed), the VCTK split "
        + "manifest's fold seed), clamped to the neighbours' oracle edges and the clip. Flips are counted against the "
        + "unjittered oracle, anything↔inconclusive included. Pass: ≤ 2% flips at ±40 ms on each set, pooled and in "
        + "every multi-syllable group (2, 3, 4+) with n ≥ 30; per-group inconclusive rise ≤ 2 points (2 and 3, "
        + "n ≥ 30); jittered inconclusive share ≤ 10%. ±20 and ±80 ms are reported only.\n\n"
    out += "| Identity | |\n|---|---|\n"
    out += "| configDigest | `\(id.configDigest)` |\n| thresholdsVersion | \(id.config.thresholdsVersion) |\n"
    out += "| algorithmVersion | \(id.config.algorithmVersion) |\n| evaluatedCommit | `\(id.evaluatedCommit)` |\n"
    out += "| sourceTreeHash | `\(id.sourceTreeHash)` |\n| cleanTree | \(id.cleanTree) |\n"
    out += "| generatedAt | \(report.generatedAt) |\n| shipped measurement | `\(report.shippedMeasurement)` |\n"
    let p = report.nucleus
    out += "| nucleus parameters (fixed, CTO markup 4) | minPeakDBFS \(p.minPeakDBFS), minProminenceDB \(p.minProminenceDB), "
        + "minSeparationMs \(p.minSeparationMs), regionDropDB \(p.regionDropDB), skipCostMs \(p.skipCostMs), "
        + "windowMs \(p.windowMs) |\n"
    out += "| ASR (synthetic set: probabilities and matching only) | \(report.asrModelID ?? "–") |\n\n"

    out += "## Acceptance 1 checks (`.nucleus`)\n\n"
    for check in report.checks { out += "- \(check.line)\n" }
    out += "\n**Nucleus jitter: \(report.met ? "MET" : "NOT MET (stop; proposal written)")**\n\n"

    for set in report.sets {
        out += "## \(set.set) (oracle: \(set.oracle), \(set.clips) clips)\n\n### ±40 ms\n\n" + table40(set) + "\n"
        for id in NucleusJitter.reportedIDs {
            out += "### ±\(id.dropFirst(7)) ms (reported)\n\n"
            out += "| Group | n | .span flips | .nucleus flips |\n|---|---|---|---|\n"
            let s = groupRows(set.comparison(id, measurement: .span))
            for (index, row) in groupRows(set.comparison(id, measurement: .nucleus)).enumerated() {
                let before = index < s.count ? "\(s[index].flips) (\(s[index].rate)) \(s[index].interval)" : "–"
                out += "| \(row.label) | \(row.n) | \(before) | \(row.flips) (\(row.rate)) \(row.interval) |\n"
            }
            out += "\n"
        }
        out += "### Near-edge diagnostic at ±40 ms (CTO markup 3)\n\n"
        out += "A word is near an edge when a detected nucleus peak lies within 40 ms of either of its unjittered "
            + "oracle edges.\n\n| Measurement | Near-edge words | Their flips | Other words | Their flips |\n|---|---|---|---|---|\n"
        for measurement in SyllableMeasurement.allCases {
            guard let e = set.comparison(NucleusJitter.gatedID, measurement: measurement)?.nearEdge else { continue }
            out += "| .\(measurement.name) | \(e.nearWords) | \(e.nearFlips) (\(pct(e.nearWords == 0 ? nil : Double(e.nearFlips) / Double(e.nearWords)))) "
                + "| \(e.farWords) | \(e.farFlips) (\(pct(e.farWords == 0 ? nil : Double(e.farFlips) / Double(e.farWords)))) |\n"
        }
        if let buckets = set.comparison(NucleusJitter.gatedID, measurement: .nucleus)?.nucleusOracle {
            out += "\n### Nucleus diagnostics on the oracle boundaries (reported)\n\n"
            out += "| Group | n | P = N_w | Nucleus-short |\n|---|---|---|---|\n"
            for b in buckets {
                out += "| \(b.bucket) | \(b.words) | \(b.countMatch) (\(pct(b.words == 0 ? nil : Double(b.countMatch) / Double(b.words)))) "
                    + "| \(b.short) (\(pct(b.words == 0 ? nil : Double(b.short) / Double(b.words)))) |\n"
            }
        }
        out += "\n"
    }
    out += "## `.span` under the same conditions (before column, reported)\n\n"
    for check in report.spanChecks { out += "- \(check.line)\n" }
    out += "\n## ±20 and ±80 ms on `.nucleus` (reported)\n\n"
    for check in report.reported { out += "- \(check.line)\n" }

    if let proposal = report.proposal { out += "\n" + proposalMarkdown(proposal) }
    return out
}

private func proposalMarkdown(_ proposal: NucleusJitterProposal) -> String {
    var out = "## Proposal: no per-word stress-placement verdicts on 2–3-syllable words\n\n"
    out += "Spec 25 §6, for CTO to route (CTO, then Raph via CPO). Nothing is cut in code, and no parameter or "
        + "threshold was changed (CTO markup 4).\n\n"
    out += "### ±40 ms per group: own flip rate and share of the pooled flips\n\n"
    out += "| Set | Measurement | Group | n | Flips | Own flip rate | Wilson 95% | Share of pooled flips |\n|---|---|---|---|---|---|---|---|\n"
    for g in proposal.groups {
        out += "| \(g.set) | .\(g.measurement) | \(g.group) | \(g.words) | \(g.flips) | \(pct(g.rate)) | "
            + "\(g.interval.map { String(format: "[%.1f, %.1f]", $0.lower * 100, $0.upper * 100) } ?? "–") | \(pct(g.shareOfPooledFlips)) |\n"
    }
    out += "\n### Pooled, and without 2–3-syllable placement verdicts\n\n"
    out += "| Set | Measurement | Pooled n | Pooled flips | Pooled rate | Without 2–3: n | Flips | Rate |\n|---|---|---|---|---|---|---|---|\n"
    for p in proposal.pooled {
        out += "| \(p.set) | .\(p.measurement) | \(p.words) | \(p.flips) | \(pct(p.rate)) | \(p.wordsWithoutCut) | "
            + "\(p.flipsWithoutCut) | \(pct(p.rateWithoutCut)) |\n"
    }
    out += "\n### What the cut removes\n\n"
    for line in proposal.removes { out += "- \(line)\n" }
    out += "\n### Positive-set and L2 rows with and without the cut\n\n"
    for line in proposal.rows { out += "- \(line)\n" }
    return out
}

/// `_cache-25/logs/acceptance1.txt`: the outcome line, then the ±40 ms pooled and per-group table for both sets and
/// both measurements.
func nucleusJitterSummary(_ report: NucleusJitterReport) -> String {
    var out = "ACCEPTANCE 1: \(report.met ? "MET" : "FAIL")\n"
    out += "±40 ms flips vs the unjittered oracle (n, flips, rate, Wilson 95%), configDigest \(report.identity.configDigest.prefix(8))\n"
    for set in report.sets {
        for measurement in SyllableMeasurement.allCases {
            out += "\n\(set.set) .\(measurement.name)\n"
            for row in groupRows(set.comparison(NucleusJitter.gatedID, measurement: measurement)) {
                out += "  \(row.label.padding(toLength: 7, withPad: " ", startingAt: 0)) n=\(row.n) flips=\(row.flips) "
                    + "\(row.rate) \(row.interval)  inconclusive \(row.inconclusive)\n"
            }
        }
    }
    out += "\nGated checks (.nucleus):\n"
    for check in report.checks { out += "  \(check.line)\n" }
    return out
}

// MARK: - §6 proposal inputs

/// What the cut would remove: placement-applicable starter words (≥ 2 dictionary syllables) that have 2–3 syllables,
/// the phrases they're in, and the L2 recall words (the 134) with 2–3 syllables; then the positive-set and L2 rows
/// with and without the cut (`scopeCutRows`).
func nucleusJitterProposal(_ sets: [NucleusJitter.Set], root: URL) async throws -> NucleusJitterProposal {
    var removes: [String] = []
    // Starter phrases (spec 15).
    struct Starter: Decodable {
        struct Phrase: Decodable { let text: String }
        let phrases: [String: Phrase]
    }
    let starter = try JSONDecoder().decode(
        Starter.self, from: Data(contentsOf: root.appendingPathComponent("fixtures/starter/phrases.json")))
    let selector = try PronunciationSelector.bundled()
    let minimum = Int(Thresholds.current.applicability.placementMinSyllables)
    var applicable = 0, cut = 0
    var affected: [String] = []
    for (id, phrase) in starter.phrases.sorted(by: { $0.key < $1.key }) {
        let words = selector.expectedPhrase(for: PhraseText(text: phrase.text, origin: .starter)).words
        let placement = words.filter { ($0.pronunciation?.syllables.count ?? 0) >= minimum }
        let removed = placement.filter { (2...3).contains($0.pronunciation!.syllables.count) }
        applicable += placement.count
        cut += removed.count
        if !removed.isEmpty {
            affected.append("\(id) (\(removed.map { "\($0.text) \($0.pronunciation!.syllables.count)" }.joined(separator: ", ")))")
        }
    }
    removes.append(String(format: "Starter phrases (spec 15, %d phrases): %d of %d placement-applicable words (≥ %d syllables) have 2–3 syllables (%.1f%%); %d phrases affected.",
                          starter.phrases.count, cut, applicable, minimum,
                          applicable == 0 ? 0 : Double(cut) / Double(applicable) * 100, affected.count))
    removes.append("Affected starter phrases and words (word, syllables): " + affected.joined(separator: "; ") + ".")
    // L2 recall words (the 134).
    let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
    let recall = SpeechOceanSets(labels: labels).recall
    let short = recall.filter { (2...3).contains($0.syllableCount) }
    removes.append(String(format: "L2 recall set (speechocean762 stress-wrong, intelligible, polysyllabic): %d of %d words have 2–3 syllables (%.1f%%): the recall the claim would lose.",
                          short.count, recall.count, recall.isEmpty ? 0 : Double(short.count) / Double(recall.count) * 100))
    let rows = try await scopeCutRows(root: root)
    return NucleusJitterProposal(sets: sets, removes: removes, rows: rows)
}
