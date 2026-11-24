// Voice verification (plan §6.4), per voice and model. A voice is kept only if all of these hold:
//   - ≥ `agreement.voiceMovedStressMin` of moved items have their observed primary on the marked syllable at medium
//     confidence or better;
//   - ≥ `agreement.voiceCorrectStressMin` of correct items have the expected primary;
//   - as the reference for the VCTK tuning speakers only, the positive-set placement-FP line (spec 02's
//     `PositiveSetGates.line`, `agreement.placementDiffPairsMax`) reads PASS. NOT EVALUATED is never a pass;
//   - the SSML check: every moved rendering differs from its correct one (the phoneme tags were honoured).
// Initial, untuned thresholds. A FAIL goes to CTO with the numbers.

import AMAlignment
import AMCore
import AMEvaluation
import AMPipeline
import Foundation

/// What the detector observed on one single-word rendering.
public struct ItemObservation: Sendable, Hashable, Codable {
    public let item: VerificationItem
    /// nil when the rendering failed or the word got no observed stress.
    public let observedPrimary: Int?
    public let confidence: Confidence?

    public init(item: VerificationItem, observedPrimary: Int?, confidence: Confidence?) {
        self.item = item
        self.observedPrimary = observedPrimary
        self.confidence = confidence
    }

    /// Moved: the marked syllable at ≥ medium confidence. Correct: the expected primary. Unobserved is a miss.
    public var meetsBar: Bool {
        guard let observedPrimary, observedPrimary == item.markedSyllable else { return false }
        switch item.variant {
        case .moved: return (confidence ?? .low) >= .medium
        case .correct: return true
        }
    }

    /// Runs the shipped stages on a single-word rendering of `item`.
    public static func observe(
        _ item: VerificationItem, audio: SynthesizedAudio, l0Key: String, thresholds: Thresholds = .current
    ) async throws -> ItemObservation {
        let word = PlacementTake.Word(
            index: WordIndex(0), text: item.word, pronunciation: try item.pronunciation(),
            accepted: [item.markedSyllable])
        let analysis = try await SyntheticScoring.analyse(
            samples: audio.samples, words: [word], heard: SyntheticScoring.heard(audio, words: [word]), l0Key: l0Key,
            thresholds: thresholds)
        let observed = analysis.words.first?.observed
        return ItemObservation(item: item, observedPrimary: observed?.primary, confidence: observed?.confidence)
    }
}

/// The TTS SSML check: moved-stress renderings differ from correct ones, word by word.
public struct SSMLCheck: Sendable, Hashable, Codable {
    public let words: Int
    /// Words whose moved rendering is sample-identical to the correct one (the tag was ignored).
    public let identical: [String]

    public init(words: Int, identical: [String]) {
        self.words = words
        self.identical = identical.sorted()
    }

    /// Honoured when there was something to check and no pair was identical.
    public var honoured: Bool { words > 0 && identical.isEmpty }

    /// Compares each word's correct and moved renderings.
    public static func check(_ renderings: [String: (correct: SynthesizedAudio, moved: SynthesizedAudio)]) -> SSMLCheck {
        let identical = renderings.filter { _, pair in
            pair.correct.samples.count == pair.moved.samples.count
                && zip(pair.correct.samples, pair.moved.samples).allSatisfy { abs($0 - $1) <= 1e-4 }
        }.map(\.key)
        return SSMLCheck(words: renderings.count, identical: identical)
    }

    public var line: String {
        honoured
            ? "SSML check: PASS (\(words) of \(words) moved renderings differ from the correct one)"
            : words == 0 ? "SSML check: NOT EVALUATED (no rendering pairs)"
            : "SSML check: FAIL (\(identical.count) of \(words) moved renderings identical: \(identical.prefix(8).joined(separator: ", ")))"
    }
}

/// One tuning speaker's take of a phrase against the voice's reference: a placement diff or not.
public struct TuningPairOutcome: Sendable, Hashable {
    /// A `TuningSpeaker`, so a held-out VCTK speaker or a speechocean762 word cannot be scored here.
    public let speaker: TuningSpeaker
    public let phrase: String
    public let placementDiff: Bool

    public init(speaker: TuningSpeaker, phrase: String, placementDiff: Bool) {
        self.speaker = speaker
        self.phrase = phrase
        self.placementDiff = placementDiff
    }
}

public enum PlacementFalsePositives {
    /// Spec 02's positive-set dependent for spec 22 (`agreement.placementDiffPairsMax`).
    public static func dependent(thresholds: Thresholds = .current) -> PositiveSetGates.Dependent {
        PositiveSetGates.dependents(thresholds: thresholds).first { $0.spec == "spec 22" }!
    }

    /// The placement-FP line for one voice, only through `PositiveSetGates.line`: blocked while the positive set is
    /// NOT EVALUATED, NOT EVALUATED below `agreement.positiveMinPairs` scored pairs, else PASS or FAIL.
    public static func line(
        _ pairs: [TuningPairOutcome], positiveSet: PositiveSetStatus, seed: UInt64 = 0,
        thresholds: Thresholds = .current
    ) -> MetricResult {
        let dependent = dependent(thresholds: thresholds)
        let units = pairs.map {
            ScoredUnit(speaker: $0.speaker.id, phrase: $0.phrase, phraseCluster: VCTK.sourcePrompt(of: $0.phrase),
                       hit: $0.placementDiff)
        }
        let measured = MetricResult.rate(
            name: dependent.name, layer: .shippedConfigCheck, units: units, gate: dependent.gate,
            minimumN: Int(thresholds.agreement.positiveMinPairs),
            bootstrap: (.speakersAndPhrases, Int(thresholds.agreement.bootstrapResamples), seed),
            reportWorstPhrase: true)
        return PositiveSetGates.line(dependent, positiveSet: positiveSet, measured: measured, pairs: pairs.count)
    }
}

/// One voice's verification result.
public struct VoiceVerification: Sendable {
    public let voice: EngineIdentity
    public let observations: [ItemObservation]
    public let moved: MetricResult
    public let correct: MetricResult
    public let ssml: SSMLCheck
    /// From `PlacementFalsePositives.line` only.
    public let placementFP: MetricResult

    public init(
        voice: EngineIdentity, observations: [ItemObservation], ssml: SSMLCheck, placementFP: MetricResult,
        thresholds: Thresholds = .current
    ) {
        self.voice = voice
        self.observations = observations
        self.ssml = ssml
        self.placementFP = placementFP
        func rate(_ variant: StressVariant, _ name: String, _ key: String,
                  _ path: KeyPath<Thresholds.Agreement, Double>) -> MetricResult {
            let units = observations.filter { $0.item.variant == variant }.map {
                ScoredUnit(speaker: voice.label, phrase: $0.item.word, hit: $0.meetsBar)
            }
            return MetricResult.rate(
                name: name, layer: .descriptive, units: units,
                gate: .agreement(key, path, .atLeast, thresholds: thresholds), minimumN: 1)
        }
        moved = rate(.moved, "Moved items on the marked syllable (≥ medium)", "agreement.voiceMovedStressMin",
                     \.voiceMovedStressMin)
        correct = rate(.correct, "Correct items with the expected primary", "agreement.voiceCorrectStressMin",
                       \.voiceCorrectStressMin)
    }

    /// Kept only when every bar reads PASS. NOT EVALUATED, blocked or FAIL on any of them drops the voice.
    public var kept: Bool { moved.status.isPass && correct.status.isPass && placementFP.status.isPass && ssml.honoured }

    /// Trap items, reported for sensitivity (not a separate bar).
    public var trapLine: String {
        let traps = observations.filter(\.item.isTrap)
        let hits = traps.filter(\.meetsBar).count
        return "stress traps: \(hits) of \(traps.count) items as rendered (reported, not gated)"
    }
}

/// Which verified voice serves as the reference. Inputs are verifications made from the verification items and
/// `TuningSpeaker`s only, so held-out speakers and speechocean762 never pick a voice.
public enum VoiceSelection {
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case notATuningSpeaker(String)

        public var description: String {
            switch self {
            case .notATuningSpeaker(let id):
                "\(id) is not a VCTK tuning speaker: voice selection uses tuning speakers only"
            }
        }
    }

    /// Speaker ids → tuning speakers through spec 02's manifest. A held-out VCTK speaker, a bundled voice, a
    /// speechocean762 speaker or anything else is refused.
    public static func tuningSpeakers(_ ids: [String], manifest: VCTKEvalSpeakersManifest) throws -> [TuningSpeaker] {
        let tuning = Dictionary(manifest.tuningSpeakers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return try ids.map { id in
            guard let speaker = tuning[id] else { throw Refusal.notATuningSpeaker(id) }
            return speaker
        }
    }

    /// The reference: among kept voices, ElevenLabs before the Mac fallback, then the lowest placement-FP rate, then
    /// the higher moved-item rate, then the voice id. nil when no voice passed: check (ii) is then NOT EVALUATED.
    public static func reference(_ verifications: [VoiceVerification]) -> VoiceVerification? {
        verifications.filter(\.kept).min { a, b in
            let ka = a.voice.kind == .elevenlabs ? 0 : 1, kb = b.voice.kind == .elevenlabs ? 0 : 1
            if ka != kb { return ka < kb }
            let fa = a.placementFP.value ?? 1, fb = b.placementFP.value ?? 1
            if fa != fb { return fa < fb }
            let ma = a.moved.value ?? 0, mb = b.moved.value ?? 0
            if ma != mb { return ma > mb }
            return a.voice.voiceID < b.voice.voiceID
        }
    }
}
