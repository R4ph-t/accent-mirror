# 11: Stress validation and threshold tuning ("03b")

Status: Ready · Branch: – · Depends on: 02 (harness, folds, tuning API), 10 (verdict path), 12 (pipeline for
held-out pairs), 22 (synthetic references, end-to-end check ii) · Estimate: 6–8 h agent run + 2 h Raph review
· Risk: high

Risk: high. This spec changes `Packages/AccentKit/Sources/AMCore/Thresholds.swift` (a risky path) and
`docs/thresholds.md`. The PR waits for Raph's Merge OK whatever the review verdict says.

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §2 tuning protocol (fixed grid, selection rule, tuning pool, nested CV, shipped config), §6.1–6.3
(positive set, L2 shared-detector gate, end-to-end check), §6.5 (baselines), §6.6 (identity), §6.7 (gate table),
§7 row 11. CTO's spec 23 ruling (2026-11-23, relayed by Accent Mirror Lead): the timing-sensitivity control and the
decision rule for #27's b2 aligner. Spec 08's l2-shared numbers and spec 10's Open question 1.

## Goal

Replace the untuned initial thresholds with one shipped config chosen on tuning data only, then run every release
check once on held-out data and print the release gate. Today spec 08's detector flags **10.7%** of the clean
1,400 L2 words after suppression (150 of 1,400, Wilson [9.2%, 12.4%]), against a selection constraint of
**≤ 1.6%** and a gate of **≤ 2%**. This spec is where that gets fixed or goes back to CTO with numbers.

## Behaviour

### 1. Nested CV estimate (the L2 recall gate; measures the procedure)

- Speaker-grouped 5-fold nested CV over the **134 intelligible majority-label stress-wrong words (72 speakers)**,
  stratified by child/adult, fold seed from the split manifest. Inner step: the fixed-grid selection rule re-run
  from scratch on the other 4 folds' stress-wrong words, the train-half FP words of speakers not in this fold, and
  the VCTK tuning speakers. Every token of an outer-fold speaker is excluded from that fold's tuning (rev 4).
- Report pooled out-of-fold recall **after suppression** (the gate) and before suppression, the 5 per-fold configs
  and scores, adults (108 / 48) and children (26 / 24) separately, the per-speaker worst case, the ≥ 4-of-5
  diagnostic (42 words), and final-syllable recall separately (§2).
- Gate: point ≥ 80% (**≥ 108 / 134**) and Wilson lower bound ≥ 70%, plus the §6.5 baseline rule (B1/B2 detectors,
  paired McNemar output). Labelled "CV estimate of the tuning procedure", never as a held-out result.
- VCTK CV estimate: 6 speaker-disjoint outer folds over the VCTK tuning speakers, same rule, reported as
  "CV estimate, not shipped".

### 2. The shipped config (one fit, tuning data only)

- Run spec 02's fixed grid (weights on the simplex in 0.1 steps, each ≥ 0.1; λ ∈ {1.0 … 2.0}; τ_med and τ_high per
  n-bucket, 0.05 steps) **once on the whole tuning pool**: the VCTK tuning speakers, all 134 L2 stress-wrong words,
  and the 1,705 train-half unanimous-correct words. Selection rule (spec 02's `TuningSelectionRule`, unchanged):
  maximise recall subject to placement FP ≤ 1.6% on VCTK pairs, any-diff FP ≤ 4%, shared-detector FP ≤ 1.6%;
  tie-breaks lower FP, then synthetic which-syllable accuracy, then the point closest to the initial values.
- Write the chosen point into `Thresholds.swift` and `docs/thresholds.md`, bump `thresholdsVersion` to the next free
  integer (**7**: main is 6, #27 holds 5), append a new golden-digest record (never edit an old one), and add an
  entry to `docs/agreement/tuning-log.md` (date, commit, `configDigest` before and after, grid slice, chosen point,
  metrics, number of feasible points, why).
- If **no grid point is feasible**, nothing in `Thresholds.swift` changes. The PR reports the closest points (by
  constraint violation), and the result goes to CTO. Never widen the grid, relax a constraint, or lower a gate here.
- Test-half stress-correct words, held-out VCTK speakers and any synthetic or ElevenLabs audio never enter tuning.

### 3. One held-out check of the shipped config

Run once each, on the shipped config, with reports under `docs/agreement/reports/<suite>-<configDigest8>.{json,md}`
bound to `sourceTreeHash` and `configDigest` (§6.6):

- **VCTK positive set** (held-out speakers, ≥ 150 headline pairs, through spec 12's pipeline): every spec 10 gate
  (any-diff, placement-diff, inconclusive, evaluation coverage, tolerance rows, band coverage from spec 09) with n,
  value, intervals, worst speaker and worst phrase.
- **L2 shared-detector FP** after suppression on the **clean 1,400 words / 90 speakers** (primary): point ≤ 2%, worst
  speaker ≤ 10% (the 74 speakers with ≥ 10 words), upper bound, adults and children separately. The 1,868-word set
  is reported as supplementary. Whisper-substituted words are counted and listed on their own line (they never
  reach the detector).
- **Unintelligible words (157):** 0 placement diffs, every one inconclusive or unscored. One violation fails the
  release gate.
- **End-to-end check (ii)** (spec 22's path): in each outer fold both paths run with the same fold-trained config;
  pooled end-to-end recall within 10 pp of pooled shared-detector recall; end-to-end FP ≤ 2% on the clean 1,400
  with the shipped config. The report header carries `syntheticReference: elevenlabs | mac-premium-fallback
  (reason)`, and fallback metrics are labelled.
- **Synthetic set** (secondary): which-syllable accuracy ≥ 80% plus the §6.5 rule; controls ≤ 2% diffs.
- **`referenceAnomaly` rate** per phrase; a phrase at ≥ 20% is listed for an override review.

### 4. CTO's timing-sensitivity control (required, reported)

On the synthetic set, run the verdict diff between two good references, **TTS markers vs MFA** (about 25 ms apart),
on the tuned thresholds, and print it next to spec 23's limits (≤ 2% of words change verdict; inconclusive rate
rises ≤ 2 points). Also print it on the initial thresholds, so the effect of tuning is visible. Break the flips down
by cue (duration, intensity, pitch), by syllable count, by transition type (feedback↔close vs anything↔inconclusive)
and by the word's own boundary error; Whisper-substituted words are counted separately and kept out of the diff.
This spec does not touch #27 or b2. It publishes the tuned thresholds and the control so CTO's rule can be applied:
control > 2% → spec 23's gate re-runs on these tuned thresholds; control ≤ 2% and b2 still > 2% → b2 is reworked.

### 5. Stability of the three optional diffs (spec 10 Open question 1)

Report, for weak length, pitch range and final direction, whether the same speaker gets the same diff on repeated
takes, wherever the data has repeated takes of one phrase by one speaker. See Open question 2.

### 6. Output

`scripts/agreement.sh --suite release` prints every row of the §6.7 table with n, value, gate and PASS / FAIL /
NOT EVALUATED (n=…, min=…), then `Negative set: …`, `Positive set: …` and `Release gate: MET | NOT MET`. PR CI keeps
running the smoke set; its goldens are re-recorded for the new `thresholdsVersion`.

## Defaults

- Tuning runs locally (`scripts/tune.sh`, the existing script) on cached L1 features, never in PR CI. The full
  release run is local or nightly; the nightly workflow is listed in the PR for Raph to add (agents don't edit
  `.github/`).
- The aligner is the one on main (Whisper word spans with the padding and segmenter of specs 03 and 07). Its ID is
  in the report identity. b2 is not used.
- Speaker counts are floors (≥ 18 tuning, ≥ 12 held-out); the manifest's actual counts (24 / 16) are used and printed.

## Guardrails

- Never lower a gate, a tolerance or a minimum, and never relax the selection rule's constraints. A FAIL goes to CTO
  with the numbers.
- NOT EVALUATED is never a pass and never a waiver.
- No held-out VCTK speaker, test-half L2 word or synthetic audio in any tuning step (a test asserts the tuning pool's
  speaker set is disjoint from every held-out set).
- No network at runtime; corpora come from the existing pinned fetchers and caches.

## Out of scope

- Reworking or shipping b2 (spec 23). UI copy. Making the release itself (Raph). Adding a French-L1 gate (not in v1).

## Open question (built with the default)

1. **Does spec 11 count as Done if the release gate is NOT MET?** Default: yes. Spec 11 is Done when its tuned
   config (or the "no feasible point" report) and its release report merge. The release gate result is printed, not
   required to pass: it blocks a release, not later specs. Specs 21 and later build on whatever config is on main.
2. **3-take stability** (v1: "ship only if the same speaker scores the same way on 3 takes in a row"). VCTK and
   speechocean762 have one take per speaker per phrase, so there may be no repeated takes. Default: the flags stay
   on, stability prints NOT EVALUATED (no repeated takes) with the reason, and the call goes to CPO. Never turn a
   flag off without a measurement.

## How to test (Raph)

1. `make check` is green, including the re-recorded smoke goldens and the golden-digest check for the new
   `thresholdsVersion`.
2. Read the diff of `Thresholds.swift` and `docs/thresholds.md`: only the tuned keys change, `thresholdsVersion` is 7,
   and `docs/agreement/tuning-log.md` has one new entry naming the grid slice and the chosen point.
3. `scripts/agreement.sh --suite release` (local) prints every §6.7 row and ends with `Release gate: MET` or
   `NOT MET`. The clean-1,400 FP line shows the new value next to the old 10.7%.
4. The timing-sensitivity control prints on both initial and tuned thresholds with the per-cue breakdown.
5. The committed reports' `sourceTreeHash` and `configDigest` match the PR head (`scripts/check-report-identity.sh`).

## Implementation notes

_(filled in by the agent)_
