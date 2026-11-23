# 10: Measures, verdict and diffs

Status: Ready · Branch: – · Depends on: 02 (harness), 08 (prominence), 09 (time map, band) · Estimate: 4–5 h agent
run + 1.5 h Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §1 (applicability, decision procedure, `close`), §3.3 (accepted-set placement rule), §5
(suppression), §6.7 (positive gates), §11 (final direction). Diff triggers, ranking and the 3-row cap are "as
before" from v1's thresholds table; confidence and suppression rows from the first v2 §5.

## Goal

In `AMScoring`: compute every measure as a `MeasureState`, apply suppression, trigger and rank diff rows, and
produce the `Verdict` through spec 01's decision procedure with real inputs. Turn on the positive-set gates.

## Behaviour

### Measures (applicability from spec 01, decided from the phrase and model only)

- **Placement** per word: spec 08's `placementDecision` against the contextual A(w). One placement row per phrase
  (the most prominent mismatch), with every mismatching word flagged in the data.
- **Contrast** C and **too much contrast**, from spec 08 over the matched S and U sets, the same sets for both
  speakers.
- **Weak length** W (raw durations).
- **Pitch range**: P10–P90 in st over comparable voiced frames.
- **Shape match**: Pearson r on comparable voiced frames on model time; `.unavailable(.tooFewOverlappingFrames)`
  below 20 overlapping frames, `.unavailable(.zeroVariance)` when either side is flat. Never 0 for "undefined".
- **Final direction** (§11): the final 200 ms of voiced frames ending at the last voiced frame of the take's
  comparable material, whatever the word class; needs ≥ 10 voiced frames, else extend back up to 300 ms, else
  `.unavailable` (`.notApplicable` on the model side). Last phrase word missing or substituted →
  `.unavailable(.wordMissing)`. Least-squares slope in st/s: rise ≥ +5, fall ≤ −5, else level.
- **nPVI**: inspector only, ≥ 3 syllables; never a diff.
- No voiced frames: pitch range, final direction and shape match are `.unavailable(.noVoicedFrames)`; `close` is
  impossible.
- Measure confidence (first v2 §5): contrast and weak length = share of S∪U syllables at medium or above (≥ 0.9
  high, ≥ 0.7 medium); pitch measures = voiced coverage of comparable frames (≥ 0.7 high, ≥ 0.5 medium); final
  direction = voiced frames in the window (≥ 15 high, ≥ 10 medium).

### Triggers (v1 table, rev 4.1 units)

- Placement: per §3.3 (outside A(w), high stress confidence, syllable ≥ medium).
- Contrast: yours < 0.7 × model's and model's ≥ 1.3.
- Too much contrast: yours > 2 × model's; lowest priority, shown only with fewer than 3 higher-priority rows.
- Weak length: yours ≥ 15 points above model's.
- Pitch range: yours < 0.6 × model's and ≥ 3 st narrower.
- Final direction: opposite, non-level directions.

### Suppression (§5)

- Placement: no diff for low stress confidence on either side, low syllable confidence, `expectedAmbiguous`, or a
  `referenceAnomaly` model.
- Contrast, weak length, too much contrast: no diff at low measure confidence.
- Pitch range, final direction, shape match: no diff and no `close` at low measure confidence.
- Poor timing: no stress, contrast or weak-length diffs; verdict `inconclusive(.timingUnreliable)`.

### Ranking and verdict

- Order: rough-timing row (first, counts toward 3, only when timing is Rough and at least one diff shows), then
  placement, contrast, weak length, pitch range, final direction, too much contrast (always last). Ties go to the
  larger relative gap. At most 3 rows (`BoundedRows`).
- Rows carry structured values only (`DiffRow`, spec 01). No sentences in `AMScoring`; copy is the app's.
- The verdict comes from spec 01's procedure. `partial` lists required applicable measures that are `.unavailable`.

### Goldens

Golden `AnalysisResult` JSON for fixture pairs built from replayed L1 data: placement mismatch ("photography", B vs
A), flat contrast (D vs A), over-stressed (too much contrast), `close` ("record", two syllables, placement only),
`feedback(partial: [.contrast])`, `inconclusive(.requiredMeasureUnavailable([.contrast]))`, a final-direction
diff ("Who did you give it to?": model falls over "it to" at about −8 st/s, you rise on "to" at about +7 st/s), and
"to" dropped → final direction `.unavailable(.wordMissing)`. Smoke-set goldens gain the verdict per item. The
golden digest and version rule from spec 01 apply.

### Gates going live (§6.7, positive set, 12 held-out VCTK speakers, ≥ 150 pairs)

- Any-diff pairs: point ≤ 5%, worst speaker ≤ 15%, worst phrase ≤ 30%.
- Placement-diff pairs: point ≤ 2%, worst speaker ≤ 7%.
- `inconclusive` pairs ≤ 10%.
- Evaluation coverage (evaluated ÷ applicable, per required measure) ≥ 90%.
- Tolerance rows: contrast ratio C_T/C_R within [0.7, 1.43] for 90%; weak length |Δ| ≤ 15 points; nPVI |Δ| ≤ 15;
  pitch range ratio ≥ 0.6 for 95%; band coverage median ≥ 80% (spec 09); final direction agreement ≥ 90%.
- `referenceAnomaly` rate reported; a phrase at ≥ 20% gets an override review.
- Output still prints `Negative set: NOT EVALUATED` and `Release gate: NOT MET` (spec 11 wires the L2 gates).
- These run on **initial, untuned** thresholds. A FAIL goes to CTO with the numbers; nothing is tuned on held-out
  speakers here (the fixed-grid fit is spec 11, on tuning data only).

## Defaults

- All values from `Thresholds` (spec 01). Vowel reduction, pitch range and final direction diffs each have an
  `enabled` flag in `Thresholds`, default on (Open question 1).
- PR CI runs the goldens and the smoke set. The full positive-set run is local or nightly (workflow listed in spec
  02, wired by Raph).

## Guardrails

- `AMScoring` imports `AMCore`, `AMProsody`, `AMWarp` only. No AppKit or UIKit.
- Banned words never appear in any `DiffRow` field that could reach the UI: prominence, F0, nPVI, z-score, lexical,
  nucleus (a test scans string fields).
- Never lower a gate or threshold to pass.

## Out of scope

- UI copy and display (Designer; app target, spec 21). Coordinator and persistence (specs 12, 16). The L2 gates,
  the end-to-end check and tuning (spec 11). Synthetic references (spec 22).

## Open question (built with the default)

1. **v1 "ship only if stable".** v1 says vowel reduction, pitch range and final direction ship only if the same
   speaker scores the same way on 3 takes in a row. Rev 4.1 doesn't restate it. Default: build all three behind
   `enabled` flags (on); spec 11 measures stability and turns a flag off if it fails. Product call stays with CPO.

## How to test (Raph)

1. `make check` is green, including every golden above and the smoke-set verdict goldens.
2. `swift test --package-path Packages/AccentKit --filter AMScoringTests` covers each suppression rule, the ranking
   order, "too much contrast" never displacing a higher row, the rough-timing row counting toward 3, shape match
   undefined below 20 frames, and slopes in st/s.
3. Local: `scripts/agreement.sh --suite positive` prints every positive gate with n, value, interval, worst speaker
   and worst phrase, plus `Negative set: NOT EVALUATED` and `Release gate: NOT MET`.

## Implementation notes

_(filled in by the agent)_
