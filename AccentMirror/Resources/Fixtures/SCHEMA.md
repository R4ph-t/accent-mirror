# UI fixtures (spec 19)

Each UI state is a JSON file. The app renders it with `-UIFixture <name>`, and `make screenshots` renders every
fixture in light and dark. The decoding types are in `AccentMirror/Fixtures/FixtureModel.swift`. The names follow
the plan v2 contract. When spec 01 freezes those types in AMCore, fix any drift by updating these files, not by
adding a second model.

```
states/<name>.json    one UI state (the fixture name is the file name)
phrases/<id>.json     the native side of a phrase: words, syllables, the native pitch band
takes/<id>.json       your take: aligned word pairs, syllables, your pitch
```

All times are fractions of a timeline (0…1). The strip uses each speaker's own timeline. The pitch chart uses model
time.

## states/<name>.json

| Field | Type | Meaning |
|---|---|---|
| `name` | string | Same as the file name |
| `summary` | string | What the state shows |
| `phrase` | string | `phrases/<phrase>.json` |
| `manifest` | object? | Replaces the static library stub (`packs[].{id,title,phrases[].{id,text}}`). A pack with no phrases is "coming soon" |
| `sidebar` | object? | `{selectedPhraseID, expandedPackIDs[]}`. Defaults to Photography selected, My Phrases and Stress Shifts open |
| `phase` | `empty` \| `recording` \| `analysing` \| `showingTake` | What the coordinator is doing |
| `recording` | object? | `{elapsed: "0:02", playhead: 0.46}` while recording |
| `take` | string? | `takes/<take>.json`: the take on screen (saved, or the unsaved last try) |
| `savedTakes` | int[] | Saved take numbers, newest first |
| `analysis` | object? | The contract result (below) |
| `operationalError` | object? | `{kind: modelUnavailable \| inferenceFailed \| referenceCacheCorrupt \| audioUnreadable, stage?: findingWords \| measuringPitch \| measuringStress \| comparing, source?: clip \| take}` |
| `persistence` | string? | `saved` \| `notSaved` \| `saveFailed` \| `savedPruneFailed` |
| `outcome` | string? | Coordinator outcome with no UI trace (`cancelled`) |
| `inspectorOpen` | bool? | Opens the Details inspector |
| `window` | object? | `{width, height}` in points: the window size the screenshot runner uses. Defaults to 1200 × 800. At least the 960 × 680 minimum |

### analysis

| Field | Type | Meaning |
|---|---|---|
| `takeProblems` | string[]? | `noMicrophone`, `micDenied`, `noSpeech`, `tooShort`, `tooQuiet`, `clipped`, `wordsDontMatch`. Only the first in that order shows |
| `verdict.kind` | `feedback` \| `close` \| `noClearDifference` \| `inconclusive` | |
| `verdict.rows` | DiffRow[]? | feedback: `{kind: roughTiming \| placement \| contrast \| reduction \| range \| finalDirection \| tooMuchContrast, word?, syllables?, acceptedIndex?, heardIndex?, likeVoice?, targets?, direction?}`. Shown in §10 order, at most 3 |
| `verdict.reasons` | string[]? | noClearDifference: `pitchShapeBelowClose`, `optionalMeasuresUnavailable`, `mediumConfidenceOnly`, `timingRough`, `nonTargetWordsIncomplete`, `insertionsPresent` |
| `verdict.inconclusive` | object? | `{reason: targetWordsMissing \| timingUnreliable \| comparableCoverageLow \| requiredMeasureUnavailable \| noApplicableStressMeasure, words?, coverage?, cause?: lowConfidence}` |
| `measures` | MeasureState[]? | `{measure: stressPlacement \| contrast \| reduction \| rhythm \| pitchShape \| range \| finalDirection, state: evaluated \| unavailable \| notApplicable, value?, reason?}`. `contrast` notApplicable with `oneWordTwoSyllables` or `tooFewExpectedUnstressed` gives the placement-only line |
| `timing` | `good` \| `rough` | |
| `notes` | object? | A6 quiet notes: `{insertions?: [word], nonTargetWordsIncomplete?: bool, partial?: {compared, total}}` |
| `stress` | StressLine[]? | Inspector STRESS lines: `{word, outcome: matchesVoice \| matchesDictionary \| differsButAccepted \| outsideAccepted \| lowConfidence \| referenceAnomaly \| notChecked, pattern?, voice?, selectedVoice?}` |

## phrases/<id>.json

`{id, text, subtitle, rangeSemitones, words[], band[]}`

- `words[]`: `{text, stressCheck?: checked | expectedAmbiguous | referenceAnomaly, start, end, syllables[]}`.
- `band[]`: one segment per stretch between pauses over 250 ms. Each is `{points: [{t, st, half}]}`, where `st` is
  semitones re your median and `half` is half the P10 to P90 width.

## takes/<id>.json

`{id, number?, hasAudio, alignment: aligned | unalignable, level?: normal | nearSilent, words[], pitch[]}`

- `words[]` are `AlignedWordPair`s:
  `{kind: present | substituted | missing | inserted, expected?, heard?, stressCheck?, syllables[], slot?}`.
  `slot` places a missing word's 24 pt slot on your timeline.
- `pitch[]`: one segment per stretch between breaks (pauses over 250 ms, `modelOnly` and `youOnly` gaps). Each is
  `{points: [{t, st, voiced?}]}`, where `voiced: false` marks bridged frames. A segment under 3 points isn't drawn.
  An empty `pitch` means no voiced frames.

## Syllable

`{text, start, end, prominence (0…1), stressed (measured: Lime bars), label: caps | lower | mistake}`

The label carries dictionary or accepted stress (caps). The bars carry measured prominence (height, Lime).
`mistake` draws blue caps with a triangle and a dotted underline, but only on the syllable named after "not" in a
placement row that card 1 shows (your stress outside the accepted set at high confidence, §8, §13 item 5).
`ShellPresenter` enforces it: in any other state a `mistake` label is drawn lowercase, and the contract tests fail
on a fixture that carries one. Low confidence, close, noClearDifference and inconclusive never show the marker.
