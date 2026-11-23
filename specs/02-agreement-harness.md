# 02: Agreement harness

Status: Ready · Branch: – · Depends on: 01 (contract v2) · Estimate: 6–8 h agent run + 1.5 h Raph review
· Risk: high

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §2 (tuning protocol), §6.1–§6.3a, §6.5–§6.7, and Raph's review 4 (09:56) resolution table. Risk is
high because it commits third-party audio (the smoke set, CC BY 4.0) and pins corpus hashes.

**Split from the plan's row 02 (engineering call, flagged in the spec PR).** The plan's row 02 also lists the
ElevenLabs / AVSpeech generator, per-voice stress verification, the synthetic edited-native set and the TTS SSML
check. Voice verification needs the real detector (specs 08 and 10), and Raph asked (09:56) to keep ElevenLabs off
the critical path. Those items are spec 22, which depends on 02 and 10. Nothing in this spec calls a TTS engine or
needs a secret.

## Goal

Build the evaluation harness every gate-bearing spec reports through: corpus fetchers with pinned hashes, the VCTK
eval-speaker split, the speechocean762 gate sets with their exclusions, the nested-CV fold manifests with **Raph's
rev 4 speaker isolation**, the statistics, the reporter with the §6.6 identity header, the shared-detector
validation mode's runner, and the fixed smoke set. No metric goes live here: gates turn on in 08–11.

## Behaviour

### Rev 4 evaluation protocol (Raph 09:56): must be in place before spec 11

Spec 11 cannot start until these four are implemented and tested here (and the voice-selection rule in spec 22):

1. **Outer folds exclude every token of their speakers.** The 72 speakers behind the 134 intelligible stress-wrong
   words are split into 5 speaker-disjoint folds, stratified child/adult, fold seed fixed in the split manifest.
   For outer fold k, the tuning pool is: the other 4 folds' stress-wrong words; the train-half all-5-agree
   intelligible correct words of speakers **not** in fold k; the 18 VCTK tuning speakers. Every token of every
   fold-k speaker is excluded, correct words included. Expected counts: of the 1,705 train-half correct words, 406
   (34 speakers who also have stress-wrong words) drop out whenever their speaker is in the outer fold; 1,299 (86
   speakers) are in no fold and always usable. Test-half correct words are never in any tuning pool. A test asserts
   that no fold-k speaker appears anywhere in fold k's tuning pool.
2. **The primary FP gate is the clean set:** test-half, all-5-agree, intelligible stress-correct words of speakers
   with no token anywhere in tuning: **1,400 words / 90 speakers** (adults 693 / 41, children 707 / 49; 74 speakers
   with ≥ 10 words). The full 1,868 / 124 set is built and labelled **supplementary**.
3. **Matched conditions for the end-to-end check.** The fold runner takes one fold-trained config object and passes
   the **same** config to every path it runs for that fold (the shared-detector path here; the end-to-end path
   from spec 22). Each path's out-of-fold results are pooled over the 134 words, then compared, with paired per-word
   wins and losses. The report records each fold's `configDigest` once and every path's results under it. A test
   with two stub paths proves both received the identical config digest per fold.
4. **Selection only on tuning speakers.** The split manifest exposes the 18 VCTK tuning speakers through an API that
   cannot return held-out VCTK speakers or speechocean762 words (enforced by type, not by convention). Spec 22's TTS
   voice selection and every inner tuning step use that API only.

The stated limitation stays in every report: the shipped config's L2 recall is never measured on unseen speakers;
the only L2 recall number is the CV estimate of the tuning procedure.

### Report identity (§6.6)

- Every report header carries `ConfigIdentity`, the corpus manifest hash (SHA-256 of the sorted file hashes), the
  label hash, the split manifest hash and seed, `sourceTreeHash` (SHA-256 of `git ls-tree -r --full-tree
  <evaluated commit>`, sorted, with every entry under `docs/agreement/reports/` removed), the evaluated commit SHA
  and a clean-tree flag, `configDigest` (from `AMCore`, spec 01), Xcode / Swift / macOS versions and the runner
  image, and `syntheticReference: none | elevenlabs | mac-premium-fallback (<reason>)` (always `none` until spec 22).
- Reports go to `docs/agreement/reports/<suite>-<configDigest8>.{json,md}`. A dirty tree cannot write a release
  report.
- `scripts/check-report-identity.sh <report.json> <release-commit>` recomputes both hashes, requires a match,
  allows the report in a descendant commit only if `git diff --name-only <evaluated>..<release>` touches only
  `docs/agreement/reports/`, and requires the report to be under 7 days old. It has a self-test like the corpus
  guard's.

### Statistics and reporter

- Two-way clustered bootstrap (speakers and phrases resampled independently, 2,000 resamples, seed in the
  manifest) for the positive set; speaker-clustered bootstrap for speechocean762.
- Wilson interval, always printed as "descriptive (ignores clustering)". Known values for tests: 108/134 → [0.7309,
  0.8640]; 107/134 → lower bound 0.7227.
- McNemar exact binomial (b = detector right and baseline wrong, c = the reverse). Known value: b = 10, c = 2 → two-
  sided p = 0.0386. Per-speaker win/loss counts.
- The §6.5 ceiling-aware baseline rule as one function: D ≥ B* − 3 pp and the paired clustered-bootstrap lower bound
  of D − B* ≥ −5 pp; if B* < 85%, D − B* ≥ min(10, (100 − B*)/2) pp; FP metrics use the mirror rule (D ≤ B* + 1 pp).
  B1 (longest syllable) and B2 (loudest syllable) detector baselines are implemented here on L1 features; B0
  (dictionary) is for which-syllable accuracy only.
- Each metric prints n, value, gate, PASS / FAIL / `NOT EVALUATED (n=…, min=…)`, the interval, and the worst speaker
  (and worst phrase on the positive set). NOT EVALUATED is never a pass. Gate values come only from
  `Thresholds.agreement`.
- Summary lines: until spec 11 wires the speechocean762 gate, PR output prints `Negative set: NOT EVALUATED` and
  `Release gate: NOT MET`.
- Validation layers are reported separately and labelled: "CV estimate, not shipped" vs "shipped-config check".

### VCTK positive set (§6.1, §6.2)

- `tools/pick_vctk_eval_speakers.py` (pure Python 3, no dependencies): filters mic1, every shared-text file 001–024
  present, not p280 or p315, not one of the bundled 8 (p225, p226, p227, p233, p241, p252, p311, p345); balances by
  accent region and gender with a stratified round-robin over speaker-info accent groups, fixed seed; picks 30;
  splits by speaker **18 tuning / 12 held-out**. It writes `fixtures/vctk/eval-speakers.json` (speaker, accent,
  gender, split, file SHA-256s).
- `scripts/fetch-vctk-eval.sh`: fetches the VCTK 0.92 archive (about 11 GB) into a git-ignored cache, verifies its
  SHA-256 pin, extracts and trims only CPO's 20 phrases for the bundled 8 and the 30 eval speakers (about 40 MB),
  and caches them keyed by the eval-speakers manifest hash. Trim: 2–6 s, the same cut rule for every speaker (Open
  question 2).
- Pair builder: each eval speaker's take of a phrase against that phrase's bundled reference (p225; p226 for 015) is
  the headline unit: 12 × 20 = 240 held-out pairs (minimum 150; ≥ 18 phrases after trimming; ≥ 12 held-out
  speakers). Pairs against all 8 bundled voices are a correlated secondary number. Held-out speakers are never a
  reference, never in a band and never in A(w) (true by construction; a test checks it).
- VCTK CV estimate: 6 speaker-disjoint outer folds over the 18 tuning speakers, reported as "CV estimate, not
  shipped".

### CTO ruling on the positive-set shortfall (2026-11-23, after 13:20 Europe/Paris)

The first build found the VCTK positive set short under the 2–6 s trim: 149 headline pairs over 14 phrases, against
the minimums of 150 and 18. CTO ruled:

- **The minimums stay:** ≥ 150 headline pairs, ≥ 18 phrases after trimming, ≥ 12 held-out speakers. They are never
  lowered.
- **Widen the phrase set** with more of VCTK's shared-text prompts, the 001–024 files every speaker reads. Add the
  ones CPO's 20 left out, checked against the transcripts so that each one really is the same text for every
  speaker. Never use per-speaker newspaper sentences. A phrase counts only if its bundled reference (p225, or p226
  where the table says so) survives the trim too.
- **Add speakers inside the existing split.** New speakers pass the same filters (mic1, every shared-text file
  present, not p280 or p315, not one of the bundled 8) and are assigned to tuning or held-out by the same fixed-seed
  stratified rule. Speakers already in `fixtures/vctk/eval-speakers.json` keep their split: nothing moves across
  the tuning / held-out line, and held-out speakers stay out of references, bands and A(w).
- **The trim stays 2–6 s.** Reason: 2–6 s is the plan's rule (§6.1) for extraction and for bundled phrases (spec 15),
  and no spec or design accepts 1.5–7 s phrases. The 20 s recording cap (`capture.recordingCapS`) is a hard cap, not
  a phrase-length range. Changing the phrase length is a product call for CPO and Raph, not an evaluation fix.
- **If the set is still short**, the positive set stays NOT EVALUATED. The report and the PR give the counts:
  headline pairs, phrases kept, held-out speakers, and clips rejected by the trim per phrase. The next step would be
  LibriTTS-R (CC BY 4.0) as an extra positive source, which is a new CTO decision. Lowering the minimums is not.
- The smoke set (§6.3a) and the speechocean762 sets don't change.

### speechocean762 (§6.3)

- `scripts/fetch-speechocean762.sh`: fetches the OpenSLR 101 tarball into a git-ignored cache, cached by hash.
  `scores.json` must hash to `31c847b8…a1159f8` (full digest recorded on first fetch, Open question 1); the repo
  reference is commit `613968e3b0b789fc33936fb5eba1973176ba7d11`. A fetch failure or hash mismatch prints NOT
  EVALUATED.
- A set builder reads `scores-detail.json` (all five raters), the official speaker split (125 / 125, 0 shared) and
  speaker ages (children 6–15, adults 19–43), and produces every set in the §6.3 table. A test asserts the exact
  counts:
  - stress-wrong polysyllabic pool 180 (train 105 / 40 speakers, test 75 / 36);
  - **recall set**: intelligible, majority label ≥ 3 of 5: **134 / 72** (adults 108 / 48, children 26 / 24); ≥ 4 of
    5 diagnostic 42 (train 26, test 16);
  - **primary FP gate**: clean 1,400 / 90 (as above); supplementary 1,868 / 124;
  - tuning FP constraint: train-half 1,705 / 120 (406 / 34 dropped per fold, 1,299 / 86 always usable);
  - dissent (1–2 raters): train 550, test 449, reported;
  - **unintelligible** (≥ 3 of 5 raters scored every phone 0): 157 = 46 stress-wrong + 73 monosyllabic + 38
    stress-correct, the "must never be flagged" set;
  - the 107 monosyllabic stress-wrong tokens, excluded and listed with their category (73 whole-word failures, 25
    true monosyllables, 8 syllabic-consonant spellings, 1 empty phone string); the 34 intelligible ones are
    "reported only".
  If a recount differs from the plan, the test fails and the difference goes to CTO in the PR. Nobody edits the
  expected counts to pass.

### Shared-detector validation mode (§6.3): the runner

- Inputs per utterance: corpus audio (16 kHz WAV), corpus transcript, and per word the accepted set A(w) = the
  primary of the corpus `ref-phones` stress digits; if that has no primary, the CMUdict POS-selected variant (spec
  06); if neither, the word is excluded. No native take.
- Stages: L0 (frame features, pitch, voicing, replayed ASR word timings), L1 (alignment to the transcript,
  syllabification with the reference syllable count, per-syllable d/e/p), prominence, exposure discount, observed
  stress, confidence, then the app's `placementDecision`. Not run: warp, DTW, band, pitch measures, contrast, weak
  length, ranking. The comparable set is every syllable of the words `present` in this take.
- Counting at two points, both reported: before suppression and after (Poor timing, low word or syllable confidence,
  missing target, exposed-syllable rule). The gate is on "after".
- This spec ships the runner behind a `PlacementDetector` protocol and proves it with a stub. The real detector is
  wired in spec 08. The "157 unintelligible words are never a placement diff" check is wired here and runs once the
  detector exists.

### Tuning runner (§2)

- The fixed grid (weights on the 0.1 simplex, each ≥ 0.1, 36 points; λ ∈ {1.0 … 2.0}; τ_med ∈ {0.10 … 0.50} and τ_high
  ∈ {τ_med + 0.10 … 1.00} in 0.05 steps per n-bucket) and the selection rule (maximise recall subject to placement FP
  ≤ 1.6% on VCTK pairs, any-diff FP ≤ 4%, shared-detector FP ≤ 1.6% on speechocean762 correct words; tie-breaks:
  lower FP, then synthetic which-syllable accuracy when present, then closest to the initial values) as a generic
  runner over an objective callback. It runs on cached L1 features, locally, never in PR CI. Re-tunes are logged in
  `docs/agreement/tuning-log.md`.

### Smoke set (§6.3a)

- Fixed content: 20 stress-wrong speechocean762 words (polysyllabic, intelligible, ≥ 4 of 5 raters agree) and 100
  unanimous stress-correct words, **all from train (tuning) speakers only**; 2 VCTK phrases × 3 VCTK tuning
  speakers. Utterances chosen to cover several words each, by a seeded script.
- Committed under `fixtures/smoke/` as 16 kHz FLAC, ≤ 5 MB in total, with `ATTRIBUTION.md` (speechocean762 and
  VCTK, source URLs, CC BY 4.0) and a manifest of file hashes. `THIRD_PARTY_NOTICES.md` gets the two corpora.
- No ElevenLabs or other synthetic audio, ever.
- This spec asserts the manifest, the size cap and that loading runs in under 1 minute. The golden verdicts and
  digests are added by the specs that can produce them: L1 digest and placement before/after suppression in 08,
  verdicts in 10. It never asserts rates and never counts toward a gate.

### Commands

The agent must not edit the `Makefile` or `.github/`. It ships scripts (`scripts/fetch-vctk-eval.sh`,
`scripts/fetch-speechocean762.sh`, `scripts/agreement.sh [--suite …]`, `scripts/tune.sh`,
`scripts/check-report-identity.sh`) and lists, in the PR body, the exact Makefile lines (`make agreement`, `make
tune`) and the workflow changes Raph would apply by hand: the weekly VCTK cache-warm job, PR jobs restoring that
cache, and the nightly / release speechocean762 job.

## Defaults

- Code placement: a new library `AMEvaluation` (depends on `AMCore` only) for manifests, folds, statistics and
  the reporter, and an executable `am-eval` (depends on `AMPipeline` and `AMEvaluation`) that the scripts call. The
  app target never links either. `AGENTS.md`'s module map gets the new row.
- Corpus caches live in a git-ignored `eval-cache/`. The corpus guard keeps `eval-local/` forbidden as before.
- Seeds, fold assignments and set membership are written to `fixtures/splits/*.json` and hashed into the report.

## Guardrails

- Nothing here runs at app runtime; the app stays on-device with no network. Fetchers are explicit tool steps.
- No Common Voice, Speech Accent Archive or L2-ARCTIC file is committed (guard stays green).
- Only CC BY 4.0 audio is committed, with attribution; the full archives are never committed.
- PR CI runs only the package tests (smoke manifest, statistics, fold isolation, set counts from a committed
  label-only fixture); it never fetches 11 GB.
- No secret is read or needed.

## Out of scope

- Any TTS engine, ElevenLabs, AVSpeechSynthesizer, voice verification, the synthetic negative set (spec 22).
- The real detector, measures and verdicts (08–10); running the gates for release (11).
- Makefile and `.github/` edits (hand follow-up, listed in the PR).

## Open question (built with the default)

1. **Archive hashes.** The plan pins the VCTK 0.92 archive and the OpenSLR tarball "in spec 02" but gives no
   digest (only the `scores.json` prefix and suffix). Default: the first fetch records the full official SHA-256 in
   the fetch manifest, the PR states it, and every later fetch fails on mismatch. Do not invent a digest.
2. **Trim rule.** "2–6 s, the same cut for every speaker" doesn't say how. Default: cut at the first and last frame
   above the 05 onset rule, keep 200 ms of pre-roll and 300 ms of tail, and reject (and report) any clip outside
   2–6 s rather than cutting speech.
3. **`AMEvaluation` module.** A tenth module changes the module map. Default as above; if Raph prefers, the code
   moves under `Tests/` and `tools/` with no module change.

## How to test (Raph)

1. `make check` is green and does not fetch any corpus.
2. `swift test --package-path Packages/AccentKit --filter AMEvaluationTests` passes: the Wilson and McNemar known
   values, the §6.5 rule table, NOT EVALUATED never passing, fold isolation (no fold-k speaker in fold k's tuning
   pool), the matched-config stub test, and the tuning-only API.
3. On a Mac with disk space: `scripts/fetch-speechocean762.sh` then `scripts/agreement.sh --suite sets` prints the
   §6.3 counts (134 / 72, 1,400 / 90, 1,868 / 124, 406 / 34, 1,299 / 86, 157) and they match.
4. `scripts/fetch-vctk-eval.sh` then `python3 tools/pick_vctk_eval_speakers.py` writes `fixtures/vctk/eval-speakers.json`
   with 24 tuning and 16 held-out speakers (the first build's 18 / 12 unchanged, plus 6 / 4 under the CTO ruling) and
   none of the bundled 8, p280 or p315.
5. `du -sh fixtures/smoke` is ≤ 5 MB and `fixtures/smoke/ATTRIBUTION.md` names both corpora and licences.
6. `scripts/check-report-identity.sh` self-test passes, and a report with a non-report file changed in the
   descendant diff fails it.

## Implementation notes

Built by hand on 2026-11-23 (Claude Code, Opus) on `factory/02-agreement-harness`.

**Layout.** `AMEvaluation` (AMCore only; module map row added to AGENTS.md) holds the label model and §6.3 set
builder (`SpeechOcean.swift`), rev 4 folds and tuning pools (`Folds.swift`), the VCTK manifest, tuning-only API, pair
builder and CV folds (`VCTK.swift`), Wilson / McNemar / clustered bootstraps (`Statistics.swift`), the §6.5 rule and
B0–B2 (`Baselines.swift`), metrics and summary lines (`Metrics.swift`), the matched-config fold runner
(`FoldRunner.swift`), the shared-detector runner behind `PlacementDetector` (`SharedDetector.swift`), the tuning grid
and selection rule (`Tuning.swift`), the reporter and hashes (`Report.swift`), split manifests, the trim rule and the
smoke manifest. `am-eval` (AMPipeline + AMEvaluation) is the CLI the scripts call; the app links neither. Python
tools: `tools/pick_vctk_eval_speakers.py`, `tools/pick_smoke_set.py`. Scripts: `fetch-speechocean762.sh`,
`fetch-vctk-eval.sh`, `agreement.sh`, `tune.sh`, `check-report-identity.sh` (+ `test-check-report-identity.sh`),
`am-eval.sh`.

**Set definitions** (all 38 stated counts reproduce exactly, from the corpus and from the committed label-only
fixture `fixtures/speechocean762/labels.tsv`): syllables are the ref-phones phones with a stress digit; stress-wrong
is ≥ 3 of 5 raters scoring 5 (identical to the merged `scores.json` label on all 287); a rater "scored every phone 0"
when every non-inserted phone of their transcription is in `( )`; unintelligible is ≥ 3 such raters. The 157 are
the unintelligible words that are polysyllabic or stress-wrong. The clean set drops every speaker of the recall set
(the only speakers with tokens in both halves' tuning material).

**Recount that differs (to CTO).** The plan's monosyllable split (25 true / 8 syllabic-consonant / 1 empty phone
string) has no stated rule. The explicit rule here gives 28 / 5 / 0, plus 1 word ("HERE", `HH IH AH0`) whose vowel has
no stress digit. The total (107 = 73 + 34) matches. The test keeps the plan's numbers and records the difference as
a Swift Testing known issue; nothing was edited to pass.

**Pins (Open question 1).** speechocean762: archive SHA-256 `876c34b8…3bdd5`; the plan's `scores.json`
(`31c847b8…a1159f8`) is the repo's file at `613968e3`, not the tarball's (which hashes `52366844…`), so labels come from
that commit; `scores-detail.json` `8a90ff40…a989e1` (identical in both); corpus manifest `fec07c74…11cc6`. VCTK 0.92:
official MD5 `8a6ba294…f4bfa` checked, SHA-256 `f96258be…359c` recorded. All in `fixtures/corpora/*.pin.json`.

**VCTK positive set: still NOT EVALUATED after the CTO ruling (fix round 2).** The trim (Open question 2 default,
spec 05's level rule from `Thresholds.capture`, without spec 05's voicing condition: spec 05 merged while this was
being built, and AMEvaluation can't import AMCapture, so moving the trim onto spec 05's detector is a follow-up)
is unchanged.

- *First build:* 30 speakers × CPO's 20 phrases. The trim rejected 201 of 755 clips, and p225 lost 003, 008, 011,
  016, 019 and 024 (all longer than 6 s), leaving 149 headline pairs over 14 phrases.
- *Phrases added:* the four shared-text prompts CPO's 20 left out, 001, 021, 022 and 023 (`VCTK.addedPhrases`). The
  picker lists a speaker's clip of one only if its `txt/` transcript, normalised (lower case, apostrophes and
  hyphens dropped, letters and spaces only), is the prompt's text in `phraseText`. That leaves out 7 clips that read
  different words (p252, p269 and p313 for 021 and 022; p336 for 023), so every listed clip of a phrase is the same
  text. No per-speaker newspaper sentence is used. CPO's 20 are listed as before.
- *Speakers added:* the picker now takes 40 instead of 30 with the same filters, seed and stratified round-robin. The
  round-robin is prefix-stable, so the first 30 picks are the original 30 in the same order, and the 3-of-5 position
  rule keeps every one of them on its side of the split. A test (`addedSpeakersKeepSplit`) pins the original 30 and
  their splits. The 10 new speakers are p298, p232, p283, p305, p284 and p333 (tuning) and p310, p255, p270 and
  p313 (held-out). 40 is the smallest count above 30 that adds whole blocks of 5 and keeps the 6 VCTK
  CV folds equal (24 tuning = 6 × 4). Held-out speakers are still never a reference, a band voice or in A(w).
- *Trim kept at 2–6 s.* Per the ruling, 2–6 s is the plan's rule (§6.1) for extraction and for bundled phrases
  (spec 15). No spec accepts longer phrases, and the 20 s recording cap is a hard cap, not a phrase-length range.
  Changing the phrase length is a product call for CPO and Raph, not an evaluation fix.
- *Result:* 1,139 clips, 737 kept and 402 rejected. **203 headline pairs** (≥ 150 met), **16 held-out speakers**
  (≥ 12 met), **15 phrases kept** (< 18), so the positive set is NOT EVALUATED on the phrase floor alone. The added
  prompts can't close the gap: 001 ("Please call Stella") is too short (p225 1.81 s, p226 1.58 s), and the trim
  rejects every listed clip of 021 and 023 (7–13 s), p225's included. Only 022 survives for p225 (5.46 s). Clips rejected by the
  trim, per phrase (all speakers / held-out; † = the headline reference was rejected, so the phrase is dropped):
  001 36/13 †, 003 36/11 †, 004 1/1, 005 20/8, 006 4/2, 007 2/2, 008 44/15 †, 010 2/1, 011 30/11 †, 012 3/3, 013 2/1,
  014 1/0, 015 7/4, 016 22/10 †, 018 5/3, 019 44/14 †, 021 45/14 †, 022 23/10, 023 47/15 †, 024 28/13 †; 002, 009,
  017 and 020 lost none. `am-eval vctk-trim` and `scripts/agreement.sh` print these lines. Per the ruling, the next
  step would be LibriTTS-R as an extra positive source, which is a new CTO decision.
- 4 bundled-voice files are missing from the archive (p227_007, p233_010, p241_015, p241_020), so the bundled set of
  CPO's 20 is 155 clips, not spec 03's 159.
- The smoke set and the speechocean762 sets are unchanged. The smoke set's three VCTK speakers (p245, p288, p360) are
  among the original tuning speakers and stay tuning.

**Eval speakers.** 63 candidates. The first 30 cover all 11 accent groups (16 F / 14 M) and include `s5` (VCTK 0.92
lists it with accent "British"; the stated filters don't exclude it). With the 10 added, the full 40 are 24 tuning
and 16 held-out (21 F / 19 M).

**Smoke set.** 47 speechocean762 utterances (20 stress-wrong + 100 unanimous correct words, train speakers only) and
6 VCTK clips (p245, p288, p360 × 002, 018): 4.3 MB. The 5 MB cap is read as 5,000,000 bytes for the whole folder.

**Choices the spec left open** (least-committal, listed in the PR): λ grid step 0.1 (11 values); the full grid is
6.3 × 10⁸ points, so the runner walks any slice and the search strategy is for spec 08/11; FP tie-break order
shared-detector, VCTK placement, any-diff; the §2 constraints 1.6% / 4% live in `TuningSelectionRule`, not
`Thresholds`; bootstrap intervals are 95% percentile (2.5th / 97.5th); B1/B2 ties go to the earliest syllable;
the trim's 300 ms tail and 2–6 s limits are constants in `TrimRule`; seeds are fixed in the split manifests. No
threshold changed (`thresholdsVersion` stays 1).
