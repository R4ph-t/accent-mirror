// The real comparison path for synthetic references: spec 08's `StressPlacementDetector` on both takes, the
// synthetic voice's high-confidence observed primaries added to A(w) as a native reader, then spec 10's
// `PairScoring.score` (warp, comparable set, measures, verdict). Nothing here is tuned or new: it only wires
// AccentKit's stages to a rendering.

import AMAlignment
import AMCore
import AMPipeline
import AMProsody
import AMScoring
import Foundation

public enum SyntheticScoring {
    /// The phrase's words for the detector: CMUdict's context-selected pronunciation (spec 06) and A(w) = its
    /// primary for a non-ambiguous polysyllable. `overrides` (word index → ARPAbet) wins, as a phrase file's does.
    public static func words(
        text: String, selector: PronunciationSelector, overrides: [Int: String] = [:]
    ) throws -> [PlacementTake.Word] {
        let expected = selector.expectedPhrase(for: PhraseText(text: text, origin: .imported(persisted: [:])))
        return try expected.words.map { word in
            let pronunciation = try overrides[word.index.rawValue].map { try Pronunciation(arpabet: $0) }
                ?? word.pronunciation
                ?? Pronunciation(arpabet: Array(repeating: "AH0", count: word.syllableCount).joined(separator: " "))
            let pattern = pronunciation.stressPattern
            let decided = pattern.count >= 2 && !word.expectedAmbiguous
            return PlacementTake.Word(
                index: word.index, text: word.text, pronunciation: pronunciation,
                accepted: decided ? pattern.firstIndex(of: .primary).map { [$0] } : nil)
        }
    }

    /// A rendering's word spans as replayed word timings (probability 1: they come from the engine, not ASR).
    public static func heard(_ audio: SynthesizedAudio, words: [PlacementTake.Word]) -> [WordTimestamp] {
        zip(words, audio.words).map { WordTimestamp(word: $0.text, start: $1.start, end: $1.end, probability: 1) }
    }

    public static func analyse(
        samples: [Float], words: [PlacementTake.Word], heard: [WordTimestamp], l0Key: String, thresholds: Thresholds
    ) async throws -> PlacementAnalysis {
        try await StressPlacementDetector.bundled(thresholds: thresholds).analyse(
            PlacementTake(samples: samples, sampleRate: 16_000, words: words, heard: heard, l0Key: l0Key))
    }

    /// The reference's observed stress per word, as native readings by `voice` (only high confidence counts in A(w)).
    public static func nativeReadings(_ reference: PlacementAnalysis, voice: String) -> [WordIndex: [NativeReading]] {
        var out: [WordIndex: [NativeReading]] = [:]
        for result in reference.words {
            if let observed = result.observed { out[result.word] = [NativeReading(voice: voice, observed: observed)] }
        }
        return out
    }

    /// `you` against the synthetic reference through spec 10's scoring, with A(w) including the voice's observed
    /// primary.
    public static func score(
        words: [PlacementTake.Word], you: PlacementAnalysis, reference: PlacementAnalysis, voice: String,
        thresholds: Thresholds
    ) throws -> Scoring {
        try PairScoring.score(
            words: words, you: you, model: reference, modelVoice: voice,
            natives: nativeReadings(reference, voice: voice), thresholds: thresholds)
    }

    /// Word indices with a placement row in the verdict.
    public static func placementWords(_ scoring: Scoring) -> Set<WordIndex> {
        guard case .verdict(.feedback(let rows, _)) = scoring.decision else { return [] }
        return Set(rows.filter { $0.kind == .placement }.compactMap(\.word))
    }
}
