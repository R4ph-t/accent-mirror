# 09: Partial time map and native band

Status: Ready · Branch: – · Depends on: 02 (harness), 04 (pitch), 07 (syllables) · Estimate: 3–4 h agent run + 1 h
Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §4.4 (partial time map, gaps, playback lookup), §9.2 (band per selected voice), §8.2 (DTW
cancellation), §6.7 (band coverage). DTW and band rules are "as before" from v1 `AMWarp` and the first v2 §5 and §9.

## Goal

In `AMWarp`: build the `PartialTimeMap` (types from spec 01) from the alignment and syllable anchors, implement
`toModel`, `toYou` and playback lookup, put your pitch on model time with breaks at gaps, use DTW only inside a
mapped segment whose anchors are Poor, and build the native band on the selected voice's timeline. Turn on the
band-coverage metric.

## Behaviour

### Building the map

- `mapped(model:you:anchors:comparable:)` for each `present` word (comparable = true; anchors at its syllable
  boundaries) and each `substituted` word (comparable = false; anchors at word edges only). Monotone piecewise-linear
  between anchors.
- `modelOnly(model:)` for a `missing` word; `youOnly(you:)` for an `inserted` word.
- Segments ordered by model time, then your time. Validation from spec 01 must pass for every map built.
- Comparable coverage = comparable model syllables ÷ model syllables (feeds §1.2 step 5).

### Lookups (§4.4)

- `toModel(_:)` returns nil inside `youOnly`; `toYou(_:)` returns nil inside `modelOnly`.
- Before the first or after the last mapped segment, clamp up to 50 ms, then nil. No extrapolation.
- `playbackRange(word:speaker:) -> TimeRange?`: the model side always returns its word span; your side returns your
  span for `present` and `substituted`, nil for `missing`; an `inserted` word is playable from your timeline only.
- A loop slice in model time maps to the union of your mapped ranges inside it; if that union is empty, only the
  model plays.

### Pitch on model time

- Your pitch line is mapped through `toModel`. It **breaks** at every `modelOnly` and `youOnly` gap (never bridged
  across), and at pauses over 250 ms as in spec 04. Comparable-frame measures skip gaps.

### DTW

- Used only inside a mapped segment when its anchors are Poor (timing confidence from spec 07). Features: MFCC plus
  log-energy. It only maps time for the pitch overlay and the playhead. It never changes syllable boundaries,
  durations, stress or any confidence, and it sets timing to Rough.
- `Task.isCancelled` every 100 DTW rows (§8.2). Budget ≤ 150 ms on an M1 for a 3 s take, printed by a benchmark test.

### Native band

- P10–P90 in semitones per aligned model frame across the native takes, each warped onto the **selected** voice's
  timeline; ±1.5 st around the model when there is only one native take.
- On a voice switch the band is re-timed to the new voice (it is L2, §9.2). `nativeSetHash` = sorted SHA-256s of the
  takes used.
- The band never contains the test speaker: in evaluation, held-out speakers are never bundled; a test checks the
  builder rejects a test take that is in the native set.
- Band coverage per pair = share of T's comparable voiced frames inside the band.

### Gate

- With spec 02's harness, the positive-set report gains **band coverage: median over pairs ≥ 80%** (§6.7, "as in the
  first v2") on the 12 held-out VCTK speakers. A FAIL goes to CTO with the numbers; nothing is tuned on held-out
  clips.

## Defaults

- MFCC: 13 coefficients, 25 ms window, 10 ms hop, via Accelerate.
- PR CI runs the coverage metric only on the smoke set's VCTK items as a deterministic golden; the full held-out run
  is local or in the nightly once Raph wires the workflow (spec 02 lists it).

## Guardrails

- `AMWarp` imports `AMCore` and `AMPitch` only. No AppKit or UIKit.
- DTW output never feeds L1 or syllable data.

## Out of scope

- Measures and verdict (spec 10). The chart drawing (spec 20).

## Open question (built with the default)

None that needs Designer: "the pitch overlay breaking at gaps" is already a Designer display item in the plan (§12,
Designer item 7); this spec ships the data break, and the drawing waits for Designer's copy and display rules.

## How to test (Raph)

1. `make check` is green.
2. `swift test --package-path Packages/AccentKit --filter AMWarpTests` passes:
   - anchors map exactly and the map is monotone;
   - `toModel` is nil inside an insertion and `toYou` nil inside a missing word; 40 ms past the last mapped segment
     clamps, 60 ms returns nil;
   - playback for a missing word is nil on your side and a span on the model side; a loop slice with only a missing
     word plays the model only;
   - your pitch has a break at each gap;
   - DTW changes no syllable output and sets Rough;
   - the band is ±1.5 st with one take and P10–P90 with several, re-timed after a voice switch.
3. Optional, local: `scripts/agreement.sh --suite positive` prints band coverage with n, median and PASS / FAIL / NOT
   EVALUATED.

## Implementation notes

_(filled in by the agent)_
