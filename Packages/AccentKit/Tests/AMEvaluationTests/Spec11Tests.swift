import Foundation
import Testing
import AMCore
@testable import AMEvaluation

@Suite("Spec 11: tuning search, guard limits, references") struct Spec11Tests {
    // MARK: Tuning search

    /// A unit whose bit depends on (weights-λ, τ pair) through `rule`.
    static func unit(_ id: String, _ kind: TuningUnitTable.Kind, axes: [TauAxis], grid: TuningGrid,
                     _ rule: (Int, [Int]) -> UnitBits) -> TuningUnitTable {
        let stride = TuningUnitTable.stride(axes: axes, grid: grid)
        var bits = [UInt8](repeating: 0, count: grid.weightLambdaCount * stride)
        for k in 0..<grid.weightLambdaCount {
            for c in 0..<stride {
                bits[k * stride + c] = rule(k, TuningUnitTable.coordinates(c, axes: axes, grid: grid)).rawValue
            }
        }
        return TuningUnitTable(id: id, speaker: "s\(id)", kind: kind, axes: axes, bits: bits)
    }

    /// A slice of the fixed grid: its first 3 weight points, 2 λ and 12 τ pairs (the initial (0.25, 0.50) among them).
    static let grid: TuningGrid = {
        let full = TuningGrid()
        let pairs = full.tauPairs.filter { [0.10, 0.25, 0.40].contains($0.medium) && [0.30, 0.50, 0.70, 0.90].contains($0.high) }
        return TuningGrid(weights: [[0.4, 0.3, 0.3], [0.1, 0.1, 0.8], [0.5, 0.1, 0.4]], lambdas: [1.6, 2.0], tauPairs: pairs)
    }()

    static func pool(_ grid: TuningGrid) -> TuningSearchPool {
        let pair = [TauAxis(bucket: 2, kind: .pair)]
        // A recall word flagged whenever τ_high (bucket 2) is at most 0.40; a correct word flagged at τ_high ≤ 0.30;
        // a VCTK pair whose placement diff depends on k parity, and a two-axis pair (buckets 0 and 2).
        let recall = unit("1", .recallWord, axes: pair, grid: grid) { _, c in grid.tauPairs[c[0]].high <= 0.40 ? .flagged : [] }
        let correct = unit("2", .correctWord, axes: pair, grid: grid) { _, c in grid.tauPairs[c[0]].high <= 0.30 ? .flagged : [] }
        let vctk = unit("3", .vctkPair, axes: pair, grid: grid) { k, _ in k % 2 == 0 ? [] : [.placementDiff, .anyDiff] }
        let multi = unit("4", .vctkPair, axes: [TauAxis(bucket: 0, kind: .pair), TauAxis(bucket: 2, kind: .highOnly)],
                         grid: grid) { _, c in c[0] == 0 && c[1] == 0 ? .inconclusive : [] }
        return TuningSearchPool(recall: [recall], correct: [correct], vctkPairs: [vctk, multi])
    }

    @Test("A slice's sums agree with per-point metrics, and its choice is the rule's best over the slice") func sliceMatchesBruteForce() {
        let grid = Self.grid
        let search = TuningSearch(grid: grid)
        let pool = Self.pool(grid)
        let guardRule = TuningGuard(invariantConditionsMet: true, inconclusivePairsMax: 0.10)
        let k = 0
        let slice = search.slice(pool, k: k, guard: guardRule)
        // Brute force: the rule's best over every τ triple of this (weights, λ), feasible under rule + budget.
        var best: ScoredPoint?
        var feasible = 0
        let n = grid.tauPairs.count
        for j0 in 0..<n {
            for j1 in 0..<n {
                for j2 in 0..<n {
                    let m = search.metrics(pool, k: k, tau: [j0, j1, j2])
                    guard search.rule.isFeasible(m.tuning), m.inconclusiveShare <= 0.10 else { continue }
                    feasible += 1
                    let index = grid.index(weightLambda: k, tau: [j0, j1, j2])
                    let candidate = ScoredPoint(index: index, point: grid[index], metrics: m, violation: 0)
                    if best.map({ search.prefers(candidate, over: $0) }) ?? true { best = candidate }
                }
            }
        }
        #expect(feasible > 0)
        #expect(slice.feasible > 0)
        #expect(slice.feasible == feasible)
        #expect(slice.chosen?.index == best?.index)
        if let chosen = slice.chosen {
            #expect(search.metrics(pool, k: k, tau: search.coordinates(of: chosen.point)!.tau) == chosen.metrics)
        }
    }

    @Test("The guard's invariant part blocks every point; the rule's unguarded choice is still reported") func guardBlocks() {
        let grid = Self.grid
        let search = TuningSearch(grid: grid)
        let slice = search.slice(Self.pool(grid), k: 0, guard: TuningGuard(invariantConditionsMet: false))
        #expect(slice.feasible == 0)
        #expect(slice.chosen == nil)
        #expect(slice.chosenWithoutGuard != nil)
        #expect(slice.closest.count == search.closestCount)
    }

    @Test("The initial thresholds are a grid point, and a point round-trips through its coordinates") func coordinates() {
        let search = TuningSearch()
        let c = search.coordinates(of: TuningPoint(.current))!
        #expect(search.grid.point(weightLambda: c.k, tau: c.tau) == TuningPoint(.current))
        #expect(TauAxis.bucket(forSyllableCount: 4) == 0 && TauAxis.bucket(forSyllableCount: 5) == 1 && TauAxis.bucket(forSyllableCount: 9) == 2)
        #expect(TauAxis.merged([.init(bucket: 2, kind: .highOnly), .init(bucket: 2, kind: .pair), .init(bucket: 0, kind: .highOnly)])
                == [.init(bucket: 0, kind: .highOnly), .init(bucket: 2, kind: .pair)])
    }

    // MARK: Guard limits

    static func run(flips: Int, words: Int, buckets: [GuardRun.Bucket]) -> GuardRun {
        func comparison(_ id: String) -> GuardRun.Comparison {
            GuardRun.Comparison(
                id: id, candidate: id, status: "evaluated", reason: nil, words: words, differing: flips,
                oracleInconclusive: 10, candidateInconclusive: 10, parts: [:], onlyCue: [:], bySyllables: buckets,
                transitions: .init(decidedToDecided: 0, involvingInconclusive: 0), boundaryError: [], keptUnjittered: 0,
                inconclusiveSplit: nil)
        }
        let set = { (name: String) in
            GuardRun.GuardSet(set: name, oracle: "mfa", status: "evaluated", reason: nil, clips: 1, clipsSkipped: [],
                              substituted: 0, deleted: 0,
                              comparisons: ["control", "b2", "jitter-20", "jitter-40", "jitter-80"].map(comparison))
        }
        return GuardRun(formatVersion: 1, thresholdsLabel: "test", seed: 1, asrModelID: nil, ctcModel: nil,
                        sets: [set("synthetic"), set("vctk-held-out")])
    }

    @Test("±40 ms is gated pooled and per multi-syllable group with n ≥ 30; smaller groups are reported") func jitterGroups() {
        let buckets = [
            GuardRun.Bucket(bucket: "1", words: 900, differing: 0, oracleInconclusive: 5, candidateInconclusive: 5),
            GuardRun.Bucket(bucket: "2", words: 60, differing: 3, oracleInconclusive: 5, candidateInconclusive: 5),
            GuardRun.Bucket(bucket: "3", words: 29, differing: 9, oracleInconclusive: 5, candidateInconclusive: 20),
            GuardRun.Bucket(bucket: "4+", words: 11, differing: 0, oracleInconclusive: 0, candidateInconclusive: 0),
        ]
        let evaluation = GuardEvaluation(run: Self.run(flips: 12, words: 1000, buckets: buckets), scope: .heldOut)
        let rows = evaluation.condition4.filter { $0.set == "synthetic" }
        #expect(rows.first { $0.name == "jitter ±40 ms" }?.status == .met)              // 1.2% pooled
        #expect(rows.first { $0.name == "jitter ±40 ms, 2-syllable flips" }?.status == .notMet)   // 5% at n 60
        #expect(rows.first { $0.name == "jitter ±40 ms, 3-syllable flips" }?.status == .reportedSmall)
        #expect(rows.first { $0.name == "jitter ±40 ms, 3-syllable inconclusive rise" }?.status == .reportedSmall)
        #expect(!GuardEvaluation.met(evaluation.condition4))
    }

    @Test("Exactly 2% passes; NOT EVALUATED is never met") func boundaries() {
        let evaluation = GuardEvaluation(run: Self.run(flips: 20, words: 1000, buckets: []), scope: .heldOut)
        #expect(evaluation.condition1.first?.status == .met)
        #expect(GuardEvaluation.met([GuardCheck(name: "x", set: "s", n: 0, value: nil, limit: 0.02, status: .notEvaluated, interval: nil, detail: "")]) == false)
        #expect(GuardEvaluation.met([]) == false)
    }

    // MARK: References and isolation

    @Test("Reference lists: bundled voices first, p226 first for 015, tuning speakers only to reach 3, never held-out or self") func referenceLists() throws {
        let manifest = try SyntheticVCTK.manifest()
        var clips = SyntheticVCTK.allClips(manifest)
        for voice in VCTK.bundledVoices.dropFirst(2) { clips.remove(VCTKClip(speaker: voice, phrase: "019")) }
        let lists = VCTKReferenceLists.make(manifest: manifest, available: clips, phrases: VCTK.phrases, evalSpeakersSHA256: "x")
        #expect(lists.phrases["002"] == VCTK.bundledVoices)
        #expect(lists.phrases["015"]?.first == "p226")
        #expect(lists.phrases["015"]?.contains("p225") == false)
        let tuning = manifest.tuningSpeakers.map(\.id).sorted()
        #expect(lists.phrases["019"] == ["p225", "p226", tuning[0]])
        #expect(lists.problems(manifest: manifest).isEmpty)
        #expect(lists.shortLists.isEmpty)
        #expect(!lists.references(for: "019", speaker: tuning[0]).contains(tuning[0]))
        let heldOut = Set(manifest.heldOutSpeakers.map(\.id))
        #expect(lists.phrases.values.allSatisfy { Set($0).isDisjoint(with: heldOut) })
    }

    @Test("Row accounting counts pairs, references, prompts and lost pairs by reason") func accounting() {
        let accounts = [
            PairAccount(speaker: "a", phrase: "021-a", reference: "p225", skipped: [:], lostReason: nil),
            PairAccount(speaker: "a", phrase: "021-b", reference: "p226", skipped: ["p225": .asrSubstitution], lostReason: nil),
            PairAccount(speaker: "b", phrase: "002", reference: nil, skipped: [:], lostReason: "noUsableReference"),
        ]
        let row = RowAccounting.make(accounts: accounts, measured: ["a_021-a"], why: { _ in "contrast unavailable" })
        #expect(row == RowAccounting(pairs: 1, referenceSpeakers: 1, prompts: 1, lostPairs: 2,
                                     lostReasons: ["contrast unavailable": 1, "noUsableReference": 1]))
    }

    @Test("Tuning pools never hold a held-out VCTK speaker, a test-half correct word or a clean-1,400 speaker") func isolation() throws {
        let manifest = try SyntheticVCTK.manifest()
        #expect(Set(manifest.tuningSpeakers.map(\.id)).isDisjoint(with: manifest.heldOutSpeakers.map(\.id)))
        let labels = try Repo.labels()
        let sets = SpeechOceanSets(labels: labels)
        #expect(sets.tuningCorrect.allSatisfy { labels.half(of: $0) == .train })
        let tuningSpeakers = Set(sets.recall.map(\.speaker)).union(sets.tuningCorrect.map(\.speaker))
        #expect(Set(sets.cleanFalsePositive.map(\.speaker)).isDisjoint(with: tuningSpeakers))
    }
}
