// Speaker-disjoint nested-CV folds with Raph's rev 4 speaker isolation (plan §2, review 4 at 09:56).
//
// For outer fold k the tuning pool is the other folds' stress-wrong words, the train-half correct words of speakers
// not in fold k, and the 18 VCTK tuning speakers. Every token of every fold-k speaker is excluded, correct words
// included, and test-half correct words are never in any tuning pool.

import Foundation

public enum FoldAssignment {
    /// Deals `speakers` into `count` speaker-disjoint folds, stratified by `stratum`: each stratum (in name order) is
    /// shuffled with the seeded generator and dealt round-robin, carrying on from where the previous stratum stopped,
    /// so fold sizes differ by at most one and each stratum is spread evenly.
    public static func stratified(
        speakers: [(id: String, stratum: String)], count: Int, seed: UInt64
    ) -> [[String]] {
        precondition(count > 0)
        var generator = SeededGenerator(seed: seed)
        var folds = [[String]](repeating: [], count: count)
        var next = 0
        let strata = Dictionary(grouping: speakers, by: \.stratum)
        for stratum in strata.keys.sorted() {
            var members = strata[stratum]!.map(\.id).sorted()
            // Fisher–Yates with the fully specified generator (not `shuffle(using:)`, whose algorithm may change).
            if members.count > 1 {
                for i in stride(from: members.count - 1, to: 0, by: -1) {
                    members.swapAt(i, generator.index(below: i + 1))
                }
            }
            for member in members {
                folds[next].append(member)
                next = (next + 1) % count
            }
        }
        return folds.map { $0.sorted() }
    }
}

/// One outer fold: its speakers, whose every token leaves the tuning pool.
public struct OuterFold: Sendable, Hashable, Codable {
    public let index: Int
    public let speakers: [String]

    public init(index: Int, speakers: [String]) {
        self.index = index
        self.speakers = speakers
    }
}

/// Everything fold k may tune on. Built only by `SpeechOceanFolds.tuningPool(for:)`.
public struct TuningPool: Sendable, Hashable {
    public let fold: Int
    /// The other folds' stress-wrong (recall) words.
    public let stressWrong: [SpeechOceanWord]
    /// Train-half unanimous correct words of speakers not in fold k.
    public let correct: [SpeechOceanWord]
    /// The 18 VCTK tuning speakers.
    public let vctkTuningSpeakers: [TuningSpeaker]

    /// Every speechocean762 speaker with a token in the pool.
    public var speechOceanSpeakers: Set<String> { Set(stressWrong.map(\.speaker)).union(correct.map(\.speaker)) }
}

/// The speechocean762 outer folds over the recall speakers, and the pools and held-out words they imply.
public struct SpeechOceanFolds: Sendable, Hashable {
    public let sets: SpeechOceanSets
    public let folds: [OuterFold]

    /// Five folds over the recall set's speakers (72), stratified child / adult, with the manifest's seed.
    public init(sets: SpeechOceanSets, count: Int = 5, seed: UInt64) {
        let speakers = SpeechOceanSets.speakers(sets.recall).sorted().map { id in
            (id: id, stratum: sets.labels.speakers[id]!.ageGroup.rawValue)
        }
        let dealt = FoldAssignment.stratified(speakers: speakers, count: count, seed: seed)
        self.init(sets: sets, folds: dealt.enumerated().map { OuterFold(index: $0, speakers: $1) })
    }

    /// Folds read back from a split manifest.
    public init(sets: SpeechOceanSets, folds: [OuterFold]) {
        self.sets = sets
        self.folds = folds
    }

    /// The tuning pool of fold `k`.
    public func tuningPool(for k: Int, vctk: [TuningSpeaker]) -> TuningPool {
        let excluded = Set(folds[k].speakers)
        return TuningPool(
            fold: k,
            stressWrong: sets.recall.filter { !excluded.contains($0.speaker) },
            correct: sets.tuningCorrect.filter { !excluded.contains($0.speaker) },
            vctkTuningSpeakers: vctk)
    }

    /// Fold k's out-of-fold recall words: the stress-wrong words of its speakers.
    public func heldOutRecall(for k: Int) -> [SpeechOceanWord] {
        let speakers = Set(folds[k].speakers)
        return sets.recall.filter { speakers.contains($0.speaker) }
    }
}
