// Spec 27 How to test, step 1: `swift test --package-path Packages/AccentKit --filter Spike27Tests`.

import AMAlignment
import AMCore
import AMEvaluation
import AMPitch
import AMSpike27
import Foundation
import Testing

private let sampleRate = 16_000.0

/// A voiced "syllable": harmonics of f0 below 4 kHz at 1/k, with 20 ms raised onsets and offsets.
private func vowel(f0: Double, seconds: Double, amplitude: Double) -> [Float] {
    let n = Int(seconds * sampleRate)
    return (0..<n).map { i in
        let t = Double(i) / sampleRate
        var v = 0.0
        var k = 1
        while Double(k) * f0 < 4_000 {
            v += sin(2 * .pi * Double(k) * f0 * t) / Double(k)
            k += 1
        }
        let ramp = min(1, t / 0.02, (seconds - t) / 0.02)
        return Float(v * ramp * amplitude * 0.3)
    }
}

private func silence(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * sampleRate)) }

/// A two-syllable pulse-train word: a long, loud, high first syllable and a short, quiet, low second one.
private func pulseTrainWord() -> [Float] {
    silence(0.15) + vowel(f0: 220, seconds: 0.26, amplitude: 0.5) + silence(0.10)
        + vowel(f0: 170, seconds: 0.12, amplitude: 0.18) + silence(0.15)
}

private func repositoryRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    while url.path != "/" {
        url.deleteLastPathComponent()
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("AGENTS.md").path) { return url }
    }
    return url
}

private func nucleus(_ peak: Double, prominence: Double, peakDB: Double = -20) -> MeasuredNucleus {
    MeasuredNucleus(peakTime: peak, regionStart: peak - 0.03, regionEnd: peak + 0.03, prominenceDB: prominence,
                    peakDB: peakDB, duration: 0.06, energyDB: -20, f0Semitones: 0, f0Residual: 0, tiltDB: 0)
}

private func split() throws -> VCTKSplitManifest {
    try JSONDecoder().decode(VCTKSplitManifest.self,
                             from: Data(contentsOf: repositoryRoot().appendingPathComponent("fixtures/splits/vctk.json")))
}

@Suite("Spike27Tests")
struct Spike27Tests {
    @Test("training and τ code refuse held-out VCTK and every L2 set")
    func guardRefusesEvaluationData() throws {
        let split = try split()
        let tuningSpeaker = split.tuning[0], heldOutSpeaker = split.heldOut[0]
        try Spike27Guard.checkTraining([(.tuningVCTK, tuningSpeaker), (.tts, "tts")], split: split, use: "training")
        for population in [Population.heldOutVCTK, .l2Recall, .l2Clean, .speechocean762, .bundled] {
            #expect(throws: Spike27Guard.Refused.self) {
                try Spike27Guard.checkTraining([(.tuningVCTK, tuningSpeaker), (population, "x")], split: split, use: "τ")
            }
        }
        // A held-out speaker labelled as tuning is refused too.
        #expect(throws: Spike27Guard.Refused.self) {
            try Spike27Guard.checkTraining([(.tuningVCTK, heldOutSpeaker)], split: split, use: "training")
        }
        try Spike27Guard.checkEnvelope([(.tuningVCTK, tuningSpeaker), (.bundled, "p225")], split: split)
        for population in [Population.heldOutVCTK, .l2Recall, .l2Clean, .speechocean762, .tts] {
            #expect(throws: Spike27Guard.Refused.self) { try Spike27Guard.checkEnvelope([(population, "x")], split: split) }
        }
        #expect(Population.allCases.filter(\.isTuningSide) == [.tuningVCTK, .tts])
    }

    @Test("transplantation on a pulse-train word swaps the measured d, e and p between the two nuclei")
    func transplantationSwaps() async throws {
        let samples = pulseTrainWord()
        let track = try await PYINTracker().track(samples, sampleRate: sampleRate)
        let before = FrontEnd.measure(samples, track: track)
        try #require(before.nuclei.count == 2)
        let (s, u) = (before.nuclei[0], before.nuclei[1])
        let marks = PSOLA.analysisMarks(samples, track: track, sampleRate: sampleRate)
        let regions = StressSwap.regions(stressed: s, unstressed: u, take: before)
        let output = PSOLA.process(samples, marks: marks, regions: regions, sampleRate: sampleRate)
        #expect(!output.clipped)
        let after = try await FrontEnd.measure(output.samples)
        try #require(after.nuclei.count == 2)
        let (a, b) = (after.nuclei[0], after.nuclei[1])
        // Duration: each nucleus takes the other's length (within 30 ms).
        #expect(abs(a.duration - u.duration) <= 0.03)
        #expect(abs(b.duration - s.duration) <= 0.03)
        // Intensity: the offset flips (within 1.5 dB).
        #expect(abs((a.energyDB - b.energyDB) + (s.energyDB - u.energyDB)) <= 1.5)
        // Pitch: the f0 difference flips (within 1 st).
        let pBefore = try #require(s.f0Semitones) - (try #require(u.f0Semitones))
        let pAfter = try #require(a.f0Semitones) - (try #require(b.f0Semitones))
        #expect(abs(pAfter + pBefore) <= 1.0)
        // The time map carries the word's edges to the new timeline.
        #expect(output.timeMap.forward(0) == 0)
        #expect(abs(output.timeMap.forward(before.duration) - Double(output.samples.count) / sampleRate) < 0.001)
    }

    @Test("the identity PSOLA leaves the measured features within tolerance")
    func identityPSOLA() async throws {
        let samples = pulseTrainWord()
        let track = try await PYINTracker().track(samples, sampleRate: sampleRate)
        let raw = FrontEnd.measure(samples, track: track)
        let marks = PSOLA.analysisMarks(samples, track: track, sampleRate: sampleRate)
        let identity = PSOLA.process(samples, marks: marks, regions: [], sampleRate: sampleRate)
        #expect(identity.samples.count == samples.count)
        let processed = try await FrontEnd.measure(identity.samples)
        try #require(processed.nuclei.count == raw.nuclei.count)
        for (x, y) in zip(raw.nuclei, processed.nuclei) {
            #expect(abs(x.duration - y.duration) <= 0.011)
            #expect(abs(x.energyDB - y.energyDB) <= 0.5)
            #expect(abs(x.tiltDB - y.tiltDB) <= 0.5)
            #expect(abs((x.f0Semitones ?? 0) - (y.f0Semitones ?? 0)) <= 0.2)
        }
    }

    @Test("the heteronym table resolves or excludes every starter heteronym")
    func heteronyms() throws {
        let root = repositoryRoot()
        let entries = try TargetRule.loadHeteronyms(root.appendingPathComponent("docs/agreement/spike27/heteronyms.json"))
        struct Manifest: Decodable { struct Phrase: Decodable { let id: String; let text: String }; let phrases: [Phrase] }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("Resources/Starter/manifest.json")))
        let dictionary = try PronouncingDictionary.bundled()
        let selector = try PronunciationSelector.bundled()
        let rule = TargetRule(dictionary: dictionary, heteronyms: entries)
        var heteronymCount = 0
        for phrase in manifest.phrases {
            let expected = selector.expectedPhrase(for: PhraseText(text: phrase.text, origin: .starter))
            for (i, word) in expected.words.enumerated() {
                let variants = dictionary.pronunciations(of: word.text)
                guard variants.contains(where: { $0.syllables.count >= 2 }) else { continue }
                let primaries = Set(variants.map(\.primarySyllable))
                guard primaries.count > 1 || Set(variants.map(\.syllables.count)).count > 1 else { continue }
                heteronymCount += 1
                let entry = entries.first { $0.phrase == phrase.id && $0.wordIndex == i }
                #expect(entry != nil, "no heteronym entry for \(phrase.id) word \(i) \(word.text)")
                let (target, exclusion) = rule.target(word: word.text, index: i, phrase: phrase.id, context: word.pronunciation)
                if let stress = entry?.stressIndex { #expect(target == stress) } else { #expect(target == nil && exclusion != nil) }
            }
        }
        #expect(heteronymCount == entries.count)
        // Outside the table, disagreeing CMUdict entries exclude the word.
        let (target, exclusion) = rule.target(word: "record", index: 0, phrase: nil,
                                              context: dictionary.pronunciations(of: "record").first)
        #expect(target == nil && exclusion == "CMUdict entries disagree on primary stress")
        #expect(rule.target(word: "cat", index: 0, phrase: nil, context: dictionary.pronunciations(of: "cat").first).0 == nil)
    }

    @Test("arm B picks the N most prominent nuclei in time order and abstains only below N")
    func armBTopK() {
        let nuclei = [nucleus(0.10, prominence: 9), nucleus(0.20, prominence: 3), nucleus(0.30, prominence: 12),
                      nucleus(0.40, prominence: 6), nucleus(0.90, prominence: 20)]
        #expect(ArmSelection.topK(nuclei, start: 0.05, end: 0.45, count: 2, paddingSeconds: 0) == [0, 2])
        #expect(ArmSelection.topK(nuclei, start: 0.05, end: 0.45, count: 3, paddingSeconds: 0) == [0, 2, 3])
        #expect(ArmSelection.topK(nuclei, start: 0.05, end: 0.45, count: 4, paddingSeconds: 0) == [0, 1, 2, 3])
        #expect(ArmSelection.topK(nuclei, start: 0.05, end: 0.45, count: 5, paddingSeconds: 0) == nil)
        // The runtime source's padding reaches the nucleus just outside.
        #expect(ArmSelection.topK(nuclei, start: 0.05, end: 0.82, count: 5, paddingSeconds: 0.08) == [0, 1, 2, 3, 4])
        #expect(ArmSelection.padding(.oracle) == 0)
        #expect(ArmSelection.padding(.runtime) == Thresholds.current.alignment.asrPaddingMs / 1000)
        // Ties: the higher peak, then the earlier.
        let tied = [nucleus(0.1, prominence: 5, peakDB: -30), nucleus(0.2, prominence: 5, peakDB: -20), nucleus(0.3, prominence: 5, peakDB: -20)]
        #expect(ArmSelection.topK(tied, start: 0, end: 1, count: 1, paddingSeconds: 0) == [1])
    }

    @Test("the speechocean762 label rule and the overlap drop by utterance id match the spec")
    func speechOceanRule() throws {
        let dropped: Set<String> = ["000010011"]
        func label(_ stress: Double, _ accuracy: Double, _ syllables: Int, _ utterance: String = "000020022")
            -> Result<SpeechOcean762Rule.Label, SpeechOcean762Rule.ExclusionError> {
            SpeechOcean762Rule.label(stress: stress, accuracy: accuracy, syllables: syllables, utterance: utterance, dropped: dropped)
        }
        #expect(try label(5, 7, 2).get() == .misplaced)
        #expect(try label(10, 5, 3).get() == .correct)
        #expect(throws: SpeechOcean762Rule.ExclusionError(.fewerThanTwoSyllables)) { try label(5, 9, 1).get() }
        #expect(throws: SpeechOcean762Rule.ExclusionError(.unintelligible)) { try label(10, 4, 2).get() }
        #expect(throws: SpeechOcean762Rule.ExclusionError(.otherStressScore)) { try label(8, 9, 2).get() }
        #expect(throws: SpeechOcean762Rule.ExclusionError(.overlapsThe134)) { try label(10, 9, 2, "000010011").get() }
        // The committed overlap list is exactly the utterances of the 134 (from the label-only fixture).
        let root = repositoryRoot()
        let labels = try SpeechOceanLabels.parseFixture(String(contentsOf: root.appendingPathComponent("fixtures/speechocean762/labels.tsv"), encoding: .utf8))
        let sets = SpeechOceanSets(labels: labels)
        #expect(sets.recall.count == 134)
        struct File: Decodable { let droppedUtterances: [String] }
        let committed = try JSONDecoder().decode(File.self, from: Data(contentsOf: root.appendingPathComponent("docs/agreement/spike27/speechocean762.json")))
        #expect(Set(committed.droppedUtterances) == SpeechOcean762Rule.overlap(recall: sets.recall))
        #expect(committed.droppedUtterances.count == 124)
    }

    @Test("a prompt with under 30 natural takes is NOT EVALUATED, and TTS counts at most once per voice")
    func envelopeMinimum() {
        func take(_ i: Int, tts: String? = nil) -> EnvelopeTake {
            EnvelopeTake(speaker: tts ?? "s\(i)", population: tts == nil ? .tuningVCTK : .tts, ttsVoice: tts,
                         metrics: PhraseMetrics(pitchRange: Double(i), finalSlope: 0, finalClass: .level, npvi: 50))
        }
        let natural29 = (0..<29).map { take($0) }
        let withTTS = natural29 + [take(100, tts: "voice-a"), take(101, tts: "voice-a"), take(102, tts: "voice-b")]
        #expect(NativeEnvelope.counts(withTTS).natural == 29)
        #expect(NativeEnvelope.counts(withTTS).ttsVoices == 2)
        #expect(NativeEnvelope.interval(withTTS, value: \.pitchRange, q: 0) == nil)
        let natural30 = natural29 + [take(29)]
        let interval = NativeEnvelope.interval(natural30 + [take(500, tts: "voice-a")], value: \.pitchRange, q: 0)
        #expect(interval == 0...29)
        #expect(NativeEnvelope.monotone(PhraseMetrics(pitchRange: -1, finalSlope: nil, finalClass: nil, npvi: nil), envelope: 0...29) == true)
        #expect(NativeEnvelope.monotone(PhraseMetrics(pitchRange: 3, finalSlope: nil, finalClass: nil, npvi: nil), envelope: 0...29) == false)
    }

    @Test("two runs are identical")
    func deterministic() async throws {
        let samples = pulseTrainWord()
        let first = try await FrontEnd.measure(samples)
        let second = try await FrontEnd.measure(samples)
        #expect(first == second)
        let words: [(nuclei: [MeasuredNucleus], label: Int)] = (0..<60).map { i in
            let a = MeasuredNucleus(peakTime: 0.1, regionStart: 0.05, regionEnd: 0.15, prominenceDB: 10, peakDB: -20,
                                    duration: 0.1 + Double(i % 7) * 0.01, energyDB: -20 + Double(i % 5), f0Semitones: 1,
                                    f0Residual: Double(i % 3), tiltDB: Double(i % 4))
            let b = MeasuredNucleus(peakTime: 0.3, regionStart: 0.25, regionEnd: 0.35, prominenceDB: 8, peakDB: -22,
                                    duration: 0.08 + Double(i % 5) * 0.01, energyDB: -22 + Double(i % 3), f0Semitones: 0,
                                    f0Residual: -Double(i % 2), tiltDB: Double(i % 6))
            return ([a, b], i % 3 == 0 ? 1 : 0)
        }
        for family in ModelFamily.allCases {
            let x = StressClassifier.fit(words, variant: .tiltF0, family: family)
            let y = StressClassifier.fit(words, variant: .tiltF0, family: family)
            #expect(x == y)
            #expect(x.probabilities(words[0].nuclei) == y.probabilities(words[0].nuclei))
        }
        let track = try await PYINTracker().track(samples, sampleRate: sampleRate)
        let marks = PSOLA.analysisMarks(samples, track: track, sampleRate: sampleRate)
        let regions = StressSwap.regions(stressed: first.nuclei[0], unstressed: first.nuclei[1], take: first)
        #expect(PSOLA.process(samples, marks: marks, regions: regions, sampleRate: sampleRate).samples
                == PSOLA.process(samples, marks: marks, regions: regions, sampleRate: sampleRate).samples)
    }

    @Test("the abstaining decision flags only past τ, and ROC AUC is Mann–Whitney")
    func decisionAndAUC() {
        #expect(WordVerdict.decide(probabilities: [0.2, 0.7], target: 0, tau: 0.4).0 == .flag(1))
        #expect(WordVerdict.decide(probabilities: [0.4, 0.7], target: 0, tau: 0.4).0 == .unsure)
        #expect(WordVerdict.decide(probabilities: [0.8, 0.7], target: 0, tau: 0.0).0 == .close)
        #expect(ROC.auc(positives: [0.9, 0.8], negatives: [0.1, 0.2]) == 1)
        #expect(ROC.auc(positives: [0.5], negatives: [0.5]) == 0.5)
        #expect(SpikeStats.wilson(0, 0).upper == 1)
    }

    @Test("arm C: vowel-letter groups and the CTC letter alignment")
    func armC() {
        func groups(_ w: String) -> Int { ArmC.vowelGroups(Array(w)).count }
        #expect(groups("physical") == 3)
        #expect(groups("station") == 2)
        #expect(groups("rainbow") == 2)
        #expect(groups("imagine") == 3)
        #expect(groups("explanation") == 4)
        // Classes: 0 blank, 1 separator, 2 "A", 3 "B"; "A" at frames 0–1, the separator at 2–3, "B" at 4–5.
        let best: [Int] = [2, 2, 1, 1, 3, 3]
        var logProbs = [Float](repeating: log(0.01), count: 6 * 4)
        for (t, c) in best.enumerated() { logProbs[t * 4 + c] = log(0.97) }
        let spans = ArmC.align(logProbs: logProbs, frames: 6, classes: 4, words: [[2], [3]], letters: [["A"], ["B"]],
                               blank: 0, separator: 1)
        #expect(spans == [ArmC.LetterSpan(word: 0, letter: "A", first: 0, last: 1),
                          ArmC.LetterSpan(word: 1, letter: "B", first: 4, last: 5)])
        let nuclei = [nucleus(0.10, prominence: 5), nucleus(0.30, prominence: 5)]
        #expect(ArmC.select(nuclei, groupCentres: [0.12, 0.27], syllables: 2) == [0, 1])
        #expect(ArmC.select(nuclei, groupCentres: [0.12], syllables: 2) == nil)
        #expect(ArmC.select(nuclei, groupCentres: [0.12, 0.13], syllables: 2) == nil)
        #expect(ArmC.select(nuclei, groupCentres: [0.12, 0.45], syllables: 2) == nil)
    }
}
