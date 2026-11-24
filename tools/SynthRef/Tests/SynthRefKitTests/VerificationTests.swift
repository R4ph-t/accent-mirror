// Verification items, SSML, the voice bars, the positive-set placement-FP line (only through PositiveSetGates.line),
// tuning-only voice selection, the end-to-end path under the fold runner, and the negative set's DSP and metrics.

import AMAlignment
import AMCore
import AMEvaluation
import Foundation
import Synchronization
import Testing
@testable import SynthRefKit

func manifest() throws -> VCTKEvalSpeakersManifest {
    try VCTKEvalSpeakersManifest.load(Repo.url("fixtures/vctk/eval-speakers.json"))
}

@Suite("Verification items and SSML") struct ItemTests {
    @Test("CPO's targets plus traps, each once correct and once moved to another syllable")
    func items() throws {
        let set = try VerificationSet.build(dictionary: try .bundled(), stressShifts: try .bundled())
        #expect(set.targets.contains("rainbow") && set.targets.contains("reflection"))
        #expect(!set.targets.contains("call"), "monosyllables are not targets")
        for trap in CPOSet.extraTraps { #expect(set.traps.contains(trap)) }
        let words = Set(set.items.map(\.word))
        #expect(set.items.count == 2 * words.count)
        for word in words {
            let correct = try #require(set.items.first { $0.word == word && $0.variant == .correct })
            let moved = try #require(set.items.first { $0.word == word && $0.variant == .moved })
            #expect(correct.markedSyllable != moved.markedSyllable, "\(word)")
            #expect(try moved.pronunciation().primarySyllable == moved.markedSyllable, "\(word)")
            #expect(try moved.pronunciation().phones.count == correct.pronunciation().phones.count, "\(word)")
        }
        let photograph = try #require(set.items.first { $0.id == "photograph/moved" })
        #expect(photograph.arpabet == "F OW0 T AH1 G R AE2 F")
    }

    @Test("ElevenLabs gets cmu-arpabet phoneme tags; the Mac gets IPA with stress marks and word bookmarks")
    func ssml() throws {
        let words = [SpokenWord(text: "the"), SpokenWord(text: "photograph", arpabet: "F OW1 T AH0 G R AE2 F")]
        #expect(SSML.elevenLabs(words)
            == #"the <phoneme alphabet="cmu-arpabet" ph="F OW1 T AH0 G R AE2 F">photograph</phoneme>"#)
        let apple = try SSML.apple(words)
        #expect(apple.hasPrefix("<speak>") && apple.hasSuffix("</speak>"))
        #expect(apple.contains(#"<mark name="w0"/>the"#) && apple.contains(#"<mark name="w1"/>"#))
        #expect(apple.contains(#"alphabet="ipa" ph="ˈfoʊtəˌɡɹæf""#))
        #expect(SSML.escape(#"a<b>&"c""#) == "a&lt;b&gt;&amp;&quot;c&quot;")
    }
}

@Suite("Voice verification") struct VoiceVerificationTests {
    static let voice = EngineIdentity(kind: .elevenlabs, voiceID: "v", modelID: "eleven_flash_v2")

    static func observations(movedHits: Int, of moved: Int, correctHits: Int, of correct: Int) -> [ItemObservation] {
        let m = (0..<moved).map { i in
            ItemObservation(
                item: VerificationItem(word: "w\(i)", variant: .moved, arpabet: "AH0 B AH1", markedSyllable: 1, isTrap: false),
                observedPrimary: i < movedHits ? 1 : 0, confidence: .medium)
        }
        let c = (0..<correct).map { i in
            ItemObservation(
                item: VerificationItem(word: "w\(i)", variant: .correct, arpabet: "AH1 B AH0", markedSyllable: 0, isTrap: false),
                observedPrimary: i < correctHits ? 0 : 1, confidence: .high)
        }
        return m + c
    }

    static func tuning(_ n: Int) throws -> [TuningSpeaker] { Array(try manifest().tuningSpeakers.prefix(n)) }

    static func pairs(_ n: Int, diffs: Int) throws -> [TuningPairOutcome] {
        let speakers = try manifest().tuningSpeakers
        return (0..<n).map { i in
            TuningPairOutcome(
                speaker: speakers[i % speakers.count], phrase: VCTK.starterPhrases[i % VCTK.starterPhrases.count],
                placementDiff: i < diffs)
        }
    }

    @Test("a moved item needs the marked syllable at medium confidence or better; unobserved is a miss")
    func movedBar() {
        let item = VerificationItem(word: "x", variant: .moved, arpabet: "AH0 B AH1", markedSyllable: 1, isTrap: false)
        #expect(ItemObservation(item: item, observedPrimary: 1, confidence: .medium).meetsBar)
        #expect(!ItemObservation(item: item, observedPrimary: 1, confidence: .low).meetsBar)
        #expect(!ItemObservation(item: item, observedPrimary: 0, confidence: .high).meetsBar)
        #expect(!ItemObservation(item: item, observedPrimary: nil, confidence: nil).meetsBar)
    }

    @Test("placement-FP line: blocked while the positive set is NOT EVALUATED, whatever the pairs say")
    func fpBlocked() throws {
        let line = PlacementFalsePositives.line(
            try Self.pairs(300, diffs: 0), positiveSet: .notEvaluated(shortfalls: ["phrases 10 < 18"], blockedOn: "spec 24"))
        guard case .blocked = line.status else { Issue.record("expected blocked, got \(line.status)"); return }
        #expect(line.status.text.hasPrefix("NOT EVALUATED"))
        #expect(!line.status.isPass)
        #expect(line.dependsOnPositiveSet == true)
        #expect(line.gate?.key == "agreement.placementDiffPairsMax")
    }

    @Test("placement-FP line: NOT EVALUATED below the minimum pairs on an evaluable set")
    func fpTooFew() throws {
        let line = PlacementFalsePositives.line(try Self.pairs(20, diffs: 0), positiveSet: .evaluable)
        guard case .notEvaluated = line.status else { Issue.record("expected NOT EVALUATED, got \(line.status)"); return }
        #expect(line.status.text.hasPrefix("NOT EVALUATED"))
        #expect(!line.status.isPass)
    }

    @Test("placement-FP line: measured PASS at or under 2%, FAIL above")
    func fpMeasured() throws {
        #expect(PlacementFalsePositives.line(try Self.pairs(200, diffs: 4), positiveSet: .evaluable).status == .pass)
        #expect(PlacementFalsePositives.line(try Self.pairs(200, diffs: 5), positiveSet: .evaluable).status == .fail)
    }

    @Test("a voice is kept only when every bar passes; a NOT EVALUATED FP line drops it")
    func kept() throws {
        let good = Self.observations(movedHits: 19, of: 20, correctHits: 20, of: 20)
        let ssml = SSMLCheck(words: 20, identical: [])
        let pass = PlacementFalsePositives.line(try Self.pairs(200, diffs: 0), positiveSet: .evaluable)
        let notEvaluated = PlacementFalsePositives.line(try Self.pairs(20, diffs: 0), positiveSet: .evaluable)
        #expect(VoiceVerification(voice: Self.voice, observations: good, ssml: ssml, placementFP: pass).kept)
        #expect(!VoiceVerification(voice: Self.voice, observations: good, ssml: ssml, placementFP: notEvaluated).kept)
        let fewMoved = Self.observations(movedHits: 17, of: 20, correctHits: 20, of: 20)
        #expect(!VoiceVerification(voice: Self.voice, observations: fewMoved, ssml: ssml, placementFP: pass).kept)
        let fewCorrect = Self.observations(movedHits: 20, of: 20, correctHits: 18, of: 20)
        #expect(!VoiceVerification(voice: Self.voice, observations: fewCorrect, ssml: ssml, placementFP: pass).kept)
        #expect(!VoiceVerification(
            voice: Self.voice, observations: good, ssml: SSMLCheck(words: 20, identical: ["rainbow"]), placementFP: pass).kept)
    }

    @Test("the SSML check fails when a moved rendering is identical to the correct one")
    func ssmlCheck() {
        let a = SynthesizedAudio(samples: [0, 0.1, 0.2], words: [])
        let b = SynthesizedAudio(samples: [0, 0.3, 0.2], words: [])
        #expect(SSMLCheck.check(["x": (a, b)]).honoured)
        let ignored = SSMLCheck.check(["x": (a, b), "y": (a, a)])
        #expect(!ignored.honoured && ignored.identical == ["y"])
        #expect(!SSMLCheck.check([:]).honoured)
    }

    @Test("ElevenLabs before the Mac fallback among kept voices; none kept, no reference")
    func reference() throws {
        let good = Self.observations(movedHits: 20, of: 20, correctHits: 20, of: 20)
        let ssml = SSMLCheck(words: 20, identical: [])
        let pass = PlacementFalsePositives.line(try Self.pairs(200, diffs: 0), positiveSet: .evaluable)
        let mac = VoiceVerification(
            voice: EngineIdentity(kind: .macPremium, voiceID: "m", modelID: "x"), observations: good, ssml: ssml,
            placementFP: pass)
        let eleven = VoiceVerification(voice: Self.voice, observations: good, ssml: ssml, placementFP: pass)
        #expect(VoiceSelection.reference([mac, eleven])?.voice == Self.voice)
        let dropped = VoiceVerification(
            voice: Self.voice, observations: good, ssml: ssml,
            placementFP: PlacementFalsePositives.line([], positiveSet: .evaluable))
        #expect(VoiceSelection.reference([dropped]) == nil)
    }
}

@Suite("Voice selection uses tuning speakers only") struct SelectionTests {
    @Test("a held-out VCTK speaker passed in is refused")
    func heldOutRefused() throws {
        let manifest = try manifest()
        let heldOut = try #require(manifest.heldOutSpeakers.first?.id)
        #expect(throws: VoiceSelection.Refusal.notATuningSpeaker(heldOut)) {
            _ = try VoiceSelection.tuningSpeakers([manifest.tuningSpeakers[0].id, heldOut], manifest: manifest)
        }
    }

    @Test("bundled voices and speechocean762 speakers are refused; tuning speakers resolve")
    func othersRefused() throws {
        let manifest = try manifest()
        #expect(throws: VoiceSelection.Refusal.notATuningSpeaker("p225")) {
            _ = try VoiceSelection.tuningSpeakers(["p225"], manifest: manifest)
        }
        #expect(throws: VoiceSelection.Refusal.self) {
            _ = try VoiceSelection.tuningSpeakers(["0001"], manifest: manifest)
        }
        let ids = manifest.tuningSpeakers.map(\.id)
        #expect(try VoiceSelection.tuningSpeakers(ids, manifest: manifest).map(\.id) == ids)
        #expect(manifest.tuningCount >= VCTKEvalSpeakersManifest.minimumTuningSpeakers, "a floor, read from the manifest")
    }
}

/// A scorer that records the thresholds it was called with and flags every word.
final class RecordingScorer: EndToEndUtteranceScorer, Sendable {
    let seen = Mutex<[Thresholds]>([])

    func flags(utterance: String, words: [SpeechOceanWord], thresholds: Thresholds) async throws -> [String: Bool] {
        seen.withLock { $0.append(thresholds) }
        return Dictionary(uniqueKeysWithValues: words.map { ($0.id, true) })
    }
}

struct FlagNothingPath: EvaluationPath {
    var name: String { "stub-shared" }
    func run(config: FoldConfig, words: [SpeechOceanWord]) async throws -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: words.map { ($0.id, false) })
    }
}

@Suite("End-to-end check (ii) path") struct EndToEndTests {
    @Test("in every fold it runs with the same fold-trained config as the other path, one digest per fold")
    func foldRunner() async throws {
        let labels = try SpeechOceanLabels.parseFixture(
            String(contentsOf: Repo.url("fixtures/speechocean762/labels.tsv"), encoding: .utf8))
        let folds = SpeechOceanFolds(sets: SpeechOceanSets(labels: labels), seed: 7)
        let scorer = RecordingScorer()
        let trained = Mutex<[Thresholds]>([])
        let runner = FoldRunner(folds: folds, vctkTuningSpeakers: try manifest().tuningSpeakers)
        let record = try await runner.run(
            train: { pool in
                var t = Thresholds.current
                t.agreement.bootstrapResamples = Double(1000 + pool.fold)
                trained.withLock { $0.append(t) }
                return try FoldConfig(
                    identity: ConfigIdentity(asrModelID: "replayed", pitchTrackerID: "p", voicingID: "v"), thresholds: t)
            },
            paths: [FlagNothingPath(), EndToEndPath(scorer: scorer)])
        #expect(record.folds.count == folds.folds.count)
        let used = Set(scorer.seen.withLock { $0 })
        #expect(used == Set(trained.withLock { $0 }), "the end-to-end path ran under each fold's trained config")
        #expect(record.pooled["end-to-end (ii)"]?.hits == folds.sets.recall.count)
        for fold in record.folds { #expect(fold.results["end-to-end (ii)"] != nil && fold.results["stub-shared"] != nil) }
    }

    @Test("its FP line on the clean words is reported, never a pass")
    func falsePositives() {
        let words = (0..<10).map {
            SpeechOceanWord(utterance: "u\($0)", index: 0, speaker: "s", text: "word", refPhones: "W ER1 D",
                            stressWrongVotes: 0, allPhonesZeroVotes: 0)
        }
        let line = EndToEndReport.falsePositiveLine(flags: [words[0].id: true], clean: words)
        #expect(line.value == 0.1 && line.status == .reported && !line.status.isPass)
        #expect(EndToEndReport.falsePositiveLine(flags: [:], clean: []).status.text.hasPrefix("NOT EVALUATED"))
    }
}

@Suite("Synthetic negative set") struct NegativeSetTests {
    static let rate = 16_000.0

    static func tone(_ hz: Double, seconds: Double = 1) -> [Float] {
        (0..<Int(rate * seconds)).map { i in
            let t = Double(i) / rate
            return Float(0.3 * sin(2 * .pi * hz * t) + 0.15 * sin(4 * .pi * hz * t))
        }
    }

    @Test("TD-PSOLA at factor 1 and 0 dB reproduces the input (null processing)")
    func nullProcessing() {
        let input = Self.tone(120)
        let output = TDPSOLA.modify(input, sampleRate: Self.rate, region: 4000..<12000, pitchFactor: 1, durationFactor: 1, gainDB: 0)
        #expect(output.count == input.count)
        let error = zip(input, output).map { Double(abs($0 - $1)) }.max() ?? 1
        #expect(error < 0.02, "max deviation \(error)")
    }

    @Test("TD-PSOLA shifts F0 by the requested semitones and stretches only the region")
    func pitchAndDuration() throws {
        let input = Self.tone(120)
        let region = 4000..<12000
        let up = TDPSOLA.modify(input, sampleRate: Self.rate, region: region, pitchFactor: pow(2, 4 / 12), durationFactor: 1, gainDB: 0)
        let f0 = try #require(TDPSOLA.medianF0(up, region: 5000..<11000, sampleRate: Self.rate))
        #expect(abs(12 * log2(f0 / 120) - 4) < 0.5, "measured \(f0) Hz")
        let before = try #require(TDPSOLA.medianF0(up, region: 0..<3500, sampleRate: Self.rate))
        #expect(abs(before - 120) < 3, "outside the region F0 is untouched")
        let long = TDPSOLA.modify(input, sampleRate: Self.rate, region: region, pitchFactor: 1, durationFactor: 1.5, gainDB: 0)
        #expect(long.count == input.count + 4000)
    }

    @Test("magnitudes are native P50, P90 and 1.5 × P90")
    func magnitudes() throws {
        let natives = (1...10).map { StressMagnitude(semitones: Double($0), durationRatio: 1 + Double($0) / 10, gainDB: Double($0)) }
        let m = try #require(NativeContrast.magnitudes(natives))
        let p90 = try #require(m[.p90]), high = try #require(m[.p90x15])
        #expect(abs(high.semitones - 1.5 * p90.semitones) < 1e-9)
        #expect(abs((high.durationRatio - 1) - 1.5 * (p90.durationRatio - 1)) < 1e-9)
        #expect(try #require(m[.p50]).semitones < p90.semitones)
        #expect(NativeContrast.magnitudes([]) == nil)
    }

    @Test("which-syllable accuracy, controls, and DSP agreement (NOT EVALUATED without the second DSP)")
    func metrics() throws {
        let speaker = try manifest().tuningSpeakers[0]
        func word(_ kind: EditedWord.Kind, _ dsp: DSP, hit: Bool, diff: Bool = false) -> EditedWord {
            EditedWord(speaker: speaker, phrase: "002", word: 0, kind: kind, dsp: dsp, targetSyllable: 1,
                       observedPrimary: hit ? 1 : 0, anyDiff: diff, achievedSemitones: nil)
        }
        let psola = (0..<10).map { word(.edit(.p90), .tdpsola, hit: $0 < 9) } + [word(.nullControl, .tdpsola, hit: false)]
        #expect(NegativeSetMetrics.whichSyllable(psola, dsp: .tdpsola).value == 0.9)
        #expect(NegativeSetMetrics.whichSyllable(psola, dsp: .tdpsola).status == .pass)
        #expect(NegativeSetMetrics.controls(psola, dsp: .tdpsola).status == .pass)
        let agreement = NegativeSetMetrics.dspAgreement(psola)
        #expect(agreement.status.text.hasPrefix("NOT EVALUATED"))
        let both = psola + (0..<10).map { word(.edit(.p90), .rubberband, hit: $0 < 8) }
        #expect(NegativeSetMetrics.dspAgreement(both).status == .fail, "0.9 vs 0.8 is 10 points apart")
        let close = psola + (0..<10).map { word(.edit(.p90), .rubberband, hit: $0 < 9) }
        #expect(NegativeSetMetrics.dspAgreement(close).status == .pass)
        let noisy = [word(.nullControl, .tdpsola, hit: false, diff: true), word(.correctBoost, .tdpsola, hit: false)]
        #expect(NegativeSetMetrics.controls(noisy, dsp: .tdpsola).status == .fail)
    }

    @Test("Rubber Band is found only on PATH, and is invoked as a CLI with time and pitch")
    func rubberBand() {
        #expect(RubberBandCLI.locate(path: "") == nil)
        #expect(RubberBandCLI.locate(path: "/nonexistent") == nil)
        let args = RubberBandCLI.arguments(
            input: URL(fileURLWithPath: "/tmp/in.wav"), output: URL(fileURLWithPath: "/tmp/out.wav"), semitones: 2,
            timeRatio: 1.25)
        #expect(args == ["--quiet", "-t", "1.2500", "-p", "2.0000", "/tmp/in.wav", "/tmp/out.wav"])
    }
}
