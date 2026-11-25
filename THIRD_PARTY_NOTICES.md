# Third-party notices

Accent Mirror is licensed under GPL-3.0 (see `LICENSE`). This file lists every third-party component, model and
recording bundled with the app or committed to this repo, with its licence and attribution.

Each section below is filled in by the spec that adds the component.

## Fonts (SIL Open Font License 1.1)

Bundled with the app by spec 18, unmodified, under `AccentMirror/Resources/Fonts/` and in the app bundle under
`Contents/Resources/Fonts/`. Each family's official `OFL.txt` sits next to its font files and is also shown in the
app's About panel. The fonts stay under the SIL Open Font License 1.1; they are not relicensed under the GPL.
Neither licence file declares a Reserved Font Name.

### Geist and Geist Mono

- Files: `Geist/Geist-Regular.ttf`, `Geist-Medium.ttf`, `Geist-SemiBold.ttf`, `Geist-Bold.ttf`, `GeistMono-Medium.ttf`
  (400, 500, 600, 700; Mono 500), the italic `Geist/Geist-Italic[wght].ttf` (variable, weight axis), and
  `Geist/OFL.txt`.
- Source: the official release v1.9.2, `https://github.com/vercel/geist-font/releases/download/v1.9.2/geist-font-v1.9.2.zip`
  (SHA-256 `15f066d58dcb99fb10014a49913009fdaf41e464cfb8851a44b44e593c95d3d8`). The upright files are from its
  `ttf/` folders; the italic is from `Geist/variable/`, added with the fixes to specs
  18–19. File SHA-256s:
  - `Geist-Italic[wght].ttf`: `4eeb1676258a06e609dda278e569081919249872daa5aa10f95bff485e9bbdf4`
  - `Geist-Regular.ttf`: `2c460a7a71063e53491f343d44b382267bc0cf496e31db64865f962af3152e68`
  - `Geist-Medium.ttf`: `e9099e006d4934cae4a8c7d14a1ca2ea724ee2f69f9bdd5b2ffe715baf5524fc` (added for v3.2 W3)
  - `Geist-SemiBold.ttf`: `01923aa148e5202ae70a2e11b2ab4dc41b80bcc374aedccc913d47bb2f591c06`
  - `Geist-Bold.ttf`: `1c24df313b8ddc9550e060cfe5321c6374997f2892880af303b5ded45fed2582`
  - `GeistMono-Medium.ttf`: `34c0828460d47e697655bc9d730027a4b8baf6e6c9aa46f5f32b653b4797cf36`
  - `OFL.txt`: `021caa749f89fecd7c2e40a50499de29e84d2bc19251659b47d499c2fbfffc17`
- Copyright: "Copyright 2026 The Geist Project Authors (https://github.com/vercel/geist-font)", as in the release's
  `OFL.txt`. Geist is made by Vercel in collaboration with basement.studio.
- Licence: SIL Open Font License 1.1.

### Funnel Display

- Files: `FunnelDisplay/FunnelDisplay-SemiBold.ttf` (600) and `FunnelDisplay/OFL.txt`.
- Source: the official release 1.001, `https://github.com/Dicotype/Funnel/releases/download/Upgrade/Funnel_1001.zip`
  (SHA-256 `00f3b4131ecf9164a5d52138c83c312d7edde3f1012b0f83b2e1fa6e65702374`), file from `Funnel_Display/ttf/`.
  The release archive carries no licence file, so `OFL.txt` is the repository's own, at commit
  `5f3a46a76b89b91e47d9c191042c91d73b7479c9` (`https://github.com/Dicotype/Funnel/blob/5f3a46a76b89b91e47d9c191042c91d73b7479c9/OFL.txt`).
- Copyright: "Copyright 2025 The Funnel Project Authors (https://github.com/Dicotype/Funnel)", as in that `OFL.txt`.
- Licence: SIL Open Font License 1.1.

## WhisperKit (MIT)

Linked into `AMAlignment` by spec 03 for on-device word timestamps, as a Swift package pinned to release 1.1.1
(commit `1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4`), `https://github.com/argmaxinc/WhisperKit`. Its own dependency
swift-argument-parser (Apple, Apache-2.0) is resolved but not linked by AccentKit.

- Copyright: "Copyright (c) 2024 argmax, inc.", as in the package's `LICENSE`.
- Licence: MIT. GPL-3.0-compatible. Full text, verbatim from `LICENSE` at commit
  `1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4`:

```text
MIT License

Copyright (c) 2024 argmax, inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Whisper base.en Core ML weights

Not committed and not yet bundled with the app (bundling waits for the licence check). Fetched by
`scripts/fetch-models.sh` at pinned commits and SHA-256 checked against `Resources/Models/openai_whisper-base.en/manifest.json`;
the full licence texts are in that folder's `LICENSE` and `NOTICE`.

- Whisper base.en model: "Copyright (c) 2022 OpenAI", MIT (`https://github.com/openai/whisper`).
- Core ML conversion: `argmaxinc/whisperkit-coreml` at commit `0f63a7800b00dd0226abd051b906c246e1907482`, model card
  licence MIT.
- Tokenizer files: `openai/whisper-base.en` at commit `911407f4214e0e1d82085af863093ec0b66f9cd6`, model card licence
  Apache-2.0.

## CMUdict (BSD-style)

Bundled by spec 06, unmodified, as an `AMAlignment` package resource under
`Packages/AccentKit/Sources/AMAlignment/Resources/CMUdict/` (in the app inside the AccentKit `AMAlignment` resource
bundle). Its `LICENSE` sits next to it and ships in the same bundle; `manifest.json` records the source and hashes.

- File: `cmudict.dict` (the Carnegie Mellon Pronouncing Dictionary, continuing cmudict 0.7b).
- Source: `https://github.com/cmusphinx/cmudict` at commit `74790861f652b15e4ac49015a90074ad62a27690`
  (2025-10-24). SHA-256 of `cmudict.dict`: `81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22`;
  of `LICENSE`: `bd4ce8e44170a5f9f481310ca85c51de3c4f851a65e679b40e603b143bd3542a`.
- Derived file: `stress-shift-pairs.json`, generated from `cmudict.dict` by `tools/gen_stress_shift_pairs.py`.
- Copyright: "Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved."
- Licence: BSD-style (two clauses: keep the copyright notice in source redistributions, reproduce it in the
  documentation or other materials of binary redistributions), with the usual warranty disclaimer. GPL-3.0-compatible.
  Full text:

```text
Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
   The contents of this file are deemed to be source code.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in
   the documentation and/or other materials provided with the
   distribution.

This work was supported in part by funding from the Defense Advanced
Research Projects Agency, the Office of Naval Research and the National
Science Foundation of the United States of America, and by member
companies of the Carnegie Mellon Sphinx Speech Consortium. We acknowledge
the contributions of many volunteers to the expansion and improvement of
this dictionary.

THIS SOFTWARE IS PROVIDED BY CARNEGIE MELLON UNIVERSITY ``AS IS'' AND
ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL CARNEGIE MELLON UNIVERSITY
NOR ITS EMPLOYEES BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## wav2vec2-base-960h (Apache-2.0): evaluation tooling only

Evaluation tooling only; not distributed in the app; weights fetched by SHA-256 pin, never committed. Spec 23's b2
aligner (`ctc-w2v2b960-1`) is measurement-only (CTO ruling 2026-11-24): it lives in the tooling-only
`AMAlignmentCTC` target, which nothing the app links depends on, and the shipped aligner is `whisper`.
`scripts/fetch-ctc.sh` fetches the model into the git-ignored `.cache/models/` for local tooling and tests only; the
app build and CI never run it. The pinned manifest, `LICENSE` and `NOTICE` are in `fixtures/models/wav2vec2-base-960h/`.

- Model: `facebook/wav2vec2-base-960h` at commit `22aad52d435eb6dbaf354bdad9b0da84ce7d6156`, model card
  https://huggingface.co/facebook/wav2vec2-base-960h/blob/22aad52d435eb6dbaf354bdad9b0da84ce7d6156/README.md,
  licence Apache-2.0.
- Conversion: `coremltools` 8.3.0 (BSD-3-Clause), pinned in `tools/ctc-requirements.txt` and run only by
  `scripts/fetch-ctc.sh` in a git-ignored venv to convert the model to Core ML. Never linked into the app.

## VCTK (CC BY 4.0)

Bundled with the app by spec 15 as the starter library's native recordings (`Resources/Starter/`, read-only at
`Contents/Resources/Starter/`).

- Work: Christophe Veaux, Junichi Yamagishi, Kirsten MacDonald, "CSTR VCTK Corpus: English Multi-speaker Corpus
  for CSTR Voice Cloning Toolkit (version 0.92)", The Centre for Speech Technology Research (CSTR), University of
  Edinburgh. https://doi.org/10.7488/ds/2645
- Source: https://datashare.ed.ac.uk/handle/10283/3443 (archive pinned in `fixtures/corpora/vctk.pin.json`).
- Licence: Creative Commons Attribution 4.0 International (CC BY 4.0),
  https://creativecommons.org/licenses/by/4.0/
- Bundled: 101 clips of 14 shared-text prompts by 8 speakers (p225, p226, p227, p233, p241, p252, p311, p345;
  mic1). Changes: each clip is trimmed to its speech (200 ms before, 300 ms after) and re-encoded as mono 16-bit
  FLAC at its source rate; word timings (WhisperKit) and prosody analyses are derived from it. Per-clip source,
  speaker, accent, trim and SHA-256: `Resources/Starter/manifest.json`; per-speaker list:
  `Resources/Starter/ATTRIBUTION.md`.

## LibriTTS-R (CC BY 4.0)

Not yet bundled; notice added by spec 02.

## Sound-judging calibration (CC BY 4.0)

`Packages/AccentKit/Sources/AMJudging/Resources/calibration.json` is bundled with the app: 81 logistic-regression
weights that turn a sound's GOP into P(error), fitted by `tools/export_judge_calibration.py` on the phone accuracy
labels of the speechocean762 train split. No audio or labels are bundled, only the fitted weights.

- Work: speechocean762 (https://www.openslr.org/101/, https://huggingface.co/datasets/mispeech/speechocean762).
- Attribution: Junbo Zhang et al., "speechocean762: An Open-Source Non-native English Speech Corpus For
  Pronunciation Assessment", Interspeech 2021; SpeechOcean.
- Licence: Creative Commons Attribution 4.0 International (CC BY 4.0).

## Evaluation corpora (CC BY 4.0)

Committed by spec 02 for the agreement harness only: never bundled with the app, never read at runtime. The full
archives are fetched by `scripts/fetch-vctk-eval.sh` and `scripts/fetch-speechocean762.sh` into the git-ignored
`eval-cache/` and never committed. Details and file hashes: `fixtures/smoke/ATTRIBUTION.md`,
`fixtures/smoke/manifest.json`, `fixtures/corpora/*.pin.json`.

### speechocean762

- Committed: 47 utterances as 16 kHz FLAC under `fixtures/smoke/audio/`, and a label-only fixture derived from
  `resource/scores-detail.json` (`fixtures/speechocean762/labels.tsv`, no audio).
- Source: OpenSLR 101 (https://www.openslr.org/101/) and https://github.com/jimbozhang/speechocean762 at commit
  `613968e3b0b789fc33936fb5eba1973176ba7d11`.
- Attribution: Junbo Zhang et al., "speechocean762: An Open-Source Non-native English Speech Corpus For
  Pronunciation Assessment", Interspeech 2021; SpeechOcean.
- Licence: Creative Commons Attribution 4.0 International (CC BY 4.0).

### CSTR VCTK Corpus 0.92

- Committed: 6 trimmed clips (p245, p288, p360; phrases 002 and 018, mic1) as 16 kHz FLAC under
  `fixtures/smoke/audio/`, and the eval-speaker manifest with file hashes (`fixtures/vctk/eval-speakers.json`).
- Source: https://datashare.ed.ac.uk/handle/10283/3443 (https://doi.org/10.7488/ds/2645).
- Attribution: Junichi Yamagishi, Christophe Veaux and Kirsten MacDonald, CSTR, University of Edinburgh.
- Licence: Creative Commons Attribution 4.0 International (CC BY 4.0).
