import AMCore
import Foundation

// Fixture schema for the UI shell (spec 19, v3 in spec 29). Field names follow the contract (spec 28's `notScored`,
// `comparableCoverage`, `describe` and `expectedStress`; take problems; operational errors; `AlignedWordPair`;
// `PersistenceStatus`). AMCore does not define these types yet (spec 01); when it does, the
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
    /// Earlier saved takes drawn faintly behind yours, newest first (`takes/<id>.json`).
    var earlierTakes: [String]?
    /// View ▸ Show Earlier Takes for this state; nil keeps the remembered choice (on by default).
    var earlierTakesVisible: Bool?
    /// Play Both on the injected clock: the fixture freezes the sequence at `elapsed` seconds.
    var playBoth: PlayBothFrame?
    /// The inspector's MODEL RECORDING.
    var modelRecording: ModelRecording?
    /// Replaces the phrase file's toolbar subtitle for this state (`voice-popup-open`: "… from Iowa, VCTK").
    var subtitle: String?
    /// The window size the screenshot runner renders this state at, in points. Nil: the default 1200 × 800.
    var window: WindowSize?
    /// Spec 20: the charts' motion inputs, frozen on the fixture clock. The screenshot runner also renders every
    /// state that has one with Reduce Motion on.
    var chart: ChartFixture?
    /// v3.5 I7: the Input popover drawn open.
    var inputPopover: InputPopoverFixture?
    /// v5 §3: the phrase word (index) whose Native vs You popover is drawn open.
    var wordPopover: Int?
    /// v5 §4: the Rhythm and pitch disclosure drawn expanded (the strip and pitch cards). Nil: collapsed, the default.
    var rhythmAndPitchExpanded: Bool?

    struct ChartFixture: Decodable, Sendable {
        /// Milliseconds since every change in this state began (hover, loop, ghosts, voice switch). Nil: 0.
        var clockMs: Double?
        /// Model or You playing, frozen at `position` along that take's own timeline (0…1).
        var playback: Playback?
        /// The phrase word whose strip label the pointer is over.
        var hoveredWord: Int?
        /// The phrase word a label click is looping, and how many seconds into the loop the frame is.
        var loopingWord: Int?
        var loopElapsed: Double?
        /// The earlier takes' last change: `saved` (a new take came in; `before` were the ghosts until then),
        /// `toggledOff` or `toggledOn` (⇧⌘G).
        var earlierTakes: EarlierTakesChange?
        /// `takes/<id>.json` hovered in the open take menu: drawn as the only ghost.
        var menuPreview: String?
        var voiceSwitch: VoiceSwitch?

        struct Playback: Decodable, Sendable {
            enum Side: String, Decodable, Sendable { case model, you }
            var side: Side
            var position: Double
        }

        struct EarlierTakesChange: Decodable, Sendable {
            enum Change: String, Decodable, Sendable { case saved, toggledOff, toggledOn }
            var change: Change
            /// `takes/<id>.json`, newest first: the earlier takes before a `saved` change.
            var before: [String]?
        }

        /// The selected voice changed to `phrase` (the new voice's native side) with your take re-timed onto it
        /// (`take`). `pending`: the subtitle names the new voice and the old drawing stays; `easing`: the new L2
        /// arrived `clockMs` ago; `done`: drawn on the new voice.
        struct VoiceSwitch: Decodable, Sendable {
            enum Stage: String, Decodable, Sendable { case pending, easing, done }
            var phrase: String
            var take: String?
            var voice: String
            var stage: Stage
        }
    }

    struct PlayBothFrame: Decodable, Sendable {
        var elapsed: Double
        var modelSeconds: Double
        var youSeconds: Double
    }

    struct ModelRecording: Decodable, Sendable {
        /// "p225", or "From demo-talk.m4a" for a clip.
        var voice: String
        var region: String?
        var attribution: String
        /// The voice pop-up's choices (spec 15); empty for a clip.
        var voices: [String]
        /// Each row's right-aligned tag, "p225 · F" (r6 E7), in `voices` order.
        var tags: [String]?
        /// The checked row, an index into `voices`.
        var selected: Int?
        /// The pop-up drawn open (`voice-popup-open`, v3.2 W2).
        var open: Bool?
    }

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
        /// Older fixtures: how far in, as a fraction of the model's duration.
        var playhead: Double
        /// Seconds of envelope recorded so far (spec 20's live strip); wins over `playhead`.
        var seconds: Double?
        /// The E5 level meter's frozen frame (v3.2 W2). Without it the meter isn't drawn, as outside a live take.
        var level: LevelReading?
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
    /// One entry per syllable, from the starter override or the part-of-speech variant saved at import (spec 28).
    /// Nil: the word is ambiguous (out of vocabulary, or no single context pronunciation).
    var expectedStress: [SyllableStress]?
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

/// A syllable cluster on a speaker's own timeline (0…1). Bars are the recording's envelope only (v3.1 V1): nothing
/// about stress lives here.
struct Syllable: Decodable, Sendable {
    var text: String
    var start: Double
    var end: Double
    /// Envelope height, normalised within the take (0…1).
    var prominence: Double
}

/// AMCore's `SyllableStress`: the phrase's context-resolved stress (spec 28 `WordSpan.expectedStress`).
enum SyllableStress: String, Decodable, Sendable { case primary, secondary, unstressed }

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
    /// Decoded so a fixture can say `.notScored`; no view or presenter reads it (spec 28).
    var verdict: Verdict?
    var timing: Timing?
    /// `AnalysisResult.comparableCoverage` (spec 28): comparable syllables over the model's. Nil for older takes.
    var comparableCoverage: Double?
    /// `AnalysisResult.describe` (spec 28 §4a): you, and the range across the phrase's native voices.
    var describe: Describe?
    /// v3.5 I4 tier B: the saved take has a run of frames at −1 dBFS lasting 50 ms or more (`ClippingTier`).
    var clipped: Bool?
    /// `AnalysisResult.sounds` (v5 sound judging), AMCore's own type and JSON. Its times are seconds from the start of
    /// each speaker's timeline (the fixture's playback lengths); live, `LoadedFixture.timelines` places them.
    var sounds: SoundJudgementOutcome?

    enum Timing: String, Decodable, Sendable { case good, rough }
}

enum TakeProblem: String, Decodable, Sendable, CaseIterable {
    // Plan order: only the first present is shown.
    case noMicrophone, micDenied, noSpeech, tooShort, tooQuiet, clipped, wordsDontMatch
}

/// Show-don't-judge v1: every analysed fixture is `.notScored`. `{"notScored": {}}` (the contract's canonical form)
/// and `{"kind": "notScored"}` both decode; the presenter never reads it.
struct Verdict: Decodable, Sendable {
    var kind: Kind

    enum Kind: String, Decodable, Sendable { case notScored }

    enum CodingKeys: String, CodingKey { case kind, notScored }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if !container.contains(.kind), container.contains(.notScored) {
            kind = .notScored
            return
        }
        kind = try container.decode(Kind.self, forKey: .kind)
    }
}

/// Mirrors AMCore's `DescribedMeasures` (spec 28 §4a): plain values, never a verdict.
struct Describe: Decodable, Sendable, Equatable {
    var you: Speaker
    var native: Native

    struct Speaker: Decodable, Sendable, Equatable {
        var lengthSeconds: Value
        var syllablesPerSecond: Value
        var pitchRangeSemitones: Value
        var rhythmNPVI: Value
        var endingDirection: Direction?
    }

    struct Native: Decodable, Sendable, Equatable {
        /// Native voices measured (one for an imported clip).
        var voices: Int
        var lengthSeconds: Range
        var syllablesPerSecond: Range
        var pitchRangeSemitones: Range
        var rhythmNPVI: Range
        /// How many voices end rising, falling and level.
        var endingDirections: [String: Int]
    }

    /// `{"value": 2.4}` or `{"reason": "noVoicedFrames"}`.
    struct Value: Decodable, Sendable, Equatable {
        var value: Double?
        var reason: MissingReason?
    }

    struct Range: Decodable, Sendable, Equatable {
        var min: Double?
        var max: Double?
        var count: Int
    }

    enum MissingReason: String, Decodable, Sendable, CaseIterable {
        case noVoicedFrames, tooFewSyllables, tooFewFinalFrames, noWords
    }

    enum Direction: String, Decodable, Sendable, CaseIterable { case rise, fall, level }
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

/// One frame of the E5 level meter: the frame's RMS and the held peak (−60…0 dBFS), and whether "Too loud" holds.
struct LevelReading: Sendable, Equatable, Decodable {
    var rmsDBFS: Double
    var peakDBFS: Double
    var tooLoud: Bool = false

    init(rmsDBFS: Double, peakDBFS: Double, tooLoud: Bool = false) {
        self.rmsDBFS = rmsDBFS
        self.peakDBFS = peakDBFS
        self.tooLoud = tooLoud
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rmsDBFS = try c.decode(Double.self, forKey: .rmsDBFS)
        peakDBFS = try c.decode(Double.self, forKey: .peakDBFS)
        tooLoud = try c.decodeIfPresent(Bool.self, forKey: .tooLoud) ?? false
    }

    private enum CodingKeys: String, CodingKey { case rmsDBFS, peakDBFS, tooLoud }
}

/// The Input popover drawn open (Designer addendum v3.5 I7): `input-popover`, `input-popover-no-volume`,
/// `input-popover-too-loud`.
struct InputPopoverFixture: Decodable, Sendable {
    /// The chosen input's name; nil is "System Default".
    var device: String?
    /// The inputs listed after "System Default".
    var devices: [String]?
    /// The Mac input volume, 0…1; nil: the device sets its own level (the slider is disabled).
    var volume: Double?
    var notice: InputPopoverState.Notice?
    /// The meter's frozen frame.
    var level: LevelReading?
}
