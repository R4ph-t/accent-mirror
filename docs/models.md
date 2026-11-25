# Models

Model weights are never committed and never in Git LFS (AGENTS.md). Each model has a committed manifest that pins the
upstream commit and every file's SHA-256; a fetch script downloads into the git-ignored cache
(`MODELS_CACHE`, default `.cache/models`) and fails, keeping nothing, on any mismatch. The app build bundles a model
only when `--verify` passes, which never touches the network; otherwise it prints a note and the build still passes.

| Model | Used for | Manifest | Fetch | In the app |
|---|---|---|---|---|
| `openai_whisper-base.en` | word timings (spec 03) | `Resources/Models/openai_whisper-base.en/` | `make fetch-models` | `Contents/Resources/Models/openai_whisper-base.en/`, 142 MB |
| `wav2vec2-lv-60-espeak-cv-ft` | per-sound judging (`AMJudging`) | `Resources/Models/wav2vec2-lv-60-espeak-cv-ft/` | `scripts/fetch-judge-model.sh` | `Contents/Resources/Models/wav2vec2-lv-60-espeak-cv-ft/`, 302 MB |
| `wav2vec2-base-960h` | spec 23 CTC aligner, evaluation only | `fixtures/models/wav2vec2-base-960h/` | `scripts/fetch-ctc.sh` | never |

## Sound judging model

`facebook/wav2vec2-lv-60-espeak-cv-ft` (Apache-2.0; Libri-Light, public domain, and Common Voice, CC0), pinned at
commit `ae45363bf3413b374fecd9dc8bc1df0e24c3b7f4`.

- `scripts/fetch-judge-model.sh` downloads the six upstream files, checks them, and converts them with
  `tools/convert_judge_model.py` in a venv pinned by `tools/convert_judge_model.requirements.txt` (Python 3.12,
  coremltools 9.0, torch 2.15.0, transformers 5.24.1; `JUDGE_VENV`, default `.cache/judge-venv`, about 0.8 GB).
  It then checks the package's three files and `packageSHA256`, and deletes the 1.26 GB PyTorch weights.
  `--verify` checks the kept files offline.
- The conversion is bit-reproducible with the pinned venv (three independent conversions gave byte-identical
  packages), so `packageSHA256` pins what the script produces.
- The package: `LV60Int8.mlpackage`, mlprogram (macOS 14), input `audio` (1 x N float32, 16 kHz, normalised as
  (y − mean) / sqrt(var + 1e-7)), output `logprobs` (1 x T x 392 float32 log-softmax over espeak IPA, 320 samples a
  frame). N is enumerated at 2, 4, 6, 8, 10, 12 and 15 s: the caller zero-pads the raw take to the smallest bucket
  that holds it, then normalises. fp16 compute, int8 per-channel linear-symmetric weights.
- The "Bundle judge model" build phase compiles the verified package with `xcrun coremlcompiler compile` into
  `LV60Int8.mlmodelc` next to `manifest.json`, `LICENSE` and `NOTICE`, so the app never compiles at runtime. It
  skips the compile while its stamp (`packageSHA256` and the three committed files) matches the bundled copy.
- **Never open the cached `.mlpackage` in place with Core ML** (for example `coremltools.models.MLModel(path)`):
  Core ML rewrites the package's `Manifest.json` when it loads it, and `--verify` then fails. Copy it first, or use
  the compiled `.mlmodelc`. `coremlcompiler compile` leaves the package unchanged.

### Parity and latency (local only)

`tools/judge_model_parity.py` (never CI) compares the package against PyTorch fp32 posteriors through the judging
spike's GOP on 20 VCTK starter clips (891 units), and times the 4 s bucket on CPU_AND_NE. It copies every package
before loading it. Measured 2026-11-25 on an M3 Max:

| Comparison | GOP Pearson | Flag agreement at τ −4.75 |
|---|---|---|
| int8 package vs PyTorch fp32, same padded input | 0.9979 | 100% (5 vs 5 flags) |
| int8 package (padded) vs PyTorch fp32 (unpadded, the spike's reference) | 0.9955 | 99.8% |
| the spike's `lv60_int8.mlpackage` vs this package | 0.9999 | 100% |

Forward pass, 4 s bucket, CPU_AND_NE: 35.8 ms median (bar < 60 ms); the spike's single-shape package measured
22.1 ms in the same run. Enumerated shapes cost about 11 ms at 4 s; the same gap shows with buckets up to 10 s only, so
it is the enumeration, not the 15 s bucket. 591 of 601 ops run on the Neural Engine. The first CPU_AND_NE load
compiles for the Neural Engine and took 39–83 s on a loaded machine; later loads hit the system cache.
