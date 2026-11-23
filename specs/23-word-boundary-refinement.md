# 23: Word-boundary refinement

Status: Ready · Branch: – · Depends on: 03 (WhisperKit word timings, the unpadded bar and its eval), 04 (pYIN),
07 (the segmenter the downstream gate runs) ·
Estimate: 6–8 h agent run + 1.5 h Raph review · Risk: high

Source: CTO ruling on spec 03 (2026-11-23 13:00 Europe/Paris, relayed by Accent Mirror Lead). WhisperKit `base.en`
fails spec 03's word-boundary bar: its word ends come systematically early against the MFA baseline. This spec adds
an on-device refinement step after Whisper and gates it on spec 03's corrected bar (unpadded starts and ends). Risk is
high because candidate b2 fetches third-party weights and would edit `THIRD_PARTY_NOTICES.md` and `Resources/Models/`.

## Goal

Move each Whisper word boundary closer to where the word really starts and ends, on device, with no network, so
that refined boundaries pass spec 03's bar: on **unpadded** word starts and ends, reported separately per side and
per speaker, median absolute error ≤ 40 ms and at least 85% within 80 ms on each side. Two candidates are compared.
The **simplest one that passes** ships. If b1 passes, b2 isn't built beyond the evaluation it needs.

## Behaviour

### The seam

- `protocol WordBoundaryRefiner: Sendable` with an `id` (the `aligner` value below) and
  `refine(_ words: [WordTimestamp], samples: [Float], sampleRate: Double) async throws -> [WordTimestamp]`. It keeps
  word order and text. It only moves `start` and `end`: never earlier than the previous word's refined end, never
  later than the next word's refined start, and never outside the take. Probabilities are unchanged.
- `WhisperOnly` (id `whisper`) returns the input unchanged. It's the baseline and the fallback.
- Refinement runs after ASR and before syllable segmentation (spec 07). Spec 07 takes word boundaries from an
  injected source, so it doesn't import this spec.
- Cancellation (§8.2): `Task.isCancelled` is checked at least every 50 ms of work. A cancel 100 ms into a call
  returns `CancellationError` within about 300 ms, with no partial result and no teardown of any loaded model.

### Candidate b1: DSP snapping (`dsp-snap-1`)

- For each Whisper boundary, search ±150 ms (`Thresholds.wordBoundaries.snapWindowMs`), clamped as above.
- **Ends:** move the end to the word's voicing offset (the last voiced frame of spec 04's `PYINTracker` in the
  window, plus one hop) or its intensity offset (the first frame after the last local intensity peak where frame RMS
  falls below that peak − `intensityDropDB`), whichever is later. Intensity is frame RMS in dBFS, 10 ms hop,
  20·log10(RMS), the same definition as spec 05.
- **Starts:** move the start to the voicing or intensity onset (the mirror rule), whichever is earlier, only when
  that onset is inside the window.
- If no onset or offset is found in the window, the boundary stays where Whisper put it.
- No new weights and no new dependency. Our own pYIN (spec 04) and vDSP only.

### Candidate b2: CTC forced aligner in Core ML (`ctc-w2v2b960-1`), only if b1 fails

- Model: `facebook/wav2vec2-base-960h`, licence **Apache-2.0** (model card `license: apache-2.0`, checked at commit
  `22aad52d435eb6dbaf354bdad9b0da84ce7d6156`). That's GPL-3.0-compatible. About 94M parameters, float32.
- **Rejected:** MMS and torchaudio `MMS_FA`. The MMS checkpoints (`facebook/mms-300m`, `mms-1b-all`) are CC-BY-NC
  4.0, which is not GPL-compatible.
- Fetched at build time like Whisper (spec 03), never committed and never in LFS. `scripts/fetch-ctc.sh` downloads
  the pinned commit, checks the SHA-256 of every file, and converts to Core ML with pinned `coremltools`. The
  converted package's SHA-256 is recorded in `Resources/Models/wav2vec2-base-960h/manifest.json`, and any mismatch
  fails the fetch and the load. LICENSE and NOTICE sit next to the manifest. `THIRD_PARTY_NOTICES.md` gains a section
  with the full Apache-2.0 text.
- Alignment: CTC forced alignment (Viterbi over the character emissions) of the phrase transcript, restricted to
  each Whisper word's span ± 150 ms, giving word starts and ends.
- Report: model size on disk (fp32 and fp16 if converted), load time, and per-clip latency (median, p90, max) on an
  M-series Mac. Latency on the GitHub `macos-26` runner is measured by a manual workflow that Raph adds by hand (the
  exact workflow diff goes in the PR). Until then, that line is NOT RUN. The report also covers the cancellation
  contract above (cancel at 100 ms, return within about 300 ms).

### Identity

- `ConfigIdentity` gains `aligner: String` (`whisper`, `dsp-snap-1` or `ctc-w2v2b960-1`), so
  `AnalysisIdentity.config.aligner`, `configDigest` and the L1/L2 cache keys change with it. Adding the field is a
  contract change: bump `contractVersion`, re-record the golden JSON and append a golden digest. Changing which
  aligner ships bumps `algorithmVersion`.
- New tunables go in `Thresholds.wordBoundaries` (`snapWindowMs` 150, `intensityDropDB`, with a default of 10 dB,
  marked untuned), mirrored in `docs/thresholds.md`. Bump `thresholdsVersion`. **Check main first:** main is at 2,
  spec 03 makes it 3, and spec 07 takes the next one. Use whatever is next when you merge `origin/main`.

### Evaluation (gate)

- Same set and baseline as spec 03: the VCTK held-out clips, WhisperKit `base.en`, and the MFA word baseline (a
  baseline, not ground truth). Same unpadded bar per side and per speaker. The report puts `whisper`, `dsp-snap-1`
  and (if built) `ctc-w2v2b960-1` side by side.
- **b1's extra gate, so snapping doesn't fake stress:** b1 uses intensity to move ends, which can couple duration to
  intensity. On spec 02's unmodified-control and sham-control pairs (when spec 02's sets are on the machine), compute
  the Pearson correlation between syllable duration and mean intensity with `whisper` boundaries and with
  `dsp-snap-1` boundaries (syllables split proportionally to phone count, the same split for both). b1 passes this
  gate only if the bootstrap 95% CI of Δr = r_snap − r_whisper has its lower bound ≤ 0 (2,000 resamples, seed in the
  report). If spec 02's sets are missing, the line is NOT EVALUATED, which is not a pass.
- The ≤ 2% placement-diff rule on synthetic and unmodified controls (§6.7) still applies to whichever aligner ships.
  It needs specs 08 and 10, so it's checked in the agreement run (spec 11) with `aligner` in the identity. This spec
  records it as a pending line, not a pass.
- Decision: ship b1 if it passes the unpadded bar on both sides and the correlation gate. Otherwise build and
  evaluate b2, and ship it if it passes the bar. If neither passes, nothing ships (`whisper` stays), the report is
  FAIL, and it goes to CTO.

### CTO ruling on b2 and the ship gate (2026-11-23 14:05 Europe/Paris)

This ruling came after the first build (#27): b1 missed the unpadded bar on both sides, and b2 missed it narrowly. It
**supersedes** the Goal's "simplest one that passes", the Decision bullet above and b1's place on the ship path
wherever they differ. The rest of this spec stands.

1. **b2 (`ctc-w2v2b960-1`) is the aligner.** b1 (`dsp-snap-1`) leaves the ship path. Its code, tests and report
   column stay as a test diagnostic only, and its Δr line is diagnostic too.
2. **Reference error, reported, never netted out of a gate.** For each side (starts, ends), the report gives three
   numbers (median, share within 80 ms, mean signed, n):
   - MFA-on-TTS against the TTS markers: the reference's own error. The TTS audio is the eval phrase texts spoken by
     a pinned on-device voice, with SSML `<mark>` bookmarks as the word truth.
   - b2-on-TTS against the TTS markers: real ground truth.
   - b2 against MFA on VCTK.

   It also gives a quadrature estimate sqrt(max(0, obs² − ref²)) of b2's own VCTK error, where obs is b2-vs-MFA and
   ref is MFA-on-TTS. It is labelled **estimate**, and no gate reads it.
3. **The v1 ship gate is downstream.** Run spec 07's segmenter on oracle boundaries (TTS markers for the synthetic
   set, MFA for VCTK) and on b2's boundaries, with everything else identical. Compare the per-word verdicts:
   - The word verdict at this stage is spec 07's output for the word: inconclusive (any syllable at low confidence),
     the syllable count, the index of the longest syllable and the index of the syllable with the highest mean
     intensity. A word's verdict differs if any part differs.
   - **Pass** if verdicts differ on ≤ 2% of comparable words **and** the inconclusive rate under b2 is at most 2
     points above the rate under the oracle. This is checked separately for the synthetic set and for VCTK, and both
     must pass.
   - When spec 08 lands, it re-runs the same harness with its placement verdicts. A FAIL there sends b2 back to CTO.
   - The 40 ms / 85% numbers become a **reported target, not a gate**. The `wordTimestamps` rows keep their values.
4. **Confidence gating.** b2 gives each word a CTC confidence (0–1). State its definition in the PR, for example the
   mean posterior of the word's aligned characters. A word below `Thresholds.wordBoundaries.ctcConfidenceMin` gets
   an inconclusive verdict: the adapter into spec 07's `WordSpan` sets its probability to 0, so c_w = 0 and every
   syllable is low.
   - The threshold is set on **spec 02's tuning speakers only**. Until spec 02's split is on main, it is the default
     0.5, marked untuned, and b2 doesn't ship.
   - Those inconclusives count inside the existing ≤ 10% inconclusive budget (`agreement.inconclusivePairsMax`).
     They are not a new allowance.
   - The threshold and the two gate values (`verdictDiffMax` 0.02, `inconclusiveRiseMaxPoints` 0.02) go in
     `Thresholds.wordBoundaries`, with a `thresholdsVersion` bump.
   - `ConfigIdentity` (reached through `AnalysisIdentity.config`) gains `alignerModelSHA256`: the converted package's
     SHA-256 for b2, and `none` for `whisper` and `dsp-snap-1`. That's part of the contract change already in this
     spec.
5. **The number of record** is the re-run on spec 02's 12 held-out speakers once spec 02 is on main. It doesn't block
   spec 07, and it never tunes anything.
6. **Before b2 ships, the report has:**
   - the licence verified on the model card at the pinned commit;
   - the SHA-256 pin;
   - the size on disk;
   - latency on the `macos-26` runner, from the manual workflow Raph adds; until then that line is NOT RUN and b2
     doesn't ship;
   - a passing cancel test (cancel at 100 ms, return within about 300 ms).
7. **Shipping b2:**
   - sets the shipped aligner to `ctc-w2v2b960-1` and bumps `algorithmVersion`;
   - moves the manifest, LICENSE and NOTICE to `Resources/Models/wav2vec2-base-960h/`;
   - adds the `THIRD_PARTY_NOTICES.md` section with the full Apache-2.0 text.

   The `Resources/Models/` and `THIRD_PARTY_NOTICES.md` changes need Raph's OK at merge. If the ship conditions
   aren't all met when this spec's PR is otherwise ready, it merges with `whisper` still shipped and the ship lines
   marked PENDING, and the ship flip follows as its own small PR.
8. **If b2 fails gate 3**, it goes back to CTO. There's no retuning, and nothing is ever chosen on held-out data.

## Defaults

- b1 is built and evaluated first. b2 starts only if b1 fails, and the PR says which gate b1 failed.
- Replay in CI: the refined boundaries for the spec 03 clips are recorded as JSON next to spec 03's replays, and a
  package test replays them. CI never runs ASR or the CTC model.
- The report is `docs/agreement/reports/word-boundaries-<configDigest8>.{json,md}`, with spec 03's identity header.

## Guardrails

- On device at runtime. No network calls, analytics or accounts. A test with networking denied runs the refiner.
- No weights in git. A hash mismatch fails the fetch and the load.
- Never lower the 40 ms / 85% bars, and never tune on held-out speakers. `intensityDropDB` and any b1 constant are
  chosen on tuning speakers only (spec 02's split), never on the 12 held-out speakers the gate uses.
- No AppKit or UIKit in AccentKit. Swift 6 strict concurrency.
- Don't edit the `Makefile` or `.github/`. List the exact diffs under "Hand follow-up for Raph".

## Out of scope

- Syllable boundaries inside a word (spec 07). Padding as an analysis window (spec 07). Bundling weights in the app
  (a release decision).

## Open question (built with the default)

1. **Which reference for "start/end".** Default: MFA word boundaries, as in spec 03. Where MFA and Whisper disagree
   on the word sequence, that boundary isn't comparable, as in spec 03.
2. **b1 where voicing and intensity disagree.** Default: the later offset for ends and the earlier onset for starts,
   since Whisper's error is early ends. Report the share of boundaries where each rule won.

## How to test (Raph)

1. `make check` is green.
2. `swift test --package-path Packages/AccentKit --filter WordBoundaryRefinerTests` passes:
   - on a synthetic word (a voiced carrier with a known offset) whose Whisper end is 120 ms early, `dsp-snap-1`
     moves the end to within 20 ms of truth;
   - a boundary is never moved past the neighbouring word's refined boundary or outside the take;
   - with no offset in ±150 ms, the boundary is unchanged;
   - a cancel 100 ms in returns `CancellationError` within about 300 ms;
   - `ConfigIdentity` with a different `aligner` gives a different `configDigest`;
   - the replay of the recorded refined boundaries runs with networking denied.
3. Local: `scripts/eval-word-boundaries.sh` writes the report with unpadded start and end tables per side and per
   speaker for each aligner, the correlation gate (or NOT EVALUATED), and PASS / FAIL. A FAIL goes to CTO.
4. If b2 was built: `scripts/fetch-ctc.sh` fetches and verifies, a tampered file fails, and the report shows size,
   latency and the cancellation result.

## Implementation notes

**Under the CTO ruling of 2026-11-23 14:05:** b2 (`ctc-w2v2b960-1`) is the aligner of record, and b1 is a diagnostic.
The ship gate is downstream, and b2 **fails it on both sets**: spec 07's word verdicts under b2's boundaries differ
from those under oracle boundaries on 22.5% of words, against a 2% bar. The inconclusive rate also rises by 10–11
points, against a 2-point bar. This goes to CTO with no retuning. `whisper` stays shipped, `algorithmVersion` stays
1, and every ship line is PENDING or FAIL. The report is `docs/agreement/reports/word-boundaries-<configDigest8>.{json,md}`.

| Downstream gate | Words | Verdicts differ | Inconclusive: oracle → b2 | Outcome |
|---|---|---|---|---|
| Synthetic (TTS markers as oracle) | 307 | 22.5% | 5.2% → 16.3% | FAIL |
| VCTK (MFA as oracle) | 2,382 | 22.5% | 8.7% → 18.9% | FAIL |

Reference error, per side (median / within 80 ms / mean signed). This is reported only and never netted out of a
gate:

| | Starts | Ends |
|---|---|---|
| MFA on TTS vs markers | 23.5 ms / 98.4% / −24.3 ms | 25.1 ms / 94.2% / −36.8 ms |
| b2 on TTS vs markers | 27.7 ms / 87.3% / −8.1 ms | 56.3 ms / 73.1% / −82.1 ms |
| b2 vs MFA on VCTK | 50 ms / 80.0% / −1.2 ms | 40 ms / 76.4% / −53.3 ms |
| Quadrature **estimate** of b2's VCTK error | 44.1 ms | 31.1 ms |

- **Harness.** Spec 07's `SyllableSegmenter` runs twice per take on the same audio, voicing (`ACFVoicing`),
  pronunciations (spec 06, starter origin) and comparable words. Only the word spans differ, plus the probability:
  the oracle run carries Whisper's word probability, and b2's run carries the same probability after the CTC
  confidence gate. A word's verdict is inconclusive (any low syllable), syllable count, longest syllable index and
  loudest syllable index.
- **CTC confidence.** A word's confidence is the mean posterior, over the frames the Viterbi path spends on the
  word's characters, of the character it's on there. A word b2 can't align gets 0. Below `ctcConfidenceMin` (0.5,
  untuned), the word's `WordSpan` probability is 0, which makes it inconclusive inside the 10% budget. On VCTK, 3.1%
  of words fall below it.
- **Identity.** `ConfigIdentity.alignerModelSHA256` is b2's `packageSHA256`, and `none` otherwise. Contract 2.
  Thresholds 5, because spec 07 took 4. That adds `ctcConfidenceMin`, `verdictDiffMax` and
  `inconclusiveRiseMaxPoints`, and appends a digest after spec 07's.

The first build's notes follow. b1 and b2 still miss the 40 ms / 85% bar, which is now a reported target.

- **Seam (AMAlignment).** `WordBoundaryRefiner`, `WhisperOnly` (`whisper`) and `BoundarySearch`. `BoundarySearch`
  is the one place the clamps live: words are refined left to right, a start window runs from the previous refined
  end to the word's own recognised end, and an end window from its refined start to the next word's recognised end.
  So the next word's start can always follow, and nothing leaves `[0, take]`.
- **b1 (AMProsody, `DSPSnapRefiner`).** `AMProsody` is the lowest module allowed to import both `AMAlignment` and
  `AMPitch`. It runs pYIN once per take (spec 04) and frame RMS in dBFS (spec 05's definition, vDSP). A voicing or
  intensity edge counts only when it's a real transition inside the window: a window edge that is still voiced is
  not an offset. Rule shares are in the report (Open question 2). No constant was tuned.
- **b2 (AMAlignment, `CTCAligner`, an actor owning the `MLModel`).** One forward pass, then a banded CTC Viterbi over
  the Whisper words' letters, each word confined to its span ± `snapWindowMs`. The model's `|` separator is folded
  into blank. Word start is the first letter frame; word end is the frame after the last. A single Core ML
  prediction can't stop part-way, so `CancellableWork` returns `CancellationError` at once and drops the
  prediction's late result. The model stays loaded.
- **b2 model.** `scripts/fetch-ctc.sh` fetches facebook/wav2vec2-base-960h at `22aad52…`, checks 7 upstream SHA-256s,
  converts in a pinned venv under `.cache/` (`tools/convert_ctc.py`, `tools/ctc-requirements.txt`), and checks the
  package's 3 files and `packageSHA256`. The conversion is made byte-reproducible: the protobuf spec is re-serialised
  deterministically and `Manifest.json` gets path-derived identifiers. A clean fetch reproduces the pin. The licence
  (Apache-2.0) was re-read at the pinned commit. Because b2 doesn't ship, its pin, LICENSE and NOTICE live in
  `fixtures/models/wav2vec2-base-960h/` (eval-only, like spec 03's `fixtures/vctk/*.sha256`).
  `Resources/Models/` and `THIRD_PARTY_NOTICES.md` are untouched.
- **Eval.** `scripts/eval-word-boundaries.sh` (`am-timestamps boundaries`, sandboxed with networking denied) replays
  spec 03's committed WhisperKit base.en words on the same VCTK audio, so no ASR runs. The refined boundaries are
  recorded in `fixtures/timestamps/openai_whisper-base.en+<aligner>/`. A release run fails if it doesn't reproduce
  them, and a package test replays them with networking denied.
- **Identity.** `ConfigIdentity.aligner` (contract 2), `Thresholds.wordBoundaries` (thresholds 4), goldens
  re-recorded and digest appended. `algorithmVersion` is unchanged: the shipped aligner is still `whisper`.
- **Reference sanity check (CTO review, not a gate).** `scripts/reference-check.sh` synthesises the 20 eval phrases
  with `com.apple.voice.compact.en-US.Samantha`, with SSML `<mark>` bookmarks around every word. The bookmarks come
  back through the delegate during `write`, in whole 256-sample buffers, so the resolution is 11.6 ms. The audio is
  aligned through `scripts/mfa-align.sh` (same MFA, models and command, new opt-in input-corpus mode). MFA against the
  marks, MFA minus mark: starts median 23.5 ms, 98.4% within 80 ms, mean signed −24.3 ms; ends median 25.1 ms,
  94.2%, −36.8 ms (n 313); ends of words with no punctuation after them median 24.3 ms, 97.9%, −28.1 ms (n 281).
  End marks fire where the next word starts, so a pause after a word counts as part of it. The check skips cleanly
  with no voice or no MFA, and fetches nothing.
- **Diagnostic, not a fix.** b2's ends are early by a fairly constant amount (median signed −40 ms), the usual
  peaky-CTC effect. Any change to b2's end rule would have to be chosen on spec 02's tuning speakers, which aren't on
  main. Choosing it on these clips would be tuning on the gate.
