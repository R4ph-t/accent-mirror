# 01: Contract v2

Status: Draft · Branch: – · Depends on: 00 (project skeleton) · Estimate: 3–4 h agent run + 1 h Raph review
· Risk: high

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris). Contract §1, §1.1–§1.3, alignment types §4.3–§4.4, confidence §5, persistence §8.3, identity and
versions §9.1, gate values §6.7. Where rev 4.1 says "as before", the value is taken from the first v2 (09:10
Europe/Paris) and the line says so. Risk is high because this spec creates `AMCore/Thresholds.swift` (a risky path)
and freezes the contract every later spec and the UI read.

## Goal

Freeze the analysis output contract in `AMCore` as plain `Sendable`, `Codable` value types with golden JSON. Ship
the decision procedure (§1.2) as one pure, table-tested function, the applicability rules (§1.1) as one pure
function, `Thresholds.swift` mirroring `docs/thresholds.md`, and `Versions.swift` with the golden digest check. No
signal processing, no ASR, no UI.

## Behaviour

### Types (names from the plan, verbatim)

All in `Packages/AccentKit/Sources/AMCore/`, Foundation only, every type `Sendable` and `Codable` (and `Hashable`
where it is used as a key).

- **Outcome:** `AnalysisResponse` (`requestID`, `identity`, `outcome`), `AnalysisOutcome` (`analysed`,
  `takeProblem`, `failed`, `cancelled`).
- **Take problems:** `TakeProblem` with cases in Designer's order `noMicrophone, micDenied, noSpeech, tooShort,
  tooQuiet, clipped, wordsDontMatch`, and `Comparable` in that order. A helper returns only the first problem of a
  set.
- **Operational errors:** `OperationalError` = `modelUnavailable(ModelFailure)`, `inferenceFailed(stage: Stage)`,
  `referenceCacheCorrupt(RecordingID)`, `audioUnreadable`. Storage failures are **not** here (§8.3).
- **Measures:** `MeasureState<Value>` = `notApplicable(NotApplicableReason)`, `unavailable(UnavailableReason)`,
  `evaluated(Value, Confidence)`. `NotApplicableReason` = `noEligibleWord, tooFewSyllablesInPhrase,
  tooFewExpectedUnstressed, modelHasNoFinalVoicing, modelTooFewVoicedFrames`. `UnavailableReason` = `wordMissing,
  wordSubstituted, lowConfidence, noVoicedFrames, tooFewOverlappingFrames, zeroVariance, coverageLow`.
  `MeasureKind` = `stressPlacement, contrast, tooMuchContrast, weakLength, rhythm, pitchRange, shapeMatch,
  finalDirection`. `Confidence` = `low, medium, high` (`Comparable`).
- **Verdict:** `Verdict` = `feedback(rows: BoundedRows, partial: [MeasureKind])`, `close`,
  `noClearDifference([NeutralReason])`, `inconclusive([InconclusiveReason])`. `BoundedRows` cannot hold 0 rows or
  more than 3 (its initialiser fails, and decoding such JSON throws). `NeutralReason` and `InconclusiveReason` have
  exactly the cases in §1, including `nonTargetWordsIncomplete([WordIndex])`, `insertionsPresent([String])` and
  `requiredMeasureUnavailable([MeasureKind])`.
- **Diff rows:** `DiffRow` (`kind: DiffKind`, word index, syllable indices, accepted and heard syllable index,
  `likeVoice`, values). `DiffKind` = `roughTiming, placement, contrast, weakLength, pitchRange, finalDirection,
  tooMuchContrast`. Rows carry structured values only, never sentences (copy lives in the app, Designer owns it).
- **Alignment:** `AlignedWordPair` (`present`, `substituted`, `missing`, `inserted`) and `WordAlignment`, exactly
  as §4.3. `PartialTimeMap` with `Segment` (`mapped`, `modelOnly`, `youOnly`) and `Anchor`, as §4.4. This spec
  ships the data types and their validation (segments ordered by model time then your time, mapped ranges monotone,
  anchors inside their segment). `toModel`, `toYou` and playback lookup are spec 09.
- **Timing:** `TimingLevel` = `good, rough, poor`.
- **Voicing seam:** `protocol VoicingSource: Sendable` with an `id` (the `voicingID`) and a per-frame voiced
  decision over 10 ms frames. It lives here so spec 05 (`ACFVoicing`) and spec 07 (the syllable segmenter) can both
  use it without importing each other; this spec ships the protocol only, no implementation.
- **Persistence:** `PersistenceStatus` = `notSaved(NotSavedReason)`, `pending`, `saved(TakeID)`,
  `saveFailed(StorageError)`, `savedPruneFailed(TakeID, StorageError)`. `NotSavedReason` = `takeProblem, failed,
  cancelled, notAccepted`.
- **Identity:** `ConfigIdentity` (`algorithmVersion`, `thresholdsVersion`, `contractVersion` as monotonic integers;
  `asrModelID`, `pitchTrackerID`, `voicingID` as strings), `ReferenceIdentity` (`phraseID`, `recordingID`,
  `recordingSHA256`, `transcriptRevision`, `pronunciationOverridesHash`, `targetsHash`, `nativeSetHash`),
  `AnalysisIdentity` (take audio SHA-256, `ReferenceIdentity`, `ConfigIdentity`), `AnalysisRequest` (`id`,
  `generation`, `inputs`, `config`, §8.1). ID types (`RequestID`, `PhraseID`, `RecordingID`, `TakeID`,
  `WordIndex`) are distinct wrapper types, not bare strings or ints.
- **`AnalysisResult`:** see Open question 1.

### Applicability (§1.1)

One pure function decides, **from the phrase and the model take only, never from your take**, which measures are
applicable and which are required: placement (at least one target or content word with ≥ 2 syllables that isn't
`expectedAmbiguous`; required if applicable), contrast / too-much-contrast / weak length (|S| ≥ 1 and |U| ≥ 2;
required if applicable), nPVI (≥ 3 syllables; inspector only), pitch range and shape match (model ≥ 20 voiced
frames; optional), final direction (model's final window has ≥ 10 voiced frames and a non-level slope; optional).
A one-word, two-syllable phrase gets placement applicable and contrast `.notApplicable(.tooFewExpectedUnstressed)`.

### Decision procedure (§1.2)

One pure function maps a `DecisionInput` (take problems, alignment summary, timing level, comparable coverage, the
measure states with their applicable/required flags, the ranked triggered and unsuppressed diffs, shape match) to an
`AnalysisOutcome` case or a `Verdict`, in the plan's order, first match wins:

1. any `TakeProblem` → `.takeProblem(first)`;
2. match % < 80% or more than 2 non-filler insertions → `.takeProblem(.wordsDontMatch)`;
3. any target word `missing` or `substituted` → `inconclusive(.targetWordsMissing)`;
4. timing Poor → `inconclusive(.timingUnreliable)`;
5. comparable coverage < 70% of the model's syllables → `inconclusive(.comparableCoverageLow)`;
6. placement and contrast both `.notApplicable` → `inconclusive(.noApplicableStressMeasure)`;
7. at least one triggered diff → `feedback`, ranked, `partial` = required applicable measures that are
   `.unavailable`; with Rough timing the rough-timing row is first and counts toward the 3;
8. nothing triggered and any required applicable measure `.unavailable` →
   `inconclusive(.requiredMeasureUnavailable([kinds]))`;
9. `close` if every §1.3 condition holds;
10. otherwise `noClearDifference(reasons)`, including `nonTargetWordsIncomplete` and `insertionsPresent` whenever
    they apply.

`close` (§1.3): every phrase word `present` (no substituted, no missing, no non-filler insertions), every applicable
measure evaluated at medium or high and every required one at high, shape match ≥ 0.7 when applicable, timing Good,
nothing triggered.

### Thresholds and versions

- `AMCore/Thresholds.swift` holds every tunable number in one value (`Thresholds.current`), including
  `Thresholds.agreement` (the §6.7 gate table). `docs/thresholds.md` is rewritten to plan v2 rev 4.1 (see Defaults)
  and stays the human mirror. A test fails if a row in `docs/thresholds.md` and the Swift value disagree (each table
  row gets a `Key` column naming the Swift property).
- `AMCore/Versions.swift`: `algorithmVersion = 1`, `thresholdsVersion = 1`, `contractVersion = 1`, monotonic
  integers, not semver (§9.1). A golden-output digest (SHA-256 of the canonical JSON of every golden fixture) sits
  next to it. A test fails if the digest changes without a version bump.
- `CanonicalJSON` (sorted keys, no whitespace, fixed float formatting) and `configDigest` (SHA-256 of the canonical
  JSON of `ConfigIdentity` plus the full `Thresholds`, §6.6) live in `AMCore`, so specs 02 and 03 compute them the
  same way. If spec 03 lands first with its own copy, this spec moves callers to the `AMCore` one and deletes the
  copy.

## Defaults

- `docs/thresholds.md` is updated to rev 4.1 values; nothing is lowered, and the PR lists every changed row with its
  plan section. In particular:
  - Onset: RMS ≥ max(−50 dBFS, floor + 10 dB) for 3 frames with a voiced frame within 100 ms, offset below floor
    + 6 dB, settling and retraction rules, `ACFVoicing` (peak ≥ 0.45, RMS > floor + 3 dB) (§10, first v2 §10). This
    replaces the old "max(−45, floor + 12)" row.
  - Confidence levels (first v2 §5, "as before"): word c_w and syllable split s_w levels ≥ 0.7 high / ≥ 0.45
    medium; timing Good ≥ 0.8, Rough ≥ 0.5, else Poor (share of comparable syllables at medium or above); measure
    confidence rows as in first v2 §5.
  - Prominence (§2): w = (0.4, 0.3, 0.3), floors (0.05, 1 dB, 1 st), λ = 1.6, τ_med = 0.25 and τ_high = 0.5 in every
    n-bucket {2–4, 5–8, ≥ 9}, exposure pause > 150 ms.
  - Final direction (§11): rise ≥ +5 st/s, fall ≤ −5 st/s, window 200 ms extending to 300 ms, ≥ 10 voiced frames.
    This replaces the old "|slope| ≥ 1 st" row.
  - Decision: match ≥ 80%, ≤ 2 non-filler insertions, comparable coverage ≥ 70%, shape match ≥ 0.7 for `close`.
  - Agreement: every §6.7 row, verbatim. The old "agreement false positives ≤ 5% of phrases" row is replaced by the
    §6.7 pair-based rows; the old "stress-detection bar, owner 03" row moves to spec 11.
- Golden JSON lives in `Packages/AccentKit/Tests/AMCoreTests/Golden/`, one file per outcome case and per verdict
  case, plus the five §1.3 examples.

## Guardrails

- `AMCore` imports Foundation only. No AppKit, UIKit, AVFoundation or third-party code.
- Swift 6 language mode, strict concurrency, no `@unchecked Sendable`.
- No app-target changes. The app's `FixtureModel` keeps decoding its own fixtures (see Open question 2).
- Never lower a threshold quietly. Values come from the plan; the PR names the section for each.
- `make check` stays green with no new warnings.

## Out of scope

- Signal processing, alignment logic, prominence, measures and diff triggering (specs 04–10).
- `toModel` / `toYou` / playback lookup (spec 09), the coordinator and request lifecycle (spec 12), the take store
  (spec 16), the agreement harness and reports (spec 02).
- Sentences and UI copy (Designer, app target).

## Open question (built with the default)

1. **`AnalysisResult` fields.** Rev 4.1 changes the outcome and alignment types but does not restate the result
   struct. Default: v1's `AnalysisResult` with these replacements: `WordAlignment` replaces `WordSpan.isMissing`;
   `PartialTimeMap` replaces `WarpMap`; measures are `[MeasureKind: MeasureState<Double>]` plus the applicability
   table; `verdict: Verdict`; `timing: TimingLevel`; per-word stress lines (expected pattern, observed primary,
   margin, confidence, matched accepted pattern, `referenceAnomaly`); `identity: AnalysisIdentity`. Pitch frames keep
   `voiced: Bool`. The model side and your side are both `SpeakerAnalysis` on their own timelines.
2. **UI fixture drift.** The spec 19 fixtures use a few names the plan doesn't (`notApplicable` reason
   `oneWordTwoSyllables`; stress-line outcomes `matchesVoice / matchesDictionary / differsButAccepted /
   outsideAccepted / lowConfidence / referenceAnomaly / notChecked`; diff kind `reduction`). Default: `AMCore`
   follows the plan (`tooFewExpectedUnstressed`, `weakLength`); the app fixtures are not touched here. List every
   drift in Implementation notes so spec 21 (coordinator-wired UI) maps or renames them in one place.
3. **Diff ranking ties.** v1: placement, contrast, weak length, pitch range, final direction, too much contrast
   (always last), ties to the larger relative gap, rough-timing row first. Default: encode exactly that in the
   `DiffKind` order; spec 10 computes the gaps.

## How to test (Raph)

1. `make check` is green: generate, unsigned build, package tests, corpus guard, no AppKit/UIKit in AccentKit.
2. `swift test --package-path Packages/AccentKit --filter DecisionProcedureTests` passes and covers every step of
   §1.2 plus the five §1.3 examples ("record" → `close`; shape 0.5 → `noClearDifference([.pitchShapeBelowClose(0.5)])`;
   "record" substituted → `inconclusive(.targetWordsMissing)`; contrast unavailable and placement fires →
   `feedback(rows: [placement], partial: [.contrast])`; same with nothing firing →
   `inconclusive(.requiredMeasureUnavailable([.contrast]))`).
3. `BoundedRows` with 0 or 4 rows fails to build, and decoding a golden file with 4 rows throws.
4. Open `docs/thresholds.md`: every row has a key and a plan section, and the `ThresholdsMirrorTests` test passes.
   Change one value in the doc only and confirm the test fails.
5. Change one golden file without bumping a version and confirm the digest test fails.

## Implementation notes

_(filled in by the agent)_
