# Smoke set attribution

The audio under `audio/` is a fixed sample of two corpora, both licensed under the Creative Commons Attribution 4.0
International licence (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/). It is used only to test Accent
Mirror's evaluation harness (spec 02, plan §6.3a) and is never bundled with the app. `manifest.json` lists every file
with its SHA-256, speaker and source item.

Changes made: utterances were selected by `tools/pick_smoke_set.py` (seeded) and re-encoded as 16 kHz mono 16-bit
FLAC; the VCTK clips were also trimmed to their speech (200 ms before, 300 ms after) and downsampled from 48 kHz.
No other change was made to the recordings.

## speechocean762

- 47 utterances by train-half speakers, with the word labels from `resource/scores-detail.json`.
- Source: OpenSLR resource 101, https://www.openslr.org/101/ (`speechocean762.tar.gz`), and the label files at
  https://github.com/jimbozhang/speechocean762 commit `613968e3b0b789fc33936fb5eba1973176ba7d11`.
- Authors: Junbo Zhang, Zhiwen Zhang, Yongqing Wang, Zhiyong Yan, Qiong Song, Yukai Huang, Ke Li, Daniel Povey and
  Yujun Wang. "speechocean762: An Open-Source Non-native English Speech Corpus For Pronunciation Assessment",
  Interspeech 2021. Copyright SpeechOcean (Haitian).
- Licence: CC BY 4.0.

## VCTK

- Speakers p245, p288 and p360 (VCTK tuning speakers), shared-text phrases 002 and 018, mic1.
- Source: CSTR VCTK Corpus: English Multi-speaker Corpus for CSTR Voice Cloning Toolkit, version 0.92,
  https://datashare.ed.ac.uk/handle/10283/3443 (`VCTK-Corpus-0.92.zip`).
- Authors: Junichi Yamagishi, Christophe Veaux and Kirsten MacDonald, Centre for Speech Technology Research (CSTR),
  University of Edinburgh, 2019. https://doi.org/10.7488/ds/2645
- Licence: CC BY 4.0.
