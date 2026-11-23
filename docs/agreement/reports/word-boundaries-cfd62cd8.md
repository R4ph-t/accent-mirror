# Word-boundary refinement (spec 23): downstream gate FAIL, ship FAIL

Generated 2026-11-23T13:27:43Z. Refined WhisperKit word boundaries against the MFA word baseline (Montreal Forced Aligner 3.4.4, english_mfa.zip) on 155 VCTK 0.92 clips. **No stress claims.**

## Decision (CTO ruling 2026-11-23 14:05)

Aligner of record: `ctc-w2v2b960-1` (b2). `dsp-snap-1` (b1) is a diagnostic only. Shipped aligner: `whisper`, unchanged in this PR. ctc-w2v2b960-1 fails the downstream gate (Synthetic (TTS), VCTK): back to CTO, no retuning. `whisper` stays shipped.

### Ship gate: downstream verdicts (spec 07's segmenter, oracle vs b2 boundaries)

| Set | Oracle | Comparable words | Verdicts differ (≤ 2.0%) | Inconclusive: oracle → b2 (rise ≤ 2 points) | Gated by CTC confidence | Outcome |
|---|---|---|---|---|---|---|
| Synthetic (TTS) | TTS markers | 307 | 69 (22.5%); inconclusive 34, longestSyllable 29, loudestSyllable 34 FAIL | 5.2% → 16.3% (+11.1 points) FAIL | 11 | **FAIL** |
| VCTK | MFA word baseline | 2382 | 537 (22.5%); inconclusive 348, longestSyllable 199, loudestSyllable 190 FAIL | 8.7% → 18.9% (+10.2 points) FAIL | 51 | **FAIL** |

A word's verdict is spec 07's output for it: inconclusive (any syllable at low confidence), the syllable count, the index of the longest syllable and of the syllable with the highest mean intensity. It differs if any part differs. Both sets must pass.

CTC confidence (mean posterior of a word's aligned characters on the Viterbi path; 0 for a word b2 could not align) on VCTK: 2441 words, median 0.989848, 75 below `ctcConfidenceMin` 0.5 (3.1%), untuned until spec 02's tuning split is on main. Those words are inconclusive and count inside `agreement.inconclusivePairsMax` (10.0%), not as a new allowance.

### Ship prerequisites

| Prerequisite | Status |
|---|---|
| Licence on the model card at the pinned commit | Apache-2.0, verified at `22aad52d` |
| SHA-256 pin | packageSHA256 `9ae95d751153f85e…`, checked before every load |
| Size on disk | 360.2 MiB (float32) |
| Latency on the macos-26 runner | NOT RUN: waits for the manual workflow Raph adds (PENDING) |
| Cancel test (cancel at 100 ms, return within about 300 ms) | PASS |
| Downstream gate (synthetic and VCTK) | FAIL (PENDING) |
| `ctcConfidenceMin` tuned on spec 02's tuning speakers | NOT TUNED: default 0.5 until spec 02's split is on main (PENDING) |

### Reference error

| Comparison (**reported, not a gate**) | Side | Median | Within 80 ms | Mean signed | n |
|---|---|---|---|---|---|
| MFA on TTS vs TTS markers (the reference's own error) | starts | 23.5 ms | 98.4% | -24.3 ms | 313 |
| MFA on TTS vs TTS markers (the reference's own error) | ends | 25.1 ms | 94.2% | -36.8 ms | 313 |
| b2 on TTS vs TTS markers (ground truth; b2 seeded by live Whisper base.en) | starts | 27.7 ms | 87.3% | -8.1 ms | 308 |
| b2 on TTS vs TTS markers (ground truth; b2 seeded by live Whisper base.en) | ends | 56.3 ms | 73.1% | -82.1 ms | 308 |
| b2 vs MFA on VCTK | starts | 50.0 ms | 80.0% | -1.2 ms | 2390 |
| b2 vs MFA on VCTK | ends | 40.0 ms | 76.4% | -53.3 ms | 2390 |

- Quadrature **estimate** of b2's own VCTK error, sqrt(max(0, obs² − ref²)) on the medians (obs: b2 vs MFA on VCTK; ref: MFA on TTS): starts 44.1 ms, ends 31.1 ms. An estimate; no gate reads it, and nothing is netted out of any figure.
- TTS: `com.apple.voice.compact.en-US.Samantha`, SSML `<mark>` bookmarks around every word, marker resolution 11.6 ms. A word's end marker fires where the next word starts, so a pause after it counts as the word's.

### Word boundaries against MFA on VCTK (40 ms / 85% is a **reported target**, not a gate)

| Line | `whisper` | `dsp-snap-1` | `ctc-w2v2b960-1` |
|---|---|---|---|
| Role | shipped baseline | diagnostic (b1) | aligner (b2) |
| Starts: median error (≤ 40.0 ms) | 90.0 ms FAIL | 70.0 ms FAIL | 50.0 ms FAIL |
| Starts: within 80.0 ms (≥ 85.0%) | 46.1% FAIL | 59.0% FAIL | 80.0% FAIL |
| Ends: median error (≤ 40.0 ms) | 110.0 ms FAIL | 80.0 ms FAIL | 40.0 ms PASS |
| Ends: within 80.0 ms (≥ 85.0%) | 38.5% FAIL | 52.6% FAIL | 76.4% FAIL |
| Every speaker, both sides | 8 of 8 miss | 8 of 8 miss | 8 of 8 miss |
| Comparable boundaries per side | 2390 | 2390 | 2390 |
| Mean signed start / end (negative: early) | -120.0 ms / -137.5 ms | -67.6 ms / -94.1 ms | -1.2 ms / -53.3 ms |
| Boundaries moved | 0.0% | 61.6% | 97.8% |
| Refinement per clip: median / p90 / max | 0.0 ms / 0.0 ms / 0.0 ms | 5.2 ms / 8.0 ms / 13.3 ms | 32.2 ms / 50.6 ms / 99.7 ms |
| Target 40 ms / 85%, both sides and every speaker (reported, not a gate) | not met | not met | not met |

Within each cell, PASS/FAIL is against the target, not a gate.

- Correlation diagnostic (b1 only, spec 02's control pairs; diagnostic since 14:05): NOT EVALUATED. Spec 02's unmodified-control and sham-control sets are not on this machine (spec 02 is not merged), so Δr cannot be computed. NOT EVALUATED is not a pass.
  - Bootstrap: 2000 resamples over clips, seed 23
- ≤ 2% placement-diff rule (§6.7): PENDING: checked in spec 11's agreement run with `aligner` in the identity (needs specs 08 and 10)

## b2 model (`ctc-w2v2b960-1`)

- facebook/wav2vec2-base-960h at `22aad52d435eb6dbaf354bdad9b0da84ce7d6156`, Apache-2.0. Licence evidence: README.md front matter `license: apache-2.0` at https://huggingface.co/facebook/wav2vec2-base-960h/raw/22aad52d435eb6dbaf354bdad9b0da84ce7d6156/README.md; Hub API cardData.license apache-2.0 at that revision
- Converted package (Core ML mlprogram, float32): `packageSHA256` `9ae95d751153f85e2282590668e2ab1ffd4db3b1a10292ccdd3660b50f7ee4d8`, 360.2 MiB on disk; fp16: not converted (the spec names float32)
- Verify 253.2 ms; compile and load 2910.6 ms; compute units `all`
- Per clip on this Mac (Apple M3 Max, Mac15,11), warm: median 32.2 ms, p90 50.6 ms, max 99.7 ms over 154 clips
- Cancellation: a 17.0 s call takes 93.9 ms with compute units `all`, too short to cancel 100 ms in, so the trials load the same verified package with `cpuOnly`, where the call takes 492.9 ms. Cancel 100 ms in, 5 trials: all CancellationError: yes; returned 0.1, 0.0, 0.0, 0.0, 0.1 ms after the cancel (about 300 ms allowed); model still loaded: yes. **PASS**
- `macos-26` runner latency: NOT RUN: needs a manual workflow on GitHub's macos-26 runner that Raph adds by hand (.github/ is off-limits to agents)

A downstream FAIL goes to CTO with no retuning; NOT EVALUATED is not a pass. No threshold is changed to pass.

## Identity (plan §6.6)

- `configDigest` (the shipped aligner's identity): `cfd62cd8badc5191fd60fa2a903ff229ff1b5d7b75a2710aba19bde5f095af00`
- `sourceTreeHash`: `d7aafe0de03004768bce1f9aadf22096dcc7a1961361f34a10c9f21d26452757`
- Evaluated commit: `68abae13c61261de7d520e8398ff71adba29558d`; clean tree: yes
- `ConfigIdentity`: algorithmVersion 1, thresholdsVersion 5, contractVersion 2, asrModelID `openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631`, pitchTrackerID `none`, voicingID `none`, aligner `whisper`
  - `whisper`: configDigest `cfd62cd8badc5191fd60fa2a903ff229ff1b5d7b75a2710aba19bde5f095af00` (pitchTrackerID `none`)
  - `dsp-snap-1`: configDigest `fbce8e403fb2a9397828bd5e4e54c7546428528e58e59ffa21013f3926d9e323` (pitchTrackerID `pyin-1`)
  - `ctc-w2v2b960-1`: configDigest `1ba658bf703db9db51e2c8bb0b9e9c59ad31f2a8e2ab2dcc405632a1ddb65314` (pitchTrackerID `none`)
- Corpus manifest hash: `1ba061d2ca470e64ae96b6aeab93251255e0505226348eb962f423fc0723e716`
- Label (baseline) hash: `e2751a293ac6a886775d0ae1bd608d6d27ef9c48a0c1f09362859899ec8dcb59` (`fixtures/vctk/mfa-word-baseline.json`)
- Toolchain: Xcode 26.2 build 17C52; swift-driver version: 1.127.14.1 Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2); macOS 26.3 (25D125); Apple M3 Max, Mac15,11
- Whisper words: spec 03 replay `fixtures/timestamps/openai_whisper-base.en`; asrModelID `openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631`
- Thresholds: `wordBoundaries.snapWindowMs` 150, `wordBoundaries.intensityDropDB` 10 (spec default, untuned)

Recompute by hand:

```sh
# sourceTreeHash
git ls-tree -r --full-tree 68abae13c61261de7d520e8398ff71adba29558d | grep -v "$(printf '\t')docs/agreement/reports/" | LC_ALL=C sort | shasum -a 256
# configDigest: SHA-256 of identity.configCanonicalJSON in the JSON report (no trailing newline)
printf '%s' "$(plutil -extract identity.configCanonicalJSON raw -o - word-boundaries-cfd62cd8.json)" | shasum -a 256
```

## Corpus

- VCTK 0.92, archive SHA-256 `f96258be9fdc2cbff6559541aae7ea4f59df3fcaf5cf963aae5ca647357e359c`; 155 of 159 specified clips evaluated; voices p225, p226, p227, p233, p241, p252, p311, p345
- Not in the archive, so not evaluated: p227_007, p233_010, p241_015, p241_020
- Audio and transcripts from CSTR VCTK Corpus 0.92 (Yamagishi, Veaux, MacDonald; University of Edinburgh, Centre for Speech Technology Research), CC BY 4.0, https://doi.org/10.7488/ds/2645

## `whisper`: per speaker (unpadded)

| Speaker | n | Starts: median | Starts: within 80.0 ms | Starts | Ends: median | Ends: within 80.0 ms | Ends |
|---|---|---|---|---|---|---|---|
| p225 | 289 | 90.0 ms | 49.8% | FAIL | 110.0 ms | 41.2% | FAIL |
| p226 | 310 | 100.0 ms | 43.9% | FAIL | 130.0 ms | 35.8% | FAIL |
| p227 | 294 | 100.0 ms | 43.5% | FAIL | 120.0 ms | 37.1% | FAIL |
| p233 | 301 | 100.0 ms | 42.9% | FAIL | 130.0 ms | 35.9% | FAIL |
| p241 | 282 | 90.0 ms | 48.9% | FAIL | 115.0 ms | 40.4% | FAIL |
| p252 | 306 | 90.0 ms | 46.1% | FAIL | 110.0 ms | 38.9% | FAIL |
| p311 | 304 | 80.0 ms | 50.3% | FAIL | 110.0 ms | 42.1% | FAIL |
| p345 | 304 | 100.0 ms | 43.4% | FAIL | 120.0 ms | 37.2% | FAIL |

## `dsp-snap-1`: per speaker (unpadded)

| Speaker | n | Starts: median | Starts: within 80.0 ms | Starts | Ends: median | Ends: within 80.0 ms | Ends |
|---|---|---|---|---|---|---|---|
| p225 | 289 | 60.0 ms | 62.6% | FAIL | 70.0 ms | 57.4% | FAIL |
| p226 | 310 | 80.0 ms | 51.9% | FAIL | 90.0 ms | 46.8% | FAIL |
| p227 | 294 | 70.0 ms | 57.8% | FAIL | 80.0 ms | 50.3% | FAIL |
| p233 | 301 | 60.0 ms | 59.1% | FAIL | 80.0 ms | 53.8% | FAIL |
| p241 | 282 | 70.0 ms | 62.1% | FAIL | 80.0 ms | 53.5% | FAIL |
| p252 | 306 | 70.0 ms | 57.2% | FAIL | 80.0 ms | 51.6% | FAIL |
| p311 | 304 | 60.0 ms | 65.5% | FAIL | 70.0 ms | 55.9% | FAIL |
| p345 | 304 | 75.0 ms | 56.6% | FAIL | 80.0 ms | 51.3% | FAIL |

Rule that set each boundary (Open question 2: later offset for ends, earlier onset for starts), over all words:

| Side | voicing | intensity | tie | unchanged |
|---|---|---|---|---|
| Starts | 323 (13.2%) | 281 (11.5%) | 0 (0.0%) | 1837 (75.3%) |
| Ends | 778 (31.9%) | 590 (24.2%) | 34 (1.4%) | 1039 (42.6%) |

Recorded for CI replay: `fixtures/timestamps/openai_whisper-base.en+dsp-snap-1`, recordingsSHA256 `62ba37d343222e638e58def777b8780a2674777415743e9b9b6803ff3e9f9d3a`; this run matches the recording: yes

## `ctc-w2v2b960-1`: per speaker (unpadded)

| Speaker | n | Starts: median | Starts: within 80.0 ms | Starts | Ends: median | Ends: within 80.0 ms | Ends |
|---|---|---|---|---|---|---|---|
| p225 | 289 | 50.0 ms | 83.4% | FAIL | 40.0 ms | 77.9% | FAIL |
| p226 | 310 | 60.0 ms | 72.3% | FAIL | 40.0 ms | 71.3% | FAIL |
| p227 | 294 | 60.0 ms | 72.4% | FAIL | 40.0 ms | 71.8% | FAIL |
| p233 | 301 | 50.0 ms | 82.7% | FAIL | 40.0 ms | 78.1% | FAIL |
| p241 | 282 | 40.0 ms | 85.5% | PASS | 40.0 ms | 77.3% | FAIL |
| p252 | 306 | 50.0 ms | 81.4% | FAIL | 40.0 ms | 79.4% | FAIL |
| p311 | 304 | 50.0 ms | 84.2% | FAIL | 30.0 ms | 78.6% | FAIL |
| p345 | 304 | 50.0 ms | 78.3% | FAIL | 40.0 ms | 77.3% | FAIL |

Recorded for CI replay: `fixtures/timestamps/openai_whisper-base.en+ctc-w2v2b960-1`, recordingsSHA256 `39edd9e55c2c0eedb52839a8af4d28ef9c5ec470bd607cdfda1c317d098fad57`; this run matches the recording: yes

## Notes

- Whisper words are spec 03's committed replay of WhisperKit base.en on these clips (`fixtures/timestamps/openai_whisper-base.en`), so no ASR runs here; refiners read the same 16 kHz audio WhisperKit was given.
- Since the CTO ruling of 2026-11-23 14:05 the ship gate is downstream (spec 07's verdicts, oracle vs b2); spec 03's 40 ms / 85% bar on unpadded starts and ends is a reported target. The clips are spec 03's set (the 8 bundled voices); the number of record is the re-run on spec 02's 12 held-out speakers once spec 02 is on main.
- Nothing was tuned: `ctcConfidenceMin` is the 0.5 default and b1's `intensityDropDB` the 10 dB default, because spec 02's tuning split is not on main.
- End-bias diagnostic for `whisper` (fitted and measured on these same clips; applied nowhere, not a fix, not the gate): median signed end error -110.0 ms; ends after subtracting it: median 70.0 ms, within 80 ms 62.5%. Any rule change would have to be chosen on spec 02's tuning speakers.
- End-bias diagnostic for `dsp-snap-1` (fitted and measured on these same clips; applied nowhere, not a fix, not the gate): median signed end error -70.0 ms; ends after subtracting it: median 60.0 ms, within 80 ms 63.1%. Any rule change would have to be chosen on spec 02's tuning speakers.
- End-bias diagnostic for `ctc-w2v2b960-1` (fitted and measured on these same clips; applied nowhere, not a fix, not the gate): median signed end error -40.0 ms; ends after subtracting it: median 40.0 ms, within 80 ms 85.7%. Any rule change would have to be chosen on spec 02's tuning speakers.
- 4 specified clips are not in the VCTK 0.92 archive (p227_007, p233_010, p241_015, p241_020), as in spec 03.
