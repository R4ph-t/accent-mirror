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

Linked into `AMAlignment` by spec 03 for on-device word timestamps, as a Swift package pinned to release 1.1.1
(commit `1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4`), `https://github.com/argmaxinc/WhisperKit`. Its own dependency
swift-argument-parser (Apple, Apache-2.0) is resolved but not linked by AccentKit.

- Copyright: "Copyright (c) 2024 argmax, inc.", as in the package's `LICENSE`.
- Licence: MIT.

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

Not yet bundled; notice added by spec 06.

## VCTK (CC BY 4.0)

Not yet bundled; notice added by spec 02.

## LibriTTS-R (CC BY 4.0)

Not yet bundled; notice added by spec 02.
