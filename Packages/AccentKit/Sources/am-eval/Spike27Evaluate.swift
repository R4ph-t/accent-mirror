// Spec 27 §3: every gate for each arm (A, B) × boundary source (oracle MFA, runtime Whisper), on evaluation data
// only (held-out VCTK, the 134, the clean 1,400, speechocean762; the TTS synthetic set and the bundled voices for
// jitter and coverage). Nothing here fits or chooses: the classifiers, τ, the arm and the envelopes come frozen from
// the train stage. GO is judged on the runtime source.

import AMAlignment
import AMCore
import AMEvaluation
import AMSpike27
import Foundation

enum GateStatus: String, Codable, Sendable { case met = "MET", notMet = "NOT MET", notEvaluated = "NOT EVALUATED", reported = "REPORTED" }

struct GateLine: Codable, Sendable {
    let gate: String
    let arm: String
    let source: String
    let population: String
    let n: Int
    let count: Int
    let value: Double?
    let lower: Double?
    let upper: Double?
    let limit: String
    let status: GateStatus
    let detail: String

    var text: String {
        let v = value.map { String(format: "%.2f%%", $0 * 100) } ?? "–"
        let ci = lower.flatMap { l in upper.map { String(format: " [%.2f, %.2f]", l * 100, $0 * 100) } } ?? ""
        return "\(gate) | arm \(arm) | \(source) | \(population): n=\(n) \(count)/\(n) \(v)\(ci) (\(limit)): \(status.rawValue)"
            + (detail.isEmpty ? "" : "; \(detail)")
    }
}

struct McNemarRow: Codable, Sendable {
    let arm: String
    let source: String
    let population: String
    let n: Int
    let detector: Int
    let b1: Int
    let b2: Int
    /// Detector flags, B1 doesn't / B1 flags, detector doesn't.
    let detectorOnly: Int
    let b1Only: Int
    let both: Int
    let neither: Int
    let p: Double
    let covered: Int
}

struct PRPoint: Codable, Sendable {
    let tau: Double
    let recall: Double
    let recallCount: Int
    let nativeFalseFlag: Double
    let cleanFalseFlag: Double
    let precision5: Double?
    let precision10: Double?
    let operating: Bool
}

struct PhraseLine: Codable, Sendable {
    let metric: String
    let source: String
    let prompt: String
    let n: Int
    let flags: Int
    let upper: Double
    let status: GateStatus
}

struct EvaluationFile: Codable {
    var gates: [GateLine] = []
    var mcnemar: [McNemarRow] = []
    var pr: [String: [PRPoint]] = [:]
    var phrase: [PhraseLine] = []
    var abstentions: [String: [String: Int]] = [:]
    var coverage134: [String: Int] = [:]
}

enum SpikeEvaluate {
    static func groupName(_ syllables: Int) -> String { syllables >= 4 ? "4+" : "\(syllables)" }

    static func outcomes(_ clips: [SpikeClip], source: BoundarySource, arm: Arm, classifier: StressClassifier,
                         tau: Double, where keep: (TimedWord) -> Bool = { _ in true }) -> [(SpikeClip, WordOutcome)] {
        clips.flatMap { clip -> [(SpikeClip, WordOutcome)] in
            guard let words = clip.words(source) else { return [] }
            let byIndex = Dictionary(words.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
            return TakeScoring.score(clip.measured, words: words, arm: arm, source: source, classifier: classifier, tau: tau)
                .filter { byIndex[$0.index].map(keep) ?? false }
                .map { (clip, $0) }
        }
    }

    /// Gate 1's word-stress false-flag line: point ≤ 1% and Wilson upper ≤ 2% on n ≥ 600 non-abstained words.
    static func falseFlags(_ outcomes: [WordOutcome], arm: Arm, source: BoundarySource, population: String) -> GateLine {
        let decided = outcomes.filter { !$0.verdict.isAbstain }
        let flags = decided.count { $0.verdict.isFlag }
        let n = decided.count
        let w = SpikeStats.wilson(flags, n)
        let rate = n > 0 ? Double(flags) / Double(n) : nil
        let status: GateStatus = n < 600 ? .notEvaluated
            : (rate! <= 0.01 + 1e-12 && w.upper <= 0.02 + 1e-12 ? .met : .notMet)
        return GateLine(gate: "gate 1 false flags", arm: arm.rawValue, source: source.rawValue, population: population,
                        n: n, count: flags, value: rate, lower: n > 0 ? w.lower : nil, upper: n > 0 ? w.upper : nil,
                        limit: "point ≤ 1% and Wilson upper ≤ 2%, n ≥ 600", status: status,
                        detail: "\(outcomes.count) target words, \(outcomes.count - n) abstained"
                            + (n < 600 ? " (n < 600: NOT EVALUATED)" : ""))
    }

    static func coverage(_ outcomes: [WordOutcome], arm: Arm, source: BoundarySource, population: String,
                         total: Int? = nil) -> GateLine {
        let n = total ?? outcomes.count
        let decided = outcomes.count { !$0.verdict.isAbstain }
        let w = SpikeStats.wilson(decided, n)
        return GateLine(gate: "gate 4 coverage", arm: arm.rawValue, source: source.rawValue, population: population,
                        n: n, count: decided, value: n > 0 ? Double(decided) / Double(n) : nil,
                        lower: n > 0 ? w.lower : nil, upper: n > 0 ? w.upper : nil,
                        limit: "reported; the minimum is a CPO call", status: .reported, detail: "")
    }

    /// Gate 3: ±40 ms flips (spec 11 §4b's jitter, the split manifest's seed); a flip to or from abstain counts.
    static func jitter(_ clips: [SpikeClip], source: BoundarySource, arm: Arm, classifier: StressClassifier,
                       tau: Double, seed: UInt64, population: String) -> [GateLine] {
        var all: [(Int, Bool)] = []
        for clip in clips {
            guard let words = clip.words(source) else { continue }
            let base = TakeScoring.score(clip.measured, words: words, arm: arm, source: source, classifier: classifier, tau: tau)
            let moved = SpikeTrain.jittered(words, duration: clip.measured.duration, seed: seed, clipID: clip.id)
            let after = Dictionary(TakeScoring.score(clip.measured, words: moved, arm: arm, source: source,
                                                     classifier: classifier, tau: tau).map { ($0.index, $0.verdict) },
                                   uniquingKeysWith: { a, _ in a })
            for o in base { all.append((o.syllables, after[o.index] != o.verdict)) }
        }
        func line(_ name: String, _ items: [(Int, Bool)], gated: Bool) -> GateLine {
            let n = items.count, flips = items.count(where: \.1)
            let w = SpikeStats.wilson(flips, n)
            let rate = n > 0 ? Double(flips) / Double(n) : nil
            let status: GateStatus = n == 0 ? .notEvaluated : !gated ? .reported : (rate! <= 0.02 + 1e-12 ? .met : .notMet)
            return GateLine(gate: "gate 3 jitter ±40 ms (\(name))", arm: arm.rawValue, source: source.rawValue,
                            population: population, n: n, count: flips, value: rate, lower: n > 0 ? w.lower : nil,
                            upper: n > 0 ? w.upper : nil, limit: "≤ 2% flips (point), groups gated at n ≥ 30",
                            status: status, detail: gated || n == 0 ? "" : "n < 30: reported only")
        }
        var lines = [line("pooled", all, gated: true)]
        for group in ["2", "3", "4+"] {
            let items = all.filter { groupName($0.0) == group }
            lines.append(line("\(group)-syllable", items, gated: items.count >= 30))
        }
        return lines
    }

    static func notEvaluated(_ gate: String, arm: Arm, source: BoundarySource, population: String, why: String) -> GateLine {
        GateLine(gate: gate, arm: arm.rawValue, source: source.rawValue, population: population, n: 0, count: 0,
                 value: nil, lower: nil, upper: nil, limit: "", status: .notEvaluated, detail: why)
    }
}

func spike27Evaluate(_ env: SpikeEnvironment, args: Arguments) async throws -> Int32 {
    let training = try JSONDecoder().decode(TrainingFile.self, from: Data(contentsOf: env.file("training.json")))
    let heldOut = try await SpikeData.clips(.heldOutVCTK, env: env, log: spikeLog)
    let tts = try await SpikeData.clips(.tts, env: env, log: spikeLog)
    let bundled = try await SpikeData.clips(.bundled, env: env, log: spikeLog)
    let l2 = try await SpikeData.clips(.speechocean762, env: env, log: spikeLog)
    let seed = env.split.foldSeed
    guard Set(heldOut.map(\.speaker)).isSubset(of: Set(env.split.heldOut)) else {
        throw CLIError.failed("spike27 evaluate: held-out takes from a non-held-out speaker")
    }
    var out = EvaluationFile()
    func tagged(_ tag: String) -> (TimedWord) -> Bool { { ($0.label ?? "").split(separator: ",").contains(Substring(tag)) } }
    let recallTotal = 134

    for armTraining in training.arms {
        let arm = armTraining.arm, classifier = armTraining.classifier, tau = armTraining.tau
        for source in [BoundarySource.oracle, .runtime] {
            // Held-out native VCTK: gate 1, gate 3, coverage.
            let native = SpikeEvaluate.outcomes(heldOut, source: source, arm: arm, classifier: classifier, tau: tau).map(\.1)
            out.gates.append(SpikeEvaluate.falseFlags(native, arm: arm, source: source, population: "vctk-held-out"))
            out.gates.append(SpikeEvaluate.coverage(native, arm: arm, source: source, population: "vctk-held-out candidate words"))
            out.abstentions["\(arm.rawValue)/\(source.rawValue)/vctk-held-out"] = Dictionary(
                grouping: native.compactMap { if case .abstain(let r) = $0.verdict { r.rawValue } else { nil } }, by: { $0 }).mapValues(\.count)
            out.gates += SpikeEvaluate.jitter(heldOut, source: source, arm: arm, classifier: classifier, tau: tau, seed: seed,
                                              population: "vctk-held-out")
            if source == .oracle {
                out.gates += SpikeEvaluate.jitter(tts, source: source, arm: arm, classifier: classifier, tau: tau, seed: seed,
                                                  population: "synthetic (TTS)")
            } else {
                out.gates.append(SpikeEvaluate.notEvaluated(
                    "gate 3 jitter ±40 ms (pooled)", arm: arm, source: source, population: "synthetic (TTS)",
                    why: "no Whisper word times for the TTS references in the caches (ASR is never run by this spike)"))
            }
            // Coverage on the starter words across the bundled voices (runtime only: no MFA for them).
            if source == .runtime {
                let starter = SpikeEvaluate.outcomes(bundled, source: source, arm: arm, classifier: classifier, tau: tau).map(\.1)
                out.gates.append(SpikeEvaluate.coverage(starter, arm: arm, source: source,
                                                        population: "starter words × bundled voices"))
            } else {
                out.gates.append(SpikeEvaluate.notEvaluated("gate 4 coverage", arm: arm, source: source,
                                                            population: "starter words × bundled voices",
                                                            why: "no MFA alignment of the bundled recordings"))
            }
        }
        // L2: known text (runtime) and the ASR-transcript variant; no oracle (no MFA alignment of speechocean762).
        for source in [BoundarySource.runtime, .asr] {
            let label = source == .runtime ? "runtime (known text)" : "runtime (ASR transcript)"
            let recall = SpikeEvaluate.outcomes(l2, source: source, arm: arm, classifier: classifier, tau: tau, where: tagged("134")).map(\.1)
            let detector = recall.count { $0.verdict.isFlag }
            let b1 = recall.count { $0.b1Flag == true }, b2 = recall.count { $0.b2Flag == true }
            let dOnly = recall.count { $0.verdict.isFlag && $0.b1Flag != true }
            let bOnly = recall.count { !$0.verdict.isFlag && $0.b1Flag == true }
            let both = recall.count { $0.verdict.isFlag && $0.b1Flag == true }
            let p = Statistics.mcnemarExact(b: dOnly, c: bOnly)
            out.mcnemar.append(McNemarRow(arm: arm.rawValue, source: label, population: "l2-134", n: recallTotal,
                                          detector: detector, b1: b1, b2: b2, detectorOnly: dOnly, b1Only: bOnly,
                                          both: both, neither: recallTotal - dOnly - bOnly - both, p: p,
                                          covered: recall.count { !$0.verdict.isAbstain }))
            let w = SpikeStats.wilson(detector, recallTotal)
            let win = detector > b1 && p < 0.05
            out.gates.append(GateLine(
                gate: "gate 2 L2 recall vs B1 (McNemar)", arm: arm.rawValue, source: label, population: "l2-134",
                n: recallTotal, count: detector, value: Double(detector) / Double(recallTotal), lower: w.lower, upper: w.upper,
                limit: "beats B1 with exact McNemar p < 0.05", status: win ? .met : .notMet,
                detail: String(format: "B1 %d/134, B2 %d/134; discordant detector-only %d, B1-only %d, p = %.4g", b1, b2, dOnly, bOnly, p)))
            out.gates.append(SpikeEvaluate.coverage(recall, arm: arm, source: source, population: "l2-134 (\(label))",
                                                    total: recallTotal))
            out.coverage134["\(arm.rawValue)/\(label)/timed with a target"] = recall.count
            out.coverage134["\(arm.rawValue)/\(label)/non-abstained"] = recall.count { !$0.verdict.isAbstain }
            let clean = SpikeEvaluate.outcomes(l2, source: source, arm: arm, classifier: classifier, tau: tau, where: tagged("clean")).map(\.1)
            out.gates.append(SpikeEvaluate.falseFlags(clean, arm: arm, source: source, population: "l2-clean-1400"))
            let cleanDecided = clean.filter { !$0.verdict.isAbstain }
            out.gates.append(GateLine(
                gate: "B1/B2 flag rate, same words", arm: arm.rawValue, source: label, population: "l2-clean-1400",
                n: cleanDecided.count, count: cleanDecided.count { $0.b1Flag == true }, value: cleanDecided.isEmpty ? nil
                    : Double(cleanDecided.count { $0.b1Flag == true }) / Double(cleanDecided.count), lower: nil, upper: nil,
                limit: "precision context", status: .reported,
                detail: "B1 \(cleanDecided.count { $0.b1Flag == true }), B2 \(cleanDecided.count { $0.b2Flag == true }), detector \(cleanDecided.count { $0.verdict.isFlag }) of \(cleanDecided.count) non-abstained"))
            let soCorrect = SpikeEvaluate.outcomes(l2, source: source, arm: arm, classifier: classifier, tau: tau, where: tagged("so762:correct")).map(\.1)
            out.gates.append(SpikeEvaluate.falseFlags(soCorrect, arm: arm, source: source, population: "speechocean762 correctly stressed"))
            let soWrong = SpikeEvaluate.outcomes(l2, source: source, arm: arm, classifier: classifier, tau: tau, where: tagged("so762:misplaced")).map(\.1)
            out.gates.append(GateLine(
                gate: "gate 2 L2 recall vs B1 (McNemar)", arm: arm.rawValue, source: label, population: "speechocean762 misplaced",
                n: soWrong.count, count: soWrong.count { $0.verdict.isFlag }, value: nil, lower: nil, upper: nil,
                limit: "second test set, reported", status: soWrong.isEmpty ? .notEvaluated : .reported,
                detail: soWrong.isEmpty ? "no misplaced word (stress 5) with ≥ 2 syllables, accuracy ≥ 5 and Whisper times outside the 134's utterances" : ""))
        }
        for source in [BoundarySource.oracle] {
            for population in ["l2-134", "l2-clean-1400", "speechocean762"] {
                out.gates.append(SpikeEvaluate.notEvaluated("gates 1–2 (L2)", arm: arm, source: source, population: population,
                                                            why: "no MFA alignment of speechocean762 in the caches (oracle L2 not available)"))
            }
        }
        // PR curve on the runtime source (known text): recall on the 134 against native and clean-1,400 false flags.
        let taus = Array(Set([0.0, 0.02, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.99, tau])).sorted()
        var curve: [PRPoint] = []
        for t in taus {
            let r = SpikeEvaluate.outcomes(l2, source: .runtime, arm: arm, classifier: classifier, tau: t, where: tagged("134")).map(\.1)
            let nat = SpikeEvaluate.outcomes(heldOut, source: .runtime, arm: arm, classifier: classifier, tau: t).map(\.1).filter { !$0.verdict.isAbstain }
            let cl = SpikeEvaluate.outcomes(l2, source: .runtime, arm: arm, classifier: classifier, tau: t, where: tagged("clean")).map(\.1).filter { !$0.verdict.isAbstain }
            let rc = r.count { $0.verdict.isFlag }
            let recall = Double(rc) / Double(recallTotal)
            let ff = nat.isEmpty ? 0 : Double(nat.count { $0.verdict.isFlag }) / Double(nat.count)
            let cf = cl.isEmpty ? 0 : Double(cl.count { $0.verdict.isFlag }) / Double(cl.count)
            func precision(_ prevalence: Double) -> Double? {
                let tp = prevalence * recall, fp = (1 - prevalence) * ff
                return tp + fp > 0 ? tp / (tp + fp) : nil
            }
            curve.append(PRPoint(tau: t, recall: recall, recallCount: rc, nativeFalseFlag: ff, cleanFalseFlag: cf,
                                 precision5: precision(0.05), precision10: precision(0.10), operating: abs(t - tau) < 1e-9))
        }
        out.pr[arm.rawValue] = curve
    }

    // §2: phrase verdicts on held-out VCTK, per prompt, against the frozen envelopes.
    let envelopes = Dictionary(uniqueKeysWithValues: training.envelopes.map { ($0.prompt, $0) })
    for source in [BoundarySource.oracle, .runtime] {
        let byPrompt = Dictionary(grouping: heldOut.filter { envelopes[$0.phrase] != nil && $0.words(source) != nil }, by: \.phrase)
        var jitterFlips: [String: (Int, Int)] = [:]
        for prompt in envelopes.keys.sorted() {
            let e = envelopes[prompt]!
            let takes = byPrompt[prompt] ?? []
            for metric in ["monotone", "final direction"] {
                if metric == "final direction" && !e.finalDirectionVerdicted { continue }
                guard e.evaluated, let interval = (metric == "monotone" ? e.pitchRange : e.finalSlope) else {
                    out.phrase.append(PhraseLine(metric: metric, source: source.rawValue, prompt: prompt, n: 0, flags: 0,
                                                 upper: 1, status: .notEvaluated))
                    continue
                }
                func verdict(_ m: PhraseMetrics) -> Bool? {
                    metric == "monotone" ? NativeEnvelope.monotone(m, envelope: interval[0]...interval[1])
                        : e.dominantFinal.flatMap { NativeEnvelope.finalDirection(m, envelope: interval[0]...interval[1], dominant: $0) }
                }
                var n = 0, flags = 0
                for clip in takes {
                    let words = clip.words(source)!
                    guard let v = verdict(PhraseMetrics.measure(clip.measured, words: words)) else { continue }
                    n += 1
                    if v { flags += 1 }
                    let moved = SpikeTrain.jittered(words, duration: clip.measured.duration, seed: seed, clipID: clip.id)
                    let after = verdict(PhraseMetrics.measure(clip.measured, words: moved))
                    var j = jitterFlips[metric] ?? (0, 0)
                    j.0 += 1
                    if after != v { j.1 += 1 }
                    jitterFlips[metric] = j
                }
                let upper = SpikeStats.wilson(flags, n).upper
                out.phrase.append(PhraseLine(metric: metric, source: source.rawValue, prompt: prompt, n: n, flags: flags,
                                             upper: upper, status: n == 0 ? .notEvaluated : upper <= 0.05 + 1e-12 ? .met : .notMet))
            }
        }
        for metric in ["monotone", "final direction"] {
            let (n, flips) = jitterFlips[metric] ?? (0, 0)
            let w = SpikeStats.wilson(flips, n)
            out.gates.append(GateLine(
                gate: "gate 3 jitter ±40 ms (phrase \(metric))", arm: "–", source: source.rawValue, population: "vctk-held-out",
                n: n, count: flips, value: n > 0 ? Double(flips) / Double(n) : nil, lower: n > 0 ? w.lower : nil,
                upper: n > 0 ? w.upper : nil, limit: "≤ 2% flips (point)",
                status: n == 0 ? .notEvaluated : Double(flips) / Double(n) <= 0.02 + 1e-12 ? .met : .notMet, detail: ""))
        }
    }
    for line in out.gates { spikeLog(line.text) }
    for line in out.phrase {
        spikeLog(String(format: "phrase %@ | %@ | %@: n=%d flags=%d Wilson upper %.1f%% (≤ 5%%): %@", line.metric, line.source,
                        line.prompt, line.n, line.flags, line.upper * 100, line.status.rawValue))
    }
    return try spike27Report(env, training: training, evaluation: out, write: args.flag("write-report"))
}
