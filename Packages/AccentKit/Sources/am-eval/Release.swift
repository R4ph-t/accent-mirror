// Spec 11 §3–§6: `am-eval suite --suite release`, the one held-out check of the shipped config. It prints every §6.7
// row, the §4–§4b rows and the closing lines, and writes `docs/agreement/reports/release-<configDigest8>.{json,md}`.
// Inputs it reads, never recomputes: the tuning run (`scripts/tune.sh`) and the guard measurements on held-out data
// (`am-timestamps spec11-guard`, run by `scripts/agreement.sh --suite release`).

import AMAlignment
import AMCore
import AMEvaluation
import AMPipeline
import AMProsody
import Foundation

/// The suite's L2 rows on one set and thresholds: per word, flagged after suppression and its split group.
struct L2Flags {
    enum Group: String, CaseIterable {
        case substituted = "Whisper-substituted or deleted"
        case lowConfidence = "low ASR confidence"
        case clean = "clean matched"
    }

    var flagged: [String: Bool] = [:]
    var group: [String: Group] = [:]
    var present: [String: Bool] = [:]

    init(takes: [L2Take], detector: StressPlacementDetector, lowBelow: Double) {
        for take in takes {
            let outcomes = take.outcomes(detector)
            let segmented = Dictionary(take.segmentation.words.map { ($0.phraseWord, $0) }, uniquingKeysWith: { a, _ in a })
            for (index, id) in take.decided {
                flagged[id] = outcomes[id]?.contains(.flagged) ?? false
                let pair = take.alignment.pairs.first { $0.phraseWord?.rawValue == index }
                switch pair {
                case .present?:
                    let word = segmented.first { $0.key.rawValue == index }?.value
                    present[id] = word?.kind == .present
                    group[id] = (word?.injected.probability ?? 0) < lowBelow ? .lowConfidence : .clean
                default:
                    present[id] = false
                    group[id] = .substituted
                }
            }
        }
    }
}

func release(_ args: Arguments, root: URL) async throws -> Int32 {
    let thresholds = Thresholds.current
    let agreement = thresholds.agreement
    let digest = try configDigest(harnessConfig())
    print("release: shipped config \(digest.prefix(8)) (thresholdsVersion \(Versions.thresholdsVersion))")
    var notes: [String] = []
    var reported: [String] = []

    // The tuning run.
    let tuningURL = args.value("tuning").map(URL.init(fileURLWithPath:))
        ?? cacheURL(root, "eval-cache/tuning/tuning-\(TuningPoint.initialDigest8(root: root)).json")
    let tuning = (try? Data(contentsOf: tuningURL)).flatMap { try? JSONDecoder().decode(TuningRun.self, from: $0) }
    if let tuning, tuning.shippedConfigDigest != digest {
        throw CLIError.failed("the tuning run at \(tuningURL.path) is for config \(tuning.shippedConfigDigest.prefix(8)), the head ships \(digest.prefix(8)): rerun scripts/tune.sh")
    }

    // Positive set (§3, §3a).
    let positive = try await positiveResult(args, root: root, prefix: "release: positive")
    notes += positive?.notes ?? []

    // L2 on held-out words (§3): clean 1,400, the 1,868 supplementary, the 157 unintelligible.
    let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
    let sets = SpeechOceanSets(labels: labels)
    let corpus = try SpeechOceanCorpusFiles(root: cacheURL(root, Paths.so762Cache))
    let timings = try FixtureTimestamper(directory: cacheURL(root, Paths.so762Timings))
    let base = try StressPlacementDetector.bundled()
    let lowBelow = thresholds.confidence.levelMedium
    var metrics: [MetricResult] = []
    var negative: [MetricResult] = []
    func takes(_ name: String, _ words: [SpeechOceanWord]) async throws -> [L2Take] {
        try await l2Takes(set: name, words: words, corpus: corpus, timings: timings, labels: labels, base: base)
    }
    let cleanTakes = try await takes("clean", sets.cleanFalsePositive)
    let clean = L2Flags(takes: cleanTakes, detector: base, lowBelow: lowBelow)
    // The shipped path itself must agree with the replayed tables (same stages, same thresholds).
    let runner = SharedDetectorRunner(
        detector: ReplayedPlacementDetector(
            corpus: corpus, timings: timings,
            refPhones: Dictionary(labels.words.map { ($0.id, $0.refPhones) }, uniquingKeysWith: { a, _ in a }),
            dictionary: try .bundled()),
        corpus: corpus, dictionary: SelectorPrimaryLookup(selector: try .bundled()))
    let config = try FoldConfig(identity: harnessConfig(), thresholds: thresholds)
    let real = try await runner.run(sets.cleanFalsePositive, config: config)
    let realFlags = Set(real.rows.filter { $0.outcome?.flaggedAfterSuppression == true }.map(\.word.id))
    guard realFlags == Set(clean.flagged.filter(\.value).keys) else {
        throw CLIError.failed("the clean-1,400 flags differ between the shared-detector run and the cached takes")
    }
    let fpGate = Gate.agreement("agreement.l2FalsePositiveMax", \.l2FalsePositiveMax, .atMost)
    let worstGate = Gate.agreement("agreement.l2FalsePositiveWorstSpeakerMax", \.l2FalsePositiveWorstSpeakerMax, .atMost)
    let cleanUnits = sets.cleanFalsePositive.map { ScoredUnit(speaker: $0.speaker, phrase: $0.text, hit: clean.flagged[$0.id] == true) }
    let cleanLine = MetricResult.rate(
        name: "L2 false positives, clean 1,400, after suppression", layer: .shippedConfigCheck, units: cleanUnits,
        gate: fpGate, minimumN: 1)
    negative.append(cleanLine)
    let bySpeaker = Dictionary(grouping: cleanUnits, by: \.speaker).filter { $0.value.count >= 10 }
    let worstSpeaker = bySpeaker.map { id, units in
        WorstCluster(id: id, value: Double(units.count(where: \.hit)) / Double(units.count), n: units.count)
    }.max { ($0.value, $1.id) < ($1.value, $0.id) }
    negative.append(MetricResult(
        name: "L2 false positives, clean 1,400, worst speaker (≥ 10 words)", layer: .shippedConfigCheck,
        n: bySpeaker.count, value: worstSpeaker?.value, gate: worstGate,
        status: worstSpeaker.map { worstGate.passes($0.value) ? .pass : .fail } ?? .notEvaluated(n: 0, minimum: 1),
        worstSpeaker: worstSpeaker))
    for group in [AgeGroup.adult, .child] {
        let units = sets.cleanFalsePositive.filter { labels.speakers[$0.speaker]?.ageGroup == group }
            .map { ScoredUnit(speaker: $0.speaker, phrase: $0.text, hit: clean.flagged[$0.id] == true) }
        metrics.append(MetricResult.rate(
            name: "L2 false positives, clean 1,400, \(group.rawValue)s", layer: .descriptive, units: units, gate: nil,
            minimumN: 1))
    }
    let substituted = sets.cleanFalsePositive.filter { clean.group[$0.id] == .substituted }
    metrics.append(MetricResult(
        name: "Clean 1,400: Whisper-substituted or deleted words (never reach the detector)", layer: .descriptive,
        n: sets.cleanFalsePositive.count, value: Double(substituted.count), gate: nil, status: .reported))
    reported.append("Whisper-substituted or deleted words on the clean 1,400: \(substituted.count): " + substituted.prefix(60).map { "\($0.id) \($0.text)" }.joined(separator: ", ") + (substituted.count > 60 ? ", …" : ""))
    let fpValue = cleanLine.value.map { String(format: "%.1f%%", $0 * 100) } ?? "–"
    reported.append("Clean-1,400 FP after suppression: \(fpValue) (\(cleanUnits.count(where: \.hit)) of \(cleanUnits.count)) on the shipped config, next to spec 08's 10.7% (150 of 1,400) on the initial thresholds")

    // L2 false-flag split (reported; the gate's number is unchanged by it).
    var split: [Spec11Release.SplitRow] = []
    let tunedLabel = tuning?.fallback == false ? "tuned" : "tuned (FALLBACK: the initial thresholds ship)"
    let initialFlags = L2Flags(takes: cleanTakes, detector: detector(base, tuning?.fit.initial.point.applied(to: .current) ?? .current), lowBelow: lowBelow)
    for (label, flags) in [("initial", initialFlags), (tunedLabel, clean)] {
        for group in L2Flags.Group.allCases {
            let words = sets.cleanFalsePositive.filter { flags.group[$0.id] == group }
            let hits = words.count { flags.flagged[$0.id] == true }
            split.append(.init(thresholds: label, group: group.rawValue, flagged: hits, words: words.count,
                               interval: words.isEmpty ? nil : Statistics.wilson(successes: hits, n: words.count)))
        }
        let excluded = sets.cleanFalsePositive.count { flags.group[$0.id] == nil }
        if excluded > 0 { reported.append("L2 split (\(label)): \(excluded) words have no A(w) and get no decision (never flagged)") }
    }

    let suppTakes = try await takes("supplementary", sets.supplementaryFalsePositive)
    let supp = L2Flags(takes: suppTakes, detector: base, lowBelow: lowBelow)
    metrics.append(MetricResult.rate(
        name: "L2 false positives, supplementary 1,868, after suppression", layer: .descriptive,
        units: sets.supplementaryFalsePositive.map { ScoredUnit(speaker: $0.speaker, hit: supp.flagged[$0.id] == true) },
        gate: nil, minimumN: 1))
    let unintelligibleTakes = try await takes("unintelligible", sets.unintelligible)
    let unintelligible = L2Flags(takes: unintelligibleTakes, detector: base, lowBelow: lowBelow)
    let violations = sets.unintelligible.count { unintelligible.flagged[$0.id] == true }
    let unintelligibleGate = Gate.agreement("agreement.unintelligiblePlacementDiffsMax", \.unintelligiblePlacementDiffsMax, .atMost)
    negative.append(MetricResult(
        name: "Unintelligible words with a placement diff (count)", layer: .shippedConfigCheck,
        n: sets.unintelligible.count, value: Double(violations), gate: unintelligibleGate,
        status: unintelligibleGate.passes(Double(violations)) ? .pass : .fail))

    // §1: the CV estimate of the tuning procedure, from the tuning run.
    if let tuning {
        let cv = tuning.l2CV
        let units = sets.recall.map { ScoredUnit(speaker: $0.speaker, phrase: $0.text, hit: cv.after[$0.id] == true) }
        let hits = units.count(where: \.hit)
        let wilson = Statistics.wilson(successes: hits, n: units.count)
        let recallGate = Gate.agreement("agreement.l2RecallMin", \.l2RecallMin, .atLeast)
        let lowerGate = Gate.agreement("agreement.l2RecallWilsonLowerMin", \.l2RecallWilsonLowerMin, .atLeast)
        negative.append(MetricResult.rate(
            name: "L2 recall, CV estimate, after suppression", layer: .cvEstimate, units: units, gate: recallGate,
            minimumN: units.count))
        negative.append(MetricResult(
            name: "L2 recall, CV estimate, Wilson lower bound", layer: .cvEstimate, n: units.count, value: wilson.lower,
            gate: lowerGate, status: lowerGate.passes(wilson.lower) ? .pass : .fail, intervals: [wilson]))
        // §6.5 baseline rule against B1 / B2 on the same 134 words, paired.
        let recall = Double(hits) / Double(units.count)
        let baselineRecall = cv.baselines.mapValues { flags in Double(sets.recall.count { flags[$0.id] == true }) / Double(sets.recall.count) }
        let best = cv.baselines.keys.sorted().max { baselineRecall[$0]! < baselineRecall[$1]! }!
        let paired = ClusteredBootstrap.pairedDifferenceInterval(
            units: sets.recall.map { BootstrapUnit(speaker: $0.speaker, value: cv.after[$0.id] == true ? 1 : 0,
                                                   paired: cv.baselines[best]![$0.id] == true ? 1 : 0) },
            clustering: .speakers, resamples: Int(agreement.bootstrapResamples),
            seed: (try? JSONDecoder().decode(SpeechOceanSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent(Paths.soSplit))).bootstrapSeed) ?? 0)
        let verdict = BaselineRule().evaluate(
            detector: recall, bestBaseline: baselineRecall[best]!, pairedLowerBound: paired.lower, kind: .accuracy)
        negative.append(MetricResult(
            name: "L2 recall, CV estimate, §6.5 baseline rule (best of B1, B2)", layer: .cvEstimate, n: units.count,
            value: recall - baselineRecall[best]!, gate: nil, status: verdict.passes ? .pass : .fail,
            intervals: [paired]))
        for (name, flags) in cv.baselines.sorted(by: { $0.key < $1.key }) {
            let comparison = PairedComparison(outcomes: sets.recall.map {
                (speaker: $0.speaker, detectorRight: cv.after[$0.id] == true, baselineRight: flags[$0.id] == true)
            })
            reported.append(String(format: "§1 baseline %@: recall %d/%d (%.3f); detector vs %@ paired: %d wins, %d losses, McNemar p = %.4f", name, sets.recall.count { flags[$0.id] == true }, sets.recall.count, baselineRecall[name]!, name, comparison.b, comparison.c, comparison.pValue))
        }
        reported.append("§6.5 rule (best baseline \(best)): \(verdict.passes ? "PASS" : "FAIL")\(verdict.failures.isEmpty ? "" : ": " + verdict.failures.joined(separator: "; "))")
        let before = sets.recall.count { cv.before[$0.id] == true }
        metrics.append(MetricResult(
            name: "L2 recall, CV estimate, before suppression", layer: .cvEstimate, n: units.count,
            value: Double(before) / Double(units.count), gate: nil, status: .reported,
            intervals: [Statistics.wilson(successes: before, n: units.count)]))
        func subset(_ name: String, _ words: [SpeechOceanWord]) {
            metrics.append(MetricResult.rate(
                name: "L2 recall, CV estimate, \(name)", layer: .cvEstimate,
                units: words.map { ScoredUnit(speaker: $0.speaker, phrase: $0.text, hit: cv.after[$0.id] == true) },
                gate: nil, minimumN: 1))
        }
        subset("adults", sets.recall.filter { labels.speakers[$0.speaker]?.ageGroup == .adult })
        subset("children", sets.recall.filter { labels.speakers[$0.speaker]?.ageGroup == .child })
        subset("≥ 4 of 5 raters", sets.recallDiagnostic)
        let finalIDs = Set(cv.finalSyllableWords)
        subset("final syllable lengthening-exposed", sets.recall.filter { finalIDs.contains($0.id) })
    } else {
        for name in ["L2 recall, CV estimate, after suppression", "L2 recall, CV estimate, Wilson lower bound",
                     "L2 recall, CV estimate, §6.5 baseline rule (best of B1, B2)"] {
            negative.append(MetricResult(
                name: name, layer: .cvEstimate, n: 0, value: nil, gate: nil,
                status: .notEvaluated(n: 0, minimum: sets.recall.count)))
        }
        reported.append("no tuning run at \(tuningURL.path): run scripts/tune.sh")
    }

    // §4–§4c: the guard on held-out data.
    var conditions: [Spec11Release.Condition] = []
    let guardURL = args.value("guard").map(URL.init(fileURLWithPath:))
    let guardRun = guardURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(GuardRun.self, from: $0) }
    let initialGuardRun = args.value("guard-initial").flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        .flatMap { try? JSONDecoder().decode(GuardRun.self, from: $0) } ?? guardRun
    let inconclusiveLine = positive?.lines.first { $0.name.hasPrefix("Inconclusive pairs") }
    let budget = GuardCheck(
        name: "inconclusive pairs, positive set", set: "vctk-held-out", n: inconclusiveLine?.n ?? 0,
        value: inconclusiveLine?.value, limit: agreement.inconclusivePairsMax,
        status: inconclusiveLine.map { $0.status.isPass ? .met : $0.value == nil ? .notEvaluated : .notMet } ?? .notEvaluated,
        interval: inconclusiveLine?.intervals.first, detail: "agreement.inconclusivePairsMax")
    if let guardRun {
        let evaluation = GuardEvaluation(run: guardRun, scope: .heldOut)
        conditions = [
            .init(number: 1, name: "TTS-vs-MFA control ≤ 2% (§4)", checks: evaluation.condition1),
            .init(number: 2, name: "inconclusive rate inside the 10% budget", checks: [budget]),
            .init(number: 3, name: "b2 vs oracle ≤ 2% flips and ≤ 2 points of inconclusive rise (§4a)", checks: evaluation.condition3),
            .init(number: 4, name: "jitter ±40 ms ≤ 2% flips on each set, pooled and per multi-syllable group (§4b)", checks: evaluation.condition4),
        ]
        reported += evaluation.jitterReported.map(\.line)
        if let initial = initialGuardRun {
            reported += guardBreakdowns(initial, label: initial.thresholdsLabel)
            if initial != guardRun { reported += guardBreakdowns(guardRun, label: guardRun.thresholdsLabel) }
        }
    } else {
        let missing = GuardCheck(name: "guard measurements", set: "–", n: 0, value: nil, limit: nil, status: .notEvaluated,
                                 interval: nil, detail: "no am-timestamps spec11-guard JSON (--guard)")
        conditions = [
            .init(number: 1, name: "TTS-vs-MFA control ≤ 2% (§4)", checks: [missing]),
            .init(number: 2, name: "inconclusive rate inside the 10% budget", checks: [budget]),
            .init(number: 3, name: "b2 vs oracle (§4a)", checks: [missing]),
            .init(number: 4, name: "jitter ±40 ms (§4b)", checks: [missing]),
        ]
    }

    // Reported-only lines.
    reported.append("End-to-end check (ii): NOT EVALUATED (no verified synthetic reference: no ElevenLabs key, and no Premium English voice installed for the Mac fallback; spec 22 never downloads voices)")
    reported.append("Synthetic set which-syllable accuracy and controls: NOT EVALUATED (spec 22's synthetic negative set needs a verified synthetic reference)")
    reported.append("3-take stability (weak length, pitch range, final direction): NOT EVALUATED (\(repeatedTakesNote(corpus: corpus, labels: labels))); the flags stay on, the call goes to CPO")
    if let positive { reported.append("referenceAnomaly: \(describePositive(positive.anomaly))") }
    if let tuning {
        reported.append("VCTK CV estimate, not shipped (6 folds over the tuning speakers): placement diffs \(tuning.vctkCV.placementDiffs)/\(tuning.vctkCV.pairs), any-diff \(tuning.vctkCV.anyDiffs)/\(tuning.vctkCV.pairs), inconclusive \(tuning.vctkCV.inconclusive)/\(tuning.vctkCV.pairs); \(tuning.vctkCV.folds.filter(\.fallback).count) of 6 folds had no feasible point (initial thresholds)")
    }
    for line in reported { print("release: \(line)") }

    // Tuning lines.
    var tuningLines: [String] = []
    if let tuning {
        let fit = tuning.fit
        tuningLines.append("§2 fit: \(fit.evaluated) grid points; \(fit.ruleFeasible) meet the selection rule, \(fit.ruleAndBudgetFeasible) also the 10% budget, \(fit.feasible) also the guard on tuning data; outcome: \(tuning.fallback ? "FALLBACK (" + tuning.fallbackReasons.joined(separator: "; ") + ")" : "chosen point")")
        tuningLines.append("pool: " + tuning.pool.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        tuningLines.append("initial point on the pool: " + scoredText(fit.initial))
        if let c = fit.chosen { tuningLines.append("chosen: " + scoredText(c)) }
        if let c = fit.chosenWithoutGuard { tuningLines.append("the rule's choice ignoring the guard (not shipped): " + scoredText(c)) }
        tuningLines += fit.closest.map { "closest by constraint violation: " + scoredText($0) }
        tuningLines += tuning.guardSummary.map { "guard on tuning data: \($0)" }
        tuningLines += tuning.l2CV.folds.map { f in
            "§1 fold \(f.fold) (\(f.heldOutSpeakers.count) speakers): \(f.ruleFeasible) feasible; " + (f.chosen.map(scoredText) ?? "no feasible point: initial thresholds (FALLBACK)") + "; config \(f.appliedConfigDigest.prefix(8))"
        }
        tuningLines += tuning.verification.map { "verification: \($0)" }
    }

    // Closing lines.
    let positiveStatus = positive?.status
    let negativeMet = negative.allSatisfy(\.status.isPass)
    let summary = ReleaseSummary(
        negativeSet: negativeMet ? .pass : .fail, positiveSet: positiveStatus, gated: (positive?.lines ?? []) + negative)
    let spec11 = Spec11Release(
        conditions: conditions, negativeRows: negative.map(\.name), lowAsrConfidenceBelow: lowBelow,
        falseFlagSplit: split, reportedLines: reported, tuningLines: tuningLines)
    let positiveGated = (positive?.lines ?? []).filter { $0.gate != nil }
    let positiveLine = positiveGated.isEmpty ? "NOT EVALUATED"
        : positiveGated.allSatisfy(\.status.isPass) ? "PASS"
        : "FAIL (\(positiveGated.count { !$0.status.isPass }) of \(positiveGated.count) rows not PASS)"
    let negativeLine = negativeMet ? "PASS" : "FAIL (\(negative.count { !$0.status.isPass }) of \(negative.count) rows not PASS)"
    let releaseMet = summary.releaseGateMet && spec11.guardMet && positiveGated.allSatisfy(\.status.isPass)
    let closing = [
        "Negative set: \(negativeLine)", "Positive set: \(positiveLine)", "Spec 11 guard: \(spec11.guardLine)",
        "Release gate: \(releaseMet ? "MET" : "NOT MET")",
    ]
    let all = (positive.map { $0.lines + [$0.anomaly] } ?? []) + negative + metrics
    for m in negative + metrics { print("release: \(m.layer.label): \(describePositive(m))") }
    for condition in conditions {
        print("release: guard condition \(condition.number) (\(condition.name)): \(condition.met ? "MET" : "NOT MET")")
        for check in condition.checks { print("release:   \(check.line)") }
    }
    for row in split {
        print("release: L2 split (\(row.thresholds), lowAsrConfidenceBelow \(lowBelow)): \(row.group): \(row.flagged) of \(row.words)")
    }
    for line in tuningLines { print("release: tuning: \(line)") }
    for line in closing { print(line) }

    if args.flag("write-report") {
        let manifest = try VCTKEvalSpeakersManifest.load(root.appendingPathComponent(Paths.evalSpeakers))
        let split = try JSONDecoder().decode(
            VCTKSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent(Paths.vctkSplit)))
        var identity = try reportIdentity(
            root: root,
            corpusManifestHash: ReportHashes.corpusManifestHash(fileHashes: [
                manifest.corpusManifestHash, pinValue(root, Paths.so762Pin, "corpusManifestSHA256"),
            ]),
            labelHash: ReportHashes.corpusManifestHash(fileHashes: [
                try sha256(of: root.appendingPathComponent(Paths.evalSpeakers)), labels.sourceSHA256,
                try sha256(of: root.appendingPathComponent(Paths.referenceLists)),
            ]),
            splitPath: Paths.vctkSplit, splitSeed: split.foldSeed)
        identity = ReportIdentity(
            config: identity.config, configDigest: identity.configDigest, corpusManifestHash: identity.corpusManifestHash,
            labelHash: identity.labelHash, splitManifestHash: identity.splitManifestHash, splitSeed: identity.splitSeed,
            sourceTreeHash: identity.sourceTreeHash, evaluatedCommit: identity.evaluatedCommit,
            cleanTree: identity.cleanTree, xcodeVersion: identity.xcodeVersion, swiftVersion: identity.swiftVersion,
            macOSVersion: identity.macOSVersion, runnerImage: identity.runnerImage,
            syntheticReference: .macPremiumFallback(reason: "no key; no Premium English voice installed: NOT EVALUATED"))
        let report = AgreementReport(
            suite: "release", generatedAt: Date(), release: true, identity: identity, metrics: all,
            folds: tuning?.l2CV.foldRecord, summary: summary, notes: notes, spec11: spec11, summaryLines: closing)
        let written = try ReportWriter.write(report, to: ReportWriter.directory(repositoryRoot: root))
        print("wrote \(written.json.path) and .md")
    }
    return 0
}

func scoredText(_ p: ScoredPoint) -> String {
    let m = p.metrics
    let tau = p.point.tau.map { String(format: "(%.2f, %.2f)", $0.medium, $0.high) }.joined(separator: " ")
    return String(format: "w=(%.1f, %.1f, %.1f) λ=%.1f τ=%@: recall %d/%d, VCTK placement FP %d/%d, any-diff %d/%d, shared FP %d/%d, inconclusive %d/%d, violation %.4f",
                  p.point.durationWeight, p.point.energyWeight, p.point.pitchWeight, p.point.lambda, tau,
                  m.recallHits, m.recallN, m.vctkPlacementDiffs, m.vctkPairs, m.vctkAnyDiffs, m.vctkPairs,
                  m.sharedFalsePositives, m.correctN, m.vctkInconclusive, m.vctkPairs, p.violation)
}

/// §4/§4a breakdowns of a guard run: control next to spec 23's 13.7%, b2 next to 22.5% / 22.5%, by cue, syllable
/// count, transition type and boundary error, and b2's inconclusive split.
func guardBreakdowns(_ run: GuardRun, label: String) -> [String] {
    var out: [String] = []
    for set in run.sets {
        for c in set.comparisons where c.evaluated {
            let share = Double(c.differing) / Double(c.words)
            var baseline = ""
            if c.id == "control" { baseline = "; spec 23 on the initial thresholds: 13.7% (42 / 307)" }
            if c.id == "b2" { baseline = set.set == "synthetic" ? "; spec 23: 22.5%, +11.1 points" : "; spec 23 (bundled starter clips): 22.5%, +10.2 points" }
            out.append(String(format: "%@ thresholds, %@, %@: %d of %d words differ (%.1f%%), inconclusive %d → %d%@", label, set.set, c.id, c.differing, c.words, share * 100, c.oracleInconclusive, c.candidateInconclusive, baseline))
            guard ["control", "b2", "jitter-40"].contains(c.id) else { continue }
            let cue = ["inconclusive", "longestSyllable", "loudestSyllable", "syllableCount"]
                .map { "\($0) \(c.parts[$0] ?? 0) (only \(c.onlyCue[$0] ?? 0))" }.joined(separator: ", ")
            out.append("  \(set.set) \(c.id) by cue (duration = longestSyllable, intensity = loudestSyllable; pitch is not a spec 07 verdict part): \(cue)")
            out.append("  \(set.set) \(c.id) by syllables: " + c.bySyllables.map { "\($0.bucket): \($0.differing)/\($0.words), inconclusive \($0.oracleInconclusive) → \($0.candidateInconclusive)" }.joined(separator: "; "))
            out.append("  \(set.set) \(c.id) by transition: feedback↔close (decided↔decided) \(c.transitions.decidedToDecided), anything↔inconclusive \(c.transitions.involvingInconclusive)")
            out.append("  \(set.set) \(c.id) by boundary error: " + c.boundaryError.map { "\($0.bin) \($0.differing)/\($0.words)" }.joined(separator: "; "))
            if let split = c.inconclusiveSplit {
                let rise = split.candidate - split.oracle
                let gate = split.candidate - split.candidateGateBypassed
                out.append("  \(set.set) b2 inconclusive rise \(rise) words: from the CTC confidence gate \(gate), from the margins \(rise - gate) (\(split.gatedWords) words gated)")
            }
        }
        out.append("\(label) thresholds, \(set.set): Whisper-substituted \(set.substituted), deleted \(set.deleted) (kept out of every diff); \(set.clips) clips\(set.clipsSkipped.isEmpty ? "" : ", \(set.clipsSkipped.count) skipped")")
    }
    return out
}

/// Whether the corpora have repeated takes of one phrase by one speaker (§5).
func repeatedTakesNote(corpus: SpeechOceanCorpusFiles, labels: SpeechOceanLabels) -> String {
    var counts: [String: Int] = [:]
    for utterance in Set(labels.words.map(\.utterance)) {
        let speaker = labels.words.first { $0.utterance == utterance }?.speaker ?? ""
        counts[speaker + "|" + corpus.transcript(utterance: utterance).joined(separator: " ").lowercased(), default: 0] += 1
    }
    let repeated = counts.values.count { $0 >= 3 }
    return "speechocean762: \(repeated) speaker × utterance texts with 3 or more takes among the labelled utterances; VCTK: one take per speaker per prompt"
}

extension TuningPoint {
    /// The initial config's digest, 8 hex (the tuning run's file name).
    static func initialDigest8(root: URL) -> String {
        (try? configDigest(harnessConfig()).prefix(8)).map(String.init) ?? ""
    }
}
