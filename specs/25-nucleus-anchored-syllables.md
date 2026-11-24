# 25: Nucleus-anchored syllable measurement (spec 11's FALLBACK)

Status: Ready · Branch: factory/25-nucleus-anchored (hand build) · Depends on: 07 (segmenter, syllable counts), 08 (prominence), 12 (pipeline, caches), 23
(`DownstreamHarness`, b2, oracle sets) (also spec 11's FALLBACK report and harness: see Open question 1) · Estimate:
6–8 h agent run + 1.5 h Raph review · Risk: high

Risk: high. This spec adds keys to `Packages/AccentKit/Sources/AMCore/Thresholds.swift` (a risky path) and bumps
`thresholdsVersion` and `algorithmVersion`. CTO approved this spec on 2026-11-24 at 15:04 Europe/Paris with four
markups (folded in below). **The implementation PR goes to CTO for an engine and threshold review before it merges**,
whatever the review verdict line says.

Source: CTO's ruling on spec 11 (2026-11-24 14:59 Europe/Paris, relayed by Accent Mirror Lead): the ±40 ms jitter
row (8.1% synthetic, 11.6% VCTK, on oracle boundaries, so independent of the aligner) and the 13.7% TTS-vs-MFA
control show the verdict stage is too sensitive to word boundaries, so no word-boundary aligner can pass ≤ 2% at
±40 ms. The answer is spec 11 §4c's pre-declared FALLBACK, "nucleus-anchored syllable segmentation". CTO's earlier
reasoning (spec 11 §4c, verbatim there): multi-syllable splits come from the word edges, so boundary error moves
duration and intensity between syllables, which margins alone can't fix. Spec 23's diagnostics (CTO's figures) give each
group's **own** flip rate: 2-syllable words 69% (synthetic) / 55% (VCTK), 3-syllable words 87% / 88%, monosyllables
6.4% / 9.6%. These are per-group rates, not shares of all flips.

## Goal

Measure each syllable's stress features (duration, intensity, f0) from a window around its **vowel nucleus**, found
from the take's energy envelope and voicing, instead of from a slice of the word span. Word edges only decide which
nucleus belongs to which word. Then prove, on oracle boundaries and before any aligner comparison, that verdicts no
longer move when word edges move: **≤ 2% flips at ±40 ms**, pooled and per multi-syllable group (n ≥ 30), on both
sets. No gate is loosened and nothing is cut from scope here.

## Behaviour

### 1. Nucleus detection (whole take, no word edges)

Runs once per take on the samples, before and independent of any word boundary, so moving a word edge can't change
it.

- **Energy envelope.** 10 ms hop, 25 ms window (aligned with spec 04's frames). Band-limited RMS over 300–2,500 Hz
  (the vowel formant region, so fricatives and low-frequency hum weigh less), in dB, smoothed with a 50 ms moving
  average (zero-phase).
- **Voicing.** Spec 04's `PYINTracker` voicing probability per frame (the pitch tracker on main, no new tracker). A
  frame is voiced at ≥ 0.5, as in spec 04.
- **Peak picking.** A nucleus candidate is a local maximum of the smoothed envelope that is voiced, at least
  `nucleus.minPeakDBFS` (initial −45 dBFS), and has a **prominence** (dB above the higher of the two minima separating
  it from its neighbouring candidates) of at least `nucleus.minProminenceDB` (initial 3 dB, the same value as spec
  07's `splitValleyMinDB`). Candidates closer than `nucleus.minSeparationMs` (initial 70 ms) are merged, keeping the
  higher one. Output: `Nucleus` (peak time, peak dB, prominence dB, left and right valley times, voiced run).
- **Nucleus region.** From the peak, the contiguous voiced frames whose envelope is within `nucleus.regionDropDB`
  (initial 6 dB) of the peak, never past the valley to a neighbouring nucleus.

### 2. Assigning nuclei to words and syllables

- Input: the ordered nuclei, the ordered `present` words with their spans (`SyllableSegmenter.WordSpan`) and their
  dictionary syllable counts N_w (spec 06, CMUdict with overrides).
- **Monotonic assignment.** A dynamic program over the two ordered sequences gives each word exactly N_w consecutive
  nuclei, or marks it short. Cost of putting a nucleus in a word: the distance in ms by which its peak lies outside
  the word's unpadded span (0 inside). Skipping a nucleus (an extra peak, e.g. a filled pause or an epenthetic
  vowel) costs `nucleus.skipCostMs` (initial 60 ms). A nucleus further than spec 07's padding (`alignment.asrPaddingMs`,
  about 80 ms) outside a word's span can't be assigned to it. Ties go to the earlier word. Word edges therefore act
  only as soft anchors: a ±40 ms edge move changes the assignment only for a peak within about 40 ms of a boundary.
- The k-th assigned nucleus of a word is its k-th syllable's nucleus. `substituted` words get no nuclei (as in spec
  07), and their nuclei are skipped.
- **Count mismatch (CTO markup 1).** P is counted from the DP assignment, not from raw candidates in the padded
  window: P is the number of nuclei between the previous word's last assigned nucleus and the next word's first
  assigned nucleus (exclusive), i.e. the nuclei the word could take. When P = N_w the split confidence is `splitExact`
  (0.9); otherwise 0.9 − 0.3·|P − N_w| (spec 07's rule, unchanged). When fewer than N_w nuclei can be assigned, the
  word is **nucleus-short**: no stress features, `.unavailable(.lowConfidence)` for placement and contrast (Open
  question 2), counted on its own report line. There is no proportional fallback, since that would bring the word-edge
  dependence back.

### 3. Measurement windows (what spec 08 reads)

Per syllable, from its nucleus only:

- **Duration d:** the nucleus region's length (§1), in seconds. Spec 08's ln(λ) discount applies unchanged to a
  lengthening-exposed syllable.
- **Lengthening exposure (CTO markup 2), structural and the same for `.span` and `.nucleus`:** a syllable is exposed
  if it is the last syllable (by index) of a word that is phrase-final, or of a word followed by a pause longer than
  spec 07's gap threshold (`prominence.exposurePauseMs`, 150 ms), with the pause taken from word timing (the gap to
  the next word's start). That threshold is the only input. The nucleus region's end is never compared to a word
  edge. For `.span` this replaces spec 07's syllable-end test with the same structural rule, so both modes agree.
- **Intensity e:** mean RMS in dBFS (full band, as spec 07 today) over a fixed window of ±`nucleus.windowMs` (initial
  30 ms) around the peak, clamped to the nucleus region; floored at −60 dBFS.
- **f0 p:** peak F0 in semitones relative to the speaker's median (spec 04) over the voiced frames of the nucleus
  region; missing with fewer than 3 voiced frames (spec 08's rule).
- Contrast C and weak length W (spec 08) use the same d and e. Nothing else in spec 08 changes: z-scores over the
  comparable set, weights, margins, A(w), `placementDecision`.
- Spec 07's syllable spans stay for display, spec 09's time map and band, and the strip. They are no longer stress
  inputs. Word timing is unchanged.

### 4. Where it plugs in

- **`AMProsody`:** `NucleusDetector` (samples + spec 04 track → `[Nucleus]`), `NucleusAssigner` (nuclei + words →
  per-syllable `NucleusMeasurement`), and a `SyllableMeasurement` mode (`.span` | `.nucleus`) chosen by
  `Thresholds.prominence.measurement`. `.nucleus` is the default once this spec merges; `.span` stays for the
  comparison rows and as the before column, never shipped as a choice in the app. AMProsody already depends on
  AMPitch, so no module edge is added.
- **L1 (spec 12's caches):** nuclei and measurements are part of the L1 value, which keeps its key; `algorithmVersion`
  bumps, so old L1 records are a cache miss and recompute (spec 12's rule). L0 and L2 keys don't change. Spec 12's
  coordinator and `Analyzer` stage order stay as they are: the nucleus pass runs inside the syllable stage. The L2
  voice-switch recompute budget (≤ 150 ms median) still holds, since nuclei are L1.
- **Spec 11's harness (`AMEvaluation`, `am-eval`):** the jitter runner (spec 11 §4b), the control (§4), spec 23's
  `DownstreamHarness` (§4a) and the release suite gain `--measurement span|nucleus` and print both columns. The report
  identity (§6.6) records the measurement mode and the nucleus parameters.
- **Thresholds:** new `nucleus.*` keys (initial values above, chosen before any data, never tuned on held-out data),
  `prominence.measurement`, `thresholdsVersion` to the next free integer, a new golden-digest record, and
  `docs/thresholds.md`.

### 5. Acceptance tests, in order (stop at the first that fails)

1. **Oracle-boundary jitter test, first, before any aligner comparison.** Spec 11 §4b exactly as written: oracle word
   boundaries (TTS markers on the synthetic set, MFA on the held-out VCTK speakers), both edges moved by ±20, ±40 and
   ±80 ms (three runs, the split manifest's fixed seed, clamped to neighbours and the clip), the same verdict path,
   flips counted against the unjittered oracle with anything↔inconclusive included. Pass: **≤ 2% flips at ±40 ms on
   each set, pooled and in every multi-syllable group (2, 3, 4+) with n ≥ 30**; groups with n < 30 are reported
   only; ±20 and ±80 ms reported only. Also the per-group inconclusive rise (≤ 2 points for 2- and 3-syllable groups
   with n ≥ 30) and the 10% inconclusive budget, so it can't pass by going inconclusive. Run on the thresholds on main
   (Open question 3), with the `.span` column next to it (today 8.1% / 11.6%). **Parameters stay fixed at their
   initial values (CTO markup 4).** Diagnostic line (CTO markup 3, reported): at ±40 ms, flips whose word has a
   nucleus peak within 40 ms of either unjittered edge, against flips whose word has none, with counts and rates of
   each group of words.
   **If this fails, stop:** no aligner comparison, and no parameter changes of any kind in this spec, not even on the
   tuning pool (CTO markup 4). The report and the PR say FAIL, `.nucleus` doesn't become the default, and the build
   writes the scope-cut proposal (§6) for CTO. A tuning pass would be a later spec.
2. **Timing-sensitivity control** (spec 11 §4): TTS markers vs MFA on the synthetic set, ≤ 2% verdict changes and
   ≤ 2 points of inconclusive rise.
3. **Aligner comparison:** spec 23's b2 vs oracle and Whisper vs oracle through `DownstreamHarness`, both sets, spec
   23's limits, spec 11 §4a's breakdowns.
4. **The full spec 11 gate rows** with `.nucleus`: the release suite (spec 11 §3, §3a, §4c, §7), every positive-set
   row with n ≥ 150, the L2 rows, the guard and `AnalysisGateTests`' conditions, printed PASS / FAIL / NOT EVALUATED.
   Spec 11's tuning (§2) re-runs on the tuning pool only, through spec 11's own procedure.
- **Diagnostics (reported, not gated):** the share of detected nuclei whose peak falls inside an MFA vowel interval
  (VCTK tuning speakers), the count-match rate P = N_w by syllable count, and the nucleus-short rate per set and per
  group.
- **CI enforcement**, the same pattern as spec 11 §7: `NucleusJitterGateTests` (in `AMEvaluationTests`, under
  `make test`) loads the committed `docs/agreement/reports/nucleus-jitter-<configDigest8>.json` for the head's
  `configDigest` and fails unless acceptance 1's conditions are MET. Red CI means no merge.

### 6. If acceptance 1 fails: the scope-cut proposal (for CTO to route, not decided here)

The build commits `docs/agreement/reports/nucleus-jitter-<configDigest8>.md` with a section "Proposal: no per-word
stress-placement verdicts on 2–3-syllable words", giving, for `.span` and `.nucleus`:
- at ±40 ms, per group (1, 2, 3, 4+) and per set: the group's **own flip rate** (flips ÷ the group's words, with n and
  Wilson interval) **and its share of the pooled flips** (the group's flips ÷ all flips), plus the pooled rate and
  what the pooled rate would be without 2–3-syllable placement verdicts;
- what the cut removes: the share of placement-applicable words, the starter phrases and target words affected
  (spec 15), and the L2 stress-wrong words among the 134 that are 2–3 syllables (the recall the claim would lose);
- the positive-set placement and any-diff rows and the L2 FP with and without the cut.
It's a proposal with numbers. Nothing is cut in code, and the route (CTO, then Raph via CPO) is CTO's.

## Defaults

- All nucleus parameters are fixed initial values set before any run and stay fixed in this spec, pass or fail
  (CTO markup 4). Tuning them would be a later spec (spec 11's fixed-grid procedure, tuning pool only).
- The run is local on the Mac, by the build itself (spec 11 §7's rule: no hand runs); PR CI runs the unit tests,
  the goldens and `NucleusJitterGateTests`.

## Guardrails

- Never loosen ≤ 2% flips, the ≤ 2-point inconclusive rise, the 10% inconclusive budget, the 150-pair minimum or
  any spec 11 gate. NOT EVALUATED is never a pass.
- No held-out speaker or synthetic audio in any parameter choice. A FAIL goes to CTO with the numbers.
- Detection reads no word boundary (a test proves the nuclei are identical under any word-span input).
- No new dependency, no network, no AppKit or UIKit in AccentKit, no DTW in stress features.

## Out of scope

- Phone-level CTC nuclei from b2 (spec 11 §4c names it as an option; it needs b2 shipped). Shipping or retuning b2.
- Changing spec 07's display spans, spec 09's time map or band, or the strip (they keep spans).
- Any scope cut (§6 only proposes it). UI copy. Tuning the nucleus parameters.

## Risks

- **Vowel sequences without an energy dip** ("idea", "really", hiatus and glides) give one peak for two syllables,
  so the word is nucleus-short. Watch the nucleus-short rate on 2–3-syllable words; it feeds the inconclusive budget.
- **Syllabic consonants and reduced vowels** ("button", "potato" with a devoiced first vowel) have weak or unvoiced
  nuclei. CMUdict counts them as syllables, so the word is short. The same rate shows it.
- **Edge peaks.** A nucleus within about 40 ms of a word edge (linking, "an apple") can still change words under
  jitter. The DP's soft cost limits this; acceptance 1 measures it.
- **Feature distributions shift.** Nucleus d and e differ from span d and e, so spec 11's tuned point (if any) and
  the contrast and weak-length tolerance rows may move. Acceptance 4 re-runs them; no tolerance changes.
- **Children and L2 speech** have less regular energy contours; the L2 rows report them separately (spec 11 §1, §3).
- **The fix may not be enough.** If flips come from small margins rather than from edges, acceptance 1 fails and §6
  applies.
- **Cache churn:** `algorithmVersion` and `thresholdsVersion` bumps invalidate stored L1 (spec 16's lazy recompute).

## Open question (built with the default)

CTO accepted defaults 1–5 on 2026-11-24 at 15:04 Europe/Paris.


1. **Dependency on spec 11.** Accepted. Spec 11 is Done only when its §7 gate passes, which now needs this spec, so "depends on
   11 Done" would deadlock. Default: this spec depends on 07, 08, 12 and 23 (Done) and uses spec 11's harness and
   FALLBACK report from main or from spec 11's branch. Spec 11 reaches Done afterwards, through its own gate, re-run
   with `.nucleus`.
2. **Nucleus-short words.** Accepted: placement and contrast are unavailable (low confidence), with no fallback split.
   The alternative (proportional split) brings back the edge dependence.
3. **Thresholds for acceptance 1.** Accepted: main's thresholds (spec 11's FALLBACK left them unchanged), with the
   nucleus parameters at their initial values. No retuning of anything in this spec.
4. **Duration measure.** Accepted: the −6 dB voiced nucleus region. The alternative, the inter-nucleus interval, is
   printed as a diagnostic column only.
5. **Merge rule for this spec.** Accepted: it merges when acceptances 1 and 2 are MET (`NucleusJitterGateTests`
   green), CI is green and CTO's engine and threshold review passes. Acceptances 3–4 are reported here and gated by
   spec 11's `AnalysisGateTests` when spec 11 re-runs.

## How to test (Raph)

Every step is run by the build agent and repeated by the reviewer; none needs Raph's hands.

1. `make check` is green.
2. `swift test --package-path Packages/AccentKit --filter NucleusTests`:
   - on spec 07's pulse train, every detected peak is within 10 ms of the true envelope peak and the count matches;
   - nuclei are bit-identical whatever word spans are passed (detection reads no word edges);
   - moving every word edge by ±40 ms on the pulse train changes no syllable's d, e or p unless a peak lies within
     40 ms of an edge;
   - the DP gives each word N_w consecutive nuclei, skips an extra peak, and marks a word with one peak too few as
     nucleus-short;
   - **edge invariance (CTO markup 3):** on the pulse train, with every peak more than 50 ms from any word edge,
     moving every edge by ±40 ms gives bit-identical d, e, p, split confidence and exposure for every syllable;
   - P comes from the DP assignment (the nuclei between neighbours' assigned nuclei), and exposure is the same in
     `.span` and `.nucleus` mode for a phrase-final word and a word before a 200 ms pause;
   - `.span` mode reproduces spec 08's worked examples to 2 decimals (unchanged path).
3. `scripts/agreement.sh --suite nucleus-jitter` prints acceptance 1 per set: pooled and per group at ±20 / ±40 / ±80
   ms with n and Wilson intervals, `.span` next to `.nucleus`, the inconclusive rise per group and the budget, and
   ends `Nucleus jitter: MET` or `NOT MET (stop; proposal written)`. Two runs give identical numbers.
4. If MET: the same script continues with acceptances 2–4 and prints each row.
5. `swift test --filter NucleusJitterGateTests` passes on the head, and fails on a copy of the report with one gated
   group changed to 2.1%.
6. The committed reports' `sourceTreeHash` and `configDigest` match the head (`scripts/check-report-identity.sh`).

## Implementation notes

Hand build (Claude Code), branch `factory/25-nucleus-anchored`, 2026-11-24. **Acceptance 1: FAIL.** Per §5 the build
stopped there: no aligner comparison, acceptances 2–4 not run, no parameter or threshold changed, `.nucleus` is not
the default (`prominence.measurement` stays `0`, span), and §6's proposal is in
`docs/agreement/reports/nucleus-jitter-<configDigest8>.md`.

**What was built**
- `AMProsody/Nucleus.swift`: `NucleusDetector` (samples + spec 04 track → `[Nucleus]`), `NucleusAssigner` (the
  monotonic DP), `NucleusMeasurement` (d, e, p per syllable), `NucleusWordAssignment` (P, s_w, nucleus-short).
  - Envelope: per 10 ms cell (spec 04's grid), a 25 ms Hann window centred on the cell, 512-point FFT, power in the
    300–2,500 Hz bins scaled by Parseval to a mean square, in dBFS, then a centred 5-frame (50 ms) mean.
  - Voicing: the cells the spec 04 `PitchTrack` marks voiced (pYIN probability ≥ 0.5, then spec 04's < 30 ms runs
    dropped; bridged frames are not voiced). The peak frame itself must be voiced.
  - Merging, until stable: any pair closer than 70 ms (keep the higher, the earlier on a tie), then the least
    prominent candidate under 3 dB. Prominence and valleys use the take's ends where there is no neighbour. The
    region stops before either valley frame.
  - DP: minimises the number of nucleus-short words first, then the ms cost; at equal cost a word takes its nuclei
    before a nucleus is skipped (ties go to the earlier word). A nucleus more than `alignment.asrPaddingMs` outside a
    span can't go to that word. P counts the nuclei strictly between the nearest earlier and later words' assigned
    nuclei (a short neighbour has none, so the search goes past it).
- `SyllableSegmenter`: `.nucleus` keeps spec 07's spans as `range` (display) and replaces `duration`, `energyDBFS`
  and the syllable confidence (min(c_w, s_w from P)); a nucleus-short word's syllables get confidence 0 (low), no
  `nucleus`, and leave the comparable set (`ComparableSyllable.all`), so placement and contrast are unavailable. p
  reads the nucleus region (`ProminenceFeatures`). `Input.pitch` carries the track; `.nucleus` without it throws.
  New fields are optional and omitted in `.span`, so `.span` JSON keeps its shape.
- Exposure is structural in both modes (markup 2): the last syllable of a word with nothing timed after it, or whose
  gap to the next timed word's start is > `prominence.exposurePauseMs`. The smoke set's 53 items keep every placement
  and verdict under it.
- Pipeline: the analyzer, `StressPlacementDetector.analyse` and spec 11's tuner pass the take's pitch track into
  segmentation (pitch now runs before segmentation in the two sequential paths). L0/L2 keys unchanged; L1 recomputes
  through `algorithmVersion` 2.
- Thresholds: `nucleus.*` (initial values) and `prominence.measurement` (Int-backed so the mirror holds a number:
  0 span, 1 nucleus). `thresholdsVersion` 9, `algorithmVersion` 2, golden record (2, 9, 2) appended. Re-recorded for
  the bump only: AMCore and scoring goldens (version fields), smoke detector goldens (L1 digests and versions),
  `fixtures/pipeline/analysis-golden.json` (versions) and `Resources/Starter` via `scripts/build-starter.sh` (L1 keys
  and the hashes over them).
- Harness: `am-timestamps spec11-guard --measurement span|nucleus --rows control,b2,jitter` (spec 11's runner; one
  pYIN track per clip), per-word near-edge flag (a detected nucleus peak within 40 ms of either unjittered oracle
  edge) and oracle-side P and nucleus-short counts. A nucleus-short word's `WordVerdict` is inconclusive with no
  longest or loudest syllable. `am-eval nucleus-jitter` applies the limits and writes the report;
  `scripts/agreement.sh --suite nucleus-jitter` (→ `scripts/nucleus-jitter.sh`) runs both modes without re-running
  MFA. `NucleusJitterGateTests` re-derives every check from the stored comparisons.

**Acceptance 1 at ±40 ms** (seed 20261125; `.span` → `.nucleus`; full tables in the report)

| Set | n | Pooled flips | 2-syll | 3-syll | 4+ | Oracle inconclusive | ±40 inconclusive |
|---|---|---|---|---|---|---|---|
| synthetic | 307 | 8.1% → 6.5% | 17.6% → 11.8% (n 51) | 33.3% → 13.3% (n 15) | 57.1% → 0% (n 7) | 5.2% → 26.7% | 8.5% → 28.3% |
| VCTK held-out | 3,890 | 11.6% → 4.5% | 12.2% → 3.3% (n 639) | 17.8% → 3.3% (n 213) | 18.8% → 0.9% (n 117) | 9.3% → 57.6% | 17.7% → 60.6% |

`.nucleus` misses ≤ 2% pooled on both sets and in the 2- and 3-syllable groups on VCTK and the 2-syllable group on
synthetic, and blows the 10% budget on both sets. The `.span` column reproduces spec 11's 8.1% / 11.6%.

**Why (diagnostics, reported):** nucleus-short words dominate. On VCTK 1,376 of 2,921 monosyllables, 306 of 639
2-syllable, 167 of 213 3-syllable and 101 of 117 4+-syllable words are nucleus-short on the oracle boundaries (synthetic:
45/234, 12/51, 6/15, 5/7). Checked by hand on held-out clips (no code change): the detector finds about half the
syllables because the peak must be a pYIN-voiced frame, and pYIN's voicing starts about 60 ms after ACF's at vowel
onsets, past the envelope peak (e.g. p238_001 "stella": envelope peak 1.53–1.57 s, pYIN voiced from 1.58 s, ACF from
1.52 s), so the vowel has no voiced local maximum. That is §1 as written (spec 04's tracker, no new tracker). Near-edge
(markup 3, VCTK, `.nucleus`): words with a nucleus peak within 40 ms of an oracle edge flip at 126/1,249 (10.1%), the
rest at 48/2,641 (1.8%); synthetic 9/138 vs 11/169.

**§6 proposal rows** (shipped config, `.span`; the cut applied after the fact to the suites' outputs): clean 1,400 L2
FP 150 (10.71%) → 0 (only 19 of the 1,400 words keep a placement verdict); supplementary FP 188/1,868 (10.06%) → 0
(29 keep one); L2 recall 5/134 (3.73%) → 0 (8 of the 134 keep a verdict); positive set (281 scored pairs)
placement-diff 6 (2.14%) → 0, any-diff 94 (33.45%) → 92 (32.74%). The cut removes almost every placement verdict
these sets have; the report gives the starter-phrase and group numbers.

**Not run (stopped at acceptance 1, §5):** acceptances 2–4, `NucleusJitterGateTests` green on the head (it is red: the
report says NOT MET), the MFA vowel-interval diagnostic and the inter-nucleus-interval column (Open question 4).

**Spec gaps**
- `thresholdsVersion`: the brief said 8 ("7 reserved for spec 11"), but main already holds 7 (spec 22) and 8 (spec
  23). §4 says "the next free integer": 9. Spec 11's tuned config takes the next one after.
- The 10% budget names no population for a jitter run; it's read on the compared words' jittered inconclusive share
  (the strictest reading). The flips fail without it.
- Near-edge: "the word has a nucleus peak within 40 ms of either edge" read as any detected nucleus (assigned or not).
- P's neighbours are the nearest earlier and later words with assigned nuclei, skipping nucleus-short ones.
- Voicing comes from the spec 04 track (after its 30 ms minimum run), the input §4 names, not raw per-frame
  probabilities.
