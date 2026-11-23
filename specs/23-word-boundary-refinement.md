# 23: Word-boundary refinement

Status: Ready · Branch: – · Depends on: 03 (WhisperKit word timings, the unpadded bar and its eval), 04 (pYIN) ·
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

**Result: FAIL, nothing ships. `whisper` stays, and this goes to CTO.** b1 misses the unpadded bar on both sides, so
b2 was built. b2 misses it too. The report is `docs/agreement/reports/word-boundaries-<configDigest8>.{json,md}`
(155 clips, 2,390 comparable boundaries per side):

| | `whisper` | `dsp-snap-1` (b1) | `ctc-w2v2b960-1` (b2) |
|---|---|---|---|
| Starts: median / within 80 ms | 90 ms / 46.1% | 70 ms / 59.0% | 50 ms / 80.0% |
| Ends: median / within 80 ms | 110 ms / 38.5% | 80 ms / 52.6% | 40 ms / 76.4% |
| Speakers passing both sides | 0 of 8 | 0 of 8 | 0 of 8 |
| Mean signed start / end | −120 / −138 ms | −68 / −94 ms | −1 / −53 ms |

b1's correlation gate is NOT EVALUATED: spec 02's control sets aren't on main. That isn't a pass, and b1 already
fails the bar. The placement-diff rule (§6.7) is recorded as pending spec 11.

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
