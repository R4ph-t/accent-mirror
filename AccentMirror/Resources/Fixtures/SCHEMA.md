# UI fixtures (spec 19, v3 in spec 29)

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
| `manifest` | object? | Replaces the static library stub (`packs[].{id,title,phrases[].{id,text,targets?}}`; `targets` adds words to the pitch plot's target words, r4 C6). A pack with no phrases is "coming soon" |
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
| `earlierTakes` | string[]? | `takes/<id>.json` of earlier saved takes, newest first: up to 3 aligned ones draw faintly behind your line (v3 §3.3) |
| `earlierTakesVisible` | bool? | View ▸ Show Earlier Takes for this state (`result-earlier-takes-off`); nil keeps the remembered choice, on by default |
| `playBoth` | object? | `{elapsed, modelSeconds, youSeconds}`: Play Both frozen on an injected clock at `elapsed` s (`playing-both`) |
| `modelRecording` | object? | The inspector's MODEL RECORDING: `{voice, region?, attribution, voices[], tags[]?, selected?, open?}`. `voices` feed the pop-up; `tags` are the rows' "p311 · M"; `selected` is the checked row's index; `open: true` draws the pop-up open (`voice-popup-open`) |
| `subtitle` | string? | Replaces the phrase file's toolbar subtitle for this state |
| `chart` | object? | Spec 20's motion inputs, frozen on the fixture clock (below). A state with one is also rendered with Reduce Motion (`<name>-reduce-motion-{light,dark}@2x.png`) |
| `inputPopover` | object? | The Input popover drawn open (v3.5 I7): `{device?, devices?[], volume?, notice?, level?}`. `device` is the chosen input's name (none: "System Default"), `devices` the inputs listed after it, `volume` the Mac input volume 0…1 (none: the device sets its own level, so the slider is disabled with the Sound Settings… note), `notice` `micDenied` \| `noMicrophone` (v2 §11.1 copy, no meter), `level` the meter's frozen frame (`{rmsDBFS, peakDBFS, tooLoud?}`) |
| `window` | object? | `{width, height}` in points: the window size the screenshot runner uses. Defaults to 1200 × 800. At least the 960 × 680 minimum |

`recording` also takes `seconds`: how much envelope has been recorded (spec 20's live row). Without it, `playhead` is
read as a fraction of the model's duration. `level: {rmsDBFS, peakDBFS, tooLoud?}` freezes the E5 level
meter on one frame (−60…0 dBFS; `tooLoud` draws the clipping treatment); without it the meter isn't drawn.

### chart (spec 20)

| Field | Type | Meaning |
|---|---|---|
| `clockMs` | number? | Milliseconds since every change in this state began (hover, loop, ghosts, voice switch). Default 0 |
| `playback` | object? | `{side: model \| you, position}`: Model or You playing, frozen at `position` (0…1) on that take's own timeline |
| `hoveredWord` | int? | The phrase word whose strip label the pointer is over |
| `loopingWord` | int? | The phrase word a label click is looping; `loopElapsed` is seconds into the loop |
| `earlierTakes` | object? | `{change: saved \| toggledOff \| toggledOn, before?: [take ids]}`: the ghosts' last change |
| `menuPreview` | string? | A take hovered in the open take menu: drawn as the only ghost |
| `voiceSwitch` | object? | `{phrase, take?, voice, stage: pending \| easing \| done}`: the new voice's phrase file and your take re-timed onto it |

### analysis

Show-don't-judge v1 (specs 28–29): no verdict rows, measure states, stress lines or quiet notes. The views read none.

| Field | Type | Meaning |
|---|---|---|
| `takeProblems` | string[]? | `noMicrophone`, `micDenied`, `noSpeech`, `tooShort`, `tooQuiet`, `clipped`, `wordsDontMatch`. Only the first in that order shows |
| `verdict` | object? | `{"notScored": {}}` (or `{kind: notScored}`) on every analysed fixture; a missing verdict is accepted. Never read by a view |
| `timing` | `good` \| `rough` | Inspector ALIGNMENT reads Clear / Rough; rough gives card 1's timing quiet line |
| `comparableCoverage` | number? | `AnalysisResult.comparableCoverage`: below `Thresholds.decision.minComparableCoverage`, card 1's coverage quiet line |
| `clipped` | bool? | v3.5 I4 tier B: the saved take has a run of 10 ms frames at −1 dBFS lasting 50 ms or more; card 1's first quiet line, with an Input… button. Tier A is the `clipped` take problem (not saved; Input… and Try Again) |
| `describe` | object? | `AnalysisResult.describe` (spec 28 §4a): `{you: {lengthSeconds, syllablesPerSecond, pitchRangeSemitones, rhythmNPVI: {value} \| {reason}, endingDirection?: rise \| fall \| level}, native: {voices, lengthSeconds, syllablesPerSecond, pitchRangeSemitones, rhythmNPVI: {min, max, count}, endingDirections: {fall: 5, rise: 3}}}`. The inspector's THIS TAKE |

Card 1's quiet line is the first of: clipped (`clipped`, v3.5), low coverage, rough timing, inserted words (the take's
`inserted` pairs).

## phrases/<id>.json

`{id, text, subtitle, rangeSemitones, words[], band[]}`

- `words[]`: `{text, stressCheck?: checked | expectedAmbiguous | referenceAnomaly, expectedStress?, start, end, syllables[]}`.
  `expectedStress` is spec 28's context-resolved stress, one of `primary | secondary | unstressed` per syllable. The
  single `primary` gets the Lime dot and bold caps on the native row (v3.1 V2); a word without it is ambiguous.
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

`{text, start, end, prominence (0…1)}`

Bars are each recording's real envelope, all `strip.bar` in both rows (v3.1 V1). Nothing about stress lives on a
syllable: the dot comes from the native word's `expectedStress`, and your labels are always plain lowercase (V3).
