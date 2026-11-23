import Foundation
import Testing
import AMEvaluation

/// Rev 4, item 1: outer folds exclude every token of their speakers.
@Suite("Fold isolation") struct FoldIsolationTests {
    let sets: SpeechOceanSets
    let folds: SpeechOceanFolds
    let vctk: [TuningSpeaker]

    init() throws {
        sets = SpeechOceanSets(labels: try Repo.labels())
        let manifest = try JSONDecoder().decode(
            SpeechOceanSplitManifest.self, from: Data(contentsOf: Repo.url("fixtures/splits/speechocean762.json")))
        folds = manifest.folds(for: sets)
        vctk = try SyntheticVCTK.manifest().tuningSpeakers
    }

    @Test("No fold-k speaker appears anywhere in fold k's tuning pool") func noFoldSpeakerInItsPool() {
        for fold in folds.folds {
            let pool = folds.tuningPool(for: fold.index, vctk: vctk)
            #expect(pool.speechOceanSpeakers.isDisjoint(with: fold.speakers), "fold \(fold.index)")
            #expect(!pool.stressWrong.isEmpty && !pool.correct.isEmpty)
        }
    }

    @Test("Five speaker-disjoint folds cover the 72 recall speakers, stratified child / adult") func foldShape() {
        #expect(folds.folds.count == 5)
        let all = folds.folds.flatMap(\.speakers)
        #expect(all.count == 72 && Set(all).count == 72)
        #expect(Set(all) == SpeechOceanSets.speakers(sets.recall))
        #expect(folds.folds.map(\.speakers.count).sorted() == [14, 14, 14, 15, 15])
        let children = folds.folds.map { $0.speakers.filter { sets.labels.speakers[$0]!.ageGroup == .child }.count }
        #expect(children.max()! - children.min()! <= 1)
        let heldOut = folds.folds.flatMap { folds.heldOutRecall(for: $0.index) }
        #expect(heldOut.count == 134 && Set(heldOut.map(\.id)).count == 134)
    }

    @Test("406 / 34 correct words drop out with their fold; 1,299 / 86 are always usable") func correctWordsPerFold() {
        let usable = Set(sets.tuningCorrect.filter { !SpeechOceanSets.speakers(sets.recall).contains($0.speaker) }.map(\.id))
        #expect(usable.count == 1299)
        var dropped = 0
        var droppedSpeakers = Set<String>()
        for fold in folds.folds {
            let pool = folds.tuningPool(for: fold.index, vctk: vctk)
            let ids = Set(pool.correct.map(\.id))
            #expect(usable.isSubset(of: ids))
            let gone = sets.tuningCorrect.filter { !ids.contains($0.id) }
            dropped += gone.count
            droppedSpeakers.formUnion(gone.map(\.speaker))
            #expect(pool.stressWrong.count + folds.heldOutRecall(for: fold.index).count == 134)
        }
        #expect(dropped == 406 && droppedSpeakers.count == 34)
    }

    @Test("Test-half correct words are never in any tuning pool") func testHalfNeverTunes() {
        let testCorrect = Set(sets.supplementaryFalsePositive.map(\.id))
        for fold in folds.folds {
            let pool = folds.tuningPool(for: fold.index, vctk: vctk)
            #expect(Set(pool.correct.map(\.id)).isDisjoint(with: testCorrect))
            #expect(pool.vctkTuningSpeakers.count == 18)
        }
    }

    @Test("The clean FP set shares no speaker with any tuning pool") func cleanSetIsClean() {
        let clean = SpeechOceanSets.speakers(sets.cleanFalsePositive)
        for fold in folds.folds {
            #expect(folds.tuningPool(for: fold.index, vctk: vctk).speechOceanSpeakers.isDisjoint(with: clean))
        }
        #expect(SpeechOceanSets.speakers(sets.recall).isDisjoint(with: clean))
    }

    @Test("Fold assignment reproduces from its seed") func seeded() {
        let again = SpeechOceanFolds(sets: sets, seed: 20_261_123)
        #expect(again.folds == folds.folds)
        #expect(SpeechOceanFolds(sets: sets, seed: 1).folds != folds.folds)
    }
}
