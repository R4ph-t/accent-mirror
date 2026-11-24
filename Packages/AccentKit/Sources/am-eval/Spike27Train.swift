// Spec 27 §1/§2 on the tuning side only: per arm and variant, speaker-grouped CV (the split manifest's 6 folds) for
// τ on the CV Wilson upper bound of native false flags (point ≤ 1%, upper ≤ 2%, n ≥ 600), the variant, the arm, the
// artefact control (processed vs raw AUC), and the per-prompt native envelopes with their quantile pair. Every input
// goes through Spike27Guard first.

import AMAlignment
import AMCore
import AMEvaluation
import AMSpike27
import AMTimestampEval
import Foundation

/// One scored take of the training side: the take and which of its words count.
struct TrainingTake: Sendable {
    enum Kind: String, Sendable, Codable { case positive, negative }
    let key: String
    let speaker: String
    let population: Population
    /// Nil: the TTS voice, always on the training side of every fold.
    let fold: Int?
    let kind: Kind
    let measured: MeasuredAudio
    let words: [TimedWord]
    /// Negative: the swapped word's index and the syllable that now carries the stress.
    let negativeWord: Int?
    let negativeLabel: Int?
}

struct CVPoint: Codable, Sendable {
    let tau: Double
    let positives: Int
    let flags: Int
    let negatives: Int
    let negativeFlags: Int
    let negativeAbstained: Int
    var falseFlagRate: Double { positives == 0 ? 1 : Double(flags) / Double(positives) }
    var falseFlagUpper: Double { SpikeStats.wilson(flags, positives).upper }
    var recall: Double { negatives == 0 ? 0 : Double(negativeFlags) / Double(negatives) }
    /// CTO markup 5 + lit amendment 1: point ≤ 1% and CV Wilson upper bound ≤ 2% (n ≥ 600 is gate 1's, on evaluation).
    var meetsBar: Bool { positives > 0 && falseFlagRate <= 0.01 + 1e-12 && falseFlagUpper <= 0.02 + 1e-12 }
}

struct VariantResult: Codable, Sendable {
    let family: ModelFamily
    let variant: Variant
    let points: [CVPoint]
    /// The frozen τ: the smallest grid τ meeting the bar; nil when none does.
    let tau: Double?
    /// When no τ meets the bar: the τ with the lowest CV Wilson upper bound (largest on ties), used for reporting.
    let fallbackTau: Double
    var operatingTau: Double { tau ?? fallbackTau }
    var operating: CVPoint { points.first { abs($0.tau - operatingTau) < 1e-9 }! }
}

struct ArmTraining: Codable, Sendable {
    let arm: Arm
    let trainingWords: Int
    let positiveWords: Int
    let negativeWords: Int
    let positiveAbstained: [String: Int]
    let negativeAbstained: [String: Int]
    let variants: [VariantResult]
    let chosenFamily: ModelFamily
    let chosenVariant: Variant
    let variantRule: String
    let tau: Double
    let tauMeetsBar: Bool
    let jitterTuning: FlipCount
    let artefactAUC: Double?
    let artefactRows: Int
    /// Reported control beyond CTO markup 4: round-trip (swap, swap back) vs raw on the negatives' words.
    let roundTripAUC: Double?
    let roundTripRows: Int
    /// Tuning-side diagnostic on raw natives (oracle words): how often the dictionary-stressed syllable is the argmax
    /// of each raw measure among the word's nuclei, beside the first-syllable prior.
    let signalCheck: [String: Double]
    let signalWords: Int
    let classifier: StressClassifier
    var passesTuning: Bool { tauMeetsBar && jitterTuning.rate <= 0.02 + 1e-12 }
}

struct FlipCount: Codable, Sendable {
    let n: Int
    let flips: Int
    var rate: Double { n == 0 ? 0 : Double(flips) / Double(n) }
}

struct PromptEnvelope: Codable, Sendable {
    let prompt: String
    let natural: Int
    let ttsVoices: Int
    let evaluated: Bool
    let pitchRange: [Double]?
    let finalSlope: [Double]?
    let npvi: [Double]?
    let dominantFinal: FinalClass?
    let dominantShare: Double?
    let finalDirectionVerdicted: Bool
}

struct QuantileChoice: Codable, Sendable {
    let metric: String
    let candidates: [[Double]]
    let chosen: Double?
}

struct TrainingFile: Codable {
    let seed: UInt64
    let folds: [[String]]
    let tauGrid: [Double]
    let identityTakes: Int
    let negatives: Int
    let negativeSourceWords: Int
    let negativesDropped: [String: Int]
    let extremeDurationRatio: Int
    let arms: [ArmTraining]
    let chosenArm: Arm
    let armRule: String
    let envelopes: [PromptEnvelope]
    let quantiles: [QuantileChoice]
    let finalDirectionPrompts: [String]
}

enum SpikeTrain {
    static let tauGrid: [Double] = (0...45).map { Double($0) * 0.02 } + [0.95, 0.99]
    static let jitterRadiusMs = 40

    static func trainingRows(_ takes: [TrainingTake], arm: Arm) -> (words: [(nuclei: [MeasuredNucleus], label: Int)],
                                                                     positives: Int, negatives: Int,
                                                                     positiveAbstained: [String: Int],
                                                                     negativeAbstained: [String: Int]) {
        var words: [(nuclei: [MeasuredNucleus], label: Int)] = []
        var positives = 0, negatives = 0
        var pa: [String: Int] = [:], na: [String: Int] = [:]
        for take in takes {
            let selection = TakeScoring.select(take.measured, words: take.words, arm: arm, source: .oracle,
                                               classifier: nil, tau: 0)
            // Sorted: dictionary order is per-process random, and row order changes the fitted floats.
            for (j, result) in selection.sorted(by: { $0.key < $1.key }) {
                let word = take.words[j]
                if take.kind == .negative && word.index != take.negativeWord { continue }
                switch result {
                case .success(let list):
                    let label = take.kind == .positive ? word.target! : take.negativeLabel!
                    words.append((list.map { take.measured.nuclei[$0] }, label))
                    if take.kind == .positive { positives += 1 } else { negatives += 1 }
                case .failure(let e):
                    if take.kind == .positive { pa[e.reason.rawValue, default: 0] += 1 } else { na[e.reason.rawValue, default: 0] += 1 }
                }
            }
        }
        return (words, positives, negatives, pa, na)
    }

    /// The out-of-fold outcomes of every take at every τ.
    static func cv(_ takes: [TrainingTake], arm: Arm, variant: Variant, family: ModelFamily, folds: Int) -> [CVPoint] {
        var counts = [(p: Int, f: Int, n: Int, nf: Int, na: Int)](repeating: (0, 0, 0, 0, 0), count: tauGrid.count)
        for fold in 0..<folds {
            let train = takes.filter { $0.fold != fold }
            let classifier = StressClassifier.fit(trainingRows(train, arm: arm).words, variant: variant, family: family)
            for take in takes where take.fold == fold {
                for (t, tau) in tauGrid.enumerated() {
                    let outcomes = TakeScoring.score(take.measured, words: take.words, arm: arm, source: .oracle,
                                                     classifier: classifier, tau: tau)
                    for o in outcomes {
                        if take.kind == .positive {
                            if !o.verdict.isAbstain { counts[t].p += 1; if o.verdict.isFlag { counts[t].f += 1 } }
                        } else if o.index == take.negativeWord {
                            counts[t].n += 1
                            if o.verdict.isFlag { counts[t].nf += 1 }
                            if o.verdict.isAbstain { counts[t].na += 1 }
                        }
                    }
                }
            }
        }
        return zip(tauGrid, counts).map {
            CVPoint(tau: $0.0, positives: $0.1.p, flags: $0.1.f, negatives: $0.1.n, negativeFlags: $0.1.nf,
                    negativeAbstained: $0.1.na)
        }
    }

    static func variantResult(_ variant: Variant, family: ModelFamily, points: [CVPoint]) -> VariantResult {
        let tau = points.first(where: \.meetsBar)?.tau
        let fallback = points.min { a, b in
            a.falseFlagUpper != b.falseFlagUpper ? a.falseFlagUpper < b.falseFlagUpper : a.tau > b.tau
        }!.tau
        return VariantResult(family: family, variant: variant, points: points, tau: tau, fallbackTau: fallback)
    }

    /// Lit amendment 2: the feasible variant with the highest CV recall at its τ (fewer features on a tie); with none
    /// feasible, the lowest CV Wilson upper bound of native false flags.
    /// Lit amendment 2 + CTO decision 1, tuning side only: among (family, variant) pairs meeting the CV false-flag bar,
    /// the highest CV recall at its τ; ties go to logistic regression, then to fewer features. With none feasible,
    /// the lowest CV Wilson upper bound of native false flags.
    static func chooseVariant(_ results: [VariantResult]) -> VariantResult {
        func simpler(_ a: VariantResult, _ b: VariantResult) -> Bool {
            if a.family != b.family { return a.family == .logistic }
            return a.variant.size < b.variant.size
        }
        let feasible = results.filter { $0.tau != nil }
        if let best = feasible.max(by: { a, b in
            a.operating.recall != b.operating.recall ? a.operating.recall < b.operating.recall : simpler(b, a)
        }) {
            return best
        }
        return results.min { a, b in
            a.operating.falseFlagUpper != b.operating.falseFlagUpper ? a.operating.falseFlagUpper < b.operating.falseFlagUpper
                : simpler(a, b)
        }!
    }

    /// A binary scorer of the given family on raw rows (the artefact controls: the same features and model family).
    static func binaryScorer(_ x: [[Double]], _ y: [Bool], names: [String], family: ModelFamily) -> @Sendable ([Double]) -> Double {
        switch family {
        case .logistic:
            let m = LogisticModel.fit(x, y, names: names)
            return { m.probability($0) }
        case .trees:
            let t = BoostedTrees.fit(x, y, names: names)
            return { t.probability($0) }
        }
    }

    /// ±40 ms flips on the raw tuning takes (oracle spans jittered, spec 11 §4b), out-of-fold models. A flip to or
    /// from abstain counts.
    static func tuningJitter(_ clips: [SpikeClip], arm: Arm, models: [Int: StressClassifier], tau: Double,
                             fold: (SpikeClip) -> Int?, seed: UInt64) -> FlipCount {
        var n = 0, flips = 0
        for clip in clips {
            guard let f = fold(clip), let model = models[f], let words = clip.words(.oracle) else { continue }
            let base = TakeScoring.score(clip.measured, words: words, arm: arm, source: .oracle, classifier: model, tau: tau)
            let moved = jittered(words, duration: clip.measured.duration, seed: seed, clipID: clip.id)
            let after = Dictionary(uniqueKeysWithValues: TakeScoring.score(
                clip.measured, words: moved, arm: arm, source: .oracle, classifier: model, tau: tau).map { ($0.index, $0) })
            for o in base {
                n += 1
                if after[o.index]?.verdict != o.verdict { flips += 1 }
            }
        }
        return FlipCount(n: n, flips: flips)
    }

    static func jittered(_ words: [TimedWord], duration: Double, seed: UInt64, clipID: String) -> [TimedWord] {
        let spans = words.map { Jitter.Span(start: $0.start, end: $0.end) }
        let moved = Jitter.jitter(spans, duration: duration, radiusMs: jitterRadiusMs, seed: seed, clipID: clipID)
        return zip(words, moved).map { $0.moved(start: $1.span.start, end: $1.span.end) }
    }

    /// CTO markup 4: processed-vs-raw classifier (same features, same model family), trained and scored on held-out
    /// tuning folds; nucleus rows of the words both takes put through the arm.
    static func artefactAUC(_ clips: [SpikeClip], identity: [String: MeasuredAudio], arm: Arm, variant: Variant,
                            family: ModelFamily, fold: (SpikeClip) -> Int?, folds: Int) -> (Double?, Int) {
        var rows: [(fold: Int, row: [Double], processed: Bool)] = []
        for clip in clips {
            guard let f = fold(clip), let processed = identity[clip.id], let words = clip.words(.oracle) else { continue }
            let raw = TakeScoring.select(clip.measured, words: words, arm: arm, source: .oracle, classifier: nil, tau: 0)
            let pro = TakeScoring.select(processed, words: words, arm: arm, source: .oracle, classifier: nil, tau: 0)
            for (j, r) in raw.sorted(by: { $0.key < $1.key }) {
                guard case .success(let a) = r, case .success(let b)? = pro[j] else { continue }
                for row in Features.rows(a.map { clip.measured.nuclei[$0] }, variant: variant) { rows.append((f, row, false)) }
                for row in Features.rows(b.map { processed.nuclei[$0] }, variant: variant) { rows.append((f, row, true)) }
            }
        }
        var positives: [Double] = [], negatives: [Double] = []
        for f in 0..<folds {
            let train = rows.filter { $0.fold != f }
            guard !train.isEmpty else { continue }
            let score = binaryScorer(train.map(\.row), train.map(\.processed), names: Features.names(variant), family: family)
            for r in rows where r.fold == f {
                let p = score(r.row)
                if r.processed { positives.append(p) } else { negatives.append(p) }
            }
        }
        return (ROC.auc(positives: positives, negatives: negatives), rows.count)
    }
}

extension SpikeTrain {
    /// Round-trip control (reported): the negative's word in the swapped-back take vs the same word in the raw take,
    /// nucleus rows, the same features and model family, CV on held-out tuning folds.
    static func roundTripAUC(_ negatives: [SpikeNegative], raw: [String: SpikeClip], arm: Arm, variant: Variant,
                             family: ModelFamily, fold: (Population, String) -> Int?, folds: Int) -> (Double?, Int) {
        var rows: [(fold: Int, row: [Double], processed: Bool)] = []
        for negative in negatives {
            guard let f = fold(negative.population, negative.speaker), let clip = raw[negative.clip],
                  let words = clip.words(.oracle), let j = words.firstIndex(where: { $0.index == negative.word }) else { continue }
            let a = TakeScoring.select(clip.measured, words: words, arm: arm, source: .oracle, classifier: nil, tau: 0)[j]
            let b = TakeScoring.select(negative.roundTrip, words: words, arm: arm, source: .oracle, classifier: nil, tau: 0)[j]
            guard case .success(let x)? = a, case .success(let y)? = b else { continue }
            for row in Features.rows(x.map { clip.measured.nuclei[$0] }, variant: variant) { rows.append((f, row, false)) }
            for row in Features.rows(y.map { negative.roundTrip.nuclei[$0] }, variant: variant) { rows.append((f, row, true)) }
        }
        var positives: [Double] = [], negativesScores: [Double] = []
        for f in 0..<folds {
            let train = rows.filter { $0.fold != f }
            guard !train.isEmpty else { continue }
            let score = binaryScorer(train.map(\.row), train.map(\.processed), names: Features.names(variant), family: family)
            for r in rows where r.fold == f {
                let p = score(r.row)
                if r.processed { positives.append(p) } else { negativesScores.append(p) }
            }
        }
        return (ROC.auc(positives: positives, negatives: negativesScores), rows.count)
    }
}

func spike27Train(_ env: SpikeEnvironment) async throws {
    let url = env.file("training.json")
    let negativesFile = try JSONDecoder().decode(NegativesFile.self, from: Data(contentsOf: env.file("negatives.json")))
    let tuning = try await SpikeData.clips(.tuningVCTK, env: env, log: spikeLog)
    let tts = try await SpikeData.clips(.tts, env: env, log: spikeLog)
    let clips = tuning + tts
    // Guardrails: nothing but tuning-side data reaches training, τ, the variant or the arm.
    try Spike27Guard.checkTraining(clips.map { ($0.population, $0.speaker) }, split: env.split, use: "training")
    try Spike27Guard.checkTraining(negativesFile.negatives.map { ($0.population, $0.speaker) }, split: env.split, use: "training")
    let folds = env.split.cvFolds.count
    let bundledVoices = ["p225", "p226", "p227", "p233", "p241", "p252", "p311", "p345"]
    func fold(_ population: Population, _ speaker: String) -> Int? {
        Spike27Guard.fold(of: speaker, population: population, split: env.split, bundledVoices: bundledVoices)
    }
    let identity = Dictionary(uniqueKeysWithValues: negativesFile.identity.map { ($0.clip, $0.measured) })
    var takes: [TrainingTake] = []
    for clip in clips {
        guard let processed = identity[clip.id], let words = clip.words(.oracle) else { continue }
        takes.append(TrainingTake(key: clip.id, speaker: clip.speaker, population: clip.population,
                                  fold: fold(clip.population, clip.speaker), kind: .positive, measured: processed,
                                  words: words, negativeWord: nil, negativeLabel: nil))
    }
    for negative in negativesFile.negatives {
        takes.append(TrainingTake(key: negative.id, speaker: negative.speaker, population: negative.population,
                                  fold: fold(negative.population, negative.speaker), kind: .negative,
                                  measured: negative.measured, words: negative.words, negativeWord: negative.word,
                                  negativeLabel: negative.swapped))
    }
    spikeLog("spike27 train: \(takes.count) training-side takes (\(negativesFile.identity.count) identity, "
             + "\(negativesFile.negatives.count) negatives), \(folds) speaker folds")

    let allTakes = takes
    // CTO decision 1: logistic regression first; boosted trees too, because logistic regression missed gate 2 on the
    // first evaluation run (arm B runtime: 10/134 vs B1 27/134) and time allowed. The family is still chosen on
    // tuning-side CV only (`chooseVariant`); `--families logistic` reproduces the logistic-only run.
    let families = env.families
    var arms: [ArmTraining] = []
    for arm in Arm.allCases {
        let rows = SpikeTrain.trainingRows(takes, arm: arm)
        var results: [VariantResult] = []
        try await withThrowingTaskGroup(of: VariantResult.self) { group in
            for family in families {
                for variant in Variant.allCases {
                    group.addTask {
                        SpikeTrain.variantResult(variant, family: family,
                                                 points: SpikeTrain.cv(allTakes, arm: arm, variant: variant, family: family, folds: folds))
                    }
                }
            }
            for try await r in group { results.append(r) }
        }
        results.sort { (ModelFamily.allCases.firstIndex(of: $0.family)!, Variant.allCases.firstIndex(of: $0.variant)!)
            < (ModelFamily.allCases.firstIndex(of: $1.family)!, Variant.allCases.firstIndex(of: $1.variant)!) }
        let chosen = SpikeTrain.chooseVariant(results)
        let variant = chosen.variant, family = chosen.family
        let rule = chosen.tau != nil
            ? "highest CV recall at its τ among the (family, variant) pairs meeting the CV false-flag bar; ties to logistic regression, then fewer features"
            : "no (family, variant) pair meets the CV false-flag bar at any τ: lowest CV Wilson upper bound"
        var models: [Int: StressClassifier] = [:]
        for f in 0..<folds {
            models[f] = StressClassifier.fit(SpikeTrain.trainingRows(takes.filter { $0.fold != f }, arm: arm).words,
                                             variant: variant, family: family)
        }
        let jitter = SpikeTrain.tuningJitter(tuning, arm: arm, models: models, tau: chosen.operatingTau,
                                             fold: { fold($0.population, $0.speaker) }, seed: env.split.foldSeed)
        let (auc, aucRows) = SpikeTrain.artefactAUC(tuning, identity: identity, arm: arm, variant: variant, family: family,
                                                    fold: { fold($0.population, $0.speaker) }, folds: folds)
        let classifier = StressClassifier.fit(rows.words, variant: variant, family: family)
        let (roundAUC, roundRows) = SpikeTrain.roundTripAUC(negativesFile.negatives, raw: Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) }),
                                                            arm: arm, variant: variant, family: family, fold: fold, folds: folds)
        var argmax: [String: Int] = [:]
        var signalWords = 0
        for clip in tuning {
            guard let words = clip.words(.oracle) else { continue }
            for (j, r) in TakeScoring.select(clip.measured, words: words, arm: arm, source: .oracle, classifier: nil, tau: 0)
                .sorted(by: { $0.key < $1.key }) {
                guard case .success(let list) = r, let target = words[j].target else { continue }
                let n = list.map { clip.measured.nuclei[$0] }
                signalWords += 1
                func best(_ v: [Double]) -> Int { v.indices.max { v[$0] < v[$1] || (v[$0] == v[$1] && $0 > $1) }! }
                if best(n.map(\.duration)) == target { argmax["duration", default: 0] += 1 }
                if best(n.map(\.energyDB)) == target { argmax["intensity", default: 0] += 1 }
                if best(n.map { $0.f0Residual ?? -99 }) == target { argmax["f0 residual", default: 0] += 1 }
                if best(n.map { -$0.tiltDB }) == target { argmax["flattest spectrum (−tilt)", default: 0] += 1 }
                if target == 0 { argmax["first-syllable prior", default: 0] += 1 }
            }
        }
        let signal = argmax.mapValues { Double($0) / Double(max(signalWords, 1)) }
        let result = ArmTraining(
            arm: arm, trainingWords: rows.words.count, positiveWords: rows.positives, negativeWords: rows.negatives,
            positiveAbstained: rows.positiveAbstained, negativeAbstained: rows.negativeAbstained, variants: results,
            chosenFamily: family, chosenVariant: variant, variantRule: rule, tau: chosen.operatingTau, tauMeetsBar: chosen.tau != nil,
            jitterTuning: jitter, artefactAUC: auc, artefactRows: aucRows, roundTripAUC: roundAUC, roundTripRows: roundRows,
            signalCheck: signal, signalWords: signalWords, classifier: classifier)
        arms.append(result)
        for r in results {
            let o = r.operating
            spikeLog(String(format: "spike27 train: arm %@ %@ %@: τ %@ (%.2f) CV FF %d/%d %.2f%% (upper %.2f%%), recall %d/%d %.1f%%",
                            arm.rawValue, r.family.rawValue, r.variant.rawValue, r.tau == nil ? "NOT FOUND" : "met", r.operatingTau,
                            o.flags, o.positives, o.falseFlagRate * 100, o.falseFlagUpper * 100, o.negativeFlags,
                            o.negatives, o.recall * 100))
        }
        spikeLog(String(format: "spike27 train: arm %@ chose %@ / %@ (%@), τ %.2f; tuning jitter %d/%d %.2f%%; artefact AUC %@; round-trip AUC %@ (%d rows)",
                        arm.rawValue, family.rawValue, variant.rawValue, rule, chosen.operatingTau, jitter.flips, jitter.n,
                        jitter.rate * 100, auc.map { String(format: "%.3f", $0) } ?? "–",
                        roundAUC.map { String(format: "%.3f", $0) } ?? "–", roundRows))
    }
    let a = arms.first { $0.arm == .a }!, b = arms.first { $0.arm == .b }!
    let chosenArm: Arm
    let armRule: String
    if b.passesTuning { chosenArm = .b; armRule = "B passes the tuning-side checks (CV false-flag bar, tuning jitter ≤ 2%); B is preferred" }
    else if a.passesTuning { chosenArm = .a; armRule = "only A passes the tuning-side checks" }
    else {
        let ua = a.variants.first { $0.variant == a.chosenVariant && $0.family == a.chosenFamily }!.operating.falseFlagUpper
        let ub = b.variants.first { $0.variant == b.chosenVariant && $0.family == b.chosenFamily }!.operating.falseFlagUpper
        chosenArm = ua < ub ? .a : .b
        armRule = "neither arm passes the tuning-side checks: the lower CV Wilson upper bound of native false flags (B on a tie)"
    }
    spikeLog("spike27 train: chosen arm \(chosenArm.rawValue) (\(armRule))")

    // §2: per-prompt native envelopes (runtime words; natural speakers only: bundled voices and VCTK tuning speakers).
    let bundled = try await SpikeData.clips(.bundled, env: env, log: spikeLog)
    let starterIDs = Set(bundled.map(\.phrase))
    let envelopeClips = (tuning + bundled).filter { starterIDs.contains($0.phrase) && $0.words(.runtime) != nil }
    try Spike27Guard.checkEnvelope(envelopeClips.map { ($0.population, $0.speaker) }, split: env.split)
    let takesByPrompt = Dictionary(grouping: envelopeClips, by: \.phrase).mapValues { clips in
        clips.map { clip in
            (fold(clip.population, clip.speaker),
             EnvelopeTake(speaker: clip.speaker, population: clip.population,
                          metrics: PhraseMetrics.measure(clip.measured, words: clip.words(.runtime)!)))
        }
    }
    let prompts = takesByPrompt.keys.sorted()
    var finalPrompts: [String] = []
    for prompt in prompts {
        let envelopeTakes = takesByPrompt[prompt]!.map(\.1)
        if let (_, share) = NativeEnvelope.dominantFinal(envelopeTakes), share >= 0.8 { finalPrompts.append(prompt) }
    }
    let eligible = prompts.filter { NativeEnvelope.counts(takesByPrompt[$0]!.map(\.1)).natural >= NativeEnvelope.minimumNaturalTakes }
    func cvQuantile(_ metric: String, prompts: [String], value: @escaping (PhraseMetrics) -> Double?,
                    flag: @escaping (PhraseMetrics, ClosedRange<Double>, [EnvelopeTake]) -> Bool?) -> QuantileChoice {
        var candidates: [[Double]] = []
        var chosen: Double?
        for q in NativeEnvelope.quantiles {
            var n = 0, flags = 0
            for prompt in prompts {
                let all = takesByPrompt[prompt]!
                for f in 0..<folds {
                    let train = all.filter { $0.0 != f }.map(\.1).filter { $0.ttsVoice == nil }
                    let values = train.compactMap { value($0.metrics) }.sorted()
                    guard values.count >= 2 else { continue }
                    let interval = PhraseMetrics.percentile(values, q * 100)...PhraseMetrics.percentile(values, (1 - q) * 100)
                    for take in all where take.0 == f {
                        guard let flagged = flag(take.1.metrics, interval, train) else { continue }
                        n += 1
                        if flagged { flags += 1 }
                    }
                }
            }
            let upper = SpikeStats.wilson(flags, n).upper
            candidates.append([q, Double(n), Double(flags), upper])
            if n > 0 && upper <= 0.05 + 1e-12 { chosen = q }
        }
        return QuantileChoice(metric: metric, candidates: candidates, chosen: chosen)
    }
    let monotoneChoice = cvQuantile("monotone (pitch range below the envelope)", prompts: eligible,
                                    value: \.pitchRange) { m, interval, _ in NativeEnvelope.monotone(m, envelope: interval) }
    let finalChoice = cvQuantile("final direction (slope outside the envelope, class not the dominant one)",
                                 prompts: eligible.filter(finalPrompts.contains), value: \.finalSlope) { m, interval, train in
        guard let (dominant, _) = NativeEnvelope.dominantFinal(train) else { return nil }
        return NativeEnvelope.finalDirection(m, envelope: interval, dominant: dominant)
    }
    var envelopes: [PromptEnvelope] = []
    for prompt in prompts {
        let envelopeTakes = takesByPrompt[prompt]!.map(\.1)
        let counts = NativeEnvelope.counts(envelopeTakes)
        let dominant = NativeEnvelope.dominantFinal(envelopeTakes)
        func interval(_ value: @escaping (PhraseMetrics) -> Double?, _ q: Double?) -> [Double]? {
            NativeEnvelope.interval(envelopeTakes, value: value, q: q ?? 0).map { [$0.lowerBound, $0.upperBound] }
        }
        envelopes.append(PromptEnvelope(
            prompt: prompt, natural: counts.natural, ttsVoices: counts.ttsVoices,
            evaluated: counts.natural >= NativeEnvelope.minimumNaturalTakes,
            pitchRange: interval(\.pitchRange, monotoneChoice.chosen), finalSlope: interval(\.finalSlope, finalChoice.chosen),
            npvi: interval(\.npvi, 0.025), dominantFinal: dominant?.0, dominantShare: dominant?.1,
            finalDirectionVerdicted: finalPrompts.contains(prompt)))
    }
    for e in envelopes {
        spikeLog("spike27 envelope: \(e.prompt) natural \(e.natural)\(e.evaluated ? "" : " (NOT EVALUATED: < 30)") "
                 + "range \(e.pitchRange.map { String(format: "%.2f…%.2f st", $0[0], $0[1]) } ?? "–") "
                 + "final \(e.dominantFinal?.rawValue ?? "–") \(e.dominantShare.map { String(format: "%.0f%%", $0 * 100) } ?? "")")
    }
    spikeLog("spike27 envelope: quantiles monotone \(monotoneChoice.chosen.map { String($0) } ?? "NONE ≤ 5%"), "
             + "final \(finalChoice.chosen.map { String($0) } ?? "NONE ≤ 5%"); final-direction prompts \(finalPrompts)")

    let file = TrainingFile(
        seed: env.split.foldSeed, folds: env.split.cvFolds, tauGrid: SpikeTrain.tauGrid,
        identityTakes: negativesFile.identity.count, negatives: negativesFile.negatives.count,
        negativeSourceWords: negativesFile.sourceWords, negativesDropped: negativesFile.dropped,
        extremeDurationRatio: negativesFile.extremeDurationRatio, arms: arms, chosenArm: chosenArm, armRule: armRule,
        envelopes: envelopes, quantiles: [monotoneChoice, finalChoice], finalDirectionPrompts: finalPrompts)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(file).write(to: url)
    // The final-direction prompt list is fixed and committed before any evaluation run (§2).
    struct PromptList: Encodable { let description: String; let rule: String; let prompts: [String] }
    let list = PromptList(
        description: "Spec 27 §2: prompts whose final direction is verdicted. Fixed from tuning-side native takes (bundled voices and VCTK tuning speakers, runtime word times) before any evaluation run.",
        rule: ">= 80% of the tuning-side native takes share one final-direction class (rise / fall / level, ±5 st/s)",
        prompts: finalPrompts)
    try (encoder.encode(list) + Data("\n".utf8)).write(
        to: env.root.appendingPathComponent("docs/agreement/spike27/final-direction-prompts.json"))
    // §5: the training manifest (no audio): every training-side take and negative, with its fold and swap.
    struct ManifestTake: Encodable { let clip: String; let speaker: String; let population: String; let fold: Int? }
    struct ManifestNegative: Encodable { let id: String; let clip: String; let word: Int; let target: Int; let swapped: Int; let syllables: Int }
    struct Manifest: Encodable {
        let description: String
        let seed: UInt64
        let folds: [[String]]
        let positives: [ManifestTake]
        let negativeSourceWords: Int
        let negatives: [ManifestNegative]
        let dropped: [String: Int]
    }
    let manifest = Manifest(
        description: "Spec 27 §5 training manifest (no audio). Positives: tuning-side takes through the identity TD-PSOLA path, MFA word boundaries. Negatives: one seeded stressed↔unstressed swap per native multi-syllable word whose front end found its N nuclei; syllables 0-based in the context pronunciation. Fold null: the TTS voice, on the training side of every fold.",
        seed: env.split.foldSeed, folds: env.split.cvFolds,
        positives: clips.map { ManifestTake(clip: $0.id, speaker: $0.speaker, population: $0.population.rawValue,
                                            fold: fold($0.population, $0.speaker)) },
        negativeSourceWords: negativesFile.sourceWords,
        negatives: negativesFile.negatives.map { ManifestNegative(id: $0.id, clip: $0.clip, word: $0.word, target: $0.target,
                                                                   swapped: $0.swapped, syllables: $0.syllables) },
        dropped: negativesFile.dropped)
    let compact = JSONEncoder()
    compact.outputFormatting = [.sortedKeys, .prettyPrinted]
    try (compact.encode(manifest) + Data("\n".utf8)).write(
        to: env.root.appendingPathComponent("docs/agreement/spike27/training-manifest.json"))
    spikeLog("spike27 train: wrote \(url.path), docs/agreement/spike27/final-direction-prompts.json and training-manifest.json")
}
