# Starter recordings: attribution

The native recordings in this folder are cut from the CSTR VCTK Corpus 0.92:

Christophe Veaux, Junichi Yamagishi, Kirsten MacDonald, "CSTR VCTK Corpus: English Multi-speaker Corpus for
CSTR Voice Cloning Toolkit (version 0.92)", The Centre for Speech Technology Research (CSTR), University of
Edinburgh. https://doi.org/10.7488/ds/2645. Licensed under CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/).

Changes: each clip (`wav48_silence_trimmed/<speaker>/<utterance>_mic1.flac`) was trimmed to the speech with
200 ms before and 300 ms after it (the same rule for every speaker; `trimStart`/`trimEnd` in `manifest.json`)
and re-encoded as mono 16-bit FLAC at its source rate. The word timings were recognised by WhisperKit
(`openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631`) and shifted onto the trimmed clip; the analyses are derived from both.

| Speaker | Accent | Region | Gender | Utterances |
|---|---|---|---|---|
| p225 | English | Southern England | F | p225_002, p225_004, p225_005, p225_006, p225_007, p225_009, p225_010, p225_012, p225_013, p225_014, p225_017, p225_018, p225_020 |
| p226 | English | Surrey | M | p226_002, p226_004, p226_006, p226_007, p226_009, p226_010, p226_012, p226_013, p226_014, p226_015, p226_017, p226_018, p226_020 |
| p227 | English | Cumbria | M | p227_002, p227_004, p227_009, p227_010, p227_012, p227_013, p227_014, p227_017, p227_018, p227_020 |
| p233 | English | Staffordshire | F | p233_002, p233_004, p233_006, p233_007, p233_009, p233_012, p233_013, p233_014, p233_015, p233_017, p233_018, p233_020 |
| p241 | Scottish | Perth | M | p241_002, p241_004, p241_005, p241_006, p241_007, p241_009, p241_010, p241_012, p241_013, p241_014, p241_017, p241_018 |
| p252 | Scottish | Edinburgh | M | p252_002, p252_004, p252_005, p252_006, p252_007, p252_009, p252_010, p252_012, p252_013, p252_014, p252_015, p252_017, p252_018, p252_020 |
| p311 | American | Iowa | M | p311_002, p311_004, p311_005, p311_006, p311_007, p311_009, p311_010, p311_012, p311_013, p311_014, p311_015, p311_017, p311_018, p311_020 |
| p345 | American | Florida | M | p345_002, p345_004, p345_006, p345_007, p345_009, p345_010, p345_012, p345_013, p345_014, p345_015, p345_017, p345_018, p345_020 |
