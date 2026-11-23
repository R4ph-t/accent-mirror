import Foundation

// Fixture schema for the UI shell (spec 19). Field names follow the plan v2 contract (verdict kinds `feedback`,
// `close`, `noClearDifference`, `inconclusive`; take problems; operational errors; `MeasureState`;
// `AlignedWordPair`; `PersistenceStatus`). AMCore does not define these types yet (spec 01); when it does, the
// fixtures and this decoding layer follow it instead of growing a parallel model. See `Fixtures/SCHEMA.md`.
// UI-free on purpose: no SwiftUI here.

/// One named UI state: `Fixtures/states/<name>.json`.
struct UIFixture: Decodable, Sendable {
    var name: String
    var summary: String
    /// `Fixtures/phrases/<phrase>.json`.
    var phrase: String
    /// Replaces the static manifest stub when a state needs a phrase the stub doesn't list.
    var manifest: LibraryManifest?
    var sidebar: SidebarState?
    var phase: Phase
    var recording: Recording?
    /// `Fixtures/takes/<take>.json`: the take on screen (saved, or the unsaved last try).
    var take: String?
    /// Saved take numbers, newest first.
    var savedTakes: [Int]
    var analysis: Analysis?
    var operationalError: OperationalError?
    var persistence: PersistenceStatus?
    /// Coordinator outcome that leaves no trace in the UI (`cancelled`).
    var outcome: String?
    var inspectorOpen: Bool?
    /// The window size the screenshot runner renders this state at, in points. Nil: the default 1200 × 800.
    var window: WindowSize?

    struct WindowSize: Decodable, Sendable, Equatable {
        var width: Double
        var height: Double
    }

    enum Phase: String, Decodable, Sendable {
        /// The phrase has no take on screen.
        case empty
        case recording
        case analysing
        /// A take (saved or the unsaved last try) is on screen with its analysis.
        case showingTake
    }

    struct Recording: Decodable, Sendable {
        var elapsed: String
        /// Playhead position on your timeline, 0…1.
        var playhead: Double
    }
}

// MARK: - Phrase (the native side)

struct PhraseFixture: Decodable, Sendable {
    var id: String
    var text: String
    /// "{pack} · Native speaker {voice}, VCTK" or "My Phrases · From {file name}".
    var subtitle: String
    /// Pitch axis half-range in semitones re your median (6, 12, 18 or 24).
    var rangeSemitones: Double
    var words: [NativeWord]
    /// The native band (P10 to P90), in model time, one segment per stretch between pauses over 250 ms.
    var band: [BandSegment]
}

struct NativeWord: Decodable, Sendable {
    var text: String
    var stressCheck: StressCheck?
    var start: Double
    var end: Double
    var syllables: [Syllable]
}

struct BandSegment: Decodable, Sendable {
    var points: [BandPoint]
}

struct BandPoint: Decodable, Sendable {
    var t: Double
    var st: Double
    /// Half the P10 to P90 width, in semitones.
    var half: Double
}

/// A syllable cluster on a speaker's own timeline (0…1).
struct Syllable: Decodable, Sendable {
    var text: String
    var start: Double
    var end: Double
    /// Measured prominence, normalised within the take (0…1): drives bar height.
    var prominence: Double
    /// Measured as stressed (observed primary or secondary peak): drawn in Lime.
    var stressed: Bool
    /// Dictionary / accepted stress shown in the label (caps), or the mistake marker.
    var label: LabelStyle

    enum LabelStyle: String, Decodable, Sendable {
        /// Bold caps: accepted stress.
        case caps
        /// Lowercase secondary.
        case lower
        /// Blue caps with a triangle and a dotted underline: stressed outside the accepted set.
        case mistake
    }
}

/// How a word's stress is checked (§8.1).
enum StressCheck: String, Decodable, Sendable {
    case checked
    case expectedAmbiguous
    case referenceAnomaly
}

// MARK: - Take (your side)

struct TakeFixture: Decodable, Sendable {
    var id: String
    /// Saved take number; nil for the unsaved last try.
    var number: Int?
    var hasAudio: Bool
    var alignment: Alignment
    var level: Level?
    var words: [AlignedWordPair]
    /// Your pitch on model time, one segment per stretch between breaks. Empty: no voiced frames.
    var pitch: [PitchSegment]

    enum Alignment: String, Decodable, Sendable {
        case aligned
        /// Recorded for an old wording; kept, but can't be compared (§13.6).
        case unalignable
    }

    enum Level: String, Decodable, Sendable {
        case normal
        /// Drawn as a flat, near-silent waveform.
        case nearSilent
    }
}

struct AlignedWordPair: Decodable, Sendable {
    var kind: Kind
    var expected: String?
    var heard: String?
    var stressCheck: StressCheck?
    var syllables: [Syllable]
    /// Missing words only: where the 24 pt slot sits on your timeline (0…1).
    var slot: Double?

    enum Kind: String, Decodable, Sendable {
        case present
        case substituted
        case missing
        case inserted
    }
}

struct PitchSegment: Decodable, Sendable {
    var points: [PitchPoint]
}

struct PitchPoint: Decodable, Sendable {
    var t: Double
    var st: Double
    /// False for frames bridged across unvoiced stretches (drawn lighter and thinner).
    var voiced: Bool?
}

// MARK: - Analysis (the contract)

struct Analysis: Decodable, Sendable {
    var takeProblems: [TakeProblem]?
    var verdict: Verdict?
    var measures: [MeasureState]?
    var timing: Timing?
    var notes: QuietNotes?
    var stress: [StressLine]?

    enum Timing: String, Decodable, Sendable { case good, rough }
}

enum TakeProblem: String, Decodable, Sendable, CaseIterable {
    // Plan order: only the first present is shown.
    case noMicrophone, micDenied, noSpeech, tooShort, tooQuiet, clipped, wordsDontMatch
}

struct Verdict: Decodable, Sendable {
    var kind: Kind
    var rows: [DiffRow]?
    var reasons: [NoClearDifferenceReason]?
    var inconclusive: Inconclusive?

    enum Kind: String, Decodable, Sendable {
        case feedback, close, noClearDifference, inconclusive
    }
}

struct DiffRow: Decodable, Sendable {
    var kind: Kind
    /// Placement: the word, its syllables, the accepted stressed index, the heard (wrong) index.
    var word: String?
    var syllables: [String]?
    var acceptedIndex: Int?
    var heardIndex: Int?
    /// Placement: the voice that says the nearest accepted pattern, when it isn't the selected voice.
    var likeVoice: String?
    /// Contrast, reduction, too much contrast: the syllables named in the sentence.
    var targets: [String]?
    /// Final direction: "lower" or "higher".
    var direction: String?

    enum Kind: String, Decodable, Sendable, CaseIterable {
        // Display order (§10).
        case roughTiming, placement, contrast, reduction, range, finalDirection, tooMuchContrast
    }
}

enum NoClearDifferenceReason: String, Decodable, Sendable, CaseIterable {
    // Display order (§13.1, then A6).
    case pitchShapeBelowClose, optionalMeasuresUnavailable, mediumConfidenceOnly, timingRough
    case nonTargetWordsIncomplete, insertionsPresent
}

struct Inconclusive: Decodable, Sendable {
    var reason: Reason
    var words: [String]?
    /// comparableCoverageLow: the share of the take that lined up (0…1).
    var coverage: Double?
    /// requiredMeasureUnavailable: "lowConfidence" when that is the only cause.
    var cause: String?

    enum Reason: String, Decodable, Sendable {
        case targetWordsMissing, timingUnreliable, comparableCoverageLow, requiredMeasureUnavailable
        case noApplicableStressMeasure
    }
}

/// `MeasureState`: evaluated with a value, or unavailable / notApplicable with a reason.
struct MeasureState: Decodable, Sendable {
    var measure: Measure
    var state: State
    var value: Double?
    var reason: String?

    enum Measure: String, Decodable, Sendable, CaseIterable {
        case stressPlacement, contrast, reduction, rhythm, pitchShape, range, finalDirection
    }

    enum State: String, Decodable, Sendable { case evaluated, unavailable, notApplicable }
}

/// A6 quiet notes. Only the most specific shows in card 1; the inspector lists all.
struct QuietNotes: Decodable, Sendable {
    var insertions: [String]?
    var nonTargetWordsIncomplete: Bool?
    var partial: Partial?

    struct Partial: Decodable, Sendable {
        var compared: Int
        var total: Int
    }
}

/// One inspector STRESS line (§13.5, A5).
struct StressLine: Decodable, Sendable {
    var word: String
    var outcome: Outcome
    /// The pattern shown in brackets, e.g. "phoTOGraphy".
    var pattern: String?
    /// The voice you match.
    var voice: String?
    /// The selected voice, when your pattern differs from it but is accepted.
    var selectedVoice: String?

    enum Outcome: String, Decodable, Sendable {
        case matchesVoice, matchesDictionary, differsButAccepted, outsideAccepted, lowConfidence, referenceAnomaly
        case notChecked
    }
}

struct OperationalError: Decodable, Sendable {
    var kind: Kind
    /// inferenceFailed: the stage that failed.
    var stage: Stage?
    /// audioUnreadable: "clip" or "take".
    var source: String?

    enum Kind: String, Decodable, Sendable {
        case modelUnavailable, inferenceFailed, referenceCacheCorrupt, audioUnreadable
    }

    /// inferenceFailed stages (§13.2). `Copy.inferenceStage` holds their words.
    enum Stage: String, Decodable, Sendable, CaseIterable {
        case findingWords, measuringPitch, measuringStress, comparing
    }
}

enum PersistenceStatus: String, Decodable, Sendable {
    case saved, notSaved, saveFailed, savedPruneFailed
}
