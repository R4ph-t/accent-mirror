import Foundation
import Testing
import AMCore
import AMEvaluation

/// The §6.3 counts, recounted from the committed label-only fixture. If one differs from the plan, the test fails and
/// the difference goes to CTO; nobody edits the expected counts to pass.
@Suite("speechocean762 sets") struct SpeechOceanSetsTests {
    let sets: SpeechOceanSets

    init() throws { sets = SpeechOceanSets(labels: try Repo.labels()) }

    @Test("Every §6.3 count matches the plan") func headlineCounts() {
        for check in sets.countChecks where !check.isCategorySplit {
            #expect(check.actual == check.plan, "\(check.name)")
        }
    }

    @Test("The monosyllable category split matches the plan (25 / 8 / 1)") func categorySplit() {
        // The plan states 25 true monosyllables, 8 syllabic-consonant spellings and 1 empty phone string, with no
        // rule. The explicit rule here gives 28 / 5 / 0 and 1 vowel without a stress digit ("HERE", HH IH AH0).
        // Recorded as a known issue for CTO, with the plan's numbers kept as the expectation.
        withKnownIssue("plan's category rule is unstated; recount 28 / 5 / 0 + 1 unmarked vowel, sent to CTO") {
            for check in sets.countChecks where check.isCategorySplit {
                #expect(check.actual == check.plan, "\(check.name)")
            }
        }
    }

    @Test("Speakers: 125 per half, none shared; children 6–15 and adults 19–43") func speakers() throws {
        let labels = try Repo.labels()
        let halves = Dictionary(grouping: labels.speakers.values, by: \.half)
        #expect(halves[.train]?.count == 125 && halves[.test]?.count == 125)
        let ages = labels.speakers.values.map(\.age)
        #expect(labels.speakers.values.filter { $0.ageGroup == .child }.allSatisfy { (6...15).contains($0.age) })
        #expect(labels.speakers.values.filter { $0.ageGroup == .adult }.allSatisfy { (19...43).contains($0.age) })
        #expect(ages.min() == 6 && ages.max() == 43)
    }

    @Test("The fixture came from the pinned scores-detail.json") func fixtureProvenance() throws {
        #expect(try Repo.labels().sourceSHA256 == Repo.pin("speechocean762", "scoresDetailJSONSHA256"))
        #expect(try Repo.pin("speechocean762", "scoresJSONSHA256").hasPrefix("31c847b8"))
        #expect(try Repo.pin("speechocean762", "scoresJSONSHA256").hasSuffix("a1159f8"))
    }

    @Test("The committed split manifest reproduces from the fixture and its seed") func splitManifestReproduces() throws {
        let data = try Data(contentsOf: Repo.url("fixtures/splits/speechocean762.json"))
        let committed = try JSONDecoder().decode(SpeechOceanSplitManifest.self, from: data)
        let fixtureHash = SHA256Digest.hex(of: try Data(contentsOf: Repo.url("fixtures/speechocean762/labels.tsv")))
        #expect(committed.labelFixtureSHA256 == fixtureHash)
        let rebuilt = SpeechOceanSplitManifest(
            sets: sets, folds: SpeechOceanFolds(sets: sets, seed: committed.foldSeed), labelFixtureSHA256: fixtureHash,
            foldSeed: committed.foldSeed, bootstrapSeed: committed.bootstrapSeed)
        #expect(rebuilt == committed)
        #expect(try ManifestJSON.encode(rebuilt) == data)
    }

    @Test("Syllables count digit-bearing phones; A(w) is the ref-phones primary") func wordFacts() {
        let word = SpeechOceanWord(utterance: "u", index: 0, speaker: "s", text: "PHOTOGRAPHY", refPhones: "F AH0 T AA1 G R AH0 F IY0", stressWrongVotes: 0, allPhonesZeroVotes: 0)
        #expect(word.syllableCount == 4 && word.refPrimary == 1 && word.id == "u#0")
        let here = SpeechOceanWord(utterance: "u", index: 1, speaker: "s", text: "HERE", refPhones: "HH IH AH0", stressWrongVotes: 3, allPhonesZeroVotes: 0)
        #expect(here.syllableCount == 1 && MonosyllableCategory.of(here) == .unmarkedVowel)
        let little = SpeechOceanWord(utterance: "u", index: 2, speaker: "s", text: "LITTLE", refPhones: "L IH1 T L", stressWrongVotes: 3, allPhonesZeroVotes: 0)
        #expect(MonosyllableCategory.of(little) == .syllabicConsonantSpelling)
        let empty = SpeechOceanWord(utterance: "u", index: 3, speaker: "s", text: "", refPhones: "", stressWrongVotes: 3, allPhonesZeroVotes: 0)
        #expect(MonosyllableCategory.of(empty) == .emptyPhoneString)
    }

    @Test("Rater votes: stress 5 is wrong; every non-inserted phone in parentheses is all-zero") func votes() throws {
        let json = """
            {"000010011": {"words": [{"text": "BEAR", "ref-phones": "B EH0 R",
              "stress": [5, 10, 5, 5, 10],
              "phones": ["(B) (EH0) (R)", "B {EH0} R", "(B) (EH0) (R) [IH0]", "(B) EH0 (R)", "[L]"]}]}}
            """
        let labels = try SpeechOceanLabels.fromCorpus(
            scoresDetail: Data(json.utf8), utt2spk: [.train: "000010011 0001\n"], spk2age: [.train: "0001 12\n"])
        let word = try #require(labels.words.first)
        #expect(word.stressWrongVotes == 3 && word.isStressWrong)
        #expect(word.allPhonesZeroVotes == 3 && word.isUnintelligible)
        let roundTrip = try SpeechOceanLabels.parseFixture(labels.fixtureText(sourceDescription: "test"))
        #expect(roundTrip.speakers == labels.speakers)
    }
}
