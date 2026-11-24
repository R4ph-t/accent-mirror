// Spec 25 §5 / spec 26 §4 acceptance 1: `am-eval nucleus-jitter --span <run> --nucleus <run>
// [--spec25-recomputed <run>] [--held-out-detection <json>] [--write-report] [--summary <file>]`. Reads the
// `am-timestamps spec11-guard --rows jitter` runs, prints acceptance 1 per set (pooled and per group at ±20 / ±40 /
// ±80 ms with n and Wilson intervals; `.span`, spec 25's `.nucleus` (acb3910a) and spec 26's `.nucleus`; the
// inconclusive rise per group; the budget on the unjittered and the ±40 ms run; `assignmentAmbiguous`; the near-edge
// diagnostic; spec 26 §5's diagnostics) and ends `Nucleus jitter: MET` or `NOT MET (stop; scope proposal written)`,
// with §6's scope proposal on a failure. With `--write-report` it writes
// docs/agreement/reports/nucleus-jitter-<configDigest8>.{json,md}.

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

    let identity = try reportIdentity(
        root: root, corpusManifestHash: "", labelHash: "", splitPath: "fixtures/splits/vctk.json", splitSeed: nucleus.seed)
    var report = NucleusJitterReport(
        generatedAt: ISO8601DateFormatter().string(from: Date()), identity: identity,
        shippedMeasurement: thresholds.prominence.measurement.name, nucleus: thresholds.nucleus, seed: nucleus.seed,
        asrModelID: nucleus.asrModelID, sets: sets, thresholds: thresholds, proposal: nil)
    // Spec 26: spec 25's committed `.nucleus` results (acb3910a) as a before column, and its recomputed run (§5).
    let spec25URL = root.appendingPathComponent(ReportHashes.reportsPrefix + "nucleus-jitter-acb3910a.json")
    if let spec25 = try? decoder.decode(NucleusJitterReport.self, from: Data(contentsOf: spec25URL)) {
        report.spec25 = Dictionary(uniqueKeysWithValues: spec25.sets.map { ($0.set, $0.nucleus) })
    }
    if let path = args.value("spec25-recomputed") {
        let run = try decoder.decode(GuardRun.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        report.spec25Recomputed = Dictionary(uniqueKeysWithValues: run.sets.map { ($0.set, $0.comparisons) })
    }
    if let path = args.value("held-out-detection") {
        report.heldOutDetection = try decoder.decode(HeldOutDetection.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }
    if !met { report.scope = try await nucleusScope26(sets, root: root) }

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
    print(met ? "Nucleus jitter: MET" : "Nucleus jitter: NOT MET (stop; scope proposal written)")
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

/// The ±40 ms table of one set: groups down; `.span`, spec 25's `.nucleus` (acb3910a) and spec 26's across.
private func table40v26(_ report: NucleusJitterReport, _ set: NucleusJitter.Set) -> String {
    let s = groupRows(set.comparison(NucleusJitter.gatedID, measurement: .span))
    let p = groupRows(report.spec25?[set.set]?.first { $0.id == NucleusJitter.gatedID })
    let n = groupRows(set.comparison(NucleusJitter.gatedID, measurement: .nucleus))
    var out = "| Group | n | .span flips | spec 25 .nucleus (acb3910a) flips | spec 26 .nucleus flips | Wilson 95% | inconclusive (unjittered → ±40) |\n"
    out += "|---|---|---|---|---|---|---|\n"
    for (index, row) in n.enumerated() {
        let before = index < s.count ? "\(s[index].flips) (\(s[index].rate))" : "–"
        let mid = index < p.count ? "\(p[index].flips)/\(p[index].n) (\(p[index].rate))" : "–"
        out += "| \(row.label) | \(row.n) | \(before) | \(mid) | \(row.flips) (\(row.rate)) | \(row.interval) | \(row.inconclusive) |\n"
    }
    return out
}

private func rate(_ k: Int, _ n: Int) -> String {
    n == 0 ? "–" : String(format: "%d/%d (%.1f%%, Wilson %@)", k, n, Double(k) / Double(n) * 100, wilson(k, n))
}

/// `assignmentAmbiguous` per group, unjittered and ±40 ms: count, rate, Wilson, share of the inconclusive words.
private func ambiguityTable(_ c: GuardRun.Comparison) -> String {
    guard let n = c.nucleus26 else { return "NOT EVALUATED (no spec 26 fields)\n" }
    var out = "| Group | n | unjittered ambiguous | share of unjittered inconclusive | ±40 ms ambiguous | share of ±40 ms inconclusive |\n|---|---|---|---|---|---|\n"
    let buckets = Dictionary(uniqueKeysWithValues: c.bySyllables.map { ($0.bucket, $0) })
    for g in [n.pooled] + n.groups {
        let oi = g.bucket == "pooled" ? c.oracleInconclusive : buckets[g.bucket]?.oracleInconclusive ?? 0
        let ci = g.bucket == "pooled" ? c.candidateInconclusive : buckets[g.bucket]?.candidateInconclusive ?? 0
        out += "| \(g.bucket) | \(g.words) | \(rate(g.oracleAmbiguous, g.words)) | \(pct(oi == 0 ? nil : Double(g.oracleAmbiguous) / Double(oi))) "
            + "| \(rate(g.candidateAmbiguous, g.words)) | \(pct(ci == 0 ? nil : Double(g.candidateAmbiguous) / Double(ci))) |\n"
    }
    return out
}

/// Inconclusive words by reason, per group, both runs; and the nucleus-short rate and counts' sources.
private func reasonTable(_ c: GuardRun.Comparison) -> String {
    guard let n = c.nucleus26 else { return "" }
    var out = "| Group | n | unjittered: short / ambiguous / low | ±40 ms: short / ambiguous / low | nucleus-short rate (unjittered) | P ∈ N_w (unjittered) | reduced form / CMUdict alternate counts |\n|---|---|---|---|---|---|---|\n"
    for g in [n.pooled] + n.groups {
        out += "| \(g.bucket) | \(g.words) | \(g.oracleShort) / \(g.oracleAmbiguous) / \(g.oracleLow) | \(g.candidateShort) / \(g.candidateAmbiguous) / \(g.candidateLow) "
            + "| \(pct(g.words == 0 ? nil : Double(g.oracleShort) / Double(g.words))) | \(rate(g.oracleCountMatch, g.words)) "
            + "| \(g.reducedForm) / \(g.cmudictAlternate) of \(g.words - g.oracleShort) non-short (\(pct(g.words - g.oracleShort == 0 ? nil : Double(g.reducedForm + g.cmudictAlternate) / Double(g.words - g.oracleShort)))) |\n"
    }
    return out
}

/// §5's flip breakdown of one comparison.
private func breakdown(_ label: String, _ c: GuardRun.Comparison?) -> String {
    guard let c, let n = c.nucleus26 else { return "- \(label): NOT EVALUATED (no spec 26 fields in the run)\n" }
    var out = "- \(label): \(c.differing) flips of \(c.words) words.\n"
    out += "  - transition: " + n.transitions.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + "\n"
    out += "  - the word's assigned nuclei moved under jitter: \(n.nucleiMoved); the same nuclei: \(n.sameNuclei) ("
        + n.sameNucleiBy.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ")\n"
    out += "  - exposure changed under jitter: \(n.exposureChangedWords) words, \(n.exposureChangedFlips) of them flipped "
        + "(the gate's verdict reads raw d and e, so exposure alone never flips it)\n"
    return out
}

private func markerCheck(_ c: GuardRun.Comparison?) -> String {
    guard let m = c?.nucleus26?.markers, m.words > 0 else { return "NOT EVALUATED (no marker/MFA pairs in the run)\n" }
    func q(_ v: [Double], _ p: Double) -> String { v.isEmpty ? "–" : String(format: "%.0f ms", Statistics.quantile(v, p)) }
    func over(_ v: [Double]) -> String { pct(v.isEmpty ? nil : Double(v.count { $0 > 40 }) / Double(v.count)) }
    var out = "TTS markers vs MFA on the same synthetic audio, \(m.words) words (markers have 512-sample, about 23 ms, resolution):\n\n"
    out += "| Edge | median abs Δ | p90 abs Δ | share over 40 ms |\n|---|---|---|---|\n"
    out += "| start | \(q(m.startAbsMs, 0.5)) | \(q(m.startAbsMs, 0.9)) | \(over(m.startAbsMs)) |\n"
    out += "| end | \(q(m.endAbsMs, 0.5)) | \(q(m.endAbsMs, 0.9)) | \(over(m.endAbsMs)) |\n\n"
    out += "±40 ms flips: words whose marker and MFA edges agree within 20 ms on both sides \(rate(m.agreeFlips, m.agreeWords)); "
        + "the rest \(rate(m.restFlips, m.restWords)).\n"
    return out
}

func nucleusJitterMarkdown(_ report: NucleusJitterReport) -> String {
    let id = report.identity
    var out = "# Nucleus jitter (spec 26 acceptance 1 = spec 25 §5.1, budget on both populations): \(report.outcome)\n\n"
    out += "Spec 11 §4b's oracle-boundary jitter test on `.nucleus` at spec 26's grid-chosen nucleus values and main's "
        + "verdict thresholds; `.span` and spec 25's `.nucleus` (report acb3910a) are the before columns. Oracle word "
        + "boundaries: TTS markers on the synthetic set, MFA on the held-out VCTK speakers. Both edges of every comparable "
        + "word moved by an independent uniform offset in ±R (seed \(report.seed), the VCTK split manifest's fold seed), "
        + "clamped to the neighbours' oracle edges and the clip. Flips are counted against the unjittered oracle, "
        + "anything↔inconclusive included. Pass: ≤ 2% flips at ±40 ms on each set, pooled and in every multi-syllable "
        + "group (2, 3, 4+) with n ≥ 30; per-group inconclusive rise ≤ 2 points (2 and 3, n ≥ 30); the 10% inconclusive "
        + "budget on BOTH the unjittered oracle run and the ±40 ms run (CTO markup 4). ±20 and ±80 ms are reported only.\n\n"
    out += "| Identity | |\n|---|---|\n"
    out += "| configDigest | `\(id.configDigest)` |\n| thresholdsVersion | \(id.config.thresholdsVersion) |\n"
    out += "| algorithmVersion | \(id.config.algorithmVersion) |\n| evaluatedCommit | `\(id.evaluatedCommit)` |\n"
    out += "| sourceTreeHash | `\(id.sourceTreeHash)` |\n| cleanTree | \(id.cleanTree) |\n"
    out += "| generatedAt | \(report.generatedAt) |\n| shipped measurement | `\(report.shippedMeasurement)` |\n"
    let p = report.nucleus
    out += "| nucleus values (spec 26 grid choice; others spec 25's) | minPeakDBFS \(p.minPeakDBFS), minProminenceDB \(p.minProminenceDB), "
        + "minSeparationMs \(p.minSeparationMs), regionDropDB \(p.regionDropDB), voicedWithinMs \(p.voicedWithinMs), "
        + "skipCostMs \(p.skipCostMs), windowMs \(p.windowMs), ambiguityEdgeMs \(p.ambiguityEdgeMs) |\n"
    out += "| ASR (synthetic set: probabilities and matching only) | \(report.asrModelID ?? "–") |\n\n"

    out += "## Acceptance 1 checks (spec 26 `.nucleus`)\n\n"
    for check in report.checks { out += "- \(check.line)\n" }
    out += "\n**Nucleus jitter: \(report.met ? "MET" : "NOT MET (stop; scope proposal written)")**\n\n"

    for set in report.sets {
        let c40 = set.comparison(NucleusJitter.gatedID, measurement: .nucleus)
        out += "## \(set.set) (oracle: \(set.oracle), \(set.clips) clips)\n\n### ±40 ms\n\n" + table40v26(report, set) + "\n"
        if let c40, c40.evaluated {
            out += "Budget populations: unjittered oracle inconclusive \(rate(c40.oracleInconclusive, c40.words)); ±40 ms "
                + "jittered inconclusive \(rate(c40.candidateInconclusive, c40.words)) (limit 10% each).\n\n"
            out += "### assignmentAmbiguous (unjittered and ±40 ms)\n\n" + ambiguityTable(c40) + "\n"
            out += "### Inconclusive by reason, nucleus-short rate and counts' sources\n\n" + reasonTable(c40) + "\n"
        }
        for rid in NucleusJitter.reportedIDs {
            out += "### ±\(rid.dropFirst(7)) ms (reported)\n\n"
            out += "| Group | n | .span flips | spec 26 .nucleus flips |\n|---|---|---|---|\n"
            let s = groupRows(set.comparison(rid, measurement: .span))
            for (index, row) in groupRows(set.comparison(rid, measurement: .nucleus)).enumerated() {
                let before = index < s.count ? "\(s[index].flips) (\(s[index].rate)) \(s[index].interval)" : "–"
                out += "| \(row.label) | \(row.n) | \(before) | \(row.flips) (\(row.rate)) \(row.interval) |\n"
            }
            out += "\n"
        }
        out += "### Near-edge diagnostic at ±40 ms (CTO markup 3)\n\n"
        out += "A word is near an edge when a detected nucleus peak lies within 40 ms of either of its unjittered "
            + "oracle edges.\n\n| Run | Near-edge words | Their flips | Other words | Their flips |\n|---|---|---|---|---|\n"
        let near: [(String, GuardRun.NearEdge?)] = [
            (".span", set.comparison(NucleusJitter.gatedID, measurement: .span)?.nearEdge),
            ("spec 25 .nucleus (acb3910a)", report.spec25?[set.set]?.first { $0.id == NucleusJitter.gatedID }?.nearEdge),
            ("spec 26 .nucleus", c40?.nearEdge),
        ]
        for (label, e) in near {
            guard let e else { continue }
            out += "| \(label) | \(e.nearWords) | \(rate(e.nearFlips, e.nearWords)) | \(e.farWords) | \(rate(e.farFlips, e.farWords)) |\n"
        }
        out += "\n"
    }

    out += "## §5 diagnostics (reported)\n\n### Flip breakdown at ±40 ms\n\n"
    out += "Transition types read the gate's verdict: a decided verdict is `close` when its longest and loudest syllable "
        + "are the context pronunciation's primary, else `feedback`; `inconclusive:<reason>` names the inconclusive side's "
        + "reason (the jittered side's when both are). \"The same nuclei\" splits by what changed instead.\n\n"
    for set in report.sets {
        let recomputed = report.spec25Recomputed?[set.set]?.first { $0.id == NucleusJitter.gatedID }
        out += breakdown("\(set.set), spec 25 `.nucleus` recomputed by this harness (spec 25's values, N_w the context count, no ambiguity)", recomputed)
        out += breakdown("\(set.set), spec 26 `.nucleus`", set.comparison(NucleusJitter.gatedID, measurement: .nucleus))
    }
    if let set = report.sets.first(where: { $0.set == "synthetic" }) {
        out += "\n### TTS-marker check (synthetic set, spec 26 `.nucleus` at ±40 ms)\n\n"
        out += markerCheck(set.comparison(NucleusJitter.gatedID, measurement: .nucleus))
        if let r = report.spec25Recomputed?["synthetic"]?.first(where: { $0.id == NucleusJitter.gatedID }),
           let m = r.nucleus26?.markers {
            out += "\nUnder spec 25's `.nucleus` (recomputed): agreeing words \(rate(m.agreeFlips, m.agreeWords)), the rest \(rate(m.restFlips, m.restWords)).\n"
        }
        out += "\nThe synthetic set is never dropped and its gate stays as written.\n"
    }
    if let h = report.heldOutDetection {
        out += "\n### Detection on held-out VCTK (never used to choose)\n\n"
        out += "At the head's nucleus values, \(h.speakers) held-out speakers, \(h.clips) clips, MFA words and phones: "
            + "count-match (P ∈ N_w, not short) \(rate(h.countMatched, h.words)); vowel-inside share "
            + "\(rate(h.peaksInsideVowel, h.assignedPeaks)); median region–vowel IoU \(String(format: "%.3f", h.medianIoU)).\n"
    }

    out += "\n## `.span` under the same conditions (before column, reported)\n\n"
    for check in report.spanChecks { out += "- \(check.line)\n" }
    out += "\n## ±20 and ±80 ms on `.nucleus` (reported)\n\n"
    for check in report.reported { out += "- \(check.line)\n" }

    if let scope = report.scope {
        out += "\n## §6 Scope proposal (acceptance 1 failed; no further fallback)\n\n"
        out += "Spec 26 §6, for CTO to route to Raph via CPO. Nothing is cut in code, and no parameter outside the grid "
            + "and no threshold was changed after the frozen choice. Every number below is a suite's output with the cut "
            + "applied after the fact.\n\n"
        for shape in scope.shapes {
            out += "### \(shape.name)\n\n"
            for line in shape.lines { out += "- \(line)\n" }
            out += "\n"
        }
    }
    return out
}

/// `_cache-26/logs/acceptance1.txt`: the outcome line, then the ±40 ms tables, both budgets, the ambiguity counts and
/// the synthetic diagnostics.
func nucleusJitterSummary(_ report: NucleusJitterReport) -> String {
    var out = "ACCEPTANCE 1: \(report.met ? "MET" : "FAIL")\n"
    out += "Spec 26, configDigest \(report.identity.configDigest.prefix(8)), commit \(report.identity.evaluatedCommit.prefix(12)); "
        + "±40 ms flips vs the unjittered oracle (n, flips, rate, Wilson 95%, inconclusive unjittered → ±40)\n"
    for set in report.sets {
        out += "\n\(set.set)\n"
        let columns: [(String, GuardRun.Comparison?)] = [
            (".span", set.comparison(NucleusJitter.gatedID, measurement: .span)),
            ("spec 25 .nucleus (acb3910a)", report.spec25?[set.set]?.first { $0.id == NucleusJitter.gatedID }),
            ("spec 26 .nucleus", set.comparison(NucleusJitter.gatedID, measurement: .nucleus)),
        ]
        for (label, c) in columns {
            out += "  \(label)\n"
            for row in groupRows(c) {
                out += "    \(row.label.padding(toLength: 7, withPad: " ", startingAt: 0)) n=\(row.n) flips=\(row.flips) "
                    + "\(row.rate) \(row.interval)  inconclusive \(row.inconclusive)\n"
            }
        }
        if let c = set.comparison(NucleusJitter.gatedID, measurement: .nucleus), c.evaluated {
            out += "  budget populations (limit 10%): unjittered \(rate(c.oracleInconclusive, c.words)); ±40 ms \(rate(c.candidateInconclusive, c.words))\n"
            if let n = c.nucleus26 {
                out += "  assignmentAmbiguous (unjittered / ±40 ms):\n"
                for g in [n.pooled] + n.groups {
                    out += "    \(g.bucket.padding(toLength: 7, withPad: " ", startingAt: 0)) n=\(g.words) \(rate(g.oracleAmbiguous, g.words)) / \(rate(g.candidateAmbiguous, g.words))\n"
                }
                out += "  inconclusive reasons, unjittered short/ambiguous/low \(n.pooled.oracleShort)/\(n.pooled.oracleAmbiguous)/\(n.pooled.oracleLow); "
                    + "±40 ms \(n.pooled.candidateShort)/\(n.pooled.candidateAmbiguous)/\(n.pooled.candidateLow)\n"
            }
        }
    }
    out += "\nGated checks (spec 26 .nucleus):\n"
    for check in report.checks { out += "  \(check.line)\n" }
    if let set = report.sets.first(where: { $0.set == "synthetic" }) {
        out += "\nSynthetic diagnostics (§5):\n"
        out += breakdown("spec 25 .nucleus recomputed", report.spec25Recomputed?["synthetic"]?.first { $0.id == NucleusJitter.gatedID })
        out += breakdown("spec 26 .nucleus", set.comparison(NucleusJitter.gatedID, measurement: .nucleus))
        out += markerCheck(set.comparison(NucleusJitter.gatedID, measurement: .nucleus))
    }
    if let scope = report.scope {
        out += "\n§6 scope proposal (shapes):\n"
        for shape in scope.shapes {
            out += "  \(shape.name)\n"
            for line in shape.lines { out += "    - \(line)\n" }
        }
    }
    return out
}
