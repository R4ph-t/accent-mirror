# 11: Stress validation and threshold tuning ("03b")

Status: Ready · Branch: – · Depends on: 02 (harness, folds, tuning API), 10 (verdict path), 12 (pipeline for
held-out pairs), 22 (synthetic references, end-to-end check ii; spec 23's harness and b2 for the re-run gate, 23 in
review; Done only when the analysis gate in §7 passes) · Estimate: 9–12 h agent run + 2.5 h Raph review
· Risk: high

Risk: high. This spec changes `Packages/AccentKit/Sources/AMCore/Thresholds.swift` (a risky path) and
`docs/thresholds.md`. The PR waits for Raph's Merge OK whatever the review verdict says.

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §2 tuning protocol (fixed grid, selection rule, tuning pool, nested CV, shipped config), §6.1–6.3
(positive set, L2 shared-detector gate, end-to-end check), §6.5 (baselines), §6.6 (identity), §6.7 (gate table),
§7 row 11. CTO's spec 23 ruling (2026-11-23, relayed by Accent Mirror Lead): the timing-sensitivity control and the
decision rule for #27's b2 aligner. Spec 08's l2-shared numbers and spec 10's Open question 1. Spec 23's diagnostic
report (`docs/agreement/reports/word-boundaries-diagnostics-2026-11-23.md`, on branch
`factory/23-word-boundary-refinement`): control 13.7% (> 2%), so CTO's rule's first branch applies. CTO's additions
of 2026-11-23 (relayed by Accent Mirror Lead): the b2 gate re-run, the jitter test, the anti-inconclusive guard and
the pre-declared fallback (§4–§4c below).

## Goal

Replace the untuned initial thresholds with one shipped config chosen on tuning data only, then run every release
check once on held-out data and print the release gate. Because spec 23's control came back at 13.7%, this spec
also re-runs spec 23's downstream gate (b2 vs oracle) on the tuned thresholds, and it only passes under CTO's
anti-inconclusive guard; otherwise it records the pre-declared fallback for CTO. Today spec 08's detector flags **10.7%** of the clean
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
Spec 23's diagnostic gives the baseline to print alongside: 13.7% (42 / 307) on the initial thresholds, with 2–3
syllable words flipping far more than monosyllables (control 43.1% / 66.7% vs 3.4%).

### 4a. Spec 23's downstream gate, re-run on the tuned thresholds (CTO's rule, first branch)

- Re-run spec 23's `DownstreamHarness` unchanged (same segmenter, `WordVerdict`, sets and comparability rules), with
  only the thresholds swapped for the tuned ones: **b2 (`ctc-w2v2b960-1`) vs oracle** (TTS markers on the synthetic
  set; MFA on the **held-out** VCTK speakers). Limits as in spec 23: verdicts differ on **≤ 2%** of comparable words
  **and** the inconclusive rate under b2 is **≤ 2 points** above the oracle's, checked separately per set. Print the
  initial-threshold numbers next to them (spec 23's 22.5% / 22.5%, +11.1 / +10.2 points).
- Same breakdowns as spec 23's report §3–§4: cue, syllable count (1, 2, 3, 4+), transition type, boundary-error bin,
  and the inconclusive rise split into confidence gate vs margins (spec 23 found almost all of it from the margins).
- A FAIL goes back to CTO. This spec never reworks, retunes or ships b2, and nothing is chosen on held-out data.
- If spec 23's harness and b2 aren't on main when this spec runs, the rows print NOT EVALUATED (spec 23 not merged)
  and the guard below is NOT MET; that goes to CTO too.

### 4b. Aligner-independent jitter test

- Take the oracle word boundaries (TTS markers on the synthetic set; MFA on VCTK), move **both edges** of each word by
  a random offset drawn uniformly from ±20, ±40 and ±80 ms (three runs, fixed seed from the split manifest, edges
  clamped to the neighbouring words and the clip), and re-run the same segmenter and verdict on the tuned thresholds
  (and the initial ones, for comparison).
- Report the verdict flip rate against the unjittered oracle by syllable count (**1, 2, 3, 4+**), per set, with n and
  Wilson intervals, plus the inconclusive rise per bucket. **Target: ≤ 2% flips at ±40 ms**, printed as MET / NOT
  MET. It measures how much syllable verdicts depend on exact word edges, whatever the aligner.

### 4c. Anti-inconclusive guard and the pre-declared fallback

- **Spec 11 passes only if**, on the tuned thresholds:
  1. the TTS-vs-MFA control (§4) is **≤ 2%**;
  2. the inconclusive rate stays inside the **≤ 10% budget** (`agreement.inconclusivePairsMax`);
  3. the b2 gate (§4a) meets **both** ≤ 2% verdict flips and ≤ 2 points of inconclusive rise.
- **Gaming guard:** a point that gets to ≤ 2% flips by sending 2–3-syllable words to inconclusive doesn't count. In
  each syllable-count bucket (2 and 3 separately), the inconclusive rate may rise at most 2 points over the oracle
  (Open question 4). Flips are counted with anything↔inconclusive transitions included, never excluded.
- During tuning (§2), a grid point is **feasible** only if it also meets the guard on tuning data: b2 vs MFA and the
  jitter test on the VCTK tuning speakers, plus the 10% budget. The synthetic-set control isn't tuning data, so it is
  checked only on the shipped config (Open question 5).
- **Pre-declared fallback.** If no grid point is feasible under the guard, or the shipped config fails the guard on
  held-out data, **stop tuning**: `Thresholds.swift` doesn't change, there's no retuning and no constraint is relaxed.
  The report and `docs/agreement/tuning-log.md` record the outcome "FALLBACK: nucleus-anchored syllable segmentation
  needed", with the closest points and the §4–§4b numbers, and the PR says it goes to CTO first. That later spec
  (not started here) would find vowel nuclei from intensity and voicing peaks inside the word, or from phone-level
  CTC once b2 is in, so syllable spans stop depending on exact word edges. It would be gated on §4b's jitter test and
  would then re-run spec 23's gate. CTO's reasoning, recorded verbatim in the entry: multi-syllable splits come from
  the word edges, so boundary error moves duration and intensity between syllables, which margins alone can't fix.

### 5. Stability of the three optional diffs (spec 10 Open question 1)

Report, for weak length, pitch range and final direction, whether the same speaker gets the same diff on repeated
takes, wherever the data has repeated takes of one phrase by one speaker. See Open question 2.

### 6. Output

`scripts/agreement.sh --suite release` prints every row of the §6.7 table with n, value, gate and PASS / FAIL /
NOT EVALUATED (n=…, min=…), then the §4–§4b rows, `Negative set: …`, `Positive set: …`, `Spec 11 guard: MET | NOT MET
(FALLBACK)` and `Release gate: MET | NOT MET`. PR CI keeps
running the smoke set; its goldens are re-recorded for the new `thresholdsVersion`.

### 7. Analysis gate: the build proves it, CI enforces it (Raph, 2026-11-24)

Raph, 09:08: validate the principles and core workings of the audio analysis before more UI work; 09:09: the
validation runs through the factory, with no hand runs. Specs 20 and 21 depend on this row, so this spec is Done
only when the analysis is proven on real voices.

- **The build runs the release suite itself.** On the Mac, the agent fetches what's missing with the existing pinned
  fetchers (`scripts/fetch-vctk.sh`, `fetch-vctk-eval.sh`, `fetch-speechocean762.sh`, `setup-mfa.sh`,
  `mfa-align.sh`), records any missing word timings with `am-eval record-timings`, runs `scripts/tune.sh` and then
  `scripts/agreement.sh --suite release`, and commits the report as
  `docs/agreement/reports/release-<configDigest8>.{json,md}` (§6.6 identity). Nothing here is left for Raph to run.
  A fetch, record or run failure is the build's to fix, or to report as `Blocked:` with what it tried.
- **The report covers all three dimensions on real voices** (held-out VCTK positive set through spec 12's
  pipeline): stress (placement-diff, contrast ratio), rhythm (nPVI, weak length, spec 09 band coverage) and pitch
  (pitch range ratio, final direction), plus any-diff, inconclusive and evaluation coverage. Each row has n ≥ 150
  measured pairs. The L2 rows (§1 CV recall, §3 clean-1,400 FP and worst speaker, unintelligible words) and the
  §4c guard are in the same report.
- **`AnalysisGateTests`** (new, in `AMEvaluationTests`; runs under `make test`, so CI's `build & test` check runs it
  on every PR). It finds the repo root from `#filePath`, computes `configDigest` from `Thresholds` on the head
  (AMCore `Identity`), loads `release-<configDigest8>.json`, and fails unless:
  1. the report exists and its `configDigest` equals the computed one (a stale or hand-edited report fails);
  2. every positive-set gate row reads PASS, none FAIL or NOT EVALUATED, and the rows named above are all present
     (a missing row fails, so a dimension can't drop out silently);
  3. every negative-set (L2) gate row reads PASS;
  4. `Spec 11 guard` reads MET.
  Reported-only lines (synthetic set, end-to-end check ii, `referenceAnomaly`, 3-take stability, §4b jitter) are
  printed and not asserted.
- **If the gates don't pass, CI stays red and the PR doesn't merge**, so this row isn't Done and 20 and 21 stay
  blocked. That includes FALLBACK (§4c) and spec 23 not being on main (§4a). The PR still commits the report and
  says it goes to CTO. Fix rounds may fix bugs in the pipeline or the harness, never a gate, a tolerance, a
  minimum, the selection rule, the test's conditions or the report.
- The test applies from this PR on: a later PR that changes `Thresholds` must commit a new release report that
  passes, the same "never quietly" rule as the golden digest.

## Defaults

- Tuning runs locally (`scripts/tune.sh`, the existing script) on cached L1 features, never in PR CI. The full
  release run is local or nightly; the nightly workflow is listed in the PR for Raph to add (agents don't edit
  `.github/`).
- The aligner is the one on main (Whisper word spans with the padding and segmenter of specs 03 and 07). Its ID is
  in the report identity. b2 is used only inside §4a's evaluation gate and the guard; it doesn't ship here.
- Speaker counts are floors (≥ 18 tuning, ≥ 12 held-out); the manifest's actual counts (24 / 16) are used and printed.

## Guardrails

- Never lower a gate, a tolerance or a minimum, and never relax the selection rule's constraints. A FAIL goes to CTO
  with the numbers.
- NOT EVALUATED is never a pass and never a waiver, and `AnalysisGateTests` treats it as a failure.
- No held-out VCTK speaker, test-half L2 word or synthetic audio in any tuning step (a test asserts the tuning pool's
  speaker set is disjoint from every held-out set).
- No network at runtime; corpora come from the existing pinned fetchers and caches.

## Out of scope

- Reworking or shipping b2 (spec 23). Writing or starting the nucleus-anchored segmentation spec (CTO first). UI
  copy. Making the release itself (Raph). Adding a French-L1 gate (not in v1).

## Open question (built with the default)

1. **Does spec 11 count as Done if the gates or the guard are NOT MET?** Decided (Raph, 2026-11-24): no. Spec 11
   is Done only when §7's analysis gate passes (positive set and L2 gates PASS, guard MET), enforced by
   `AnalysisGateTests` in CI. FALLBACK or a FAIL keeps the PR open with its report, for CTO. The full release gate
   (§6.7, including the reported-only lines) still blocks a release, not later specs.
2. **3-take stability** (v1: "ship only if the same speaker scores the same way on 3 takes in a row"). VCTK and
   speechocean762 have one take per speaker per phrase, so there may be no repeated takes. Default: the flags stay
   on, stability prints NOT EVALUATED (no repeated takes) with the reason, and the call goes to CPO. Never turn a
   flag off without a measurement.
3. **Is the jitter target part of the guard?** CTO's guard lists three conditions and doesn't name it. Default: §4b
   prints MET / NOT MET and feeds the tuning-side feasibility check, but the held-out pass is the three conditions.
4. **How "sending 2–3-syllable words to inconclusive" is measured.** Default: ≤ 2 points of inconclusive rise over the
   oracle in the 2-syllable and 3-syllable buckets separately, on top of spec 23's overall ≤ 2-point limit.
5. **The synthetic-set control during tuning.** The plan keeps synthetic audio out of tuning (rev 4). Default: the
   control is checked on the shipped config only, never per grid point; if it fails, that's the FALLBACK.

## How to test (Raph)

Every step below is run by the build agent and repeated by the reviewer. None needs Raph's hands for the spec to
be Done.

1. `make check` is green, including the re-recorded smoke goldens and the golden-digest check for the new
   `thresholdsVersion`.
2. Read the diff of `Thresholds.swift` and `docs/thresholds.md`: only the tuned keys change, `thresholdsVersion` is 7,
   and `docs/agreement/tuning-log.md` has one new entry naming the grid slice and the chosen point.
3. `scripts/agreement.sh --suite release` (local) prints every §6.7 row and ends with `Release gate: MET` or
   `NOT MET`. The clean-1,400 FP line shows the new value next to the old 10.7%.
4. The timing-sensitivity control prints on both initial and tuned thresholds with the per-cue breakdown, next to
   spec 23's 13.7%. The b2-vs-oracle gate prints for both sets with its breakdowns. The jitter table prints ±20 /
   ±40 / ±80 ms by syllable count, and running it twice gives identical numbers (fixed seed).
5. The output ends with `Spec 11 guard: MET` or `NOT MET (FALLBACK)`. On FALLBACK, `Thresholds.swift` is unchanged
   and the tuning log has the nucleus-anchored entry, marked for CTO.
6. The committed reports' `sourceTreeHash` and `configDigest` match the PR head (`scripts/check-report-identity.sh`).
7. `swift test --package-path Packages/AccentKit --filter AnalysisGateTests` passes on the head (CI's `build & test`
   runs it too), and it fails if one positive-set row in a copy of the report is changed to NOT EVALUATED.

## Implementation notes

_(filled in by the agent)_
