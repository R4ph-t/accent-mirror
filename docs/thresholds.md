# Thresholds

Every tunable number in Accent Mirror, in one place.

**Status: initial values.** They are tuned only on the tuning split, never on held-out clips, and mirrored in
`AMCore/Thresholds.swift` (spec 01). A change goes through a PR that says why. Never lower a threshold quietly: a
result under a bar goes back to CTO.

## Pitch

| Name | Value | Unit | Owner spec | Notes |
|---|---|---|---|---|
| Pitch window | 40 | ms | 04 | YIN/pYIN analysis window |
| Pitch hop | 10 | ms | 04 | |
| F0 search range | 60–500 | Hz | 04 | |
| Voicing probability | ≥ 0.5 | pYIN probability | 04 | Frame counts as voiced |
| Minimum voiced run | 30 | ms | 04 | 5-frame median filter and octave-jump repair |
| Pitch-line break | > 250 | ms | 04 | Shorter unvoiced gaps are interpolated (`voiced = false`) |
| Pitch axis | ±12, growing in steps of 6, up to ±24 | st | 04 | Never shrinks within a phrase |

## Capture and takes

| Name | Value | Unit | Owner spec | Notes |
|---|---|---|---|---|
| Speech frame | RMS ≥ max(−45, noise floor + 12) | dBFS | 05 | Noise floor measured over the first 200 ms |
| End of take | 1.2 | s | 05 | Trailing silence after speech |
| Recording cap | 20 | s | 05 | Hard cap |
| No speech | < 0.15 | s | 05 | Total speech frames |
| Too short | < 0.5 | s | 05 | Speech |
| Too quiet | < −40 | dBFS | 05 | Median RMS of speech frames |
| Clipped | ≥ 0.5 | % of speech frames | 05 | Runs of 3+ samples with \|x\| ≥ 0.999 |
| Import limit | 15 | s | 16 | First 15 s of speech, trimmed |

## Alignment and stress

| Name | Value | Unit | Owner spec | Notes |
|---|---|---|---|---|
| Word match | ≥ 80 | % of content words | 06 | In order, after normalising; below it, "words don't match" |
| ASR word-span padding | ~80 | ms | 07 | Both sides of each Whisper word span (CTO decision 4) |
| Timing confidence | < 0.5 | 0–1 | 07, 09 | Below it: DTW fallback and Rough |
| Secondary stress | ≥ 0.75 | × primary prominence | 08 | Not next to the primary |
| Stress-detection bar | 80 | % | 03 | Against human-labelled actual stress; counts only if it beats the CMUdict baseline on held-out misplaced-stress clips |

## Band and diffs

| Name | Value | Unit | Owner spec | Notes |
|---|---|---|---|---|
| Native band | 10th–90th | percentile | 09 | Per aligned frame across native takes |
| Native band, one take | ±1.5 | st | 09 | Around the model |
| Stress contrast diff | < 0.7 × model, model ≥ 1.3 | ratio | 10 | |
| Too much contrast | > 2 × model | ratio | 10 | Lowest priority; only with fewer than 3 higher-priority rows |
| Vowel reduction diff | ≥ 15 | points above model | 10 | Weak-syllable length |
| Pitch range diff | < 0.6 × model and ≥ 3 st narrower | ratio, st | 10 | |
| Final direction diff | opposite sign, \|slope\| ≥ 1 for both | st | 10 | Final voiced 200 ms |
| Close to the model | shape match ≥ 0.7, timing Good | Pearson r | 10 | And no diff triggers |
| Max diff rows | 3 | rows | 10 | The "timing is rough" row counts toward the 3 |

## Agreement and performance

| Name | Value | Unit | Owner spec | Notes |
|---|---|---|---|---|
| Agreement false positives | ≤ 5 | % of phrases | 02, 10 | Native takes; gate turns on with spec 10 |
| End-to-end budget | < 2 | s | 11 | 3 s take on M1, model warm; hand check (`make bench`) |
| Non-ASR stages | ≤ 500 | ms | 11 | CI gate on the runner |
| ASR (warm) | 900 | ms | 03 | `tiny.en` is the fallback if base.en goes over |
