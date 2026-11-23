import Foundation
import Testing
import AMCore
import AMEvaluation

@Suite("VCTK positive set") struct VCTKTests {
    @Test("The tuning-only API returns exactly the 18 tuning speakers, never a held-out one") func tuningOnlyAPI() throws {
        let manifest = try SyntheticVCTK.manifest()
        let tuning = manifest.tuningSpeakers
        #expect(tuning.count == 18)
        let heldOut = Set(manifest.heldOutSpeakers.map(\.id))
        #expect(heldOut.count == 12)
        #expect(Set(tuning.map(\.id)).isDisjoint(with: heldOut))
        // Selection takes [TuningSpeaker] only; there is no way to build one from a held-out speaker or a word.
        let chosen = TuningOnlySelection.best(of: tuning) { Double($0.id.dropFirst())! }
        #expect(chosen?.id == "p417")
    }

    @Test("240 headline pairs; held-out speakers are never a reference, a band voice or in A(w)") func pairs() throws {
        let manifest = try SyntheticVCTK.manifest()
        let pairs = VCTKPairs(manifest: manifest, available: SyntheticVCTK.allClips(manifest))
        #expect(pairs.headline.count == 240)
        #expect(pairs.shortfalls().isEmpty)
        let heldOut = Set(manifest.heldOutSpeakers.map(\.id))
        #expect(Set(pairs.headline.map(\.speaker)) == heldOut)
        #expect(Set(pairs.headline.map(\.reference)) == ["p225", "p226"])
        #expect(pairs.headline.filter { $0.phrase == "015" }.allSatisfy { $0.reference == "p226" })
        #expect((pairs.headline + pairs.secondary).allSatisfy { !heldOut.contains($0.reference) })
        #expect(pairs.secondary.count == 12 * (20 * 8 - 1))
        for phrase in VCTK.phrases {
            #expect(Set(VCTK.nativeReaders(for: phrase)).isDisjoint(with: heldOut))
            #expect(Set(VCTK.nativeReaders(for: phrase)).isSubset(of: VCTK.bundledVoices))
        }
        #expect(!VCTK.nativeReaders(for: "015").contains("p225"))
    }

    @Test("Too few pairs, phrases or held-out speakers is NOT EVALUATED") func shortfalls() throws {
        let manifest = try SyntheticVCTK.manifest()
        var clips = SyntheticVCTK.allClips(manifest)
        for phrase in ["002", "003", "004"] { clips.remove(VCTKClip(speaker: "p225", phrase: phrase)) }
        let fewPhrases = VCTKPairs(manifest: manifest, available: clips)
        #expect(fewPhrases.headline.count == 204)
        #expect(fewPhrases.shortfalls() == ["phrases 17 < 18"])
        let small = try SyntheticVCTK.manifest(tuning: 18, heldOut: 7)
        let smallPairs = VCTKPairs(manifest: small, available: SyntheticVCTK.allClips(small))
        #expect(smallPairs.shortfalls() == ["pairs 140 < 150", "held-out speakers 7 < 12"])
    }

    @Test("VCTK CV: 6 speaker-disjoint folds of 3 over the 18 tuning speakers") func cvFolds() throws {
        let folds = VCTKFolds.make(try SyntheticVCTK.manifest().tuningSpeakers, seed: 5)
        #expect(folds.count == 6 && folds.allSatisfy { $0.speakers.count == 3 })
        #expect(Set(folds.flatMap(\.speakers)).count == 18)
    }
}
