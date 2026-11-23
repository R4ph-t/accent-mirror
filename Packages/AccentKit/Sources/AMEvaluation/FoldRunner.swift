// The matched-conditions fold runner (rev 4, item 3). For each outer fold it trains one config on that fold's
// tuning pool and passes the *same* config to every evaluation path, records the fold's `configDigest` once, pools
// each path's out-of-fold results over the 134 recall words, and compares paths with paired per-word wins and losses.

import Foundation
import AMCore

/// A fold-trained configuration: the identity and the full thresholds, with their `configDigest` (spec 01).
public struct FoldConfig: Sendable, Hashable {
    public let identity: ConfigIdentity
    public let thresholds: Thresholds
    public let digest: String

    public init(identity: ConfigIdentity, thresholds: Thresholds) throws {
        self.identity = identity
        self.thresholds = thresholds
        self.digest = try configDigest(identity, thresholds: thresholds)
    }
}

/// One way of running the detector over held-out words (the shared-detector path here; end-to-end in spec 22).
public protocol EvaluationPath: Sendable {
    var name: String { get }
    /// Word id → flagged (after suppression), for every word the path scored.
    func run(config: FoldConfig, words: [SpeechOceanWord]) async throws -> [String: Bool]
}

/// What the fold runner records.
public struct FoldRunRecord: Sendable, Hashable, Codable {
    public struct Fold: Sendable, Hashable, Codable {
        public let index: Int
        /// Recorded once per fold; every path ran under it.
        public let configDigest: String
        public let heldOutSpeakers: [String]
        /// Path name → word id → flagged.
        public let results: [String: [String: Bool]]
    }

    public struct PathComparison: Sendable, Hashable, Codable {
        public let first: String
        public let second: String
        /// Words the first path flagged and the second missed.
        public let firstWins: Int
        /// Words the second path flagged and the first missed.
        public let secondWins: Int
        public let pValue: Double
    }

    public let folds: [Fold]
    /// Path name → pooled out-of-fold recall units over the recall set.
    public let pooled: [String: Pooled]
    public let comparisons: [PathComparison]

    public struct Pooled: Sendable, Hashable, Codable {
        public let hits: Int
        public let n: Int
        public var recall: Double { n == 0 ? 0 : Double(hits) / Double(n) }
    }
}

public struct FoldRunner: Sendable {
    public let folds: SpeechOceanFolds
    public let vctkTuningSpeakers: [TuningSpeaker]

    public init(folds: SpeechOceanFolds, vctkTuningSpeakers: [TuningSpeaker]) {
        self.folds = folds
        self.vctkTuningSpeakers = vctkTuningSpeakers
    }

    /// Runs every fold: `train` once per fold on that fold's pool, then every path with that one config.
    public func run(
        train: (TuningPool) async throws -> FoldConfig, paths: [any EvaluationPath]
    ) async throws -> FoldRunRecord {
        var records: [FoldRunRecord.Fold] = []
        for fold in folds.folds {
            let pool = folds.tuningPool(for: fold.index, vctk: vctkTuningSpeakers)
            let config = try await train(pool)
            let words = folds.heldOutRecall(for: fold.index)
            var results: [String: [String: Bool]] = [:]
            for path in paths {
                results[path.name] = try await path.run(config: config, words: words)
            }
            records.append(
                .init(index: fold.index, configDigest: config.digest, heldOutSpeakers: fold.speakers, results: results))
        }
        let recallIDs = folds.sets.recall.map(\.id)
        var pooled: [String: FoldRunRecord.Pooled] = [:]
        var flags: [String: [String: Bool]] = [:]
        for path in paths {
            var merged: [String: Bool] = [:]
            for record in records { merged.merge(record.results[path.name] ?? [:]) { a, _ in a } }
            flags[path.name] = merged
            // Unscored words count as misses: pooled over all 134, never over the scored subset.
            pooled[path.name] = .init(hits: recallIDs.filter { merged[$0] == true }.count, n: recallIDs.count)
        }
        var comparisons: [FoldRunRecord.PathComparison] = []
        for (i, first) in paths.enumerated() {
            for second in paths.dropFirst(i + 1) {
                let a = flags[first.name]!
                let b = flags[second.name]!
                let firstWins = recallIDs.filter { a[$0] == true && b[$0] != true }.count
                let secondWins = recallIDs.filter { a[$0] != true && b[$0] == true }.count
                comparisons.append(
                    .init(
                        first: first.name, second: second.name, firstWins: firstWins, secondWins: secondWins,
                        pValue: Statistics.mcnemarExact(b: firstWins, c: secondWins)))
            }
        }
        return FoldRunRecord(folds: records, pooled: pooled, comparisons: comparisons)
    }
}
