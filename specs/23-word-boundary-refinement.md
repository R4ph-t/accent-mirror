# 23: Word-boundary refinement

Status: Draft · Branch: – · Depends on: 03 (WhisperKit word timings, the unpadded bar and its eval), 04 (pYIN) ·
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

_(filled in by the agent)_
