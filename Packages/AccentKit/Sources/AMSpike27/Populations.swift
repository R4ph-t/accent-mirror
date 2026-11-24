// Spec 27 Guardrails: which data may train, choose τ, the variant, the arm and the envelopes (tuning side only), and
// which is evaluation only (held-out VCTK, the 134, the clean 1,400, speechocean762). Plus lit amendment 4's
// speechocean762 label rule and overlap drop.

import AMEvaluation
import Foundation

public enum Population: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case tuningVCTK = "vctk-tuning"
    case tts = "tts"
    case bundled = "bundled"
    case heldOutVCTK = "vctk-held-out"
    case l2Recall = "l2-134"
    case l2Clean = "l2-clean-1400"
    case speechocean762 = "speechocean762"

    /// Training, CV, τ, the variant and the arm read only these.
    public var isTuningSide: Bool { self == .tuningVCTK || self == .tts }
    /// The native envelope's natural speakers: the bundled voices and the VCTK tuning speakers.
    public var isEnvelopeSide: Bool { self == .tuningVCTK || self == .bundled }
    public var isEvaluationOnly: Bool { !isTuningSide && self != .bundled }

    public static func < (a: Population, b: Population) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

public enum Spike27Guard {
    public struct Refused: Error, Equatable, CustomStringConvertible {
        public let population: Population
        public let use: String
        public var description: String { "spike27: \(use) refuses \(population.rawValue) data (evaluation only)" }
    }

    /// Training, τ and the variant/arm choice: tuning side only, and every VCTK speaker a tuning speaker.
    public static func checkTraining(_ items: [(population: Population, speaker: String)], split: VCTKSplitManifest,
                                     use: String) throws {
        let tuning = Set(split.tuning)
        for item in items {
            guard item.population.isTuningSide else { throw Refused(population: item.population, use: use) }
            if item.population == .tuningVCTK && !tuning.contains(item.speaker) {
                throw Refused(population: .heldOutVCTK, use: use)
            }
        }
    }

    /// The envelope and its quantile choice: natural tuning-side speakers only (bundled voices, VCTK tuning).
    public static func checkEnvelope(_ items: [(population: Population, speaker: String)], split: VCTKSplitManifest)
        throws
    {
        let tuning = Set(split.tuning)
        for item in items {
            guard item.population.isEnvelopeSide else { throw Refused(population: item.population, use: "envelope") }
            if item.population == .tuningVCTK && !tuning.contains(item.speaker) {
                throw Refused(population: .heldOutVCTK, use: "envelope")
            }
        }
    }

    /// The speaker-grouped CV fold of a tuning-side speaker: the split manifest's folds; the TTS voice and the
    /// bundled voices (envelope only) by sorted position modulo the fold count. Nil outside the tuning side.
    public static func fold(of speaker: String, population: Population, split: VCTKSplitManifest,
                            bundledVoices: [String]) -> Int? {
        switch population {
        case .tuningVCTK: return split.cvFolds.firstIndex { $0.contains(speaker) }
        case .bundled: return bundledVoices.sorted().firstIndex(of: speaker).map { $0 % split.cvFolds.count }
        case .tts: return nil
        default: return nil
        }
    }
}

/// Lit amendment 4, fixed before any run (`docs/agreement/spike27/speechocean762.json`).
public enum SpeechOcean762Rule {
    public enum Label: String, Sendable, Hashable, Codable { case misplaced, correct }
    public enum Exclusion: String, Sendable, Hashable, Codable, CaseIterable {
        case fewerThanTwoSyllables = "fewer than 2 syllables (CMUdict)"
        case unintelligible = "word accuracy < 5"
        case otherStressScore = "stress score not 5 or 10"
        case overlapsThe134 = "utterance holds one of the 134"
    }

    /// The label of one released word, or why it's excluded.
    public static func label(stress: Double, accuracy: Double, syllables: Int, utterance: String,
                             dropped: Set<String>) -> Result<Label, ExclusionError> {
        if dropped.contains(utterance) { return .failure(ExclusionError(.overlapsThe134)) }
        if syllables < 2 { return .failure(ExclusionError(.fewerThanTwoSyllables)) }
        if accuracy < 5 { return .failure(ExclusionError(.unintelligible)) }
        if stress == 5 { return .success(.misplaced) }
        if stress == 10 { return .success(.correct) }
        return .failure(ExclusionError(.otherStressScore))
    }

    public struct ExclusionError: Error, Sendable, Hashable {
        public let reason: Exclusion
        public init(_ reason: Exclusion) { self.reason = reason }
    }

    /// The utterances holding any of the 134 (spec 02 §6.3's recall set), by utterance id.
    public static func overlap(recall: [SpeechOceanWord]) -> Set<String> { Set(recall.map(\.utterance)) }
}
