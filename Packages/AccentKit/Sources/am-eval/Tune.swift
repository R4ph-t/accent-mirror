// Spec 11 §1, §2 and §4c: the tuning run (`scripts/tune.sh`). Local only, on cached features; never in PR CI.
//
// 1. Features, once per take, on tuning data only: the shared detector's L0/L1 for every speechocean762 utterance of
//    the tuning pool (per set, exactly as `SharedDetectorRunner` builds them), and the spec 12 analyzer's L1 for every
//    VCTK tuning pair and its native readers. Held-out VCTK speakers, test-half words and synthetic audio never enter.
// 2. Unit tables: each unit's outcome at every (weights, λ) and every value of its τ axes, through the real stages
//    (`StressPlacementDetector.place`, `PairScoring.input`, `Scorer.score`). Only the six tuned keys change.
// 3. Searches (`TuningSearch`, spec 02's rule unchanged): the shipped fit (§2) on the whole pool with the guard (§4c),
//    the 5-fold nested CV (§1) and the 6-fold VCTK CV.
// Verification printed with the run: the tables at the initial point reproduce the real runs (shared-detector flags
// and the analyzer's pair decisions), and random grid points evaluated directly match the tables.

import AMAlignment
import AMCore
import AMEvaluation
import AMLibrary
import AMPipeline
import AMPitch
import AMProsody
import AMScoring
import AMWarp
import Foundation

// MARK: - Replay from several folders

/// Replays from whichever recording folder has the clip (the tuning takes and the bundled readers live apart).
struct ReplayUnion: WordTimestamper {
    let parts: [FixtureTimestamper]
    var asrModelID: String { parts[0].asrModelID }

    func wordTimestamps(for request: TimestampRequest) async throws -> [WordTimestamp] {
        for part in parts where part.recording(for: request.clipID) != nil {
            return try await part.wordTimestamps(for: request)
        }
        throw TimestamperError.notRecorded(clipID: request.clipID)
    }
}

// MARK: - Thresholds at a grid coordinate

/// The thresholds a unit is evaluated with: `.current` with the grid's weights and λ at `k` and the τ of `combination`
/// on the unit's axes (initial τ elsewhere; the unit reads no other bucket).
func unitThresholds(k: Int, combination: Int, axes: [TauAxis], grid: TuningGrid) -> Thresholds {
    let initial = TuningPoint(.current)
    let (weights, lambda) = grid.weightsAndLambda(k)
    let tau = TuningUnitTable.tau(combination: combination, axes: axes, grid: grid, initial: initial)
    return TuningPoint(durationWeight: weights[0], energyWeight: weights[1], pitchWeight: weights[2], lambda: lambda, tau: tau)
        .applied(to: .current)
}

func detector(_ base: StressPlacementDetector, _ thresholds: Thresholds) -> StressPlacementDetector {
    StressPlacementDetector(
        voicing: base.voicing, pitchTracker: base.pitchTracker, aligner: base.aligner, thresholds: thresholds)
}

// MARK: - L2 takes

/// One speechocean762 utterance as the shared detector analysed it for one set, kept for re-placing at every point.
struct L2Take: Sendable {
    let set: String
    let utterance: String
    let speaker: String
    /// Words and A(w) only; `place` reads nothing else of the take.
    let take: PlacementTake
    let alignment: WordAlignment
    let segmentation: SyllableSegmentation
    let pitch: PitchTrack
    let syllables: [ComparableSyllable]
    /// Transcript index → the set word decided there.
    let decided: [Int: String]

    var axes: [TauAxis] { [TauAxis(bucket: TauAxis.bucket(forSyllableCount: syllables.count), kind: .pair)] }

    /// Word id → (flagged after suppression, flagged before) under `detector`.
    func outcomes(_ detector: StressPlacementDetector) -> [String: UnitBits] {
        let analysis = detector.place(
            take, alignment: alignment, segmentation: segmentation, pitch: pitch, syllables: syllables)
        var out: [String: UnitBits] = [:]
        for result in analysis.words {
            guard let id = decided[result.word.rawValue] else { continue }
            var bits: UnitBits = []
            if result.present && result.flaggedBeforeSuppression {
                bits.insert(.flaggedBeforeSuppression)
                if result.suppression == nil { bits.insert(.flagged) }
            }
            out[id] = bits
        }
        return out
    }
}

/// Builds the L2 takes of `words` (one set), exactly as `SharedDetectorRunner.run` and `ReplayedPlacementDetector`
/// do: per utterance, the set's words with an A(w) are decided, every transcript word is aligned and segmented.
func l2Takes(
    set: String, words: [SpeechOceanWord], corpus: SpeechOceanCorpusFiles, timings: FixtureTimestamper,
    labels: SpeechOceanLabels, base: StressPlacementDetector
) async throws -> [L2Take] {
    let dictionary = try PronouncingDictionary.bundled()
    let lookup = SelectorPrimaryLookup(selector: try .bundled())
    let refPhones = Dictionary(labels.words.map { ($0.id, $0.refPhones) }, uniquingKeysWith: { first, _ in first })
    let byUtterance = Dictionary(grouping: words, by: \.utterance)
    return try await withThrowingTaskGroup(of: L2Take?.self) { group in
        var started = 0
        var out: [L2Take] = []
        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
        for utterance in byUtterance.keys.sorted() {
            if started >= limit, let done = try await group.next() { if let done { out.append(done) } }
            started += 1
            group.addTask {
                let members = byUtterance[utterance]!.sorted { $0.index < $1.index }
                let transcript = corpus.transcript(utterance: utterance)
                var decided: [Int: (id: String, accepted: AcceptedSet)] = [:]
                for word in members {
                    if let accepted = SharedDetectorAcceptedSet.of(word, transcript: transcript, dictionary: lookup),
                        decided[word.index] == nil
                    {
                        decided[word.index] = (word.id, accepted)
                    }
                }
                guard !decided.isEmpty else { return nil }
                let items = transcript.enumerated().map { index, text in
                    let word = decided[index]
                    let phones = referencePhones(
                        word.flatMap { refPhones[$0.id] }, corpus.phones(utterance: utterance, index: index), text: text,
                        dictionary: dictionary)
                    return PlacementFixtureItem.Word(
                        id: word?.id, index: index, text: text, phones: phones,
                        accepted: word.map { Array($0.accepted.primaries).sorted() })
                }
                let audio = corpus.audioURL(utterance: utterance)
                let item = PlacementFixtureItem(
                    item: utterance, corpus: "speechocean762", speaker: members[0].speaker, audio: audio.path,
                    audioSHA256: try sha256(of: audio), words: items)
                let (samples, rate) = try AudioFiles.readMono(audio)
                let mono16k = try AudioFiles.resample(samples, from: rate, to: 16_000)
                let heard = try await timings.wordTimestamps(for: TimestampRequest(clipID: item.item, samples: []))
                var take = try item.take(samples: mono16k, sampleRate: 16_000, heard: heard, asrModelID: timings.asrModelID)
                let alignment = try base.align(take).alignment
                let segmentation = try base.segment(take, alignment: alignment)
                let pitch = try await base.pitchTracker.track(take.samples, sampleRate: take.sampleRate)
                take.samples = []
                return L2Take(
                    set: set, utterance: utterance, speaker: members[0].speaker, take: take, alignment: alignment,
                    segmentation: segmentation, pitch: pitch,
                    syllables: ComparableSyllable.all(in: segmentation, pitch: pitch, thresholds: base.thresholds.prominence),
                    decided: decided.mapValues(\.id))
            }
        }
        for try await done in group { if let done { out.append(done) } }
        return out.sorted { $0.utterance < $1.utterance }
    }
}

/// Unit tables for every word of `words`: decided words from their take, excluded words (no A(w), or no take) as a
/// constant "never flagged" unit, so rates stay over the whole set.
func l2Tables(
    words: [SpeechOceanWord], takes: [L2Take], kind: TuningUnitTable.Kind, grid: TuningGrid,
    base: StressPlacementDetector
) async -> [TuningUnitTable] {
    let tables = await withTaskGroup(of: [TuningUnitTable].self) { group in
        for take in takes {
            group.addTask {
                let axes = take.axes
                let stride = TuningUnitTable.stride(axes: axes, grid: grid)
                var bits: [String: [UInt8]] = [:]
                for id in take.decided.values { bits[id] = [UInt8](repeating: 0, count: grid.weightLambdaCount * stride) }
                for k in 0..<grid.weightLambdaCount {
                    for c in 0..<stride {
                        let outcomes = take.outcomes(detector(base, unitThresholds(k: k, combination: c, axes: axes, grid: grid)))
                        for (id, value) in outcomes { bits[id]![k * stride + c] = value.rawValue }
                    }
                }
                return bits.keys.sorted().map {
                    TuningUnitTable(id: $0, speaker: take.speaker, kind: kind, axes: axes, bits: bits[$0]!)
                }
            }
        }
        var out: [String: TuningUnitTable] = [:]
        for await batch in group { for table in batch { out[table.id] = table } }
        return out
    }
    let constant = [TauAxis(bucket: 2, kind: .highOnly)]
    let constantSize = grid.weightLambdaCount * TuningUnitTable.stride(axes: constant, grid: grid)
    return words.map { word in
        tables[word.id] ?? TuningUnitTable(
            id: word.id, speaker: word.speaker, kind: kind, axes: constant,
            bits: [UInt8](repeating: 0, count: constantSize))
    }
}

// MARK: - VCTK pairs

/// One VCTK tuning pair as the analyzer saw it, kept for rescoring at every point.
struct PairTake: Sendable {
    struct Native: Sendable {
        let voice: String
        let take: PlacementTake
        let analysis: PlacementAnalysis
        let syllables: [ComparableSyllable]
    }

    let pair: VCTKPair
    let words: [PlacementTake.Word]
    let you: PlacementAnalysis
    let modelVoice: String
    let model: PlacementAnalysis
    /// Every native reader of the phrase, in the reference set's order (their readings feed A(w)).
    let natives: [Native]
    let warp: TimeWarp
    /// The analyzer's own decision at the initial thresholds.
    let decision: Decision
    let axes: [TauAxis]

    /// The pair's bits under `thresholds`, rescored through the analyzer's L2 path.
    func bits(_ base: StressPlacementDetector, _ thresholds: Thresholds,
              readings memo: inout [String: [WordIndex: [NativeReading]]], memoKey: String) -> UnitBits {
        let readings: [WordIndex: [NativeReading]]
        if let cached = memo[memoKey] {
            readings = cached
        } else {
            var built: [WordIndex: [NativeReading]] = [:]
            let placer = detector(base, thresholds)
            for native in natives {
                let placed = placer.place(
                    native.take, alignment: native.analysis.alignment, segmentation: native.analysis.segmentation,
                    pitch: native.analysis.pitch, syllables: native.syllables)
                for result in placed.words {
                    guard let observed = result.observed else { continue }
                    built[result.word, default: []].append(NativeReading(voice: native.voice, observed: observed))
                }
            }
            memo[memoKey] = built
            readings = built
        }
        let input = PairScoring.input(
            words: words, you: you, model: model, modelVoice: modelVoice, natives: readings, thresholds: thresholds,
            warp: warp)
        guard let scoring = try? Scorer.score(input, thresholds: thresholds) else { return [] }
        return PairTake.bits(scoring.decision)
    }

    static func bits(_ decision: Decision) -> UnitBits {
        var bits: UnitBits = []
        switch decision {
        case .verdict(.feedback(let rows, _)):
            if !rows.isEmpty { bits.insert(.anyDiff) }
            if rows.contains(where: { $0.kind == .placement }) { bits.insert(.placementDiff) }
        case .verdict(.inconclusive):
            bits.insert(.inconclusive)
        default:
            break
        }
        return bits
    }
}

/// Runs the analyzer on every tuning take against its §3a reference (the first listed reference usable for every
/// phrase word, as the positive set) and keeps what rescoring needs. Pairs the analyzer can't score are counted by
/// reason and left out, as the positive set leaves them out of its rates.
func pairTakes(
    pairs: [(speaker: String, phrase: String)], references: ReferencedPhrases, base: StressPlacementDetector
) async throws -> (takes: [PairTake], unscored: [String: Int]) {
    var unscored: [String: Int] = [:]
    var out: [PairTake] = []
    for (n, pair) in pairs.enumerated() {
        if (n + 1) % 100 == 0 { print("tune: analysed \(n + 1) of \(pairs.count) VCTK tuning pairs") }
        guard let phrase = references.phrases[pair.phrase] else { unscored["no phrase text", default: 0] += 1; continue }
        let (reference, _) = references.choose(speaker: pair.speaker, phrase: pair.phrase)
        guard let reference else { unscored[WordUsabilityProblem.noUsableReference.rawValue, default: 0] += 1; continue }
        let result = await references.analyzer.run(
            take: try references.take(speaker: pair.speaker, phrase: pair.phrase), phrase: phrase.input,
            reference: references.referenceSet(phrase: pair.phrase, excluding: pair.speaker),
            voice: EvalReferenceSet.recordingID(speaker: reference, phrase: pair.phrase))
        let natives = phrase.natives.filter { $0.voice != pair.speaker }.map { native in
            PairTake.Native(
                voice: native.voice, take: PlacementTake(samples: [], words: phrase.input.words, heard: [], l0Key: ""),
                analysis: native.analysis.l1.analysis,
                syllables: ComparableSyllable.all(
                    in: native.analysis.l1.analysis.segmentation, pitch: native.analysis.l1.analysis.pitch,
                    thresholds: base.thresholds.prominence))
        }
        guard let decision = result.l2?.decision,
            let record = result.derived.first(where: { $0.level == .l1 }),
            let l1 = DerivedCoding.value(L1Analysis.self, in: record, key: record.key),
            let model = natives.first(where: { $0.voice == reference })
        else {
            unscored["\(result.response.outcome)".prefix(60).description, default: 0] += 1
            continue
        }
        let words = phrase.input.words
        let warp = try PairScoring.warp(you: l1.analysis, model: model.analysis, words: words)
        let probe = PairScoring.input(
            words: words, you: l1.analysis, model: model.analysis, modelVoice: reference, natives: [:],
            thresholds: .current, warp: warp)
        let present = Set(probe.alignment.pairs.compactMap { if case .present(let w, _) = $0 { w } else { nil } })
        let yourCount = probe.you.syllables.count { present.contains($0.word) }
        let modelCount = probe.model.syllables.count { present.contains($0.word) }
        let axes = TauAxis.merged(
            [TauAxis(bucket: TauAxis.bucket(forSyllableCount: yourCount), kind: .pair),
             TauAxis(bucket: TauAxis.bucket(forSyllableCount: modelCount), kind: .pair)]
                + natives.map { TauAxis(bucket: TauAxis.bucket(forSyllableCount: $0.syllables.count), kind: .highOnly) })
        out.append(PairTake(
            pair: VCTKPair(speaker: pair.speaker, phrase: pair.phrase, reference: reference), words: words,
            you: l1.analysis, modelVoice: reference, model: model.analysis, natives: natives, warp: warp,
            decision: decision, axes: axes))
    }
    return (out, unscored)
}

/// The natives' memo key: (weights, λ) and τ_high of each bucket a native reads.
func nativesKey(_ take: PairTake, k: Int, thresholds: Thresholds) -> String {
    let buckets = Set(take.natives.map { TauAxis.bucket(forSyllableCount: $0.syllables.count) }).sorted()
    let high = thresholds.prominence.tauHigh
    let values = [high.syllables2to4, high.syllables5to8, high.syllables9Plus]
    return "\(k)|" + buckets.map { "\($0):\(values[$0])" }.joined(separator: ",")
}

func pairTables(_ takes: [PairTake], grid: TuningGrid, base: StressPlacementDetector) async -> [TuningUnitTable] {
    let byPhrase = Dictionary(grouping: takes, by: \.pair.phrase)
    let tables = await withTaskGroup(of: [TuningUnitTable].self) { group in
        for phrase in byPhrase.keys.sorted() {
            group.addTask {
                var memo: [String: [WordIndex: [NativeReading]]] = [:]
                var out: [TuningUnitTable] = []
                for take in byPhrase[phrase]! {
                    let stride = TuningUnitTable.stride(axes: take.axes, grid: grid)
                    var bits = [UInt8](repeating: 0, count: grid.weightLambdaCount * stride)
                    for k in 0..<grid.weightLambdaCount {
                        if memo.count > 4_096 { memo.removeAll(keepingCapacity: true) }
                        for c in 0..<stride {
                            let t = unitThresholds(k: k, combination: c, axes: take.axes, grid: grid)
                            bits[k * stride + c] = take.bits(base, t, readings: &memo, memoKey: nativesKey(take, k: k, thresholds: t)).rawValue
                        }
                    }
                    out.append(TuningUnitTable(
                        id: "\(take.pair.speaker)_\(take.pair.phrase)", speaker: take.pair.speaker, kind: .vctkPair,
                        axes: take.axes, bits: bits))
                }
                return out
            }
        }
        var out: [TuningUnitTable] = []
        for await batch in group { out += batch }
        return out
    }
    return tables.sorted { $0.id < $1.id }
}

// MARK: - Output

/// One fold of a CV estimate.
struct FoldFit: Codable {
    let fold: Int
    let heldOutSpeakers: [String]
    let ruleFeasible: Int
    let feasible: Int
    /// The rule's choice; nil when no point is feasible (the procedure then keeps the initial thresholds: FALLBACK).
    let chosen: ScoredPoint?
    let appliedPoint: TuningPoint
    let appliedConfigDigest: String
    let fallback: Bool
}

/// What `scripts/tune.sh` writes for the release suite (`eval-cache/tuning/tuning-<configDigest8>.json`).
struct TuningRun: Codable {
    struct L2CV: Codable {
        let folds: [FoldFit]
        /// Word id → flagged after suppression, out of fold (all 134).
        let after: [String: Bool]
        let before: [String: Bool]
        let baselines: [String: [String: Bool]]
        let finalSyllableWords: [String]
        let foldRecord: FoldRunRecord
    }

    struct VCTKCV: Codable {
        let folds: [FoldFit]
        let pairs: Int
        let placementDiffs: Int
        let anyDiffs: Int
        let inconclusive: Int
    }

    let formatVersion: Int
    let generatedAt: String
    let evaluatedCommit: String
    let initialConfigDigest: String
    /// The config the release must evaluate: the chosen point's, or the initial one on FALLBACK.
    let shippedConfigDigest: String
    let fallback: Bool
    let fallbackReasons: [String]
    let pool: [String: Int]
    let unscoredPairs: [String: Int]
    let guardSummary: [String]
    let guardInvariantMet: Bool
    let fit: TuningSearchResult
    let gridSlice: String
    let l2CV: L2CV
    let vctkCV: VCTKCV
    let verification: [String]
    let seconds: [String: Double]
}

// MARK: - The command

func tune(_ args: Arguments, root: URL) async throws -> Int32 {
    let clock = ContinuousClock()
    var seconds: [String: Double] = [:]
    var mark = clock.now
    func lap(_ name: String) {
        let now = clock.now
        let d = mark.duration(to: now)
        seconds[name] = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        mark = now
        print("tune: \(name) done in \(String(format: "%.0f", seconds[name]!)) s")
    }
    let grid = TuningGrid()
    print("tune: grid of \(grid.weights.count) weight points × \(grid.lambdas.count) λ × \(grid.tauPairs.count)³ τ pairs per n-bucket = \(grid.count) points")
    let initialDigest = try configDigest(harnessConfig())

    // Inputs: tuning data only.
    let labels = try loadLabels(Arguments(["", "--labels", root.appendingPathComponent(Paths.labels).path]), root: root)
    let sets = SpeechOceanSets(labels: labels)
    let soSplit = try JSONDecoder().decode(
        SpeechOceanSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent(Paths.soSplit)))
    let vctkSplit = try JSONDecoder().decode(
        VCTKSplitManifest.self, from: Data(contentsOf: root.appendingPathComponent(Paths.vctkSplit)))
    let manifest = try VCTKEvalSpeakersManifest.load(root.appendingPathComponent(Paths.evalSpeakers))
    let tuningSpeakers = manifest.tuningSpeakers.map(\.id)
    let heldOut = Set(manifest.heldOutSpeakers.map(\.id))
    precondition(Set(tuningSpeakers).isDisjoint(with: heldOut), "VCTK tuning and held-out speakers overlap")
    let corpus = try SpeechOceanCorpusFiles(root: args.value("corpus").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.so762Cache))
    let soTimings = try FixtureTimestamper(directory: args.value("timings").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.so762Timings))
    let base = try StressPlacementDetector.bundled()
    let limit = args.value("limit").flatMap(Int.init)

    // Spec 11 guardrail: no test-half word in any tuning pool.
    let testHalf = sets.recall.filter { labels.half(of: $0) == .test }.map(\.id)
    precondition(sets.tuningCorrect.allSatisfy { labels.half(of: $0) == .train }, "a tuning-correct word is test-half")
    print("tune: pool: \(sets.recall.count) stress-wrong words (\(testHalf.count) of them test-half, as plan §2 pools them), \(sets.tuningCorrect.count) train-half correct words, \(tuningSpeakers.count) VCTK tuning speakers")

    var recallWords = sets.recall
    var correctWords = sets.tuningCorrect
    if let limit {
        recallWords = Array(recallWords.prefix(limit))
        correctWords = Array(correctWords.prefix(limit))
    }
    let recallTakes = try await l2Takes(set: "recall", words: recallWords, corpus: corpus, timings: soTimings, labels: labels, base: base)
    let correctTakes = try await l2Takes(set: "tuningCorrect", words: correctWords, corpus: corpus, timings: soTimings, labels: labels, base: base)
    lap("L2 features (\(recallTakes.count) + \(correctTakes.count) utterances)")

    let cacheDir = args.value("vctk").map(URL.init(fileURLWithPath:)) ?? cacheURL(root, Paths.vctkCache)
    guard let cache = PositiveCache(cacheDir) else { throw CLIError.failed("no trimmed VCTK cache at \(cacheDir.path)") }
    let table = try VCTKSubPhraseTable.load(root.appendingPathComponent(Paths.subPhrases))
    let phrases = try PositivePhrases(root: root, manifest: manifest, table: table)
    var pairs = referencedPairs(speakers: tuningSpeakers, available: Set(cache.kept), phrases: table.evaluationPhrases)
    if let limit { pairs = Array(pairs.prefix(limit)) }
    precondition(pairs.allSatisfy { !heldOut.contains($0.speaker) }, "a held-out speaker entered tuning")
    let timings = ReplayUnion(parts: [
        try FixtureTimestamper(directory: cacheURL(root, Paths.vctkTuningTimings)),
        try FixtureTimestamper(directory: cacheURL(root, Paths.vctkTimings)),
    ])
    let lists = try VCTKReferenceLists.load(root.appendingPathComponent(Paths.referenceLists))
    let references = try await ReferencedPhrases.build(
        phrases: Set(pairs.map(\.phrase)), lists: lists, cache: cacheDir, available: Set(cache.kept), phrases: phrases,
        timings: timings)
    precondition(lists.phrases.values.allSatisfy { Set($0).isDisjoint(with: heldOut) }, "a held-out speaker is a reference")
    let (pairTakes, unscored) = try await pairTakes(pairs: pairs, references: references, base: base)
    let multiAxis = pairTakes.filter { $0.axes.count > 1 }.count
    print("tune: VCTK tuning pairs: \(pairs.count) takes, \(pairTakes.count) scored, unscored \(unscored.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: "; ")); \(multiAxis) read τ from more than one bucket")
    lap("VCTK features")

    let recallTables = await l2Tables(words: recallWords, takes: recallTakes, kind: .recallWord, grid: grid, base: base)
    let correctTables = await l2Tables(words: correctWords, takes: correctTakes, kind: .correctWord, grid: grid, base: base)
    lap("L2 tables")
    let pairTables = await pairTables(pairTakes, grid: grid, base: base)
    lap("VCTK tables")

    // Verification 1: the tables at the initial point reproduce the real runs.
    var verification: [String] = []
    let search = TuningSearch(grid: grid)
    let initial = search.coordinates(of: TuningPoint(.current))!
    let highIndex = grid.tauPairs.map { pair in grid.tauHighValues.firstIndex(of: pair.high)! }
    func flaggedAtInitial(_ tables: [TuningUnitTable], _ bit: UnitBits) -> Set<String> {
        Set(tables.filter { $0.bits(at: initial.k, tau: initial.tau, grid: grid, highIndex: highIndex).contains(bit) }.map(\.id))
    }
    let runner = SharedDetectorRunner(
        detector: ReplayedPlacementDetector(
            corpus: corpus, timings: soTimings,
            refPhones: Dictionary(labels.words.map { ($0.id, $0.refPhones) }, uniquingKeysWith: { first, _ in first }),
            dictionary: try .bundled()),
        corpus: corpus, dictionary: SelectorPrimaryLookup(selector: try .bundled()))
    let initialConfig = try FoldConfig(identity: harnessConfig(), thresholds: .current)
    for (name, words, tables) in [("recall", recallWords, recallTables), ("tuning-correct", correctWords, correctTables)] {
        let real = try await runner.run(words, config: initialConfig)
        let realAfter = Set(real.rows.filter { $0.outcome?.flaggedAfterSuppression == true }.map(\.word.id))
        let realBefore = Set(real.rows.filter { $0.outcome?.present == true && $0.outcome?.flaggedBeforeSuppression == true }.map(\.word.id))
        let same = realAfter == flaggedAtInitial(tables, .flagged) && realBefore == flaggedAtInitial(tables, .flaggedBeforeSuppression)
        let line = "initial point, \(name): table flags \(flaggedAtInitial(tables, .flagged).count) after / \(flaggedAtInitial(tables, .flaggedBeforeSuppression).count) before suppression; shared-detector run \(realAfter.count) / \(realBefore.count): \(same ? "identical" : "DIFFERENT")"
        print("tune: verify: \(line)")
        verification.append(line)
        guard same else { throw CLIError.failed("the tuning tables don't reproduce the shared detector (\(name))") }
    }
    var decisionsMatch = 0
    for take in pairTakes {
        var memo: [String: [WordIndex: [NativeReading]]] = [:]
        let rescored = take.bits(base, .current, readings: &memo, memoKey: "initial")
        if rescored == PairTake.bits(take.decision) { decisionsMatch += 1 }
    }
    let pairLine = "initial point, VCTK pairs: rescoring reproduces the analyzer's diff/inconclusive outcome on \(decisionsMatch) of \(pairTakes.count) pairs"
    print("tune: verify: \(pairLine)")
    verification.append(pairLine)
    guard decisionsMatch == pairTakes.count else { throw CLIError.failed("rescoring doesn't reproduce the analyzer") }

    // Verification 2: random grid points evaluated directly match the tables.
    var generator = SplitMix(seed: vctkSplit.foldSeed)
    var spotChecked = 0
    var spotMismatch = 0
    let spotCount = Int(args.value("spot-checks") ?? "60") ?? 60
    for _ in 0..<spotCount {
        let index = Int(generator.next() % UInt64(grid.count))
        let point = grid[index]
        let thresholds = point.applied(to: .current)
        let k = index / (grid.tauPairs.count * grid.tauPairs.count * grid.tauPairs.count)
        var rest = index
        let j2 = rest % grid.tauPairs.count; rest /= grid.tauPairs.count
        let j1 = rest % grid.tauPairs.count; rest /= grid.tauPairs.count
        let j0 = rest % grid.tauPairs.count
        let j = [j0, j1, j2]
        let placer = detector(base, thresholds)
        for take in (recallTakes + correctTakes).shuffledPrefix(8, &generator) {
            let direct = take.outcomes(placer)
            let tables = take.set == "recall" ? recallTables : correctTables
            for (id, bits) in direct {
                spotChecked += 1
                if tables.first(where: { $0.id == id })!.bits(at: k, tau: j, grid: grid, highIndex: highIndex) != bits { spotMismatch += 1 }
            }
        }
        for take in pairTakes.shuffledPrefix(4, &generator) {
            var memo: [String: [WordIndex: [NativeReading]]] = [:]
            let direct = take.bits(base, thresholds, readings: &memo, memoKey: "direct")
            spotChecked += 1
            let id = "\(take.pair.speaker)_\(take.pair.phrase)"
            if pairTables.first(where: { $0.id == id })!.bits(at: k, tau: j, grid: grid, highIndex: highIndex) != direct { spotMismatch += 1 }
        }
    }
    let spotLine = "\(spotCount) random grid points evaluated directly: \(spotChecked - spotMismatch) of \(spotChecked) unit outcomes match the tables"
    print("tune: verify: \(spotLine)")
    verification.append(spotLine)
    guard spotMismatch == 0 else { throw CLIError.failed("table lookups differ from direct evaluation") }
    lap("verification")

    // The guard on tuning data (§4c): read from `am-timestamps spec11-guard` on the VCTK tuning speakers.
    var guardSummary: [String] = []
    var invariantMet = false
    if let path = args.value("guard"), let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
        let run = try JSONDecoder().decode(GuardRun.self, from: data)
        let evaluation = GuardEvaluation(run: run, scope: .tuning)
        invariantMet = evaluation.tuningConditionsMet
        guardSummary = evaluation.lines
    } else {
        guardSummary = ["guard on tuning data: NOT EVALUATED (no --guard JSON from am-timestamps spec11-guard); NOT EVALUATED is never met"]
    }
    for line in guardSummary { print("tune: guard: \(line)") }

    // §2: the shipped fit on the whole pool.
    let pool = TuningSearchPool(recall: recallTables, correct: correctTables, vctkPairs: pairTables)
    let guardRule = TuningGuard(invariantConditionsMet: invariantMet)
    let fit = await search.run(pool, guard: guardRule)
    lap("§2 fit")
    func describe(_ p: ScoredPoint) -> String {
        let m = p.metrics
        let tau = p.point.tau.map { String(format: "(%.2f, %.2f)", $0.medium, $0.high) }.joined(separator: " ")
        return String(format: "#%d w=(%.1f, %.1f, %.1f) λ=%.1f τ=%@: recall %d/%d, VCTK placement FP %d/%d, any-diff %d/%d, shared FP %d/%d, inconclusive %d/%d, violation %.4f",
                      p.index, p.point.durationWeight, p.point.energyWeight, p.point.pitchWeight, p.point.lambda, tau,
                      m.recallHits, m.recallN, m.vctkPlacementDiffs, m.vctkPairs, m.vctkAnyDiffs, m.vctkPairs,
                      m.sharedFalsePositives, m.correctN, m.vctkInconclusive, m.vctkPairs, p.violation)
    }
    print("tune: §2: \(fit.evaluated) points; \(fit.ruleFeasible) meet the rule's constraints, \(fit.ruleAndBudgetFeasible) also the 10% inconclusive budget, \(fit.feasible) also the guard")
    print("tune: §2: initial point \(describe(fit.initial))")
    if let chosen = fit.chosen { print("tune: §2: chosen \(describe(chosen))") } else { print("tune: §2: no feasible point: FALLBACK") }
    if let c = fit.chosenWithoutGuard { print("tune: §2: the rule's choice without the guard (not shipped) \(describe(c))") }
    for p in fit.closest { print("tune: §2: closest \(describe(p))") }

    // §1: nested CV over the 134 recall words (5 speaker-grouped folds from the split manifest).
    let folds = soSplit.folds(for: sets)
    let vctkTuning = manifest.tuningSpeakers
    var cvFits: [FoldFit] = []
    var foldPoints: [Int: TuningPoint] = [:]
    let recallByID = Dictionary(uniqueKeysWithValues: recallTables.map { ($0.id, $0) })
    let correctByID = Dictionary(uniqueKeysWithValues: correctTables.map { ($0.id, $0) })
    func fitFold(_ index: Int, heldOutSpeakers: [String], pool: TuningSearchPool) async throws -> FoldFit {
        let result = await search.run(pool, guard: TuningGuard(invariantConditionsMet: true))
        let applied = result.chosen?.point ?? TuningPoint(.current)
        let digest = try FoldConfig(identity: harnessConfig(), thresholds: applied.applied(to: .current)).digest
        return FoldFit(fold: index, heldOutSpeakers: heldOutSpeakers, ruleFeasible: result.ruleFeasible,
                       feasible: result.feasible, chosen: result.chosen, appliedPoint: applied,
                       appliedConfigDigest: digest, fallback: result.chosen == nil)
    }
    let foldRunner = FoldRunner(folds: folds, vctkTuningSpeakers: vctkTuning)
    let realPath = SharedDetectorPath(runner: runner)
    var baselineFlags: [String: [String: Bool]] = [:]
    let recallTakeByWord = Dictionary(
        recallTakes.flatMap { take in take.decided.values.map { ($0, take) } }, uniquingKeysWith: { a, _ in a })
    for baseline in [DetectorBaseline.longestSyllable, .loudestSyllable] {
        var flags: [String: Bool] = [:]
        for word in sets.recall {
            guard let take = recallTakeByWord[word.id],
                let index = take.decided.first(where: { $0.value == word.id })?.key,
                let segmented = take.segmentation.words.first(where: { $0.phraseWord.rawValue == index && $0.kind == .present }),
                let accepted = take.take.words.first(where: { $0.index.rawValue == index })?.accepted
            else { flags[word.id] = false; continue }
            let features = BaselineWord(
                syllables: segmented.syllables.map { SyllableFeatures(durationS: $0.duration, energyDB: $0.energyDBFS) },
                dictionaryPrimary: nil)
            flags[word.id] = baseline.flags(features, accepted: accepted) ?? false
        }
        baselineFlags[baseline.rawValue] = flags
    }
    struct BaselinePath: EvaluationPath {
        let name: String
        let flags: [String: Bool]
        func run(config: FoldConfig, words: [SpeechOceanWord]) async throws -> [String: Bool] {
            Dictionary(uniqueKeysWithValues: words.map { ($0.id, flags[$0.id] ?? false) })
        }
    }
    let record = try await foldRunner.run(
        train: { tuningPool in
            let foldPool = TuningSearchPool(
                recall: tuningPool.stressWrong.compactMap { recallByID[$0.id] },
                correct: tuningPool.correct.compactMap { correctByID[$0.id] }, vctkPairs: pairTables)
            let fit = try await fitFold(
                tuningPool.fold, heldOutSpeakers: folds.folds[tuningPool.fold].speakers, pool: foldPool)
            cvFits.append(fit)
            foldPoints[tuningPool.fold] = fit.appliedPoint
            print("tune: §1 fold \(tuningPool.fold): \(foldPool.recall.count) recall + \(foldPool.correct.count) correct words + \(foldPool.vctkPairs.count) VCTK pairs; \(fit.ruleFeasible) feasible; \(fit.chosen.map { describe($0) } ?? "no feasible point: the procedure keeps the initial thresholds (FALLBACK)")")
            return try FoldConfig(identity: harnessConfig(), thresholds: fit.appliedPoint.applied(to: .current))
        },
        paths: [realPath] + [DetectorBaseline.longestSyllable, .loudestSyllable].map {
            BaselinePath(name: $0.rawValue, flags: baselineFlags[$0.rawValue]!)
        })
    var after: [String: Bool] = [:]
    var before: [String: Bool] = [:]
    for (k, fold) in folds.folds.enumerated() {
        let point = foldPoints[k]!
        let c = search.coordinates(of: point)!
        for word in folds.heldOutRecall(for: k) {
            let bits = recallByID[word.id]!.bits(at: c.k, tau: c.tau, grid: grid, highIndex: highIndex)
            after[word.id] = bits.contains(.flagged)
            before[word.id] = bits.contains(.flaggedBeforeSuppression)
        }
        _ = fold
    }
    let realAfter = record.folds.reduce(into: [String: Bool]()) { $0.merge($1.results[realPath.name] ?? [:]) { a, _ in a } }
    let cvSame = sets.recall.allSatisfy { (realAfter[$0.id] ?? false) == (after[$0.id] ?? false) }
    let cvLine = "§1 out-of-fold flags: tables and the real shared-detector path with each fold's config agree on \(cvSame ? "all" : "NOT all") \(sets.recall.count) words"
    print("tune: verify: \(cvLine)")
    verification.append(cvLine)
    let finalSyllable = sets.recall.filter { word in
        guard let take = recallTakeByWord[word.id], let index = take.decided.first(where: { $0.value == word.id })?.key,
            let segmented = take.segmentation.words.first(where: { $0.phraseWord.rawValue == index })
        else { return false }
        return segmented.syllables.last?.lengtheningExposed == true
    }.map(\.id)
    let hits = sets.recall.count { after[$0.id] == true }
    print("tune: §1 pooled out-of-fold recall after suppression \(hits)/\(sets.recall.count), before \(sets.recall.count { before[$0.id] == true })/\(sets.recall.count)")
    lap("§1 nested CV")

    // VCTK CV estimate (not shipped): 6 speaker-disjoint folds over the tuning speakers.
    var vctkFits: [FoldFit] = []
    var vctkCounts = (pairs: 0, placement: 0, any: 0, inconclusive: 0)
    for (f, speakers) in vctkSplit.cvFolds.enumerated() {
        let out = Set(speakers)
        let foldPool = TuningSearchPool(
            recall: recallTables, correct: correctTables, vctkPairs: pairTables.filter { !out.contains($0.speaker) })
        let fit = try await fitFold(f, heldOutSpeakers: speakers, pool: foldPool)
        vctkFits.append(fit)
        let c = search.coordinates(of: fit.appliedPoint)!
        for unit in pairTables where out.contains(unit.speaker) {
            let bits = unit.bits(at: c.k, tau: c.tau, grid: grid, highIndex: highIndex)
            vctkCounts.pairs += 1
            if bits.contains(.placementDiff) { vctkCounts.placement += 1 }
            if bits.contains(.anyDiff) { vctkCounts.any += 1 }
            if bits.contains(.inconclusive) { vctkCounts.inconclusive += 1 }
        }
        print("tune: VCTK CV fold \(f): \(fit.chosen.map { describe($0) } ?? "no feasible point (FALLBACK: initial thresholds)")")
    }
    print("tune: VCTK CV estimate, not shipped: placement diffs \(vctkCounts.placement)/\(vctkCounts.pairs), any-diff \(vctkCounts.any)/\(vctkCounts.pairs), inconclusive \(vctkCounts.inconclusive)/\(vctkCounts.pairs)")
    lap("VCTK CV")

    var reasons: [String] = []
    if fit.chosen == nil {
        if fit.ruleFeasible == 0 { reasons.append("no grid point meets the selection rule's constraints on the tuning pool") }
        else if fit.ruleAndBudgetFeasible == 0 { reasons.append("no grid point that meets the rule stays inside the 10% inconclusive budget") }
        if !invariantMet { reasons.append("the guard on tuning data (b2 vs MFA, ±40 ms jitter) is not met, and no tuned key reaches spec 07's verdicts") }
    }
    let shipped = fit.chosen.map { try? FoldConfig(identity: harnessConfig(), thresholds: $0.point.applied(to: .current)).digest } ?? initialDigest
    let commit = shell(["git", "rev-parse", "HEAD"], in: root)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let output = TuningRun(
        formatVersion: 1, generatedAt: ISO8601DateFormatter().string(from: Date()), evaluatedCommit: commit,
        initialConfigDigest: initialDigest, shippedConfigDigest: shipped ?? initialDigest, fallback: fit.chosen == nil,
        fallbackReasons: reasons,
        pool: ["recallWords": recallTables.count, "correctWords": correctTables.count, "vctkPairs": pairTables.count,
               "vctkTuningSpeakers": tuningSpeakers.count],
        unscoredPairs: unscored, guardSummary: guardSummary, guardInvariantMet: invariantMet, fit: fit,
        gridSlice: "the whole fixed grid (\(grid.count) points); constraints from TuningSelectionRule (placement FP ≤ \(search.rule.maxVCTKPlacementFalsePositive), any-diff FP ≤ \(search.rule.maxVCTKAnyDiffFalsePositive), shared FP ≤ \(search.rule.maxSharedDetectorFalsePositive)) plus §4c (inconclusive ≤ \(guardRule.inconclusivePairsMax), b2 vs MFA and ±40 ms jitter on the VCTK tuning speakers)",
        l2CV: .init(folds: cvFits.sorted { $0.fold < $1.fold }, after: after, before: before, baselines: baselineFlags,
                    finalSyllableWords: finalSyllable, foldRecord: record),
        vctkCV: .init(folds: vctkFits, pairs: vctkCounts.pairs, placementDiffs: vctkCounts.placement,
                      anyDiffs: vctkCounts.any, inconclusive: vctkCounts.inconclusive),
        verification: verification, seconds: seconds)
    let outDir = cacheURL(root, "eval-cache/tuning")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let file = outDir.appendingPathComponent("tuning-\(initialDigest.prefix(8)).json")
    if limit == nil { try encoder.encode(output).write(to: file, options: .atomic) }
    print("tune: \(fit.chosen == nil ? "FALLBACK: nucleus-anchored syllable segmentation needed (goes to CTO); Thresholds.swift stays unchanged" : "chosen point above: write it into Thresholds.swift and docs/thresholds.md")")
    if let chosen = fit.chosen {
        let t = chosen.point
        print("tune: prominence.durationWeight \(t.durationWeight), energyWeight \(t.energyWeight), pitchWeight \(t.pitchWeight), lengtheningLambda \(t.lambda), tauMedium \(t.tau.map(\.medium)), tauHigh \(t.tau.map(\.high))")
    }
    print(limit == nil ? "tune: wrote \(file.path)" : "tune: --limit run, nothing written")
    return 0
}

// MARK: - Small helpers

/// SplitMix64: the spot checks' fully specified generator.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Array {
    /// `count` elements drawn without replacement with `generator` (deterministic).
    func shuffledPrefix(_ count: Int, _ generator: inout SplitMix) -> [Element] {
        var copy = self
        var out: [Element] = []
        while out.count < count, !copy.isEmpty {
            out.append(copy.remove(at: Int(generator.next() % UInt64(copy.count))))
        }
        return out
    }
}
