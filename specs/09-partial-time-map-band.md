# 09: Partial time map and native band

Status: Done · Branch: factory/09-partial-time-map-band · Depends on: 02 (harness), 04 (pitch), 07 (syllables) · Estimate: 3–4 h agent run + 1 h
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
- **This gate consumes the positive-set result through spec 02's `PositiveSetGates.line`.** It was blocked on spec
  24 (CTO ruling, 2026-11-23 14:18). Spec 24 merged in #35 (6f69934): the set is now EVALUABLE (20 phrases from 17
  distinct source prompts, 274 headline pairs, 16 held-out speakers), so the gate evaluates once held-out pairs are
  measured (that needs spec 12's pipeline). Until then it prints NOT EVALUATED (n below the minimum). NOT EVALUATED
  is never a pass and never a waiver, and if the set ever falls short again the line goes back to NOT EVALUATED
  (blocked). The smoke-set golden below isn't affected. "12 held-out" is a floor (≥ 12; the manifest records the
  actual count).

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

Built by hand in Claude Code (Opus), 2026-11-23. No threshold, version or golden-digest change: the spec names no new
`Thresholds` value, so the 50 ms end clamp, the MFCC sizes and the 100-row cancellation stride are algorithm constants in
`AMWarp`, like spec 04's octave-repair constants. AMCore types are unchanged.

- **`TimeWarp`** (`AMWarp/TimeWarp.swift`) builds the map from `WordAlignment`, the model's `TimedWord`s and yours, in
  alignment order. A present word is `mapped` and comparable, with anchors at every syllable boundary when both sides
  have the same syllable count (word edges otherwise). A substituted word is `mapped` and not comparable, with anchors
  at its edges. A missing word is `modelOnly` and an inserted one is `youOnly`. Overlapping spans are clamped so
  spec 01's validation always passes. `comparableCoverage` = present words' model syllables ÷ all model syllables.
- **Lookups.** `toModel` and `toYou` are piecewise-linear between knots (segment edges plus anchors). Pauses between
  two mapped words with nothing between them map linearly. A pause next to a missing or inserted word is nil, so it
  is never bridged. Past the first or last mapped segment they clamp for up to 50 ms, then return nil.
  `playbackRange(word:speaker:)` takes the `AlignedWordPair`, so an insertion is addressable.
  `loopPlayback(modelSlice:)` joins neighbouring mapped words and never joins across a gap.
- **Pitch on model time** (`pitchOnModel`) samples your frame under each 10 ms model cell. It breaks wherever
  `toYou` is nil, where a gap lies between two cells, and wherever your own line breaks (pauses over 250 ms).
  `isComparable(modelTime:)` is true only inside present-word segments, so comparable-frame measures skip gaps.
- **DTW** (`AMWarp/DTW.swift`): 13 MFCCs plus log-energy (25 ms Hamming window, 10 ms hop, 26 HTK mel filters,
  pre-emphasis 0.97, per-take mean normalisation) through vDSP. Distances come from one matrix product. It runs only
  in mapped segments whose anchor timing is Poor on either side. The path is stored in `refinements`, separately from
  the anchors, so the map, anchors, comparable coverage and confidences are unchanged. Take timing is capped at Rough
  (Good → Rough). `Task.checkCancellation()` runs every 100 rows. Benchmark: 36 ms alone and 68 ms best of 5 under the
  full parallel suite (debug build), against the 150 ms budget.
- **`NativeBand`**: per frame of the selected voice, P10–P90 (linear-interpolated percentiles) across the selected
  take and every other take warped onto it with `pitchOnModel`; ±1.5 st with one take. `nativeSetHash` = SHA-256 of
  the sorted take SHA-256s, one per line. Building throws `testTakeInNativeSet` when the test take is a native take.
  `coverage(of:warp:)` = share of your comparable voiced frames inside the band; a frame with no band point counts
  as outside.
- **Gate.** `BandCoverageGate` (AMEvaluation) gives the median over pairs against `agreement.bandCoverageMedianMin`,
  with the worst speaker. It is NOT EVALUATED below `agreement.positiveMinPairs`, and its line is built only by
  `PositiveSetGates.line`. Today it prints `NOT EVALUATED (blocked on spec 24: phrases 15 < 18)`. `am-eval suite
  --suite positive` prints n and the value for every positive-set line. No held-out pair is measured yet: that needs
  each held-out take's word timings and syllables, which the pipeline (spec 12) produces.
- **Smoke golden** (`AMWarpTests/SmokeBandCoverageGolden.swift`): the whole path (pYIN, MFCC, DTW, band, coverage)
  runs on the smoke set's six VCTK clips and is checked against values rounded to 4 decimals. It is a regression
  golden only, not a gate. The smoke set has only tuning-split clips (p245, p288 and p360 are `tuning` in
  `fixtures/vctk/eval-speakers.json`, none held-out) and no word timings, so each pair uses one Poor
  segment over the voiced span, and its band comes from the other two smoke speakers of the phrase.

Gaps, built least-committal: (1) Poor anchors are judged per word, from spec 07's timing on each side. (2) "Sets
timing to Rough" is read as a cap: Good → Rough, and Poor stays Poor, because DTW never raises a confidence.
(3) A band frame that only one take covers gets ±1.5 st around that take. (4) The smoke golden's band voices are
the other tuning-split smoke speakers (never the test speaker), which the split allows, because the smoke set has no
bundled takes, and adding 16 bundled clips would break its 5 MB cap.
