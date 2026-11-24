// The pipeline's side of the take store (spec 16): the recompute closure `TakeStore` calls when a stored comparison is
// missing or keyed for another identity, and the ghosts' pitch read out of their stored comparisons. `AMLibrary` keeps
// only opaque records; the keys and the decoding live here.

import AMCore
import AMLibrary
import Foundation

extension TakeRecomputer {
    /// Recomputes a stored take with `analyzer` against `reference`. `phrase` gives the phrase as the pipeline reads
    /// it now (its transcript revision and pronunciations); an unknown phrase reads as stale and can't be recomputed.
    public static func pipeline(
        analyzer: Analyzer, reference: any ReferenceSet, phrase: @escaping @Sendable (PhraseID) -> PhraseInput?
    ) -> TakeRecomputer {
        TakeRecomputer(
            expectedKeys: { id, audioSHA256, voice in
                guard let input = phrase(id) else { return nil }
                let l1 = analyzer.l1Key(l0: analyzer.l0Key(takeAudioSHA256: audioSHA256), phrase: input)
                let l2 = analyzer.l2Key(l1: l1, reference: reference.identity(phrase: id, voice: voice))
                return Keys(features: l1.text, comparison: l2.text)
            },
            recompute: { stored, voice in
                guard let input = phrase(stored.ref.phrase) else { throw TakeStoreError.recomputeFailed(stored.ref) }
                let take = TakeAudio(samples: stored.samples, sha256: stored.audioSHA256, recordedAt: stored.recordedAt)
                let run = await analyzer.run(take: take, phrase: input, reference: reference, voice: voice)
                guard !run.derived.isEmpty else { throw TakeStoreError.recomputeFailed(stored.ref) }
                return run.derived
            })
    }
}

/// An earlier take's pitch on the model timeline of the current voice, for the ghosts (spec 21 draws them).
public struct GhostPitch: Sendable, Hashable {
    public let take: StoredTake
    public let pitchOnModel: [PitchSegment]

    /// The ghost's pitch, or nil when its comparison isn't an analysed result (it has no pitch on the model).
    public init?(_ ghost: Ghost) {
        guard let l2 = try? JSONDecoder().decode(L2Analysis.self, from: ghost.comparison.bytes),
            l2.key.text == ghost.comparison.key, case .analysed(let result) = l2.outcome
        else { return nil }
        take = ghost.take
        pitchOnModel = result.youPitchOnModel
    }
}
