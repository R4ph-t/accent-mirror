// What scoring reads (spec 10): the phrase's words with their accepted sets, both takes' L1 data on their own
// timelines, the word alignment and the time map. Nothing here is computed from audio; the pipeline (spec 12) or a
// replayed fixture fills it in.

import AMCore
import AMPlacement
import AMProsody
import AMWarp
import Foundation

/// One phrase word as scoring sees it.
public struct ScoringWord: Sendable, Hashable {
    public let index: WordIndex
    public let syllableCount: Int
    public let isTarget: Bool
    public let isContent: Bool
    /// The context-compatible pattern (spec 06), one entry per syllable; nil when the word is `expectedAmbiguous`.
    public let expectedPattern: [SyllableStress]?
    /// A(w) and the S set of each accepted pattern (spec 08); nil for an `expectedAmbiguous` word or one with no
    /// pronunciation: no placement decision, and outside S and U.
    public let accepted: WordAcceptedSet?

    public init(
        index: WordIndex, syllableCount: Int, isTarget: Bool, isContent: Bool, expectedPattern: [SyllableStress]?,
        accepted: WordAcceptedSet?
    ) {
        self.index = index
        self.syllableCount = syllableCount
        self.isTarget = isTarget
        self.isContent = isContent
        self.expectedPattern = expectedPattern
        self.accepted = accepted
    }

    /// Applicability's view of the word.
    var facts: PhraseWordFacts {
        PhraseWordFacts(
            syllableCount: syllableCount, isTarget: isTarget, isContentWord: isContent,
            isExpectedAmbiguous: accepted == nil)
    }
}

/// One take's L1 data on its own timeline.
public struct ScoringTake: Sendable, Hashable {
    /// The syllables of the take's present words, in time order (spec 07 levels, spec 08 features). For the model,
    /// every phrase word. `DiffRow.syllables` index into the model's list.
    public let syllables: [ComparableSyllable]
    /// 10 ms frames in semitones re the speaker's median (spec 04), one segment per stretch between long pauses.
    public let pitch: [PitchSegment]
    /// The edges of each present word, by phrase word: the take's comparable material.
    public let words: [WordIndex: TimeRange]

    public init(syllables: [ComparableSyllable], pitch: [PitchSegment], words: [WordIndex: TimeRange]) {
        self.syllables = syllables
        self.pitch = pitch
        self.words = words
    }

    /// Voiced frames anywhere in the take.
    var voicedFrameCount: Int { pitch.reduce(0) { $0 + $1.frames.count(where: \.voiced) } }
}

/// Everything one analysis is scored from.
public struct ScoringInput: Sendable {
    public let words: [ScoringWord]
    /// The selected native voice: named in a placement row ("like p311") and checked for `referenceAnomaly`.
    public let modelVoice: String
    public let model: ScoringTake
    public let you: ScoringTake
    public let alignment: WordAlignment
    /// Match share, insertions and incomplete words (spec 06).
    public let alignmentSummary: AlignmentSummary
    /// Your take on the model's timeline (spec 09): timing, comparable coverage, comparable model time.
    public let warp: TimeWarp
    public let takeProblems: [TakeProblem]
    public let hopSeconds: Double

    public init(
        words: [ScoringWord], modelVoice: String, model: ScoringTake, you: ScoringTake, alignment: WordAlignment,
        alignmentSummary: AlignmentSummary, warp: TimeWarp, takeProblems: [TakeProblem] = [],
        hopSeconds: Double = Thresholds.current.pitch.hopMs / 1000
    ) {
        self.words = words
        self.modelVoice = modelVoice
        self.model = model
        self.you = you
        self.alignment = alignment
        self.alignmentSummary = alignmentSummary
        self.warp = warp
        self.takeProblems = takeProblems
        self.hopSeconds = hopSeconds
    }

    /// Phrase words `present` in your take.
    var presentWords: Set<WordIndex> {
        Set(alignment.pairs.compactMap { if case .present(let w, _) = $0 { w } else { nil } })
    }

    /// How a phrase word fared in the alignment.
    func status(of word: WordIndex) -> WordStatus {
        for pair in alignment.pairs where pair.phraseWord == word {
            switch pair {
            case .present: return .present
            case .substituted: return .substituted
            case .missing, .inserted: return .missing
            }
        }
        return .missing
    }

    enum WordStatus { case present, substituted, missing }
}
