// Spec 26 §2: N_w as a set (CMUdict alternates, reduced forms) with index mapping onto the context pronunciation, and
// the DP accepting any count in N_w with ties to the context count.

import AMAlignment
import AMCore
import AMPitch
@testable import AMProsody
import Foundation
import Testing

@Suite("NucleusCountTests") struct NucleusCountTests {
    static func allowed(_ word: String, _ arpabet: String) throws -> AllowedSyllableCounts {
        AllowedSyllableCounts.of(
            word: word, context: try Pronunciation(arpabet: arpabet), dictionary: try .bundled(),
            reducedForms: try .bundled())
    }

    @Test("family: N_w is {2, 3}; the 2-count maps its syllables to context syllables 0 and 2")
    func familySet() throws {
        let family = try Self.allowed("family", "F AE1 M AH0 L IY0")
        #expect(family.counts == [2, 3])
        #expect(family.form(for: 2)?.contextIndex == [0, 2])
        #expect(family.form(for: 2)?.source == .cmudictAlternate)
        #expect(family.form(for: 3)?.contextIndex == [0, 1, 2])
    }

    @Test("reduced forms: memory 3 → 2 drops syllable 1 through droppedSyllable; real 1 → 2 adds an unmapped one")
    func reducedForms() throws {
        let memory = try Self.allowed("memory", "M EH1 M ER0 IY0")
        #expect(memory.counts == [2, 3])
        #expect(memory.form(for: 2) == .init(count: 2, contextIndex: [0, 2], source: .reducedForm))
        let real = try Self.allowed("real", "R IY1 L")
        #expect(real.counts == [1, 2])
        #expect(real.form(for: 2)?.contextIndex == [0, nil])
        // A word with no alternates and no entry keeps its context count alone.
        #expect(try Self.allowed("lesson", "L EH1 S AH0 N").counts == [2])
    }

    @Test("the reduced-forms file only adds counts CMUdict doesn't list, and lists the spec's dropped words")
    func reducedFormsOnlyAdd() throws {
        let dictionary = try PronouncingDictionary.bundled()
        let reduced = try ReducedForms.bundled()
        #expect(reduced.entries.count == 11)
        for entry in reduced.entries {
            let counts = Set(dictionary.pronunciations(of: entry.word).map(\.syllables.count))
            #expect(counts.contains(entry.fullCount), "\(entry.word): full count is a CMUdict count")
            #expect(!counts.contains(entry.reducedCount), "\(entry.word): CMUdict already lists \(entry.reducedCount)")
        }
        // Spec 26 §2's initial list: word → the counts it pairs (full, reduced; both ways for smoothing pairs).
        let spec: [String: [Int]] = [
            "family": [3, 2], "every": [3, 2], "camera": [3, 2], "different": [3, 2], "chocolate": [3, 2],
            "favorite": [3, 2], "several": [3, 2], "general": [3, 2], "natural": [3, 2], "probably": [3, 2],
            "restaurant": [3, 2], "evening": [3, 2], "memory": [3, 2], "history": [3, 2], "factory": [3, 2],
            "mystery": [3, 2], "boundary": [3, 2], "library": [3, 2], "separate": [3, 2], "average": [3, 2],
            "beverage": [3, 2], "opera": [3, 2], "centuries": [3, 2], "various": [3, 2], "business": [3, 2],
            "wednesday": [3, 2], "everyone": [3, 2], "temperature": [4, 3], "comfortable": [4, 3],
            "vegetable": [4, 3], "interesting": [4, 3], "actually": [4, 3], "usually": [4, 3], "basically": [4, 3],
            "everything": [4, 3], "everybody": [4, 3], "especially": [5, 4], "fire": [1, 2], "hour": [1, 2],
            "our": [1, 2], "poem": [2, 1], "real": [1, 2],
        ]
        #expect(Set(reduced.entries.map(\.word) + reduced.alreadyInCMUdict) == Set(spec.keys))
        for word in reduced.alreadyInCMUdict {
            #expect(reduced.entries(for: word).isEmpty)
            let counts = Set(dictionary.pronunciations(of: word).map(\.syllables.count))
            let added = ["fire", "hour", "our"].contains(word) ? spec[word]! : [spec[word]![1]]
            #expect(Set(added).isSubset(of: counts), "\(word) is dropped because CMUdict lists \(added)")
        }
    }

    @Test("the DP takes any count in N_w and gives ties to the context count")
    func dpAcceptsSet() {
        // A 3-syllable word with N_w {2, 3}: two nuclei inside it is not short, P = 2 matches.
        let word = NucleusAssigner.Word(start: 0.0, end: 0.6, syllables: 3, allowed: [2, 3])
        var result = NucleusAssigner.assign([0.1, 0.4], to: [word])
        #expect(result.nuclei == [[0, 1]])
        #expect(result.words[0].short == false && result.words[0].available == 2)
        #expect(result.words[0].assignedCount == 2)
        #expect(abs(result.words[0].confidence - 0.9) < 1e-12)
        // Three nuclei: both counts cost 0 if all are inside, so the tie goes to the context count (3).
        result = NucleusAssigner.assign([0.1, 0.3, 0.5], to: [word])
        #expect(result.nuclei == [[0, 1, 2]])
        #expect(result.words[0].assignedCount == nil)
        // Without the set (spec 25), two nuclei leave the word short.
        result = NucleusAssigner.assign([0.1, 0.4], to: [NucleusAssigner.Word(start: 0.0, end: 0.6, syllables: 3)])
        #expect(result.nuclei == [nil])
    }

    @Test("family with 2 nuclei matches, maps through the dropped syllable and keeps A(w) on context indices")
    func familyInTheSegmenter() async throws {
        // "family" as two bumps (fam-ly), then "lesson".
        let take = SyntheticTake(words: [
            SyntheticWord(text: "family", arpabet: "F AE1 M AH0 L IY0", edges: [0.10, 0.35, 0.55]),
            SyntheticWord(text: "lesson", arpabet: "L EH1 S AH0 N", edges: [0.85, 1.05, 1.25]),
        ], duration: 1.5)
        let pitch = try await NucleusTests.pitch(take)
        var input = take.input
        input.pitch = pitch
        let family = try Self.allowed("family", "F AE1 M AH0 L IY0")
        input.allowedCounts = [WordIndex(0): family]
        let segmentation = try SyllableSegmenter(voicing: EnergyVoicing(), thresholds: NucleusTests.nucleusThresholds)
            .segment(input)
        let word = try #require(segmentation.words.first)
        #expect(!word.isNucleusShort && !word.isAssignmentAmbiguous)
        #expect(word.nucleusAssignment?.available == 2)
        #expect(word.nucleusAssignment?.assignedCount == 2)
        #expect(word.nucleusAssignment?.allowed == [2, 3])
        #expect(word.syllables.count == 3)
        #expect(word.syllables.map { $0.nucleus != nil } == [true, false, true])
        let comparable = ComparableSyllable.all(in: segmentation, pitch: pitch).filter { $0.word == WordIndex(0) }
        #expect(comparable.map(\.indexInWord) == [0, 2])
        // Placement reads context indices: the first syllable is louder and longer, and A(w) = {0} is the context's.
        let prominence = try #require(TakeProminence(ComparableSyllable.all(in: segmentation, pitch: pitch)))
        let observed = try #require(prominence.observedStress(of: WordIndex(0)))
        #expect([0, 2].contains(observed.primary))
        let decision = placementDecision(observed: observed, accepted: [0], confidence: .high, exposure: false)
        #expect(decision?.observedPrimary == observed.primary)
    }
}
