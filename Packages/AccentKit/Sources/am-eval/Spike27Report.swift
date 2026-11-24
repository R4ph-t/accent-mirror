// Spec 27 §5: docs/agreement/reports/spike27-<configDigest8>.{json,md} with spec 02's identity header, and the plain
// summary in the build's logs/result.txt. The last line is `Spike 27: GO`, `Spike 27: NO-GO` or
// `Spike 27: NO-GO (oracle-only)`. GO is judged on the runtime source; NOT EVALUATED is never a pass.

import AMCore
import AMEvaluation
import AMSpike27
import Foundation

struct Spike27Verdict: Codable {
    struct Claim: Codable {
        let name: String
        let status: GateStatus
        let lines: [String]
    }
    let wordStress: [String: Claim]
    let phrase: [String: Claim]
    let spikeLine: String
    let partialLine: String?
}

struct Spike27Report: Encodable {
    let suite = "spike27"
    let generatedAt: String
    let identity: ReportIdentity
    let nucleusReport = "nucleus-count-69675122"
    let listen: String
    let listenFiles: [String]
    let training: TrainingFile
    let evaluation: EvaluationFile
    let verdict: Spike27Verdict

    var baseName: String { "spike27-\(identity.configDigest.prefix(8))" }
}

enum SpikeVerdict {
    /// Every gate line of a word-stress claim (arm × source) and its status: MET only when every gated line is MET.
    static func wordStress(_ e: EvaluationFile, training: TrainingFile, arm: Arm, source: BoundarySource) -> Spike27Verdict.Claim {
        let a = arm.rawValue
        var lines: [GateLine] = []
        func pick(_ gate: String, _ src: String, _ population: String) {
            lines += e.gates.filter { $0.arm == a && $0.gate.hasPrefix(gate) && $0.source == src && $0.population == population && $0.status != .reported }
        }
        let s = source.rawValue
        pick("gate 1 false flags", s, "vctk-held-out")
        pick("gate 3 jitter", s, "vctk-held-out")
        pick("gate 3 jitter", s, "synthetic (TTS)")
        if source == .runtime {
            pick("gate 1 false flags", "runtime", "l2-clean-1400")
            pick("gate 1 false flags", "runtime", "speechocean762 correctly stressed")
            pick("gate 2", "runtime (known text)", "l2-134")
        } else {
            lines += e.gates.filter { $0.arm == a && $0.source == s && $0.gate.hasPrefix("gates 1–2 (L2)") }
        }
        let auc = training.arms.first { $0.arm == arm }?.artefactAUC
        let aucMet = auc.map { $0 <= 0.6 + 1e-12 } ?? false
        var texts = lines.map(\.text)
        texts.append(String(format: "artefact control (CTO markup 4): processed-vs-raw AUC %@ (≤ 0.6): %@",
                            auc.map { String(format: "%.3f", $0) } ?? "–", aucMet ? "MET" : "NOT MET"))
        let met = !lines.isEmpty && lines.allSatisfy { $0.status == .met } && aucMet
        return .init(name: "word stress, arm \(a), \(s)", status: met ? .met : .notMet, lines: texts)
    }

    static func phrase(_ e: EvaluationFile, metric: String, source: BoundarySource) -> Spike27Verdict.Claim {
        let lines = e.phrase.filter { $0.metric == metric && $0.source == source.rawValue }
        let jitter = e.gates.filter { $0.gate == "gate 3 jitter ±40 ms (phrase \(metric))" && $0.source == source.rawValue }
        let evaluated = lines.filter { $0.status != .notEvaluated }
        var texts = lines.map {
            String(format: "gate 1 phrase %@ | %@ | %@: n=%d flags=%d Wilson upper %.1f%% (≤ 5%%): %@", $0.metric, $0.source,
                   $0.prompt, $0.n, $0.flags, $0.upper * 100, $0.status.rawValue)
        }
        texts += jitter.map(\.text)
        texts.append("gate 2 (L2 recall vs B1): not defined for phrase metrics (no L2 phrase labels)")
        let status: GateStatus
        if evaluated.isEmpty { status = .notEvaluated }
        else if lines.allSatisfy({ $0.status == .met }) && jitter.allSatisfy({ $0.status == .met }) && !jitter.isEmpty { status = .met }
        else { status = .notMet }
        return .init(name: "phrase \(metric), \(source.rawValue)", status: status, lines: texts)
    }

    static func decide(_ e: EvaluationFile, training: TrainingFile) -> Spike27Verdict {
        var word: [String: Spike27Verdict.Claim] = [:]
        for arm in Arm.allCases {
            for source in [BoundarySource.oracle, .runtime] {
                word["\(arm.rawValue)/\(source.rawValue)"] = wordStress(e, training: training, arm: arm, source: source)
            }
        }
        var phrase: [String: Spike27Verdict.Claim] = [:]
        for metric in ["monotone", "final direction"] {
            for source in [BoundarySource.oracle, .runtime] {
                phrase["\(metric)/\(source.rawValue)"] = Self.phrase(e, metric: metric, source: source)
            }
        }
        let chosen = training.chosenArm.rawValue
        let runtimeWord = word["\(chosen)/runtime"]!.status == .met
        let oracleWord = word["\(chosen)/oracle"]!.status == .met
        let keptPhrase = ["monotone", "final direction"].filter { phrase["\($0)/runtime"]!.status == .met }
        let spikeLine: String
        if runtimeWord { spikeLine = "Spike 27: GO" }
        else if oracleWord { spikeLine = "Spike 27: NO-GO (oracle-only)" }
        else { spikeLine = "Spike 27: NO-GO" }
        func s(_ status: GateStatus) -> String { status == .met ? "GO" : status == .notEvaluated ? "NOT EVALUATED (NO-GO)" : "NO-GO" }
        let partial = "Partial: word stress (arm \(chosen), runtime) \(s(word["\(chosen)/runtime"]!.status)); "
            + "phrase monotone \(s(phrase["monotone/runtime"]!.status)); final direction \(s(phrase["final direction/runtime"]!.status)); "
            + "nPVI shown only (never verdicted)"
            + (keptPhrase.isEmpty ? "" : "; phrase metrics recommended: \(keptPhrase.joined(separator: ", "))")
        return Spike27Verdict(wordStress: word, phrase: phrase, spikeLine: spikeLine, partialLine: partial)
    }
}

func spike27Report(_ env: SpikeEnvironment, training: TrainingFile, evaluation e: EvaluationFile, write: Bool) throws -> Int32 {
    let verdict = SpikeVerdict.decide(e, training: training)
    let identity = try reportIdentity(root: env.root, corpusManifestHash: "", labelHash: "",
                                      splitPath: "fixtures/splits/vctk.json", splitSeed: env.split.foldSeed)
    let negatives = try? JSONDecoder().decode(NegativesFile.self, from: Data(contentsOf: env.file("negatives.json")))
    let report = Spike27Report(generatedAt: ISO8601DateFormatter().string(from: Date()), identity: identity,
                               listen: env.listen.standardizedFileURL.path, listenFiles: negatives?.listen ?? [],
                               training: training, evaluation: e, verdict: verdict)
    let acceptance = (try? String(contentsOf: URL(fileURLWithPath: NSString(string: "~/dev/accent-mirror-wt/_cache-26/logs/acceptance1.txt").expandingTildeInPath), encoding: .utf8)) ?? ""
    let markdown = spike27Markdown(report, acceptance: acceptance)
    print(markdown)
    let summary = spike27Summary(report)
    let logs = env.work.deletingLastPathComponent().appendingPathComponent("logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try summary.write(to: logs.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    if write {
        let directory = env.root.appendingPathComponent(ReportHashes.reportsPrefix)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try (encoder.encode(report) + Data("\n".utf8)).write(to: directory.appendingPathComponent(report.baseName + ".json"))
        try markdown.write(to: directory.appendingPathComponent(report.baseName + ".md"), atomically: true, encoding: .utf8)
        print("spike27: wrote \(ReportHashes.reportsPrefix)\(report.baseName).{json,md}"
              + (identity.cleanTree ? "" : " (dirty tree: not a report of record)"))
    }
    return 0
}

private func pct(_ v: Double?) -> String { v.map { String(format: "%.2f%%", $0 * 100) } ?? "–" }

/// The acceptance-1 lines spec 27 §5's Background quotes: spec 26 `.nucleus` flips (pooled and per group), both
/// inconclusive budget populations, `assignmentAmbiguous` rates and the confident-subset result.
func spike27Background(_ text: String) -> [String] {
    var out: [String] = []
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if let first = lines.first { out.append(first) }
    if lines.count > 1 { out.append(lines[1]) }
    var set = ""
    var i = 0
    while i < lines.count {
        let line = lines[i]
        if line == "synthetic" || line == "vctk-held-out" { set = line; out.append(""); out.append(line) }
        if line.trimmingCharacters(in: .whitespaces) == "spec 26 .nucleus" && !set.isEmpty {
            out.append(line)
            var j = i + 1
            while j < lines.count && lines[j].hasPrefix("    ") { out.append(lines[j]); j += 1 }
            i = j
            continue
        }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("budget populations") { out.append(line) }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("assignmentAmbiguous") {
            out.append(line)
            var j = i + 1
            while j < lines.count && lines[j].hasPrefix("    ") { out.append(lines[j]); j += 1 }
            i = j
            continue
        }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("(a) Confident subset") {
            out.append("")
            out.append(line)
            var j = i + 1
            while j < lines.count && lines[j].hasPrefix("    -") { out.append(lines[j]); j += 1 }
            i = j
            continue
        }
        i += 1
    }
    return out
}

func spike27Markdown(_ r: Spike27Report, acceptance: String) -> String {
    let t = r.training, e = r.evaluation, v = r.verdict
    var L: [String] = []
    L.append("# Spike 27: word-stress classifier and native envelope, offline feasibility (GO / NO-GO): \(r.baseName)")
    L.append("")
    L.append("- Generated: \(r.generatedAt); commit `\(r.identity.evaluatedCommit)`" + (r.identity.cleanTree ? "" : " (dirty tree: not a report of record)"))
    L.append("- configDigest `\(r.identity.configDigest)`, sourceTreeHash `\(r.identity.sourceTreeHash)`, split manifest `fixtures/splits/vctk.json` (seed \(t.seed))")
    L.append("- Front end: spec 25's nucleus detector at spec 26's frozen detection grid (1.5 dB, 50 ms, 9 dB, ±60 ms voicing; report `\(r.nucleusReport)`), spec 25/26's assignment. No `Thresholds` key, no app or AMPipeline change.")
    L.append("- **Literature expectation (lit review 2026-11-24):** the published systems closest to this design report recall around **20–50%** at a usable operating point (Ferrer et al. 2015 miss 48.3% at a 5% false-correction rate; Korzekwa et al. 2021 94.8% precision at 49.2% recall, with an attention model); classic native-side error is about 10%. **A word-stress NO-GO with phrase metrics GO is a legitimate result.** The build did not push for a GO.")
    L.append("")
    L.append("## Background: spec 26 acceptance 1 (FAIL), quoted from the build's `acceptance1.txt` (configDigest 69675122)")
    L.append("")
    L.append("```")
    L += spike27Background(acceptance)
    L.append("```")
    L.append("")
    L.append("## Training (tuning side only)")
    L.append("")
    L.append("- Positives: \(t.identityTakes) tuning-side takes (24 VCTK tuning speakers + the spec 22 TTS references), MFA word boundaries, every one through the Swift TD-PSOLA identity path (same pitch marks, no swap) and re-measured; training and calibration read processed audio only.")
    L.append("- Negatives: \(t.negativeSourceWords) native multi-syllable source words → **\(t.negatives) negatives** (stressed nucleus ↔ a seeded unstressed one: duration ratio, intensity offset, f0 contour; re-measured through the same front end). Dropped: " + t.negativesDropped.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ". Kept swaps with a duration factor outside [0.5, 2]: \(t.extremeDurationRatio).")
    L.append("- Folds: the split manifest's 6 speaker folds " + t.folds.map { "{\($0.joined(separator: ", "))}" }.joined(separator: " ") + "; the TTS voice is on the training side of every fold.")
    L.append("- τ grid \(t.tauGrid.first!)…\(t.tauGrid.last!); τ = the smallest grid value whose CV native false-flag point is ≤ 1% and CV Wilson upper bound ≤ 2% (CTO markup 5, lit amendment 1).")
    L.append("")
    for arm in t.arms {
        L.append("### Arm \(arm.arm.rawValue)")
        L.append("")
        L.append("- Training words: \(arm.positiveWords) positive, \(arm.negativeWords) negative (front-end abstentions: positives \(arm.positiveAbstained), negatives \(arm.negativeAbstained)).")
        L.append("")
        L.append("| family | variant | τ | CV native false flags | Wilson 95% | CV recall on negatives | meets bar |")
        L.append("|---|---|---|---|---|---|---|")
        for vr in arm.variants {
            let o = vr.operating
            let w = SpikeStats.wilson(o.flags, o.positives)
            L.append(String(format: "| %@ | %@ | %.2f | %d/%d (%.2f%%) | [%.2f%%, %.2f%%] | %d/%d (%.1f%%) | %@ |", vr.family.rawValue, vr.variant.rawValue,
                            vr.operatingTau, o.flags, o.positives, o.falseFlagRate * 100, w.lower * 100, w.upper * 100,
                            o.negativeFlags, o.negatives, o.recall * 100, vr.tau == nil ? "no" : "yes") + (vr.variant == arm.chosenVariant && vr.family == arm.chosenFamily ? " **chosen**" : ""))
        }
        L.append("")
        L.append("- Chosen: **\(arm.chosenFamily.rawValue), \(arm.chosenVariant.rawValue)** (\(arm.variantRule)); frozen τ **\(String(format: "%.2f", arm.tau))**" + (arm.tauMeetsBar ? "" : " (no τ met the bar; lowest CV upper bound)") + ".")
        L.append(String(format: "- Tuning-side ±40 ms jitter (oracle, out-of-fold models): %d/%d flips (%.2f%%).", arm.jitterTuning.flips, arm.jitterTuning.n, arm.jitterTuning.rate * 100))
        L.append(String(format: "- Artefact control (CTO markup 4): processed-vs-raw AUC **%@** on %d nucleus rows, held-out tuning folds (≤ 0.6: %@).",
                        arm.artefactAUC.map { String(format: "%.3f", $0) } ?? "–", arm.artefactRows, (arm.artefactAUC ?? 1) <= 0.6 ? "MET" : "NOT MET"))
        L.append("- Front-end signal check (raw tuning natives, oracle words, \(arm.signalWords) words): the dictionary-stressed syllable is the word's largest "
                 + arm.signalCheck.sorted { $0.key < $1.key }.map { String(format: "%@ %.1f%%", $0.key, $0.value * 100) }.joined(separator: ", ")
                 + " of the time (the first-syllable line is the prior, not a measure).")
        L.append(String(format: "- Round-trip control (reported, beyond the spec): the negatives' words swapped and swapped back (two PSOLA passes in the swapped regions) vs raw, same features and family, held-out tuning folds: AUC **%@** on %d nucleus rows%@.",
                        arm.roundTripAUC.map { String(format: "%.3f", $0) } ?? "–", arm.roundTripRows,
                        (arm.roundTripAUC ?? 0) > 0.6 ? " (above 0.6: swap artefacts look learnable)" : ""))
        if let m = arm.classifier.model {
            L.append("- Coefficients (logistic regression, λ = \(m.lambda), standardised features; intercept first):")
            L.append("")
            L.append("| term | weight | mean | sd |")
            L.append("|---|---|---|---|")
            L.append(String(format: "| intercept | %.4f | | |", m.weights[0]))
            for (j, name) in m.names.enumerated() {
                L.append(String(format: "| %@ | %.4f | %.4f | %.4f |", name, m.weights[j + 1], m.mean[j], m.scale[j]))
            }
        } else if let trees = arm.classifier.trees {
            var uses: [String: Int] = [:]
            for tree in trees.trees { for node in tree where node.feature >= 0 { uses[trees.names[node.feature], default: 0] += 1 } }
            L.append("- Boosted trees: \(trees.trees.count) trees, depth ≤ \(BoostedTrees.maxDepth), shrinkage \(trees.rate), base log-odds "
                     + String(format: "%.3f", trees.base) + "; every node is in the report JSON. Splits per feature: "
                     + uses.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ".")
        }
        L.append("")
    }
    L.append("- **Arm picked on the tuning side: \(t.chosenArm.rawValue)** (\(t.armRule)).")
    L.append("- The artefact AUC is 0.5 by construction here: the identity pass divides the overlap-add by the summed windows, so it gives the input back and its re-measured features equal the raw ones. The control therefore can't see artefacts inside swapped regions (they exist only in negatives); read it as \"processing alone is not learnable\", not as a bound on swap artefacts.")
    L.append("")
    L.append("## Gates (every arm × boundary source)")
    L.append("")
    L.append("Oracle = MFA word boundaries (spec 07's pinned MFA); runtime = Whisper base.en word times (known prompt text through spec 03's aligner; for L2 also Whisper's own transcript). GO is judged on the runtime source.")
    L.append("")
    for arm in ["A", "B"] {
        for source in ["oracle", "runtime", "runtime (known text)", "asr", "runtime (ASR transcript)", "–"] {
            let lines = e.gates.filter { $0.arm == arm && $0.source == source }
            guard !lines.isEmpty else { continue }
            L.append("### Arm \(arm), \(source)")
            L.append("")
            L.append("| gate | population | n | count | value | Wilson 95% | limit | status | detail |")
            L.append("|---|---|---|---|---|---|---|---|---|")
            for g in lines {
                let ci = g.lower.flatMap { l in g.upper.map { String(format: "[%.2f%%, %.2f%%]", l * 100, $0 * 100) } } ?? "–"
                L.append("| \(g.gate) | \(g.population) | \(g.n) | \(g.count) | \(pct(g.value)) | \(ci) | \(g.limit) | **\(g.status.rawValue)** | \(g.detail) |")
            }
            L.append("")
        }
    }
    L.append("### McNemar (the 134, detector vs B1 on the same words and front end; abstentions count as no flag for both)")
    L.append("")
    L.append("| arm | source | n | detector | B1 | B2 | detector only | B1 only | both | neither | exact p | non-abstained |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for m in e.mcnemar {
        L.append(String(format: "| %@ | %@ | %d | %d | %d | %d | %d | %d | %d | %d | %.4g | %d |", m.arm, m.source, m.n, m.detector, m.b1, m.b2,
                        m.detectorOnly, m.b1Only, m.both, m.neither, m.p, m.covered))
    }
    L.append("")
    L.append("Coverage of the 134 (timed with a target / non-abstained): " + e.coverage134.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "; ") + ".")
    L.append("")
    L.append("### Precision–recall (runtime, known text): recall on the 134 vs native (held-out VCTK) and clean-1,400 false flags")
    L.append("")
    for (arm, curve) in e.pr.sorted(by: { $0.key < $1.key }) {
        L.append("Arm \(arm):")
        L.append("")
        L.append("| τ | recall (134) | native FF | clean-1,400 FF | precision @ 5% prevalence | @ 10% |")
        L.append("|---|---|---|---|---|---|")
        for p in curve {
            L.append(String(format: "| %.2f%@ | %d/134 (%.1f%%) | %.2f%% | %.2f%% | %@ | %@ |", p.tau, p.operating ? " (operating)" : "",
                            p.recallCount, p.recall * 100, p.nativeFalseFlag * 100, p.cleanFalseFlag * 100, pct(p.precision5), pct(p.precision10)))
        }
        L.append("")
    }
    L.append("## Native envelopes (§2, per prompt, natural speakers only, runtime word times)")
    L.append("")
    for q in t.quantiles {
        L.append("- \(q.metric): quantile pair chosen on speaker-grouped CV (Wilson upper of native false flags ≤ 5%): **\(q.chosen.map { "q = \($0)" } ?? "none meets it")**. Candidates: " + q.candidates.map { String(format: "q=%.3f n=%.0f flags=%.0f upper=%.1f%%", $0[0], $0[1], $0[2], $0[3] * 100) }.joined(separator: "; ") + ".")
    }
    L.append("- Final-direction prompts (≥ 80% of tuning-side natives share one class; committed before evaluation): \(t.finalDirectionPrompts.isEmpty ? "none" : t.finalDirectionPrompts.joined(separator: ", ")).")
    L.append("- With no quantile pair meeting the CV bar, the widest envelope (q = 0, the natives' min…max) is used below so the held-out lines can be printed; it doesn't make the metric pass.")
    L.append("")
    L.append("| prompt | natural n | status | pitch range envelope (st) | final slope envelope (st/s) | nPVI 2.5–97.5% | dominant final | share | final verdicted |")
    L.append("|---|---|---|---|---|---|---|---|---|")
    for env in t.envelopes {
        func iv(_ x: [Double]?) -> String { x.map { String(format: "%.2f…%.2f", $0[0], $0[1]) } ?? "–" }
        L.append("| \(env.prompt) | \(env.natural) | \(env.evaluated ? "evaluated" : "NOT EVALUATED (< 30)") | \(iv(env.pitchRange)) | \(iv(env.finalSlope)) | \(iv(env.npvi)) | \(env.dominantFinal?.rawValue ?? "–") | \(env.dominantShare.map { String(format: "%.0f%%", $0 * 100) } ?? "–") | \(env.finalDirectionVerdicted ? "yes" : "no") |")
    }
    L.append("")
    L.append("Phrase verdicts on held-out VCTK, per prompt (gate 1: Wilson upper ≤ 5%):")
    L.append("")
    L.append("| metric | source | prompt | n | flags | Wilson upper | status |")
    L.append("|---|---|---|---|---|---|---|")
    for p in e.phrase {
        L.append(String(format: "| %@ | %@ | %@ | %d | %d | %.1f%% | %@ |", p.metric, p.source, p.prompt, p.n, p.flags, p.upper * 100, p.status.rawValue))
    }
    L.append("")
    L.append("Held-out VCTK has at most 16 speakers per prompt, so a per-prompt Wilson upper bound can't reach 5% (0/16 gives 19.4%; 0 flags needs n ≥ 74).")
    L.append("")
    L.append("## Verdict")
    L.append("")
    for key in v.wordStress.keys.sorted() {
        let c = v.wordStress[key]!
        L.append("- **\(c.name): \(c.status.rawValue)**")
    }
    for key in v.phrase.keys.sorted() {
        let c = v.phrase[key]!
        L.append("- **\(c.name): \(c.status.rawValue)**")
    }
    L.append("")
    L.append("**Note for CPO:** the 1% native false-flag bar is an engineering ship bar. The precision it implies depends on how often learners actually misplace stress (see the precision column at 5% and 10% prevalence); where to set that trade-off is a product call. Coverage (gate 4) is reported, not gated: its minimum is a CPO call.")
    L.append("")
    if v.spikeLine != "Spike 27: GO" {
        let monotone = v.phrase["monotone/runtime"]!.status, final = v.phrase["final direction/runtime"]!.status
        let supported = monotone == .met || final == .met
        L.append("**v1 scope statement for CPO (NO-GO):** \"v1 ships phrase rhythm and intonation inside the native envelope only, without per-word stress verdicts.\" "
                 + (supported ? "Supported by the phrase-metric gate lines above."
                    : "The spike's phrase-metric gate lines do **not** support verdicts either: monotone is \(monotone.rawValue) and final direction is \(final.rawValue) on the runtime source, so on this evidence v1 would show the learner's contour and phrase measures against the native envelope with no phrase verdict."))
        L.append("")
    }
    L.append("## Spot-check negatives (taste call, Raph)")
    L.append("")
    L.append("\(r.listenFiles.count) negatives, each with its raw source and identity-processed version, in `\(r.listen)` (index: `\(r.listen)/index.md`).")
    L.append("")
    if let partial = v.partialLine { L.append(partial) }
    L.append("")
    L.append(v.spikeLine)
    L.append("")
    return L.joined(separator: "\n")
}

func spike27Summary(_ r: Spike27Report) -> String {
    let t = r.training, e = r.evaluation, v = r.verdict
    var L = [v.spikeLine]
    if let p = v.partialLine { L.append(p) }
    L.append("report \(r.baseName) (commit \(r.identity.evaluatedCommit.prefix(12))\(r.identity.cleanTree ? "" : ", dirty tree"))")
    L.append("chosen arm \(t.chosenArm.rawValue): \(t.armRule)")
    for arm in t.arms {
        L.append(String(format: "arm %@: %@, variant %@, τ %.2f%@, artefact AUC %@ (round trip %@), tuning jitter %d/%d", arm.arm.rawValue,
                        arm.chosenFamily.rawValue, arm.chosenVariant.rawValue,
                        arm.tau, arm.tauMeetsBar ? "" : " (bar not met)", arm.artefactAUC.map { String(format: "%.3f", $0) } ?? "–",
                        arm.roundTripAUC.map { String(format: "%.3f", $0) } ?? "–", arm.jitterTuning.flips, arm.jitterTuning.n))
    }
    L.append("")
    L.append("GATES (arm × source):")
    for g in e.gates { L.append("  " + g.text) }
    L.append("")
    L.append("McNEMAR (134):")
    for m in e.mcnemar {
        L.append(String(format: "  arm %@ %@: detector %d, B1 %d, B2 %d; detector-only %d, B1-only %d; p = %.4g; non-abstained %d/134",
                        m.arm, m.source, m.detector, m.b1, m.b2, m.detectorOnly, m.b1Only, m.p, m.covered))
    }
    L.append("")
    L.append("PR CURVE (runtime, known text):")
    for (arm, curve) in e.pr.sorted(by: { $0.key < $1.key }) {
        for p in curve {
            L.append(String(format: "  arm %@ τ %.2f%@: recall %d/134, native FF %.2f%%, clean FF %.2f%%, precision@5%% %@, @10%% %@", arm, p.tau,
                            p.operating ? " (operating)" : "", p.recallCount, p.nativeFalseFlag * 100, p.cleanFalseFlag * 100,
                            pct(p.precision5), pct(p.precision10)))
        }
    }
    L.append("")
    L.append("ENVELOPES:")
    for q in t.quantiles { L.append("  \(q.metric): chosen \(q.chosen.map { String($0) } ?? "none (CV upper > 5% at every q)")") }
    L.append("  final-direction prompts: \(t.finalDirectionPrompts)")
    for env in t.envelopes {
        L.append("  \(env.prompt): natural n \(env.natural)\(env.evaluated ? "" : " NOT EVALUATED") range \(env.pitchRange.map { String(format: "%.2f…%.2f", $0[0], $0[1]) } ?? "–") dominant final \(env.dominantFinal?.rawValue ?? "–") \(env.dominantShare.map { String(format: "%.0f%%", $0 * 100) } ?? "")")
    }
    for p in e.phrase {
        L.append(String(format: "  phrase %@ %@ %@: n=%d flags=%d upper %.1f%%: %@", p.metric, p.source, p.prompt, p.n, p.flags, p.upper * 100, p.status.rawValue))
    }
    L.append("")
    L.append("CLAIMS:")
    for key in v.wordStress.keys.sorted() { L.append("  \(v.wordStress[key]!.name): \(v.wordStress[key]!.status.rawValue)") }
    for key in v.phrase.keys.sorted() { L.append("  \(v.phrase[key]!.name): \(v.phrase[key]!.status.rawValue)") }
    L.append("")
    L.append(v.spikeLine)
    return L.joined(separator: "\n") + "\n"
}
