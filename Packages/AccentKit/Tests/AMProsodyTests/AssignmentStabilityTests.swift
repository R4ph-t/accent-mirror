// Spec 26 §3: assignment stability. A peak near a word edge gives two candidate assignments; agreeing verdicts are
// kept, and differing ones give `.assignmentAmbiguous` on exactly the words that differ. A word with no peak near an
// edge is never ambiguous.

import AMAlignment
import AMCore
import AMPitch
@testable import AMProsody
import Foundation
import Testing

@Suite("AssignmentStabilityTests") struct AssignmentStabilityTests {
    // Word A [0, 0.5] takes 1 or 2 syllables, B [0.5, 1.0] takes 1, C [1.4, 1.9] takes 1. Peaks: 0.25 and 0.47 (30 ms
    // inside A's end, next to B's start) in A, 0.75 in B, 1.65 in the middle of C.
    static let words = [
        NucleusAssigner.Word(start: 0.0, end: 0.5, syllables: 2, allowed: [1, 2]),
        NucleusAssigner.Word(start: 0.5, end: 1.0, syllables: 1),
        NucleusAssigner.Word(start: 1.4, end: 1.9, syllables: 1),
    ]
    static let peaks = [0.25, 0.47, 0.75, 1.65]

    @Test("a peak 30 ms inside a word edge gives two candidate assignments") func twoCandidates() {
        let result = NucleusAssigner.assign(Self.peaks, to: Self.words)
        #expect(result.nuclei == [[0, 1], [2], [3]])
        var seen: [[[Int]?]] = []
        _ = NucleusAssignmentStability.ambiguousWords(
            peaks: Self.peaks, words: Self.words, result: result, thresholds: .current
        ) { word, nuclei, _ in
            if word == 0 { seen.append([nuclei]) }
            return nuclei?.count
        }
        // The DP's choice ([0, 1]) and the alternative: B can't take a second nucleus, so the peak is skipped and A
        // keeps one ([0], a count in its N_w).
        #expect(seen.contains([[0, 1]]) && seen.contains([[0]]))
    }

    @Test("agreeing verdicts are kept; differing ones mark exactly the words that differ") func agreeAndDiffer() {
        let result = NucleusAssigner.assign(Self.peaks, to: Self.words)
        let agree = NucleusAssignmentStability.ambiguousWords(
            peaks: Self.peaks, words: Self.words, result: result, thresholds: .current) { _, nuclei, _ in nuclei == nil }
        #expect(agree.isEmpty)
        // A verdict that reads the count: A changes (2 → 1), B and C don't.
        let differ = NucleusAssignmentStability.ambiguousWords(
            peaks: Self.peaks, words: Self.words, result: result, thresholds: .current) { _, nuclei, _ in nuclei?.count }
        #expect(differ == [0])
        // A verdict that reads which nucleus is first: only A's set changes, so only A is ambiguous.
        let first = NucleusAssignmentStability.ambiguousWords(
            peaks: Self.peaks, words: Self.words, result: result, thresholds: .current) { _, nuclei, _ in nuclei?.last }
        #expect(first == [0])
    }

    @Test("a moved peak the neighbour can take re-verdicts both words") func neighbourTakes() {
        // B takes 1 or 2 now: the alternative moves 0.47 into B, so both A and B change.
        var words = Self.words
        words[1] = NucleusAssigner.Word(start: 0.5, end: 1.0, syllables: 1, allowed: [1, 2])
        let result = NucleusAssigner.assign(Self.peaks, to: words)
        let ambiguous = NucleusAssignmentStability.ambiguousWords(
            peaks: Self.peaks, words: words, result: result, thresholds: .current) { _, nuclei, _ in nuclei?.count }
        #expect(ambiguous == [0, 1])
    }

    @Test("a word with no peak near an edge is never marked ambiguous") func farFromEdges() {
        let result = NucleusAssigner.assign(Self.peaks, to: Self.words)
        // Whatever the verdict reads, C (peak 250 ms from both edges) never changes.
        for verdict in [{ (n: [Int]?) in n?.count ?? -1 }, { (n: [Int]?) in n?.first ?? -1 }, { (n: [Int]?) in n?.reduce(0, +) ?? -1 }] {
            let ambiguous = NucleusAssignmentStability.ambiguousWords(
                peaks: Self.peaks, words: Self.words, result: result, thresholds: .current) { _, nuclei, _ in verdict(nuclei) }
            #expect(!ambiguous.contains(2))
        }
    }

    @Test("in the segmenter, an ambiguous word gets the flag and leaves the comparable set")
    func segmenterMarksAmbiguous() async throws {
        // The pulse train, with "record"'s end moved in to 0.45: its second peak (≈ 0.425 s) sits 25 ms inside the end.
        // "the" (0.55 s) is out of reach, so the alternative skips that peak and "record" is nucleus-short there:
        // its verdict differs, so it is ambiguous. "the" is touched too: with "record" short, its P counts the nuclei
        // back to the take's start (spec 25's P), 3 against N 1, so s_w drops to low and its verdict differs as well.
        // The other words have no peak within 40 ms of an edge and aren't touched.
        let take = SyntheticTake.pulseTrain
        let pitch = try await NucleusTests.pitch(take)
        var input = take.input
        input.pitch = pitch
        input.spans[WordIndex(0)] = try SyllableSegmenter.WordSpan(start: 0.10, end: 0.45, probability: 1)
        let segmentation = try SyllableSegmenter(voicing: EnergyVoicing(), thresholds: NucleusTests.nucleusThresholds)
            .segment(input)
        let flags = segmentation.words.map(\.isAssignmentAmbiguous)
        #expect(flags == [true, true, false, false, false])
        #expect(!ComparableSyllable.all(in: segmentation, pitch: pitch).contains { $0.word == WordIndex(0) || $0.word == WordIndex(1) })
        // Unmoved, nothing is ambiguous.
        var plain = take.input
        plain.pitch = pitch
        let unmoved = try SyllableSegmenter(voicing: EnergyVoicing(), thresholds: NucleusTests.nucleusThresholds).segment(plain)
        #expect(unmoved.words.allSatisfy { !$0.isAssignmentAmbiguous })
    }
}
