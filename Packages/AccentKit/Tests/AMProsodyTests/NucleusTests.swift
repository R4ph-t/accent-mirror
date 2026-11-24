// Spec 25: nucleus-anchored syllable measurement. Detection on spec 07's pulse train, the assignment, the measurement
// windows, edge invariance (CTO markup 3), P from the assignment (markup 1), structural exposure (markup 2), and the
// `.span` path unchanged.

import AMAlignment
import AMCore
import AMPitch
@testable import AMProsody
import Foundation
import Testing

@Suite("NucleusTests") struct NucleusTests {
    static var nucleusThresholds: Thresholds {
        var thresholds = Thresholds()
        thresholds.prominence.measurement = .nucleus
        return thresholds
    }

    static func pitch(_ take: SyntheticTake) async throws -> PitchTrack {
        try await PYINTracker().track(take.samples, sampleRate: SyntheticTake.sampleRate)
    }

    /// The take segmented in `.nucleus` mode, with its spans replaced by `spans` when given.
    static func segment(_ take: SyntheticTake, pitch: PitchTrack, spans: [WordIndex: SyllableSegmenter.WordSpan]? = nil,
                        thresholds: Thresholds = nucleusThresholds) throws -> SyllableSegmentation {
        var input = take.input
        input.pitch = pitch
        if let spans { input.spans = spans }
        return try SyllableSegmenter(voicing: EnergyVoicing(), thresholds: thresholds).segment(input)
    }

    /// The take's spans with each word's start and end moved by the given offsets (seconds).
    static func moved(_ take: SyntheticTake, _ offsets: [(start: Double, end: Double)]) -> [WordIndex: SyllableSegmenter.WordSpan] {
        Dictionary(uniqueKeysWithValues: take.words.indices.map { index in
            let word = take.words[index]
            return (WordIndex(index), try! SyllableSegmenter.WordSpan(
                start: word.start + offsets[index].start, end: word.end + offsets[index].end,
                probability: word.probability))
        })
    }

    /// Per syllable: d, e, p, split confidence and exposure.
    struct Features: Equatable {
        let d: Double, e: Double, p: Double?, split: Double?, exposed: Bool
    }

    static func features(_ segmentation: SyllableSegmentation, pitch: PitchTrack) -> [String: Features] {
        var out: [String: Features] = [:]
        for word in segmentation.words {
            for syllable in word.syllables {
                let p = ProminenceFeatures(syllable, pitch: pitch, thresholds: nucleusThresholds.prominence).peakSemitones
                out["\(word.phraseWord.rawValue):\(syllable.indexInWord)"] = Features(
                    d: syllable.duration, e: syllable.energyDBFS, p: p, split: word.nucleusAssignment?.confidence,
                    exposed: syllable.lengtheningExposed)
            }
        }
        return out
    }

    /// True envelope peaks of the pulse train: the middle of each syllable's raised-cosine bump.
    static var truePeaks: [Double] {
        SyntheticTake.pulseTrain.words.flatMap { word in zip(word.edges, word.edges.dropFirst()).map { ($0 + $1) / 2 } }
    }

    // MARK: Detection

    @Test("the band envelope reads a 1 kHz tone at its RMS and rejects a 100 Hz tone") func bandEnvelope() {
        let rate = 16_000.0
        func tone(_ hz: Double, _ amplitude: Double) -> [Float] {
            (0..<16_000).map { Float(amplitude * sin(2 * .pi * hz * Double($0) / rate)) }
        }
        let inBand = NucleusDetector.envelope(samples: tone(1_000, 0.5), sampleRate: rate)
        let expected = 20 * log10(0.5 / 2.0.squareRoot())
        #expect(abs(inBand[50] - expected) < 0.5, "1 kHz: \(inBand[50]) dBFS vs \(expected)")
        let outOfBand = NucleusDetector.envelope(samples: tone(100, 0.5), sampleRate: rate)
        #expect(outOfBand[50] < expected - 30, "100 Hz: \(outOfBand[50]) dBFS")
    }

    @Test("on the pulse train, every peak is within 10 ms of the true envelope peak and the count matches")
    func pulseTrainPeaks() async throws {
        let take = SyntheticTake.pulseTrain
        let nuclei = NucleusDetector().detect(samples: take.samples, sampleRate: SyntheticTake.sampleRate,
                                              pitch: try await Self.pitch(take))
        let truth = Self.truePeaks
        #expect(nuclei.count == truth.count)
        for (nucleus, expected) in zip(nuclei, truth) {
            #expect(abs(nucleus.peakTime - expected) <= 0.010, "peak \(nucleus.peakTime) vs \(expected)")
            #expect(nucleus.region.contains(nucleus.peakTime))
            #expect(nucleus.prominenceDB >= 3)
            #expect(nucleus.leftValleyTime < nucleus.peakTime && nucleus.peakTime < nucleus.rightValleyTime)
        }
    }

    @Test("nuclei are bit-identical whatever word spans are passed") func detectionReadsNoEdges() async throws {
        let take = SyntheticTake.pulseTrain
        let pitch = try await Self.pitch(take)
        let reference = try Self.segment(take, pitch: pitch).nuclei
        #expect(reference?.isEmpty == false)
        let shifts: [[(start: Double, end: Double)]] = [
            Array(repeating: (0.04, 0.04), count: 5), Array(repeating: (-0.04, -0.04), count: 5),
            [(0.03, -0.05), (0.0, 0.02), (-0.06, 0.07), (0.05, -0.01), (-0.02, 0.0)],
        ]
        for shift in shifts {
            #expect(try Self.segment(take, pitch: pitch, spans: Self.moved(take, shift)).nuclei == reference)
        }
    }

    // MARK: Edge moves

    @Test("moving every word edge by ±40 ms changes no d, e or p unless a peak lies within 40 ms of an edge")
    func jitteredEdgesKeepFeatures() async throws {
        let take = SyntheticTake.pulseTrain
        let pitch = try await Self.pitch(take)
        let reference = Self.features(try Self.segment(take, pitch: pitch), pitch: pitch)
        // Independent ±40 ms draws per edge, fixed so the test is deterministic.
        var random = SplitMix(state: 20_261_125)
        var checked = 0
        for _ in 0..<20 {
            let offsets = take.words.map { _ in (start: random.offset(0.040), end: random.offset(0.040)) }
            let spans = Self.moved(take, offsets)
            let near = Self.truePeaks.contains { peak in
                spans.values.contains { abs(peak - $0.start) <= 0.040 || abs(peak - $0.end) <= 0.040 }
            }
            let moved = Self.features(try Self.segment(take, pitch: pitch, spans: spans), pitch: pitch)
            if near { continue }
            checked += 1
            for (key, value) in reference {
                let other = try #require(moved[key])
                #expect(other.d == value.d && other.e == value.e && other.p == value.p, "\(key)")
            }
        }
        #expect(checked > 0)
    }

    @Test("edge invariance: with every peak > 50 ms from any edge, ±40 ms moves keep d, e, p, s_w and exposure identical")
    func edgeInvariance() async throws {
        let take = SyntheticTake.pulseTrain
        let edges = take.words.flatMap { [$0.start, $0.end] }
        #expect(Self.truePeaks.allSatisfy { peak in edges.allSatisfy { abs(peak - $0) > 0.050 } })
        let pitch = try await Self.pitch(take)
        let reference = Self.features(try Self.segment(take, pitch: pitch), pitch: pitch)
        #expect(reference.count == 11)
        for shift in [0.040, -0.040] {
            let spans = Self.moved(take, Array(repeating: (shift, shift), count: take.words.count))
            #expect(Self.features(try Self.segment(take, pitch: pitch, spans: spans), pitch: pitch) == reference,
                    "every edge moved by \(shift * 1000) ms")
        }
    }

    // MARK: Assignment

    @Test("each word gets N_w consecutive nuclei, an extra peak is skipped, one peak too few is nucleus-short")
    func assignment() {
        let words = [NucleusAssigner.Word(start: 0.0, end: 0.4, syllables: 2),
                     NucleusAssigner.Word(start: 0.5, end: 0.8, syllables: 1)]
        // Exact.
        var result = NucleusAssigner.assign([0.1, 0.3, 0.65], to: words)
        #expect(result.nuclei == [[0, 1], [2]])
        #expect(result.words.map(\.available) == [2, 1])
        #expect(result.words.map(\.confidence) == [0.9, 0.9])
        // An extra peak in the pause (a filled pause) is skipped.
        result = NucleusAssigner.assign([0.1, 0.3, 0.45, 0.65], to: words)
        #expect(result.nuclei == [[0, 1], [3]])
        #expect(result.words.map(\.short) == [false, false])
        // One peak too few for the first word: nucleus-short, the second keeps its nucleus.
        result = NucleusAssigner.assign([0.2, 0.65], to: words)
        #expect(result.nuclei[0] == nil && result.nuclei[1] == [1])
        #expect(result.words[0].short && !result.words[1].short)
        #expect(result.words[0].available == 1)
        // A peak further than the padding (80 ms) outside every word can't be taken.
        result = NucleusAssigner.assign([0.1, 0.3, 0.95], to: words)
        #expect(result.nuclei == [[0, 1], nil])
    }

    @Test("P comes from the assignment: the nuclei between the neighbours' assigned nuclei")
    func availableFromAssignment() {
        // "Z" (2 syllables) takes a peak 10 ms after its end; that peak is also in "A"'s padded window, which a raw
        // count would read as A's second candidate.
        let words = [NucleusAssigner.Word(start: 0.0, end: 0.28, syllables: 2),
                     NucleusAssigner.Word(start: 0.30, end: 0.60, syllables: 1)]
        let result = NucleusAssigner.assign([0.10, 0.29, 0.45], to: words)
        #expect(result.nuclei == [[0, 1], [2]])
        #expect(result.words[1].available == 1)
        #expect(result.words[1].confidence == 0.9)
        // With an unassigned peak between them, both words could take it: P = N_w + 1, s_w = 0.6.
        let gap = NucleusAssigner.assign([0.10, 0.20, 0.40, 0.70], to: [
            NucleusAssigner.Word(start: 0.0, end: 0.28, syllables: 2),
            NucleusAssigner.Word(start: 0.55, end: 0.85, syllables: 1)])
        #expect(gap.nuclei == [[0, 1], [3]])
        #expect(gap.words.map(\.available) == [3, 2])
        #expect(gap.words.allSatisfy { abs($0.confidence - 0.6) < 1e-12 })
    }

    @Test("a word with one peak fewer is nucleus-short: low, no stress features, out of the comparable set")
    func nucleusShortWord() async throws {
        // "photography", 4 syllables; the last two share one bump with a dip under `nucleus.minProminenceDB`, so the
        // energy shows 3 nuclei. Spec 25 used a 2 dB dip under its 3 dB floor; spec 26's grid chose 1.5 dB, so the dip
        // is 1 dB: the same scenario (a dip shallower than the floor merges), not a looser check.
        let edges = [0.20, 0.40, 0.60, 0.80, 1.00]
        let word = SyntheticWord(
            text: "photography", arpabet: "F AH0 T AA1 G R AH0 F IY0", edges: edges,
            shape: { time, syllable, edges in
                guard syllable >= 2 else { return SyntheticTake.bump(time, syllable, edges) }
                let taper = min(1, (time - edges[2]) / 0.06, (edges[4] - time) / 0.06)
                let dip = 1 - (1 - pow(10, -1.0 / 20)) * exp(-pow((time - edges[3]) / 0.03, 2) / 2)
                return max(0, taper) * dip
            })
        let take = SyntheticTake(words: [word], duration: 1.2)
        let pitch = try await Self.pitch(take)
        let segmentation = try Self.segment(take, pitch: pitch)
        let segmented = try #require(segmentation.words.first)
        #expect(segmentation.nuclei?.count == 3)
        #expect(segmented.isNucleusShort)
        #expect(segmented.nucleusAssignment?.available == 3)
        #expect(segmented.syllables.count == 4)
        #expect(segmented.syllables.allSatisfy { $0.level == .low && $0.nucleus == nil })
        #expect(ComparableSyllable.all(in: segmentation, pitch: pitch).isEmpty)
    }

    @Test("d is the nucleus region, e reads ±30 ms around the peak inside it, p its voiced frames")
    func measurementWindows() async throws {
        let take = SyntheticTake.pulseTrain
        let pitch = try await Self.pitch(take)
        let segmentation = try Self.segment(take, pitch: pitch)
        let nuclei = try #require(segmentation.nuclei)
        for syllable in segmentation.syllables {
            let measured = try #require(syllable.nucleus)
            let nucleus = nuclei[measured.nucleusIndex]
            #expect(syllable.duration == nucleus.region.duration)
            #expect(measured.region == nucleus.region)
            // A raised-cosine bump: the −6 dB region is about half the syllable, never all of it.
            #expect(syllable.duration > 0.03 && syllable.duration < syllable.range.duration)
            #expect(syllable.energyDBFS > -30 && syllable.energyDBFS < -10)
            #expect(measured.peakSemitones == pitch.peakSemitones(in: nucleus.region, minVoicedFrames: 3))
        }
    }

    // MARK: Exposure and the span path

    @Test("exposure is the same in .span and .nucleus: phrase-final, and before a 200 ms pause (not 100 ms)")
    func exposureSameInBothModes() async throws {
        let take = SyntheticTake.pulseTrain
        let pitch = try await Self.pitch(take)
        let span = try take.segment().syllables.filter(\.lengtheningExposed).map { "\($0.phraseWord):\($0.indexInWord)" }
        let nucleus = try Self.segment(take, pitch: pitch).syllables.filter(\.lengtheningExposed)
            .map { "\($0.phraseWord):\($0.indexInWord)" }
        #expect(span == ["2:3", "4:1"])
        #expect(nucleus == span)
    }

    @Test(".span mode is spec 07's path: span features, no nuclei, spec 08's worked examples to 2 decimals")
    func spanPathUnchanged() throws {
        var thresholds = Thresholds()
        thresholds.prominence.measurement = .span
        let segmentation = try SyntheticTake.pulseTrain.segment(thresholds: thresholds)
        #expect(segmentation.nuclei == nil && segmentation.measurement == nil)
        for word in segmentation.words {
            #expect(word.nucleusAssignment == nil)
            for syllable in word.syllables {
                #expect(syllable.nucleus == nil)
                #expect(abs(syllable.duration - syllable.range.duration) < 1e-12)
            }
        }
        for example in ProminenceTests.cases {
            let scores = try #require(Prominence.scores(example.syllables.map(\.features), thresholds: thresholds.prominence))
            let word = example.syllables.indices.filter { example.syllables[$0].word == example.word }.map { scores[$0] }
            for (got, expected) in zip(word, example.p16) {
                #expect(ProminenceTests.near(got, expected), "\(example.name): \(got) vs \(expected)")
            }
        }
    }

    @Test(".nucleus mode needs the pitch track") func missingPitch() {
        #expect(throws: SyllableSegmenter.Failure.missingPitchTrack) {
            try SyllableSegmenter(voicing: EnergyVoicing(), thresholds: Self.nucleusThresholds)
                .segment(SyntheticTake.pulseTrain.input)
        }
    }
}

/// SplitMix64 for deterministic test offsets.
struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [−radius, +radius).
    mutating func offset(_ radius: Double) -> Double { (2 * Double(next() >> 11) * 0x1.0p-53 - 1) * radius }
}
