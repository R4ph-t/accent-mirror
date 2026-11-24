# 27: Word-stress classifier and native envelope, offline feasibility spike (GO / NO-GO)

Status: Ready · Branch: factory/27-stress-classifier-spike (hand build) · Depends on: 02, 06, 10, 22, 24, 25 (nucleus detector as the front end, from the unmerged
branch `factory/25-nucleus-anchored`) and spec 26's detection grid (frozen nucleus parameters, from the unmerged branch
`factory/26-nucleus-count-assignment`) · Time box: 10 h agent run + 1.5 h review · Risk: medium (offline only; no app
code, no `Thresholds` keys)

**Ruling this spec follows:** CTO decision record "Accent Mirror: stress and prosody reformulation, CTO decision
(2026-11-24)", https://app.notion.com/p/4220d0d445928128b258faf2852259c1. Relayed to Accent Mirror Lead at 16:51
Europe/Paris on 2026-11-24.

CTO approved this spec on 2026-11-24 at 16:56 Europe/Paris with five markups (folded in: §1, §1a, §3, §4 and §5)
and accepted defaults 1, 2, 4 and 5. Markup 1 replaces default 3. Raph held it at 16:57 for a literature review. The
review is "Accent Mirror: stress & prosody feedback literature review (2026-11-24)",
https://app.notion.com/p/4220d0d4459281a0b298e1f086014b75. CTO accepted its five amendments at 17:01 (folded in:
§1, §2, §3 and §3a, marked "lit amendment"). The spike ends with one line, `Spike 27: GO` or `Spike
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

**Expectations (the literature review, for the report header):**
- The published systems closest to this design report **recall around 20–50% at a usable operating point**: Ferrer
  et al. 2015 miss 48.3% at a 5% false-correction rate, and Korzekwa et al. 2021 report 94.8% precision at 49.2%
  recall, but only with an attention model.
- Classic native-side error is about 10%.
- **A word-stress NO-GO with phrase metrics GO is a legitimate result.** The build must not push for a GO.

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
  - **Two front-end arms (CTO markup 1),** each with every gate reported:
    - **Arm A** (default): a word is a candidate only if its assigned nucleus count is in N_w (spec 26 §2) and it
      isn't `assignmentAmbiguous`.
    - **Arm B** (top-k): take the N_w most prominent nuclei inside the word's span, in time order. Abstain only if
      fewer than N_w are found. There's no `assignmentAmbiguous` step. When N_w is a set, use the context
      pronunciation's count.
    - The shipped arm is picked **on the tuning side only**. If both pass every gate, B is preferred.
    - Any word that doesn't go through is an **abstention**. It counts against coverage, never as a flag.
- **Features,** all relative within the word, per nucleus k:
  - duration d_k / mean d;
  - intensity e_k − mean e (dB);
  - **f0 relative to the phrase contour (lit amendment 2):** the nucleus f0 residual (semitones) after a smooth
    phrase-level fit (a low-order fit over the phrase's voiced frames), compared within the word;
  - **spectral tilt/balance** of the nucleus relative to the word mean (lit amendment 2). The measure is the
    band-energy difference (low band against high band, in dB), the same for every variant;
  - each feature's rank within the word;
  - the syllable count and k's position (initial, medial, final).
  - No absolute values, speaker id or reference recording are used.
  - **Variants (lit amendment 2):** with and without spectral tilt, and with phrase-residual f0 or **no f0** (an
    ablation that's always reported). The shipped variant is picked on tuning-side speaker-grouped CV only.
- **Model:** small and inspectable. Either L2-regularised logistic regression scoring each nucleus as "primary", or
  small boosted trees (depth ≤ 3, ≤ 100 trees), fitted offline in Swift inside `am-eval`, with no new dependency.
  - The predicted stressed syllable is the argmax over the word's nuclei.
  - **Abstention:** flag "stress not on syllable k*" only when the predicted syllable ≠ the target, and its
    probability margin over the target syllable is ≥ τ. Otherwise the word is "close" or "unsure".
  - τ is chosen on training-side cross-validation only (speaker-grouped folds), and then frozen. The criterion
    is on the CV Wilson upper bound, not the point estimate alone (CTO markup 5): the point estimate of native false
    flags must be **≤ 1%** and its CV Wilson upper bound **≤ 2%** (lit amendment 1).
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
  - **Artefact control (CTO markup 4):**
    - Every positive goes through the same Swift PSOLA path with an **identity modification** (same pitch marks, no
      swap). Training and calibration use processed audio for both classes only.
    - **Check, reported:** a processed-vs-raw classifier (the same features and model family) trained and scored on
      held-out tuning folds must have **AUC ≤ 0.6**. If it's above 0.6, PSOLA artefacts are learnable: the report
      says so, and word stress can't be GO.
- **Evaluation only, never used to fit or choose anything:**
  - held-out VCTK (the split manifest's held-out speakers);
  - the 134 speechocean762 l2-shared stress-wrong words, plus the clean 1,400 for precision context.
  - **Known text (CTO markup 3):** L2 words are evaluated with the **prompt text as the transcript**. The
    ASR-transcript variant (spec 03's Whisper transcript) is printed beside it, and coverage of the 134 is reported
    under both.
  - **speechocean762 (CC BY 4.0) is a second L2 test set, evaluation only (lit amendment 4).** It is kept out of
    training, feature choice and τ.
    - Utterances that overlap the 134 set are dropped, by utterance id.
    - **Label rule, fixed here before any run:** only words with ≥ 2 syllables in CMUdict and a word accuracy score
      ≥ 5 (intelligible) count. A word is **misplaced** when its released word-level stress score is 5 ("stress is
      wrong"), and **correctly stressed** when it's 10. Any other value is excluded and counted.
    - The data is fetched to the build's `_cache-27` on the Mac. This is dev-time data, not an app network call.
  - A test asserts that the training and threshold code reads neither set.

### 2. Native envelope for phrase metrics

- **Metrics:** nPVI, pitch range and final direction, using spec 10's definitions on spec 09/10's measurements.
- **Per-prompt native envelope (lit amendment 3):** one envelope per starter prompt, never pooled across prompts.
  - Its natural speakers are the 8 bundled voices (p225, p226, p227, p233, p241, p252, p311, p345) and the VCTK
    tuning speakers reading the same prompt.
  - **Only natural speakers count toward n and the spread.** TTS takes count at most once per voice.
  - **Under 30 natural takes for a prompt, that prompt's metrics are NOT EVALUATED,** with no pooling fallback.
  - The envelope is an empirical central interval whose quantile pair is chosen on the tuning side only, on the
    speaker-grouped CV Wilson upper bound of native false flags ≤ 5% (CTO markup 5). Its n is printed.
- **Intonation is shown by default:** the learner's contour against the native envelope, with no verdict. **Verdicts
  are given only for:**
  - **monotone:** pitch range below the envelope;
  - **final direction,** only on prompts where ≥ 80% of the tuning-side native takes share one class. That prompt
    list is fixed and committed before any evaluation run.
  - nPVI and the other phrase measures are shown and reported, never verdicted.
- **Flag only outside the envelope.** Never compare against a single voice.

### 3. Gates (they replace the reference-diff rows for this spike)

Each gate is printed with n, its point estimate and its Wilson 95% interval, **for both arms (A, B) and for both
boundary sources (CTO markup 2)**:
- **Oracle:** MFA word boundaries (spec 07's pinned MFA).
- **Runtime:** Whisper base.en word times, the shipped source. b2 is measurement-only and isn't a runtime source.

**GO is judged on the runtime source.** A GO on oracle boundaries only is reported as `oracle-only` and counts as
NO-GO.

1. **False flags (lit amendment 1).**
   - **Word stress:** the point estimate is **≤ 1% AND** the Wilson upper bound is **≤ 2%**, on **n ≥ 600**
     non-abstained words per population, otherwise NOT EVALUATED. It applies separately to:
     - **held-out native VCTK;**
     - **correctly stressed L2 words** (the clean 1,400, and speechocean762's correctly stressed words, each
       reported on its own).
   - Also reported: the full precision–recall curve, and precision at the operating point at an assumed 5% and 10%
     prevalence of stress errors.
   - **Note for CPO, written in the report:** the 1% is an engineering ship bar. The precision it implies is a
     product trade-off.
   - **Phrase verdicts** (monotone, and final direction where it's verdicted): native false flags ≤ 5% on held-out
     VCTK, judged on the Wilson upper bound, per prompt.
2. **L2 word-stress recall on the 134 beats B1** (spec 02's longest-syllable detector, the same words and front end),
   with a **significant paired McNemar win** (exact test, p < 0.05, on the discordant pairs). This test stays
   unchanged. Also report B2, precision on the clean 1,400, and coverage (non-abstained share) of the 134. The same
   rows are reported on speechocean762 as a second test set.
3. **±40 ms jitter ≤ 2% flips** on held-out VCTK and on the synthetic set, pooled and per multi-syllable group with
   n ≥ 30. This is spec 11 §4b's test with its fixed seed. **A flip to or from abstain counts as a flip** (CTO
   markup 1).
4. **Coverage:** the non-abstained share of the starter words' placement-applicable recordings across the bundled
   voices, and of held-out VCTK candidate words, is reported. **Its minimum is a CPO product call** and isn't gated
   here.

### 3a. Arm C (report-only, lit amendment 5)

Arms A and B stay as gated. **Arm C** takes vowel positions from b2's character CTC under the known prompt text. It is
built **only if time remains**, and it is **report-only**. If C passes alone, that is not a GO: it means a follow-up
spec.

**GO** needs gates 1–3 all met **on the runtime source**, for word stress (on the arm picked on the tuning side)
and for every phrase metric the spike recommends keeping. For word stress, GO also needs the §1 artefact control
(AUC ≤ 0.6).
- A partial result is written out: for example, "phrase metrics GO, word stress NO-GO". Each metric's line is MET,
  NOT MET or NOT EVALUATED. NOT EVALUATED is never a pass.
- Gate limits are never loosened.

### 4. Prosody transplantation (negatives only, offline only)

- **Method:** TD-PSOLA (Moulines & Charpentier 1990). Pitch marks come from spec 04's tracker; the stressed and
  unstressed nuclei swap their duration ratio, intensity offset and f0 contour, with overlap-add at the new marks.
  - Implement it in Swift inside `am-eval`, from the published algorithm, with no copied code.
  - Spot-check 20 negatives by listening, as a taste call (Raph). Write them, each next to its source and its
    identity-processed version, to a folder outside the worktree (the build's cache `listen/` folder), with an
    index file. Print the paths in the report.
- **Licences (checked 2026-11-24):**
  - Praat's PSOLA (GPL-3.0-or-later as distributed) and Parselmouth (GPL-3.0-or-later) are compatible, but not
    needed. The default is our own Swift implementation.
  - Rubber Band (GPL-2.0-or-later, App Store needs a commercial licence) is not used.
  - The Rust `tdpsola` crate (AGPL-3.0) is not used.
  - Any later dependency must be GPL-3.0-compatible and run on device.
- **What never ships:** the transplanted audio. Caches go outside the worktree (AGENTS.md).

### 5. Deliverables

- `docs/agreement/reports/spike27-<configDigest8>.{json,md}` with spec 02's identity header. It opens with a
  **Background** section that quotes spec 26's acceptance 1 FAIL numbers from the build's `acceptance1.txt` (16:48
  run, configDigest 69675122). The report header also carries the literature's expectation: recall at the operating
  point is around 20–50%, and a word-stress NO-GO with phrase metrics GO is a legitimate result. The background
  quotes:
  - ±40 ms flips on synthetic and VCTK, pooled and per group;
  - both inconclusive budget populations;
  - `assignmentAmbiguous` rates;
  - the confident-subset result.

  The report then covers:
  - the training-set counts (positives, negatives, dropped negatives and why), the folds and the frozen τ;
  - the model's coefficients or trees;
  - every gate line for each arm × boundary source, the B1 and B2 comparison, the McNemar table and the coverage
    figures (with the known-text and ASR-transcript variants of the 134);
  - the artefact-control AUC;
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
- Arm choice, the feature variant, τ and the envelope quantiles use tuning-side data only. Held-out numbers are
  reported for both arms but never used to choose. speechocean762 and the 134 never enter training or τ. Nobody
  pushes for a GO.

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
  coverage may be too low for CPO even if precision is good. Arm B is CTO's hedge against this.
- **Runtime boundaries** (Whisper) are noisier than MFA, which is why GO is judged on them.
- **The envelope is small:** about 8 bundled voices plus the tuning speakers who share prompts. Phrase metrics under
  n 30 can't be evaluated.
- **The 134 words mostly aren't starter words.** Recall there measures the classifier, not the starter claim.

## Decided (CTO, 2026-11-24 16:56)

1. **Model family:** logistic regression first, with boosted trees only if it misses gate 2 and time allows
   (accepted).
2. **Envelope:** an empirical central interval, with quantiles chosen on the CV Wilson upper bound (accepted, and
   markup 5).
3. **Front end:** replaced by markup 1, two arms (A: count-matched and not ambiguous; B: top-k), picked on the tuning
   side, with B preferred if both pass.
4. **Evaluation words outside the starter set** use CMUdict primary stress with automatic heteronym exclusion
   (accepted).
5. **Spec path:** `specs/27-…` (accepted).

## How to test (Raph)

Every step is run by the build agent and repeated by the reviewer.

1. `swift test --package-path Packages/AccentKit --filter Spike27Tests` checks that:
   - the training and τ code refuse held-out and L2 inputs;
   - transplantation on a pulse-train word swaps the measured d, e and p between the two nuclei within tolerance;
   - the heteronym table resolves or excludes every starter heteronym;
   - the identity PSOLA leaves the measured features within tolerance;
   - arm B picks the N_w most prominent nuclei in time order and abstains only below N_w;
   - the speechocean762 label rule and the overlap drop by utterance id match the spec;
   - a prompt with under 30 natural takes is NOT EVALUATED, and TTS counts at most once per voice;
   - two runs are identical.
2. `scripts/agreement.sh --suite spike27` prints every gate line with n and Wilson intervals for each arm (A, B) ×
   boundary source (oracle MFA, runtime Whisper). It also prints the B1/B2 McNemar table, coverage (known-text and
   ASR-transcript), the artefact-control AUC and the envelopes. It ends `Spike 27: GO`, `Spike 27: NO-GO` or
   `Spike 27: NO-GO (oracle-only)`.
3. Listen to the 20 spot-check negatives (taste call, Raph).
4. The report's identity header matches the head (`scripts/check-report-identity.sh`).

## Implementation notes

**Result: `Spike 27: NO-GO`** (report `docs/agreement/reports/spike27-69675122.{json,md}`, clean tree, identity check OK).
Partial: word stress (arm B, runtime) NO-GO; phrase monotone NOT EVALUATED (NO-GO); final direction NOT EVALUATED
(NO-GO); nPVI shown only. No `Thresholds` key, app, AMPipeline or version change; configDigest is spec 26's (69675122).

**Where it lives.**
- `AMSpike27` is a new evaluation-only library target. Its only consumers are `am-eval` and `Spike27Tests`; it isn't
  in `modules` and isn't linked by the app or AMPipeline. It holds the front-end measures, the TD-PSOLA, the swap,
  features, logistic regression, boosted trees, arms A/B/C, the envelopes, the guards and the speechocean762 rule.
  I split it out of `am-eval` because tests can't link an executable target cleanly.
- `am-eval spike27 --stage prepare|negatives|train|evaluate|all` lives in `Sources/am-eval/Spike27*.swift`.
- Run it with `scripts/spike27.sh` or `scripts/agreement.sh --suite spike27 [--write-report]`. It runs niced with
  3 jobs and writes its work files and `listen/` outside the worktree.
- Two small additions in eval tooling:
  - `am-eval record-timings --set tts-references`, so the TTS references get Whisper word times for the synthetic
    set's runtime jitter. ASR ran locally once; never in CI.
  - `CTCAligner.logProbabilities` is now public, for arm C.

**What was built (tuning side only; `Spike27Guard` refuses held-out VCTK, L2, speechocean762 and held-out speakers;
tested).**
- **Front end:** spec 25's detector at spec 26's frozen grid.
  - Per nucleus: d (region), e (±30 ms), f0 residual from a least-squares line over the take's voiced frames, and
    spectral balance (100–1,000 Hz minus 1,000–4,000 Hz).
  - Runtime known text goes through spec 03's shipped aligner. Present and substituted prompt words take the heard
    span; with LCS-only matching, 124 instead of 69 of the 134 are placed.
- **PSOLA** is written from Moulines & Charpentier.
  - The identity pass reproduces the input exactly, because overlap-add is normalised by the summed windows.
  - Each swap stretch is widened by up to 30 ms toward its valleys. Without this, the vowel tails outside the
    9 dB region stayed loud and split the shortened syllable (caught by the pulse-train test).
- **Negatives:** 1,739 source words gave 493 negatives. Dropped: 1,103 where the front end found fewer than N nuclei
  in the MFA span, 91 for clipping, 52 for pitch-mark coverage. 163 kept swaps have a duration factor outside
  [0.5, 2].
- **CV:** the manifest's 6 speaker folds. Per arm: 2 families × 4 variants.
  - τ is the smallest grid value with CV false flags at point ≤ 1% and Wilson upper ≤ 2%.
  - Boosted trees were run because logistic regression missed gate 2 on the first evaluation pass. Family and
    variant were still chosen on tuning CV only.
  - Arm B was picked on the tuning side: logistic regression, f0 variant, τ 0.42, tuning jitter 33/1,667.
- **Artefact control:** processed-vs-raw AUC 0.500 for both arms (MET). This is trivial by construction, because the
  identity pass is exact; the report says so.
  - Extra, reported control: round trip (swap, then swap back) vs raw. AUC 0.468 for arm B; 0.604 for arm A's tree
    model, which is above 0.6, so swap artefacts look learnable there.
- **Front-end signal check** (raw tuning natives, arm B, 583 words): the dictionary-stressed syllable has the
  largest d 49.9% of the time, f0 residual 52.3%, intensity 64.2% and flattest spectrum 70.2%. The first-syllable
  prior alone is 80.8%. The measures carry less information than the position prior, which is why the classifier
  can't separate swapped from natural words.

**Key numbers (arm B, runtime; full rows in the report header and in `_cache-27/logs/result.txt`).**
- Gate 1, held-out VCTK native false flags: 48/532 (9.0%), NOT EVALUATED because n < 600. Clean 1,400: 55/760
  (7.2%), NOT MET. speechocean762 correctly stressed: 171/2,266 (7.5%), NOT MET.
- Gate 2: 9/134 vs B1 27/134; McNemar discordant 2 vs 20, p = 0.00012 in B1's favour. NOT MET. ASR-transcript
  variant: 4/134. Coverage of the 134: 60 (known text), 25 (ASR).
- Gate 3: held-out pooled 25/948 (2.6%), NOT MET; synthetic 4/72 (5.6%), NOT MET.
- Gate 4 coverage: held-out candidates 56%; starter words × bundled voices 41%.
- PR curve: even at τ = 0, recall is 23% against 50% native false flags (no discrimination). Precision at the
  operating point is 3.8% at 5% prevalence and 7.6% at 10%.
- Arm A is NOT MET everywhere. Arm C (report-only, b2 CTC vowel groups with arm B's classifier) is NOT MET (3/134;
  speechocean762 false flags 3.0%).
- Phrase envelopes: 12 of 14 prompts have ≥ 30 natural takes; vctk-005 and vctk-015 are NOT EVALUATED.
  - No quantile pair meets the CV ≤ 5% bar for monotone; the widest gives 5.9%.
  - No prompt reaches 80% final-direction agreement, so the committed list is empty.
  - Held-out VCTK has at most 16 takes per prompt, so every per-prompt verdict row is NOT EVALUATED (n < 30). That
    makes both phrase claims NOT EVALUATED (NO-GO).

**Spec gaps (least-committal reading taken).**
- **Oracle L2 is NOT EVALUATED:** there's no MFA alignment of speechocean762 in the caches (MFA cache is read-only).
  The oracle source can therefore never pass, so `NO-GO (oracle-only)` can't occur here.
- **speechocean762 recall is NOT EVALUATED:** under the fixed label rule, only 4 misplaced (stress 5) words survive,
  and none has Whisper times.
- **The ambiguity check is defined by the classifier's verdict:** arm A's `assignmentAmbiguous` reads the
  classifier's own verdict, so training rows skip it; CV and evaluation apply it.
- **Arm A abstains when count ≠ context:** an assigned count in N_w that isn't the context count can't map the
  stress index, so it abstains.
- **CV envelopes are exempt from the 30-take rule:** CV builds them from the other folds' takes, since 5/6 of a prompt
  is under 30. The rule still gates which prompts are evaluated.
- **Final-direction verdict definition:** flag when the slope is outside the envelope and the class isn't the
  dominant one.
- **nPVI is read on assigned nucleus regions** (spec 25's `.nucleus` d).
- **Gate 2 isn't defined for phrase metrics:** there are no L2 phrase labels.
- **Arm C details:**
  - It uses arm B's frozen classifier and τ.
  - The word-boundary jitter can't move it, so its gate 3 is NOT EVALUATED.
  - Words whose vowel-letter groups ≠ N abstain.
- **Gate 3 uses the point estimate,** as spec 11 §4b does.

**How to test.**
1. `swift test --filter Spike27Tests`: 11 tests pass. This covers the eight listed checks, plus the decision/AUC
   check, arm C, and phrase rows under 30 being NOT EVALUATED.
2. `scripts/agreement.sh --suite spike27 --write-report`: run on a clean tree; it ends `Spike 27: NO-GO`. Two runs
   from scratch give byte-identical negatives and training files and identical gate lines.
3. The 20 spot-check negatives are in `~/dev/accent-mirror-wt/_cache-27/listen/` (`index.md`). Taste call (Raph).
4. `scripts/check-report-identity.sh docs/agreement/reports/spike27-69675122.json <commit>`: OK.
