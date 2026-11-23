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

- Files: `Geist/Geist-Regular.ttf`, `Geist-SemiBold.ttf`, `Geist-Bold.ttf`, `GeistMono-Medium.ttf` (400, 600, 700;
  Mono 500), and `Geist/OFL.txt`.
- Source: the official release v1.9.2, `https://github.com/vercel/geist-font/releases/download/v1.9.2/geist-font-v1.9.2.zip`
  (SHA-256 `15f066d58dcb99fb10014a49913009fdaf41e464cfb8851a44b44e593c95d3d8`), files from its `ttf/` folders.
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

Not yet bundled; notice added by spec 03.

## Whisper base.en Core ML weights

Not yet bundled; notice added by spec 03. The weights' LICENSE/NOTICE will also live next to their manifest in
`Resources/Models/`.

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

## VCTK (CC BY 4.0)

Not yet bundled; notice added by spec 02.

## LibriTTS-R (CC BY 4.0)

Not yet bundled; notice added by spec 02.
