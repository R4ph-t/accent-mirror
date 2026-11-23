import Foundation
import Testing
import AMCore
import AMEvaluation

/// Rev 4, item 3: one fold-trained config object, the same one to every path.
@Suite("Matched-config fold runner") struct MatchedConfigTests {
    /// Records every config digest it is given, per fold (keyed by the fold's held-out words).
    actor Recorder {
        var seen: [String: [String]] = [:]
        func record(path: String, digest: String) { seen[path, default: []].append(digest) }
    }

    struct StubPath: EvaluationPath {
        let name: String
        let recorder: Recorder
        /// Flags words whose index is in this set.
        let flagsIndexBelow: Int

        func run(config: FoldConfig, words: [SpeechOceanWord]) async throws -> [String: Bool] {
            await recorder.record(path: name, digest: config.digest)
            return Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0.index < flagsIndexBelow) })
        }
    }

    @Test("Both stub paths receive the identical config digest per fold, recorded once per fold") func sameConfigPerFold() async throws {
        let sets = SpeechOceanSets(labels: try Repo.labels())
        let folds = SpeechOceanFolds(sets: sets, seed: 20_261_123)
        let runner = FoldRunner(folds: folds, vctkTuningSpeakers: try SyntheticVCTK.manifest().tuningSpeakers)
        let recorder = Recorder()
        let identity = ConfigIdentity(asrModelID: "replayed", pitchTrackerID: "pyin-1", voicingID: "none")
        let record = try await runner.run(
            train: { pool in
                // A different config per fold, as a trained one would be.
                var t = Thresholds.current
                t.prominence.lengtheningLambda = 1.0 + Double(pool.fold) / 10
                return try FoldConfig(identity: identity, thresholds: t)
            },
            paths: [
                StubPath(name: "shared-detector", recorder: recorder, flagsIndexBelow: 3),
                StubPath(name: "end-to-end", recorder: recorder, flagsIndexBelow: 5),
            ])
        let seen = await recorder.seen
        #expect(record.folds.map(\.configDigest) == seen["shared-detector"])
        #expect(seen["shared-detector"] == seen["end-to-end"])
        #expect(Set(record.folds.map(\.configDigest)).count == 5)
        for fold in record.folds { #expect(Set(fold.results.keys) == ["shared-detector", "end-to-end"]) }
        // Pooled over the 134, and paired per word.
        #expect(record.pooled["shared-detector"]?.n == 134 && record.pooled["end-to-end"]?.n == 134)
        let shared = sets.recall.filter { $0.index < 3 }.count
        let endToEnd = sets.recall.filter { $0.index < 5 }.count
        #expect(record.pooled["shared-detector"]?.hits == shared && record.pooled["end-to-end"]?.hits == endToEnd)
        let comparison = try #require(record.comparisons.first)
        #expect(comparison.firstWins == 0 && comparison.secondWins == endToEnd - shared)
    }
}
