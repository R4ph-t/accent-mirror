# 25: Nucleus-anchored syllable measurement (spec 11's FALLBACK)

Status: Draft · Branch: – · Depends on: 07 (segmenter, syllable counts), 08 (prominence), 12 (pipeline, caches), 23
(`DownstreamHarness`, b2, oracle sets) (also spec 11's FALLBACK report and harness: see Open question 1) · Estimate:
6–8 h agent run + 1.5 h Raph review · Risk: high

Risk: high. This spec adds keys to `Packages/AccentKit/Sources/AMCore/Thresholds.swift` (a risky path) and bumps
`thresholdsVersion` and `algorithmVersion`. **Draft, not Ready: CTO approves this spec before the factory or a hand
build picks it up.**

Source: CTO's ruling on spec 11 (2026-11-24 14:59 Europe/Paris, relayed by Accent Mirror Lead): the ±40 ms jitter
row (8.1% synthetic, 11.6% VCTK, on oracle boundaries, so independent of the aligner) and the 13.7% TTS-vs-MFA
control show the verdict stage is too sensitive to word boundaries, so no word-boundary aligner can pass ≤ 2% at
±40 ms. The answer is spec 11 §4c's pre-declared FALLBACK, "nucleus-anchored syllable segmentation". CTO's earlier
reasoning (spec 11 §4c, verbatim there): multi-syllable splits come from the word edges, so boundary error moves
duration and intensity between syllables, which margins alone can't fix. Spec 23's diagnostics (CTO's figures): 2–3-syllable
words at 55–88% of flips, monosyllables at 6–10%.

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
- **Count mismatch.** Raw candidates in the word's padded window P vs N_w: when P = N_w the split confidence is
  `splitExact` (0.9); otherwise 0.9 − 0.3·|P − N_w| (spec 07's rule). When fewer than N_w nuclei can be assigned, the
  word is **nucleus-short**: no stress features, `.unavailable(.lowConfidence)` for placement and contrast (Open
  question 2), counted on its own report line. There is no proportional fallback, since that would bring the word-edge
  dependence back.

### 3. Measurement windows (what spec 08 reads)

Per syllable, from its nucleus only:

- **Duration d:** the nucleus region's length (§1), in seconds. For a lengthening-exposed syllable (spec 07's rule,
  judged from the nucleus region's end), spec 08's ln(λ) discount applies unchanged.
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
   (Open question 3), with the `.span` column next to it (today 8.1% / 11.6%).
   **If this fails, stop:** no aligner comparison and no tuning. The report and the PR say FAIL, `.nucleus` doesn't
   become the default, and the build writes the scope-cut proposal (§6) for CTO.
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
- the ±40 ms flips pooled and per group (1, 2, 3, 4+) with n and Wilson intervals, and what the pooled rate would be
  without 2–3-syllable placement verdicts;
- what the cut removes: the share of placement-applicable words, the starter phrases and target words affected
  (spec 15), and the L2 stress-wrong words among the 134 that are 2–3 syllables (the recall the claim would lose);
- the positive-set placement and any-diff rows and the L2 FP with and without the cut.
It's a proposal with numbers. Nothing is cut in code, and the route (CTO, then Raph via CPO) is CTO's.

## Defaults

- All nucleus parameters are fixed initial values set before any run. If CTO wants them tuned, that is spec 11's
  fixed-grid procedure on the tuning pool only, in a later spec.
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

1. **Dependency on spec 11.** Spec 11 is Done only when its §7 gate passes, which now needs this spec, so "depends on
   11 Done" would deadlock. Default: this spec depends on 07, 08, 12 and 23 (Done) and uses spec 11's harness and
   FALLBACK report from main or from spec 11's branch. Spec 11 reaches Done afterwards, through its own gate, re-run
   with `.nucleus`.
2. **Nucleus-short words.** Default: placement and contrast are unavailable (low confidence), with no fallback split.
   The alternative (proportional split) brings back the edge dependence.
3. **Thresholds for acceptance 1.** Default: main's thresholds (spec 11's FALLBACK left them unchanged). Retuning
   margins on nucleus features before acceptance 1 is not allowed here.
4. **Duration measure.** Default: the −6 dB voiced nucleus region. The alternative, the inter-nucleus interval, is
   printed as a diagnostic column only.
5. **Merge rule for this spec.** Default: it merges when acceptance 1 and 2 are MET (`NucleusJitterGateTests` green).
   Acceptances 3–4 are reported here and gated by spec 11's `AnalysisGateTests` when spec 11 re-runs.

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
   - `.span` mode reproduces spec 08's worked examples to 2 decimals (unchanged path).
3. `scripts/agreement.sh --suite nucleus-jitter` prints acceptance 1 per set: pooled and per group at ±20 / ±40 / ±80
   ms with n and Wilson intervals, `.span` next to `.nucleus`, the inconclusive rise per group and the budget, and
   ends `Nucleus jitter: MET` or `NOT MET (stop; proposal written)`. Two runs give identical numbers.
4. If MET: the same script continues with acceptances 2–4 and prints each row.
5. `swift test --filter NucleusJitterGateTests` passes on the head, and fails on a copy of the report with one gated
   group changed to 2.1%.
6. The committed reports' `sourceTreeHash` and `configDigest` match the head (`scripts/check-report-identity.sh`).

## Implementation notes

_(filled in by the agent)_
