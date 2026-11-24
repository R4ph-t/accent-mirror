# 27: Word-stress classifier and native envelope, offline feasibility spike (GO / NO-GO)

Status: Draft · Branch: – · Depends on: 02, 06, 10, 22, 24, 25 (nucleus detector as the front end, from the unmerged
branch `factory/25-nucleus-anchored`) and spec 26's detection grid (frozen nucleus parameters, from the unmerged branch
`factory/26-nucleus-count-assignment`) · Time box: 10 h agent run + 1.5 h review · Risk: medium (offline only; no app
code, no `Thresholds` keys)

**Ruling this spec follows:** CTO decision record "Accent Mirror: stress and prosody reformulation, CTO decision
(2026-11-24)", https://app.notion.com/p/4220d0d445928128b258faf2852259c1. Relayed to Accent Mirror Lead at 16:51
Europe/Paris on 2026-11-24.

**Draft, not Ready: CTO reviews this spec before any build.** The spike ends with one line, `Spike 27: GO` or `Spike
27: NO-GO`, and CTO decides what follows. A GO leads to integration specs, and their merges still need Raph's Merge
OK. A NO-GO means v1 ships with phrase rhythm and intonation inside the native envelope only, and that scope call goes
to Raph via CPO.

Source: CTO's decision record above, based on spec 11's honest result in #66
(`docs/agreement/reports/release-4fc683ef.md`):
- native-vs-native any-diff is 33.5% (gate 5%), with 38.1% inconclusive;
- the TTS-marker vs MFA control is 13.7%;
- ±40 ms jitter flips 11.6% of verdicts on VCTK;
- L2 recall is 5/134, against 26/134 for B1;
- the tuning grid had no feasible point.

CTO's diagnosis: comparing per-syllable prosody against one reference recording measures normal native variation, not
learner error, so the formulation is infeasible, not badly tuned. Specs 26 and 25 confirmed it: 7.1% and 4.5% VCTK
flips at ±40 ms, with 63.5% and 57.6% inconclusive. This spec tests a different formulation, and only offline.

## Goal

Find out, offline and within the time box, whether two narrower claims are reachable at the existing bars:
- **(a) word stress as a lexical target:** "the most prominent syllable is the dictionary's primary stress";
- **(b) phrase rhythm and intonation against a native envelope**, not a single voice.

The answer is GO or NO-GO with numbers. There's no app integration.

## Behaviour

### 1. Word stress as a lexical-target classifier

- **Target:** CMUdict primary stress (spec 06's bundled dictionary) for the curated starter words (spec 15's 14
  phrases).
  - Heteronyms ("record", "present", "object", …) are resolved by hand for each phrase in a committed table
    (`docs/agreement/spike27/heteronyms.json`: phrase, word, stress index, reason) or excluded, with the reason
    recorded.
  - A word whose CMUdict entries disagree on primary stress, and that isn't in the table, is excluded.
  - Monosyllables are out of scope for placement.
- **Front end:** spec 25's nucleus detector with spec 26's frozen detection parameters (1.5 dB, 50 ms, 9 dB, ±60 ms
  voicing; report `nucleus-count-69675122`), plus spec 25/26's assignment.
  - A word is a candidate only if its assigned nucleus count is in N_w (spec 26 §2) and it isn't
    `assignmentAmbiguous`. Every other word is an **abstention** and counts against coverage, never as a flag.
- **Features,** all relative within the word, per nucleus k:
  - duration d_k / mean d;
  - intensity e_k − mean e (dB);
  - f0 p_k − median p (semitones);
  - each feature's rank within the word;
  - the syllable count and k's position (initial, medial, final).
  - No absolute values, speaker id or reference recording are used.
- **Model:** small and inspectable. Either L2-regularised logistic regression scoring each nucleus as "primary", or
  small boosted trees (depth ≤ 3, ≤ 100 trees), fitted offline in Swift inside `am-eval`, with no new dependency.
  - The predicted stressed syllable is the argmax over the word's nuclei.
  - **Abstention:** flag "stress not on syllable k*" only when the predicted syllable ≠ the target, and its
    probability margin over the target syllable is ≥ τ. Otherwise the word is "close" or "unsure".
  - τ is chosen on training-side cross-validation only (speaker-grouped folds), to keep native false flags under the
    gate, and is then frozen.
- **Training data,** fully automated and never using evaluation speakers:
  - **Positives:** native words from the VCTK tuning speakers (MFA word boundaries, spec 07's pinned MFA) and from the
    spec 22 TTS references, labelled with the target index.
  - **Negatives:** synthetic misplaced stress made by **prosody transplantation between syllables**. For a native
    multi-syllable word, swap the duration, intensity and f0 profile of the stressed nucleus with an unstressed one,
    using a TD-PSOLA-style resynthesis (§4).
    - Re-measure the result through the same front end, so the model learns from features of real audio, not edited
      numbers.
    - Each negative records its source word and swapped indices.
    - A negative that fails a resynthesis quality check (pitch-mark coverage ≥ 90% of the voiced span, no clipping)
      is dropped and counted.
- **Evaluation only, never used to fit or choose anything:**
  - held-out VCTK (the split manifest's held-out speakers);
  - the 134 speechocean762 l2-shared stress-wrong words, plus the clean 1,400 for precision context.
  - A test asserts that the training and threshold code reads neither set.

### 2. Native envelope for phrase metrics

- **Metrics:** nPVI, pitch range and final direction, using spec 10's definitions on spec 09/10's measurements.
- **Envelope:** for each starter phrase (and pooled across phrases for each metric), the native distribution from the
  **8 bundled voices** (p225, p226, p227, p233, p241, p252, p311, p345) plus the **VCTK tuning speakers** reading the
  same prompts where they exist.
  - The envelope is the central 95% interval, or an empirical quantile pair chosen on the tuning side only to hold
    native false flags ≤ 5%. Its n is printed.
  - Final direction uses the native share of each direction class. A learner is flagged only on a class with a native
    share < 5%.
- **Flag only outside the envelope.** Never compare against a single voice.
- A phrase metric with fewer than 30 native takes is reported as NOT EVALUATED and is never gated or flagged.

### 3. Gates (they replace the reference-diff rows for this spike)

Each gate is printed with n, its point estimate and its Wilson 95% interval.

1. **Native false flags ≤ 5% on held-out VCTK, judged on the Wilson upper bound.** This holds for word stress (flags
   among candidate words) and separately for each phrase metric (nPVI, pitch range, final direction).
2. **L2 word-stress recall on the 134 beats B1** (spec 02's longest-syllable detector, the same words and front end),
   with a **significant paired McNemar win** (exact test, p < 0.05, on the discordant pairs). Also report B2,
   precision on the clean 1,400, and coverage (non-abstained share) of the 134.
3. **±40 ms jitter ≤ 2% flips** on held-out VCTK and on the synthetic set, pooled and per multi-syllable group with
   n ≥ 30. This is spec 11 §4b's test with its fixed seed. Flips include anything↔abstain.
4. **Coverage:** the non-abstained share of the starter words' placement-applicable recordings across the bundled
   voices, and of held-out VCTK candidate words, is reported. **Its minimum is a CPO product call** and isn't gated
   here.

**GO** needs gates 1–3 all met, for word stress and for every phrase metric the spike recommends keeping.
- A partial result is written out: for example, "phrase metrics GO, word stress NO-GO". Each metric's line is MET,
  NOT MET or NOT EVALUATED. NOT EVALUATED is never a pass.
- Gate limits are never loosened.

### 4. Prosody transplantation (negatives only, offline only)

- **Method:** TD-PSOLA (Moulines & Charpentier 1990). Pitch marks come from spec 04's tracker; the stressed and
  unstressed nuclei swap their duration ratio, intensity offset and f0 contour, with overlap-add at the new marks.
  - Implement it in Swift inside `am-eval`, from the published algorithm, with no copied code.
  - Spot-check 20 negatives by listening, as a taste call (Raph), with paths printed in the report.
- **Licences (checked 2026-11-24):**
  - Praat's PSOLA (GPL-3.0-or-later as distributed) and Parselmouth (GPL-3.0-or-later) are compatible, but not
    needed. The default is our own Swift implementation.
  - Rubber Band (GPL-2.0-or-later, App Store needs a commercial licence) is not used.
  - The Rust `tdpsola` crate (AGPL-3.0) is not used.
  - Any later dependency must be GPL-3.0-compatible and run on device.
- **What never ships:** the transplanted audio. Caches go outside the worktree (AGENTS.md).

### 5. Deliverables

- `docs/agreement/reports/spike27-<configDigest8>.{json,md}` with spec 02's identity header. It covers:
  - the training-set counts (positives, negatives, dropped negatives and why), the folds and the frozen τ;
  - the model's coefficients or trees;
  - every gate line, the B1 and B2 comparison, the McNemar table and the coverage figures;
  - the envelopes with their n;
  - the final line `Spike 27: GO` or `Spike 27: NO-GO`, plus a partial-result line if one applies.
- `docs/agreement/spike27/heteronyms.json`, the training manifest (no audio) and a short README of the procedure.
- A NO-GO also writes the v1 scope statement for CPO: "v1 ships phrase rhythm and intonation inside the native
  envelope only, without per-word stress verdicts", with the phrase-metric gate lines that support it, or say it isn't
  supported.

## Housekeeping (once spec 27 is Ready)

- The index and the specs mark **the verdict gates of specs 11, 23, 25 and 26 as superseded by spec 27**, linking the
  CTO decision record. Their measurement code, harnesses and reports stay as history.
- #66, spec 25 (`factory/25-nucleus-anchored`) and spec 26 (`factory/26-nucleus-count-assignment`) stay unmerged. Spec
  26's detection grid is kept as data.
- The Ready flip edits only `specs/` (the Status and Depends-on text of 11, 23, 25 and 26, plus the index rows).

## Defaults

- Everything runs offline on the Mac through `am-eval` and `scripts/agreement.sh --suite spike27`, niced, under the
  load gates. No app target, AMPipeline or UI change. **No `Thresholds` keys:** τ, the model and the envelopes live in
  the spike report only.
- Seeds: the split manifest's fixed seed for folds, jitter and negative sampling. Two runs give identical numbers.
- The time box is 10 h of agent time. When it runs out, the build writes what it has with each gate's status (NOT
  EVALUATED where it didn't get there) and ends NO-GO for anything not evaluated.

## Guardrails

- No held-out VCTK, l2-shared or clean-1,400 data enters training, feature choice, τ or the envelope, and tests assert
  it.
- Gates are never loosened, and an expected number is never edited to pass. A NO-GO is reported as NO-GO.
- No new dependency, no network, and GPL-3.0-compatible only. No code copied from Praat, Prosogram or any PSOLA
  library.
- Spec 26's frozen detection parameters are used as they are. Retuning the front end is out of scope.

## Out of scope

- App integration, UI copy, `Thresholds` keys, AMPipeline changes and shipping a model.
- Retuning the nucleus detector or the aligner, and any further reference-diff work.
- Contrast and weak-length verdicts, which aren't in CTO's formulation.
- Words outside the starter set as a product claim. They're used only as evaluation words (the 134, held-out VCTK),
  with CMUdict as their target.

## Risks

- **Transplanted negatives may be easier than real L2 errors,** so recall on the 134 could disappoint. The McNemar win
  against B1 is the honest check.
- **The front end abstains often** (spec 26: 63.5% inconclusive on held-out VCTK, 24.7% `assignmentAmbiguous`), so
  coverage may be too low for CPO even if precision is good.
- **The envelope is small:** about 8 bundled voices plus the tuning speakers who share prompts. Phrase metrics under
  n 30 can't be evaluated.
- **The 134 words mostly aren't starter words.** Recall there measures the classifier, not the starter claim.

## Open questions (built with the default)

1. **Model family.** Default: logistic regression first, with boosted trees only if logistic misses gate 2 and time
   allows. Both are reported if both run.
2. **Envelope definition.** Default: an empirical central interval set on the tuning side to hold ≤ 5%, per phrase
   where n ≥ 30, otherwise pooled per metric with per-phrase centring.
3. **Front-end gating.** Default: count-matched and not `assignmentAmbiguous` (spec 26). The alternative of all
   detected words with the classifier abstaining isn't the default.
4. **Evaluation words outside the starter set.** Default: the 134 and held-out VCTK use CMUdict primary stress as the
   target, with the same heteronym exclusions applied automatically.
5. **Spec path.** The request said `docs/specs/27-…`. The repo's specs live in `specs/` (the factory's `SPEC_DIR`),
   so it's `specs/27-…` here.

## How to test (Raph)

Every step is run by the build agent and repeated by the reviewer.

1. `swift test --package-path Packages/AccentKit --filter Spike27Tests` checks that:
   - the training and τ code refuse held-out and L2 inputs;
   - transplantation on a pulse-train word swaps the measured d, e and p between the two nuclei within tolerance;
   - the heteronym table resolves or excludes every starter heteronym;
   - two runs are identical.
2. `scripts/agreement.sh --suite spike27` prints every gate line with n and Wilson intervals, the B1/B2 McNemar
   table, coverage and the envelopes, and ends `Spike 27: GO` or `Spike 27: NO-GO`.
3. Listen to the 20 spot-check negatives (taste call, Raph).
4. The report's identity header matches the head (`scripts/check-report-identity.sh`).

## Implementation notes

_(filled in by the agent)_
