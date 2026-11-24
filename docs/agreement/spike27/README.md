# Spike 27 procedure (offline, evaluation tooling only)

Spec 27 asks whether two narrower claims are reachable at the existing bars: (a) word stress as a lexical target
(the most prominent syllable is CMUdict's primary stress) and (b) phrase rhythm and intonation against a per-prompt
native envelope. Nothing here ships: no app, AMPipeline or `Thresholds` change; τ, the models and the envelopes live
in the report only.

Run: `scripts/agreement.sh --suite spike27 [--write-report]` (= `scripts/spike27.sh`, niced, 3 jobs). It reads the
caches under `AM_EVAL_CACHE` and `REFERENCE_DIR`, writes its work files to `$AM_EVAL_CACHE/../spike27` and the 20
spot-check negatives to `$AM_EVAL_CACHE/../listen` (both outside the worktree). Arm C needs `MODELS_CACHE` (b2's
wav2vec2-base-960h). The TTS references' Whisper times come from
`am-eval record-timings --set tts-references --reference $REFERENCE_DIR --out $AM_EVAL_CACHE/tts-timings` (local ASR,
run once, never in CI).

Stages (`am-eval spike27 --stage …`):

1. **prepare.** Every take (VCTK tuning and held-out speakers, the TTS references, the bundled starter voices, the
   speechocean762 utterances holding a 134, clean-1,400 or speechocean762-rule word) goes through spec 25's nucleus
   detector at spec 26's frozen grid (1.5 dB, 50 ms, 9 dB, ±60 ms voicing). Per nucleus: region length d, intensity e
   (±30 ms), mean f0 and its residual from a least-squares line over the take's voiced frames, and spectral balance
   (100–1,000 Hz minus 1,000–4,000 Hz, dB). Words per boundary source: oracle = MFA (spec 07), runtime = Whisper
   base.en under the known prompt through spec 03's aligner (present and substituted words take the heard span), and
   for L2 the ASR-transcript variant (Whisper's own words, exact matches only). Targets: CMUdict primary stress,
   `heteronyms.json` first, words whose entries disagree excluded, monosyllables out of scope.
2. **negatives.** Every tuning-side take goes through the Swift TD-PSOLA (`AMSpike27/PSOLA.swift`, written from
   Moulines & Charpentier 1990) with an identity modification and is re-measured. Each native multi-syllable word
   (MFA span, arm B's nuclei) swaps its stressed nucleus with one unstressed nucleus chosen by the split manifest's
   seed: duration ratio, intensity offset and f0 contour, each stretch widened by up to 30 ms toward its valleys. A
   swap with pitch-mark coverage under 90% of the voiced span or any clipped sample is dropped and counted. The
   negative is re-measured through the same front end; its words follow the PSOLA time map. A round trip (swap, then
   swap back) is kept as an extra artefact control.
3. **train** (tuning side only; `Spike27Guard` refuses anything else). Per arm (A: count-matched and not ambiguous;
   B: top-k), per model family (logistic regression; boosted trees, depth ≤ 3, ≤ 100 trees) and per variant (tilt
   and f0 on or off), speaker-grouped CV over the split manifest's 6 folds. τ is the smallest grid value whose CV
   native false-flag point is ≤ 1% and Wilson upper bound ≤ 2%. The (family, variant) pair with the highest CV recall
   on negatives at its τ is kept (ties: logistic regression, then fewer features); the arm is B when B passes the
   tuning-side checks (CV bar and tuning jitter ≤ 2%). The artefact control is a processed-vs-raw classifier of the
   same features and family on held-out folds (AUC ≤ 0.6). Envelopes: per starter prompt, natural speakers only (the
   bundled voices and VCTK tuning speakers, runtime word times), NOT EVALUATED under 30 natural takes; the quantile
   pair is the narrowest whose speaker-grouped CV Wilson upper bound of native false flags is ≤ 5%. The
   final-direction prompt list (≥ 80% of tuning-side natives share one class) is written to
   `final-direction-prompts.json` and committed before any evaluation run. `training-manifest.json` lists every
   training take and negative (no audio).
4. **evaluate.** Every gate for each arm × boundary source on held-out VCTK, the 134 (known text and ASR transcript),
   the clean 1,400 and speechocean762 (`speechocean762.json`'s rule; utterances holding a 134 word dropped), the TTS
   synthetic set (jitter) and the bundled voices (coverage), plus arm C (report-only) and the phrase verdicts per
   prompt. Then the report: `docs/agreement/reports/spike27-<configDigest8>.{json,md}` and the build's
   `logs/result.txt`.

Files here: `heteronyms.json` (starter heteronyms), `speechocean762.json` (label rule and the 124 dropped utterances),
`final-direction-prompts.json`, `training-manifest.json`.
