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
- **No longer blocked on spec 24.** Every gate in this list consumes spec 02's positive-set result through spec 02's
  `PositiveSetGates.line`. They were blocked on spec 24 (CTO ruling, 2026-11-23 14:18). Spec 24 merged in #35
  (6f69934), and the set is now EVALUABLE (20 phrases from 17 distinct source prompts, 274 headline pairs, 16
  held-out speakers), so the gates evaluate. A gate with too few measured pairs still prints NOT EVALUATED, which is
  never a pass and never a waiver. If the set ever falls short again, the gates go back to NOT EVALUATED (blocked).
  The release gate stays NOT MET until spec 11. "12 held-out" is a floor (≥ 12; the manifest records the actual count).

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

Built by hand on 2026-11-23 (Claude Code, Opus) on `factory/10-measures-verdict-diffs`, merged with main after spec 24
(#35) and the docs PR (#39). The positive set reads EVALUABLE (20 phrases, 274 headline pairs, 16 held-out speakers).

**Layout.** `AMScoring` (imports AMCore, AMProsody, AMWarp only): `ScoringInput.swift` (phrase words with A(w), both
takes' L1 data, alignment, time map), `StressMeasures.swift` (placement, the contrast group, nPVI, `WordPlacement`,
`ScoringSuppression`), `PitchMeasures.swift` (pitch range, shape match, `FinalWindow`, `PitchDirection`) and
`Scorer.swift` (`Scorer.score` → `Scoring`: applicability, `MeasureAssessments`, model-side values, placements, stress
lines, ranked rows, `decide`). `AMPipeline/PairScoring.swift` feeds it from two `StressPlacementDetector` analyses
(`PlacementAnalysis` now carries its alignment and pitch track). `AMEvaluation/PositiveGates.swift` measures spec 10's
gates from `PairOutcome`s. AMCore types and `decide` are unchanged.

**Thresholds.** `diffs.weakLengthEnabled`, `.pitchRangeEnabled` and `.finalDirectionEnabled` were added (Bool, on;
Open question 1), mirrored in `docs/thresholds.md` as `1`. `thresholdsVersion` 4 → 6 (spec 23 holds 5), with a golden
digest appended for (1, 6, 1). No existing value changed. `contractVersion` is unchanged.

**Measures.**
- *Comparable set:* prominence for both takes is computed over the syllables of the words present in your take, so
  your P and the model's are measured over the same material.
- *Placement:* spec 08's `placementDecision` on every eligible word (target or content, 2 or more syllables, not
  `expectedAmbiguous`). On top of the rule, suppression runs in this order: Poor timing, `referenceAnomaly`, the model's
  stress confidence low, then the rule's own reasons. The state is the reported word's margin (the flagged word with
  the largest margin, else the least certain decided word), at the lowest stress confidence over the decided words.
- *Contrast group:* S and U come per word from the pattern your primary matched, else the context pronunciation,
  pooled over the phrase. Only syllables both takes have count, and the model uses the same sets. Confidence is the
  lower of the two takes' S∪U shares. W is in points.
- *Pitch:* comparable frames are the model's voiced frames in comparable model time. Coverage is the share of them
  where your on-model frame is voiced too. P10–P90 uses the band's percentile.
- *Shape match:* Pearson r over the frames voiced on both sides. Fewer than 20 → `.tooFewOverlappingFrames`; a flat
  side → `.zeroVariance`.
- *Final direction:* each take on its own timeline, over its present words: voiced frames within 200 ms of the last
  voiced frame, else 300 ms. The slope is least squares in st/s. The model's window also feeds applicability.
- *nPVI:* over your comparable syllables in time order, at the contrast-share confidence.

**Diffs and verdict.** Triggers follow the v1 table, with each `enabled` flag gating its diff (the measure is still
computed). Each kind gives at most one row. `Scorer.rank` sorts by `DiffKind`, then the larger relative gap. `decide`
adds the rough-timing row and caps at 3, so too much contrast can never displace a higher row. Rows carry only
structured values. A test scans every row's JSON for the banned words.

**Goldens.** Eight `AnalysisResult` files live under `Tests/AMCoreTests/Golden/scoring/`, so spec 01's digest covers
them. They are built from replayed L1 data (spec 08's worked examples A, B and D, plus "record", "I love photography"
and "Who did you give it to?"). Verdicts:
- placement B vs A: `feedback([placement, contrast, weakLength])`;
- flat D vs A: `feedback([contrast, weakLength, pitchRange])`;
- over-stressed: `feedback([tooMuchContrast])`;
- "record": `close`;
- `feedback([roughTiming, placement], partial: [.contrast])`;
- `inconclusive(.requiredMeasureUnavailable([.contrast]))`;
- final direction: model −8.0 st/s, you +7.0 st/s → `feedback([finalDirection])`;
- "to" dropped: final direction `.unavailable(.wordMissing)` → `noClearDifference`.

To re-record: `AM_RECORD_GOLDEN=1 swift test --filter "recordGolden|recordScoringGolden"`.

**Smoke verdicts** (`fixtures/smoke/detector/goldens.json`, `am-eval smoke-detector --record`). Each VCTK item is
scored against the first other smoke speaker of its phrase whose take has every word present (p288_018 skips p245,
whose take misses word 1). The speechocean762 items have no native take, so they have no verdict. Results with initial
thresholds:
- the three phrase 002 items: `inconclusive(noApplicableStressMeasure)` (all monosyllables, |U| = 1);
- p245_018 vs p288: `feedback([roughTiming, pitchRange], partial: [.contrast])` (you 2.30 st against 5.31 st);
- p288_018 and p360_018: `noClearDifference`.

The smoke set is never a rate gate, but the pitch-range row on a native pair is a false positive at untuned
thresholds, for spec 11 and CTO.

**Gates.** `PositiveSetGates.dependents` gains the tolerance rows. Each spec 10 line is built only through
`PositiveSetGates.line`. While the positive set is short it reads NOT EVALUATED (blocked); with the set evaluable but
fewer than 150 measured pairs, it reads NOT EVALUATED (n, min 150). It is never a pass. `referenceAnomaly` is a
reported line (worst phrase, with the phrases due an override review) and is kept out of the release gate.
`am-eval suite --suite positive` prints n, value, gate, intervals, worst speaker and worst phrase for every line. No
held-out pair is measured yet: that needs the pipeline (spec 12) to analyse held-out takes, so every line is
NOT EVALUATED (n=0, min=150), and the output ends `Negative set: NOT EVALUATED`, `Positive set: EVALUABLE`,
`Release gate: NOT MET`.

**Choices the spec left open (least-committal; listed as spec gaps in the PR).**
1. *Low measure confidence → `.unavailable(.lowConfidence)`* for the contrast group, pitch measures, final direction
   and nPVI. This follows spec 01's example 5, and it is the only way the spec's `partial: [.contrast]` and
   `requiredMeasureUnavailable([.contrast])` goldens can arise. Placement stays evaluated at its (possibly low) stress
   confidence; its diff is suppressed.
2. *The contrast group reports as `.contrast`* in `partial` and `requiredMeasureUnavailable` (spec 01 gap 1). The
   three share one S∪U evidence and go unavailable together. AMScoring collapses the list after `decide`, so AMCore is
   untouched; `mediumConfidenceOnly` still lists each kind.
3. *Pitch coverage* is measured against the model's voiced comparable frames, not every comparable frame.
4. *Weak length and nPVI tolerances* name no share, so the gate is the largest |Δ| over pairs (every pair within 15).
   This is the literal reading and the strictest; CTO may set a share.
5. *Evaluation coverage* is one line whose value is the lowest required measure's evaluated ÷ applicable; each
   measure is printed too.
6. *Inconclusive pairs* count `inconclusive` verdicts only; a take problem counts in n but in neither rate.
7. *`DiffRow.syllables`* for placement are model syllable indices: accepted, then heard. Phrase-level rows have none.
   The final-direction row names the last phrase word.
