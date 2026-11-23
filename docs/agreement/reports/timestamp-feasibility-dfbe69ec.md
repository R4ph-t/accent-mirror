# Timestamp feasibility (spec 03): FAIL

Generated 2026-11-23T12:06:44Z. WhisperKit word timings against the MFA word baseline (Montreal Forced Aligner 3.4.4, english_mfa.zip) on 155 VCTK 0.92 clips. **No stress claims.**

## Verdict

The gate (CTO ruling 2026-11-23 13:00): absolute error per boundary on **unpadded** WhisperKit word starts and ends against the MFA word baseline, each side judged on its own. A side that misses fails the gate.

| Line | Bar | Result | n | Outcome |
|---|---|---|---|---|
| Starts: median error | ≤ 40.0 ms | 90.0 ms | 2390 | FAIL |
| Starts: within 80.0 ms | ≥ 85.0% | 46.1% | 2390 | FAIL |
| Ends: median error | ≤ 40.0 ms | 110.0 ms | 2390 | FAIL |
| Ends: within 80.0 ms | ≥ 85.0% | 38.5% | 2390 | FAIL |
| Calibration (unpadded): low-probability bin has more error than high | low > high | 134.4 ms vs 128.2 ms | 2216 + 2564 | PASS |
| Warm ASR, median over clips | ≤ 900.0 ms | 108.4 ms | 154 | PASS |
| **Overall** | | | | **FAIL** |

Under the bar, or not evaluated: this report goes to CTO. Thresholds are not changed to pass.

## Identity (plan §6.6)

- `configDigest`: `dfbe69ecb19fc4dee69801d68d5a34d91f594f18446afbd7462dd3adc1dba430`
- `sourceTreeHash`: `8054118f65c468ceac9c381df78e0a6aa2af3923cacb2869a0b0a4b99858e5bb`
- Evaluated commit: `4398c83fc50d254f887a636a9f44be45681f4ac1`; clean tree: yes
- `ConfigIdentity`: algorithmVersion 1, thresholdsVersion 3, contractVersion 1, asrModelID `openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631`, pitchTrackerID `none`, voicingID `none`
- Corpus manifest hash: `1ba061d2ca470e64ae96b6aeab93251255e0505226348eb962f423fc0723e716`
- Label (baseline) hash: `e2751a293ac6a886775d0ae1bd608d6d27ef9c48a0c1f09362859899ec8dcb59` (`fixtures/vctk/mfa-word-baseline.json`)
- Toolchain: Xcode 26.2 build 17C52; swift-driver version: 1.127.14.1 Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2); macOS 26.3 (25D125); Apple M3 Max, Mac15,11

Recompute by hand:

```sh
# sourceTreeHash
git ls-tree -r --full-tree 4398c83fc50d254f887a636a9f44be45681f4ac1 | grep -v "$(printf '\t')docs/agreement/reports/" | LC_ALL=C sort | shasum -a 256
# configDigest: SHA-256 of identity.configCanonicalJSON in the JSON report (no trailing newline)
printf '%s' "$(plutil -extract identity.configCanonicalJSON raw -o - timestamp-feasibility-dfbe69ec.json)" | shasum -a 256
# corpus manifest hash, in the VCTK cache folder
shasum -a 256 <clip files> | cut -d' ' -f1 | LC_ALL=C sort | shasum -a 256
```

## Model

- `asrModelID`: `openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631`; model SHA-256 `a59b5631ca10e3067f1af5ee23d2d03c0cc6c00c8399f030ce2d99a4e98401fd`
- WhisperKit 1.1.1 (`1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4`), greedy (temperature 0, WhisperKit fallback), English, word timestamps
- model: https://huggingface.co/argmaxinc/whisperkit-coreml at `0f63a7800b00dd0226abd051b906c246e1907482`, `openai_whisper-base.en/` (MIT)
- tokenizer: https://huggingface.co/openai/whisper-base.en at `911407f4214e0e1d82085af863093ec0b66f9cd6` (Apache-2.0)
- Model that would ship: `openai_whisper-base.en`

<details><summary>File SHA-256s (22 files)</summary>

- `c4e096b2abd561f00b9b698401df3fbe1a0d0c8d2476ff19cb4e1995680e827e` `model/AudioEncoder.mlmodelc/analytics/coremldata.bin`
- `e316980638e2099e83cb1a93b903717dc12b3c2168d0ab69113764c3767696ba` `model/AudioEncoder.mlmodelc/coremldata.bin`
- `d6785fae31c3f86d60058c14c79902f716f106dd9e36af7d3fe78b9c34867fce` `model/AudioEncoder.mlmodelc/metadata.json`
- `dc74813e26fce790fe22a33dcef8be535b9dce566f38a8bdb677f5e07dcf9138` `model/AudioEncoder.mlmodelc/model.mil`
- `1d42038f84b508da5ce9b953302387ffedc097c346d36a56b765109002b6080e` `model/AudioEncoder.mlmodelc/model.mlmodel`
- `74f15e6d2f7694af54e90227cbf22fd6c04082638f163b78a909967b16edc1c7` `model/AudioEncoder.mlmodelc/weights/weight.bin`
- `7f77e6457285248f99cd7aa3fd4cc2efbb17733e63e7023ac53abe1f95785d07` `model/MelSpectrogram.mlmodelc/analytics/coremldata.bin`
- `dabdc5aa69f6ef4d97dc9499f5c30514e00e96b53b750b33a5a6471363c71662` `model/MelSpectrogram.mlmodelc/coremldata.bin`
- `66a60d0babfcae566910a6d699471efde002d92205a7d349e16989ca4d6729d3` `model/MelSpectrogram.mlmodelc/metadata.json`
- `b8063d8e57c113472ac7c2d248e44383568a018978a753c1884ac406b997a374` `model/MelSpectrogram.mlmodelc/model.mil`
- `ee77f9b67765f7abc33f16374081b2389cf1d3a89536187b241950c5a2e5d6c1` `model/MelSpectrogram.mlmodelc/weights/weight.bin`
- `e870aac5de88676c1ad93cb3939f257e6de30e5235c3f9d7686398ebecafdb8d` `model/TextDecoder.mlmodelc/analytics/coremldata.bin`
- `4b23ff9d9fe376f2b86f9cf55af3218560a4e4d692041360510fbad490c0db43` `model/TextDecoder.mlmodelc/coremldata.bin`
- `da9be60fd96a13938445fd589a54bf56f77474efd541027bfb79537ddf67d10c` `model/TextDecoder.mlmodelc/metadata.json`
- `e380edc70b68dc1e06c1ae19aaa8fd5f85a2b14242b9cc871ce5648cfb3ed3ce` `model/TextDecoder.mlmodelc/model.mil`
- `72f1214f7c8b26e467dd8233572eaa5cbe200f30a36b918d4c289f9fc8c4f401` `model/TextDecoder.mlmodelc/model.mlmodel`
- `4649599bd2d97f87ffc716e6da2f61a06c06ac5a9424dd23edc3d4bf66fb6221` `model/TextDecoder.mlmodelc/weights/weight.bin`
- `ab22779256bdb966a5dc4f033cb9ac6471e0e1e2574fda258655c8ad2a5ea700` `model/config.json`
- `ea4714d2f89ab6de18c6dead99c10fbeeb383768fa6b564d9d4d7889140d70b5` `model/generation_config.json`
- `160c1df40a60d4ef5a6014d536fd845c33aabfd1f318458ac7f87cfe91ebbe76` `tokenizer/config.json`
- `5eb60cec1e77aeeb6869a2bb5a8e01a84c3fe5d072d75369343021fe6f5310d0` `tokenizer/tokenizer.json`
- `14f84bdf4b9ecdbd4738ddc81c17a1baedfc02bb93c6e049c951e15a1b40b70d` `tokenizer/tokenizer_config.json`

</details>

## Baseline

- Montreal Forced Aligner 3.4.4; acoustic model `english_mfa.zip` (SHA-256 `2c08bd4f82c3943dd57ac09aeac99dbce17a1e1bfe9fd932c8d95cd13d971068`); dictionary `english_mfa.dict` (SHA-256 `975bf9c7791535c5aec57995e0bd2b77eb7ca364d1d974c2134e07bb0f16b079`)
- Command: `mfa align --clean --overwrite --output_format json --num_jobs 4 CORPUS english_mfa.dict english_mfa.zip OUTPUT`

## Corpus

- VCTK 0.92, archive SHA-256 `f96258be9fdc2cbff6559541aae7ea4f59df3fcaf5cf963aae5ca647357e359c`; 155 of 159 specified clips evaluated; voices p225, p226, p227, p233, p241, p252, p311, p345; texts 002, 003, 004, 005, 006, 007, 008, 009, 010, 011, 012, 013, 014, 015, 016, 017, 018, 019, 020, 024
- Not in the archive, so not evaluated: p227_007, p233_010, p241_015, p241_020 (no substitutes chosen)
- Audio: wav48_silence_trimmed/<speaker>/<speaker>_<text>_mic1.flac, as published
- Audio and transcripts from CSTR VCTK Corpus 0.92 (Yamagishi, Veaux, MacDonald; University of Edinburgh, Centre for Speech Technology Research), CC BY 4.0, https://doi.org/10.7488/ds/2645

## Accuracy

Coverage: 2390 of 2437 phrase tokens comparable (98.1%); skipped: 47 missing from WhisperKit only, 0 missing from the baseline only, 0 missing from both. Each comparable token gives one start and one end.

Mean signed unpadded error (ASR minus baseline; negative is early): starts -120.0 ms, ends -137.5 ms.

### Per speaker (unpadded, the gate's figures by voice)

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

### Padded (not the gate; padding belongs to spec 07)

Kept for comparison with the first report only. Whisper spans expanded by 80.0 ms on both sides.

| Padded boundaries | n | Median error | Within 80.0 ms | Mean error |
|---|---|---|---|---|
| Starts | 2390 | 170.0 ms | 9.3% | 200.6 ms |
| Ends | 2390 | 60.0 ms | 64.2% | 87.4 ms |
| Starts and ends pooled | 4780 | 120.0 ms | 36.8% | 144.0 ms |

### End-bias diagnostic (diagnostic baseline only, not a fix, not the gate)

Constant end-bias correction, fitted on these same clips (median signed end error): -110.0 ms. Unpadded ends after subtracting it: n 2390, median 70.0 ms, within 80.0 ms 62.5%, mean 83.1 ms. It is applied nowhere in the code path, and it is fitted and measured on the same clips, so it overstates what a correction would achieve.

### Calibration (unpadded)

Two bins split at the median word probability over comparable tokens (low: below it; high: at or above it).

| Split | Low bin: words, p range, mean error | High bin: words, p range, mean error | Outcome |
|---|---|---|---|
| 0.980 | 1108, 0.330–0.970, 134.4 ms | 1282, 0.980–1.000, 128.2 ms | PASS |

### Per phrase (unpadded, information)

| Text | n | Starts: median | Starts: within 80.0 ms | Starts | Ends: median | Ends: within 80.0 ms | Ends |
|---|---|---|---|---|---|---|---|
| 002 | 88 | 100.0 ms | 42.0% | FAIL | 100.0 ms | 42.0% | FAIL |
| 003 | 143 | 140.0 ms | 28.7% | FAIL | 140.0 ms | 26.6% | FAIL |
| 004 | 120 | 95.0 ms | 45.8% | FAIL | 110.0 ms | 39.2% | FAIL |
| 005 | 158 | 95.0 ms | 45.6% | FAIL | 110.0 ms | 41.1% | FAIL |
| 006 | 129 | 70.0 ms | 55.8% | FAIL | 90.0 ms | 48.1% | FAIL |
| 007 | 82 | 120.0 ms | 37.8% | FAIL | 145.0 ms | 28.0% | FAIL |
| 008 | 175 | 120.0 ms | 32.6% | FAIL | 130.0 ms | 26.9% | FAIL |
| 009 | 104 | 80.0 ms | 51.9% | FAIL | 110.0 ms | 32.7% | FAIL |
| 010 | 56 | 85.0 ms | 50.0% | FAIL | 100.0 ms | 39.3% | FAIL |
| 011 | 205 | 80.0 ms | 52.2% | FAIL | 90.0 ms | 46.8% | FAIL |
| 012 | 88 | 160.0 ms | 39.8% | FAIL | 195.0 ms | 29.5% | FAIL |
| 013 | 78 | 105.0 ms | 41.0% | FAIL | 160.0 ms | 32.1% | FAIL |
| 014 | 120 | 60.0 ms | 69.2% | FAIL | 70.0 ms | 63.3% | FAIL |
| 015 | 110 | 90.0 ms | 48.2% | FAIL | 100.0 ms | 45.5% | FAIL |
| 016 | 166 | 80.0 ms | 51.8% | FAIL | 115.0 ms | 43.4% | FAIL |
| 017 | 64 | 115.0 ms | 48.4% | FAIL | 185.0 ms | 35.9% | FAIL |
| 018 | 125 | 70.0 ms | 54.4% | FAIL | 90.0 ms | 46.4% | FAIL |
| 019 | 151 | 110.0 ms | 41.7% | FAIL | 130.0 ms | 32.5% | FAIL |
| 020 | 63 | 110.0 ms | 38.1% | FAIL | 140.0 ms | 27.0% | FAIL |
| 024 | 165 | 90.0 ms | 43.6% | FAIL | 110.0 ms | 32.7% | FAIL |

## Timing

- Manifest verification (SHA-256 of every file): 77.0 ms
- Model load and prewarm: 704.9 ms
- Cold ASR (first clip after load): 168.8 ms
- Warm ASR over 154 clips: median 108.4 ms, p90 143.1 ms, max 224.2 ms
- Budget: warm ASR ≤ 900.0 ms (median): PASS
- Clip length: median 5.928 s, max 9.028 s

## Comparator: Apple SpeechAnalyzer (SpeechTranscriber)

Status: comparator not present (AssetInventory status: supported) (en_US). Its assets are never downloaded or installed by this tool.

## Notes

- Clips are the official VCTK 0.92 wav48_silence_trimmed mic1 files, untrimmed by this spec: no shared 02/15 trim exists yet.
- Comparable tokens: the longest in-order match of normalised words (lower case, punctuation stripped) against the transcript's phrase tokens, on each side. The padded comparison spans are not clamped to the clip.
- 4 of the 159 specified clips are not in the VCTK 0.92 archive (p227_007, p233_010, p241_015, p241_020). They are reported, not replaced.

