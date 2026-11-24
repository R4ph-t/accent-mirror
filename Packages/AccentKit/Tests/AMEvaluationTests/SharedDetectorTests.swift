import Foundation
import Testing
import AMCore
import AMEvaluation

@Suite("Shared-detector runner") struct SharedDetectorTests {
    struct Corpus: SpeechOceanCorpus {
        func audioURL(utterance: String) -> URL { URL(fileURLWithPath: "/dev/null/\(utterance).WAV") }
        func transcript(utterance: String) -> [String] { ["A", "B", "C", "D", "E", "F"] }
    }

    struct Dictionary0: DictionaryPrimaryLookup {
        func primary(of words: [String], at index: Int, syllableCount: Int) -> Int? { index == 1 ? 0 : nil }
    }

    /// Flags words by index: 0 flagged and kept, 1 flagged then suppressed, 2 not flagged, 3 absent.
    actor Calls { var utterances: [DetectorUtterance] = []; func add(_ u: DetectorUtterance) { utterances.append(u) } }
    struct Stub: PlacementDetector {
        let calls: Calls
        var id: String { "stub" }
        func placements(for utterance: DetectorUtterance, config: FoldConfig) async throws -> [String: PlacementOutcome] {
            await calls.add(utterance)
            return Dictionary(uniqueKeysWithValues: utterance.words.map { word in
                switch word.index {
                case 0: (word.id, PlacementOutcome(present: true, flaggedBeforeSuppression: true, suppression: nil))
                case 1: (word.id, PlacementOutcome(present: true, flaggedBeforeSuppression: true, suppression: .lowSyllableConfidence))
                case 3: (word.id, PlacementOutcome(present: false, flaggedBeforeSuppression: true, suppression: nil))
                default: (word.id, PlacementOutcome(present: true, flaggedBeforeSuppression: false, suppression: nil))
                }
            })
        }
    }

    static func word(_ index: Int, ref: String, utterance: String = "u1") -> SpeechOceanWord {
        SpeechOceanWord(utterance: utterance, index: index, speaker: "s1", text: "W\(index)", refPhones: ref, stressWrongVotes: 3, allPhonesZeroVotes: 0)
    }

    @Test("Counts before and after suppression; absent words are not comparable; no A(w) is excluded") func counting() async throws {
        let words = [
            Self.word(0, ref: "AA1 B AH0"), Self.word(1, ref: "AA0 B AH0"), Self.word(2, ref: "AA0 B AH1"),
            Self.word(3, ref: "AA1 B AH0"), Self.word(4, ref: "AA0 B AH0"),
        ]
        let calls = Calls()
        let runner = SharedDetectorRunner(detector: Stub(calls: calls), corpus: Corpus(), dictionary: Dictionary0())
        let config = try FoldConfig(identity: ConfigIdentity(asrModelID: "r", pitchTrackerID: "p", voicingID: "v", aligner: "whisper", alignerModelSHA256: "none"), thresholds: .current)
        let results = try await runner.run(words, config: config)
        #expect(results.excluded.map(\.index) == [4])
        #expect(results.comparable.count == 3)
        #expect(results.units(afterSuppression: false).filter(\.hit).count == 2)
        #expect(results.units(afterSuppression: true).filter(\.hit).count == 1)
        #expect(results.placementDiffs == 1)
        let utterances = await calls.utterances
        #expect(utterances.count == 1)
        let sent = try #require(utterances.first)
        #expect(sent.words.map(\.accepted) == [
            AcceptedSet(primaries: [0], source: .corpusRefPhones), AcceptedSet(primaries: [0], source: .dictionary),
            AcceptedSet(primaries: [1], source: .corpusRefPhones), AcceptedSet(primaries: [0], source: .corpusRefPhones),
        ])
        #expect(sent.transcript.count == 6)
    }

    @Test("The 157 unintelligible words are a count gate of 0 placement diffs") func unintelligibleGate() throws {
        let sets = SpeechOceanSets(labels: try Repo.labels())
        #expect(sets.unintelligible.count == 157)
        let gate = Gate.agreement("agreement.unintelligiblePlacementDiffsMax", \.unintelligiblePlacementDiffsMax, .atMost)
        #expect(gate.passes(0) && !gate.passes(1))
    }
}
