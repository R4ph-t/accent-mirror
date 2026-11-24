# Nucleus jitter (spec 26 acceptance 1 = spec 25 §5.1, budget on both populations): NOT MET

Spec 11 §4b's oracle-boundary jitter test on `.nucleus` at spec 26's grid-chosen nucleus values and main's verdict thresholds; `.span` and spec 25's `.nucleus` (report acb3910a) are the before columns. Oracle word boundaries: TTS markers on the synthetic set, MFA on the held-out VCTK speakers. Both edges of every comparable word moved by an independent uniform offset in ±R (seed 20261125, the VCTK split manifest's fold seed), clamped to the neighbours' oracle edges and the clip. Flips are counted against the unjittered oracle, anything↔inconclusive included. Pass: ≤ 2% flips at ±40 ms on each set, pooled and in every multi-syllable group (2, 3, 4+) with n ≥ 30; per-group inconclusive rise ≤ 2 points (2 and 3, n ≥ 30); the 10% inconclusive budget on BOTH the unjittered oracle run and the ±40 ms run (CTO markup 4). ±20 and ±80 ms are reported only.

| Identity | |
|---|---|
| configDigest | `69675122c0665f107ef1062509ab426e586ebdfd7e53d08b9a9a404f20baa676` |
| thresholdsVersion | 10 |
| algorithmVersion | 3 |
| evaluatedCommit | `8b7a9628798f2c4628a33383973b42a5edaa190d` |
| sourceTreeHash | `5000fc378936541ecf6bedde30c501f856f164b96aeec784cc5b3fa17479c45d` |
| cleanTree | true |
| generatedAt | 2026-11-24T15:47:45Z |
| shipped measurement | `span` |
| nucleus values (spec 26 grid choice; others spec 25's) | minPeakDBFS -45.0, minProminenceDB 1.5, minSeparationMs 50.0, regionDropDB 9.0, voicedWithinMs 60.0, skipCostMs 60.0, windowMs 30.0, ambiguityEdgeMs 40.0 |
| ASR (synthetic set: probabilities and matching only) | openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631 |

## Acceptance 1 checks (spec 26 `.nucleus`)

- jitter ±40 ms, synthetic: n=307 value 0.1498 [0.1143, 0.1941] Wilson 95% (≤ 0.02): NOT MET; 46 of 307 words
- jitter ±40 ms, 2-syllable flips, synthetic: n=51 value 0.2157 [0.1249, 0.3463] Wilson 95% (≤ 0.02): NOT MET; 11 of 51 words
- jitter ±40 ms, 3-syllable flips, synthetic: n=15 value 0.2667 [0.1090, 0.5195] Wilson 95% (≤ 0.02): reported (n < 30); 4 of 15 words
- jitter ±40 ms, 4+-syllable flips, synthetic: n=7 value 0.1429 [0.0257, 0.5131] Wilson 95% (≤ 0.02): reported (n < 30); 1 of 7 words
- jitter ±40 ms, 1-syllable inconclusive rise, synthetic: n=234 value 0.1154 (no limit): REPORTED; oracle 106/234 [0.390, 0.517], candidate 133/234 [0.504, 0.630]; flips 30/234
- jitter ±40 ms, 2-syllable inconclusive rise, synthetic: n=51 value 0.1569 (≤ 0.02): NOT MET; oracle 18/51 [0.236, 0.490], candidate 26/51 [0.377, 0.641]; flips 11/51
- jitter ±40 ms, 3-syllable inconclusive rise, synthetic: n=15 value 0.1333 (≤ 0.02): reported (n < 30); oracle 7/15 [0.248, 0.699], candidate 9/15 [0.357, 0.802]; flips 4/15
- jitter ±40 ms, 4+-syllable inconclusive rise, synthetic: n=7 value 0.1429 (no limit): REPORTED; oracle 4/7 [0.250, 0.842], candidate 5/7 [0.359, 0.918]; flips 1/7
- jitter ±40 ms, unjittered inconclusive budget, synthetic: n=307 value 0.4397 [0.3853, 0.4957] Wilson 95% (≤ 0.10): NOT MET; unjittered oracle 135/307 inconclusive
- jitter ±40 ms, inconclusive budget, synthetic: n=307 value 0.5635 [0.5076, 0.6179] Wilson 95% (≤ 0.10): NOT MET; jittered 173/307 inconclusive (oracle 135/307, 44.0%)
- jitter ±40 ms, vctk-held-out: n=3890 value 0.0715 [0.0638, 0.0800] Wilson 95% (≤ 0.02): NOT MET; 278 of 3890 words
- jitter ±40 ms, 2-syllable flips, vctk-held-out: n=639 value 0.0986 [0.0778, 0.1242] Wilson 95% (≤ 0.02): NOT MET; 63 of 639 words
- jitter ±40 ms, 3-syllable flips, vctk-held-out: n=213 value 0.0704 [0.0431, 0.1129] Wilson 95% (≤ 0.02): NOT MET; 15 of 213 words
- jitter ±40 ms, 4+-syllable flips, vctk-held-out: n=117 value 0.0427 [0.0184, 0.0962] Wilson 95% (≤ 0.02): NOT MET; 5 of 117 words
- jitter ±40 ms, 1-syllable inconclusive rise, vctk-held-out: n=2921 value 0.0531 (no limit): REPORTED; oracle 1800/2921 [0.598, 0.634], candidate 1955/2921 [0.652, 0.686]; flips 195/2921
- jitter ±40 ms, 2-syllable inconclusive rise, vctk-held-out: n=639 value 0.0736 (≤ 0.02): NOT MET; oracle 401/639 [0.589, 0.664], candidate 448/639 [0.664, 0.735]; flips 63/639
- jitter ±40 ms, 3-syllable inconclusive rise, vctk-held-out: n=213 value 0.0376 (≤ 0.02): NOT MET; oracle 172/213 [0.749, 0.855], candidate 180/213 [0.790, 0.888]; flips 15/213
- jitter ±40 ms, 4+-syllable inconclusive rise, vctk-held-out: n=117 value 0.0427 (no limit): REPORTED; oracle 99/117 [0.770, 0.900], candidate 104/117 [0.819, 0.934]; flips 5/117
- jitter ±40 ms, unjittered inconclusive budget, vctk-held-out: n=3890 value 0.6355 [0.6202, 0.6505] Wilson 95% (≤ 0.10): NOT MET; unjittered oracle 2472/3890 inconclusive
- jitter ±40 ms, inconclusive budget, vctk-held-out: n=3890 value 0.6907 [0.6760, 0.7051] Wilson 95% (≤ 0.10): NOT MET; jittered 2687/3890 inconclusive (oracle 2472/3890, 63.5%)

**Nucleus jitter: NOT MET (stop; scope proposal written)**

## synthetic (oracle: tts-markers, 20 clips)

### ±40 ms

| Group | n | .span flips | spec 25 .nucleus (acb3910a) flips | spec 26 .nucleus flips | Wilson 95% | inconclusive (unjittered → ±40) |
|---|---|---|---|---|---|---|
| pooled | 307 | 25 (8.1%) | 20/307 (6.5%) | 46 (15.0%) | [11.4, 19.4] | 44.0% → 56.4% (+12.4 pt) |
| 1 | 234 | 7 (3.0%) | 12/234 (5.1%) | 30 (12.8%) | [9.1, 17.7] | 45.3% → 56.8% (+11.5 pt) |
| 2 | 51 | 9 (17.6%) | 6/51 (11.8%) | 11 (21.6%) | [12.5, 34.6] | 35.3% → 51.0% (+15.7 pt) |
| 3 | 15 | 5 (33.3%) | 2/15 (13.3%) | 4 (26.7%) | [10.9, 52.0] | 46.7% → 60.0% (+13.3 pt) |
| 4+ | 7 | 4 (57.1%) | 0/7 (0.0%) | 1 (14.3%) | [2.6, 51.3] | 57.1% → 71.4% (+14.3 pt) |

Budget populations: unjittered oracle inconclusive 135/307 (44.0%, Wilson [38.5, 49.6]); ±40 ms jittered inconclusive 173/307 (56.4%, Wilson [50.8, 61.8]) (limit 10% each).

### assignmentAmbiguous (unjittered and ±40 ms)

| Group | n | unjittered ambiguous | share of unjittered inconclusive | ±40 ms ambiguous | share of ±40 ms inconclusive |
|---|---|---|---|---|---|
| pooled | 307 | 98/307 (31.9%, Wilson [27.0, 37.3]) | 72.6% | 135/307 (44.0%, Wilson [38.5, 49.6]) | 78.0% |
| 1 | 234 | 79/234 (33.8%, Wilson [28.0, 40.0]) | 74.5% | 107/234 (45.7%, Wilson [39.5, 52.1]) | 80.5% |
| 2 | 51 | 14/51 (27.5%, Wilson [17.1, 40.9]) | 77.8% | 20/51 (39.2%, Wilson [27.0, 52.9]) | 76.9% |
| 3 | 15 | 5/15 (33.3%, Wilson [15.2, 58.3]) | 71.4% | 7/15 (46.7%, Wilson [24.8, 69.9]) | 77.8% |
| 4+ | 7 | 0/7 (0.0%, Wilson [0.0, 35.4]) | 0.0% | 1/7 (14.3%, Wilson [2.6, 51.3]) | 20.0% |

### Inconclusive by reason, nucleus-short rate and counts' sources

| Group | n | unjittered: short / ambiguous / low | ±40 ms: short / ambiguous / low | nucleus-short rate (unjittered) | P ∈ N_w (unjittered) | reduced form / CMUdict alternate counts |
|---|---|---|---|---|---|---|
| pooled | 307 | 30 / 98 / 7 | 31 / 135 / 7 | 9.8% | 245/307 (79.8%, Wilson [75.0, 83.9]) | 1 / 0 of 277 non-short (0.4%) |
| 1 | 234 | 23 / 79 / 4 | 22 / 107 / 4 | 9.8% | 186/234 (79.5%, Wilson [73.9, 84.2]) | 0 / 0 of 211 non-short (0.0%) |
| 2 | 51 | 2 / 14 / 2 | 4 / 20 / 2 | 3.9% | 45/51 (88.2%, Wilson [76.6, 94.5]) | 0 / 0 of 49 non-short (0.0%) |
| 3 | 15 | 2 / 5 / 0 | 2 / 7 / 0 | 13.3% | 12/15 (80.0%, Wilson [54.8, 93.0]) | 1 / 0 of 13 non-short (7.7%) |
| 4+ | 7 | 3 / 0 / 1 | 3 / 1 / 1 | 42.9% | 2/7 (28.6%, Wilson [8.2, 64.1]) | 0 / 0 of 4 non-short (0.0%) |

### ±20 ms (reported)

| Group | n | .span flips | spec 26 .nucleus flips |
|---|---|---|---|
| pooled | 307 | 11 (3.6%) [2.0, 6.3] | 23 (7.5%) [5.0, 11.0] |
| 1 | 234 | 5 (2.1%) [0.9, 4.9] | 13 (5.6%) [3.3, 9.3] |
| 2 | 51 | 2 (3.9%) [1.1, 13.2] | 7 (13.7%) [6.8, 25.7] |
| 3 | 15 | 2 (13.3%) [3.7, 37.9] | 2 (13.3%) [3.7, 37.9] |
| 4+ | 7 | 2 (28.6%) [8.2, 64.1] | 1 (14.3%) [2.6, 51.3] |

### ±80 ms (reported)

| Group | n | .span flips | spec 26 .nucleus flips |
|---|---|---|---|
| pooled | 307 | 38 (12.4%) [9.2, 16.5] | 78 (25.4%) [20.9, 30.6] |
| 1 | 234 | 20 (8.5%) [5.6, 12.8] | 56 (23.9%) [18.9, 29.8] |
| 2 | 51 | 11 (21.6%) [12.5, 34.6] | 18 (35.3%) [23.6, 49.0] |
| 3 | 15 | 6 (40.0%) [19.8, 64.3] | 3 (20.0%) [7.0, 45.2] |
| 4+ | 7 | 1 (14.3%) [2.6, 51.3] | 1 (14.3%) [2.6, 51.3] |

### Near-edge diagnostic at ±40 ms (CTO markup 3)

A word is near an edge when a detected nucleus peak lies within 40 ms of either of its unjittered oracle edges.

| Run | Near-edge words | Their flips | Other words | Their flips |
|---|---|---|---|---|
| .span | 150 | 10/150 (6.7%, Wilson [3.7, 11.8]) | 157 | 15/157 (9.6%, Wilson [5.9, 15.2]) |
| spec 25 .nucleus (acb3910a) | 138 | 9/138 (6.5%, Wilson [3.5, 11.9]) | 169 | 11/169 (6.5%, Wilson [3.7, 11.3]) |
| spec 26 .nucleus | 150 | 11/150 (7.3%, Wilson [4.1, 12.7]) | 157 | 35/157 (22.3%, Wilson [16.5, 29.4]) |

## vctk-held-out (oracle: mfa, 299 clips)

### ±40 ms

| Group | n | .span flips | spec 25 .nucleus (acb3910a) flips | spec 26 .nucleus flips | Wilson 95% | inconclusive (unjittered → ±40) |
|---|---|---|---|---|---|---|
| pooled | 3890 | 453 (11.6%) | 174/3890 (4.5%) | 278 (7.1%) | [6.4, 8.0] | 63.5% → 69.1% (+5.5 pt) |
| 1 | 2921 | 315 (10.8%) | 145/2921 (5.0%) | 195 (6.7%) | [5.8, 7.6] | 61.6% → 66.9% (+5.3 pt) |
| 2 | 639 | 78 (12.2%) | 21/639 (3.3%) | 63 (9.9%) | [7.8, 12.4] | 62.8% → 70.1% (+7.4 pt) |
| 3 | 213 | 38 (17.8%) | 7/213 (3.3%) | 15 (7.0%) | [4.3, 11.3] | 80.8% → 84.5% (+3.8 pt) |
| 4+ | 117 | 22 (18.8%) | 1/117 (0.9%) | 5 (4.3%) | [1.8, 9.6] | 84.6% → 88.9% (+4.3 pt) |

Budget populations: unjittered oracle inconclusive 2472/3890 (63.5%, Wilson [62.0, 65.0]); ±40 ms jittered inconclusive 2687/3890 (69.1%, Wilson [67.6, 70.5]) (limit 10% each).

### assignmentAmbiguous (unjittered and ±40 ms)

| Group | n | unjittered ambiguous | share of unjittered inconclusive | ±40 ms ambiguous | share of ±40 ms inconclusive |
|---|---|---|---|---|---|
| pooled | 3890 | 960/3890 (24.7%, Wilson [23.3, 26.1]) | 38.8% | 1157/3890 (29.7%, Wilson [28.3, 31.2]) | 43.1% |
| 1 | 2921 | 734/2921 (25.1%, Wilson [23.6, 26.7]) | 40.8% | 875/2921 (30.0%, Wilson [28.3, 31.6]) | 44.8% |
| 2 | 639 | 163/639 (25.5%, Wilson [22.3, 29.0]) | 40.6% | 206/639 (32.2%, Wilson [28.7, 36.0]) | 46.0% |
| 3 | 213 | 52/213 (24.4%, Wilson [19.1, 30.6]) | 30.2% | 59/213 (27.7%, Wilson [22.1, 34.1]) | 32.8% |
| 4+ | 117 | 11/117 (9.4%, Wilson [5.3, 16.1]) | 11.1% | 17/117 (14.5%, Wilson [9.3, 22.0]) | 16.3% |

### Inconclusive by reason, nucleus-short rate and counts' sources

| Group | n | unjittered: short / ambiguous / low | ±40 ms: short / ambiguous / low | nucleus-short rate (unjittered) | P ∈ N_w (unjittered) | reduced form / CMUdict alternate counts |
|---|---|---|---|---|---|---|
| pooled | 3890 | 1335 / 960 / 177 | 1345 / 1157 / 185 | 34.3% | 1963/3890 (50.5%, Wilson [48.9, 52.0]) | 14 / 15 of 2555 non-short (1.1%) |
| 1 | 2921 | 945 / 734 / 121 | 948 / 875 / 132 | 32.4% | 1539/2921 (52.7%, Wilson [50.9, 54.5]) | 0 / 0 of 1976 non-short (0.0%) |
| 2 | 639 | 200 / 163 / 38 | 204 / 206 / 38 | 31.3% | 332/639 (52.0%, Wilson [48.1, 55.8]) | 0 / 0 of 439 non-short (0.0%) |
| 3 | 213 | 116 / 52 / 4 | 118 / 59 / 3 | 54.5% | 76/213 (35.7%, Wilson [29.6, 42.3]) | 14 / 13 of 97 non-short (27.8%) |
| 4+ | 117 | 74 / 11 / 14 | 75 / 17 / 12 | 63.2% | 16/117 (13.7%, Wilson [8.6, 21.1]) | 0 / 2 of 43 non-short (4.7%) |

### ±20 ms (reported)

| Group | n | .span flips | spec 26 .nucleus flips |
|---|---|---|---|
| pooled | 3890 | 225 (5.8%) [5.1, 6.6] | 164 (4.2%) [3.6, 4.9] |
| 1 | 2921 | 166 (5.7%) [4.9, 6.6] | 113 (3.9%) [3.2, 4.6] |
| 2 | 639 | 31 (4.9%) [3.4, 6.8] | 43 (6.7%) [5.0, 8.9] |
| 3 | 213 | 17 (8.0%) [5.0, 12.4] | 5 (2.3%) [1.0, 5.4] |
| 4+ | 117 | 11 (9.4%) [5.3, 16.1] | 3 (2.6%) [0.9, 7.3] |

### ±80 ms (reported)

| Group | n | .span flips | spec 26 .nucleus flips |
|---|---|---|---|
| pooled | 3890 | 618 (15.9%) [14.8, 17.1] | 524 (13.5%) [12.4, 14.6] |
| 1 | 2921 | 361 (12.4%) [11.2, 13.6] | 386 (13.2%) [12.0, 14.5] |
| 2 | 639 | 157 (24.6%) [21.4, 28.1] | 107 (16.7%) [14.1, 19.8] |
| 3 | 213 | 62 (29.1%) [23.4, 35.5] | 22 (10.3%) [6.9, 15.1] |
| 4+ | 117 | 38 (32.5%) [24.7, 41.4] | 9 (7.7%) [4.1, 14.0] |

### Near-edge diagnostic at ±40 ms (CTO markup 3)

A word is near an edge when a detected nucleus peak lies within 40 ms of either of its unjittered oracle edges.

| Run | Near-edge words | Their flips | Other words | Their flips |
|---|---|---|---|---|
| .span | 1677 | 234/1677 (14.0%, Wilson [12.4, 15.7]) | 2213 | 219/2213 (9.9%, Wilson [8.7, 11.2]) |
| spec 25 .nucleus (acb3910a) | 1249 | 126/1249 (10.1%, Wilson [8.5, 11.9]) | 2641 | 48/2641 (1.8%, Wilson [1.4, 2.4]) |
| spec 26 .nucleus | 1677 | 86/1677 (5.1%, Wilson [4.2, 6.3]) | 2213 | 192/2213 (8.7%, Wilson [7.6, 9.9]) |

## §5 diagnostics (reported)

### Flip breakdown at ±40 ms

Transition types read the gate's verdict: a decided verdict is `close` when its longest and loudest syllable are the context pronunciation's primary, else `feedback`; `inconclusive:<reason>` names the inconclusive side's reason (the jittered side's when both are). "The same nuclei" splits by what changed instead.

- synthetic, spec 25 `.nucleus` recomputed by this harness (spec 25's values, N_w the context count, no ambiguity): 20 flips of 307 words.
  - transition: feedback↔close 1, inconclusive:lowConfidence 7, inconclusive:nucleusShort 12
  - the word's assigned nuclei moved under jitter: 14; the same nuclei: 6 (P, s_w or c_w (word timing) 6)
  - exposure changed under jitter: 0 words, 0 of them flipped (the gate's verdict reads raw d and e, so exposure alone never flips it)
- synthetic, spec 26 `.nucleus`: 46 flips of 307 words.
  - transition: feedback↔close 1, inconclusive:assignmentAmbiguous 39, inconclusive:nucleusShort 6
  - the word's assigned nuclei moved under jitter: 10; the same nuclei: 36 (P, s_w or c_w (word timing) 3, other 33)
  - exposure changed under jitter: 0 words, 0 of them flipped (the gate's verdict reads raw d and e, so exposure alone never flips it)
- vctk-held-out, spec 25 `.nucleus` recomputed by this harness (spec 25's values, N_w the context count, no ambiguity): 174 flips of 3890 words.
  - transition: feedback↔feedback 1, inconclusive:lowConfidence 120, inconclusive:nucleusShort 53
  - the word's assigned nuclei moved under jitter: 68; the same nuclei: 106 (P, s_w or c_w (word timing) 106)
  - exposure changed under jitter: 10 words, 0 of them flipped (the gate's verdict reads raw d and e, so exposure alone never flips it)
- vctk-held-out, spec 26 `.nucleus`: 278 flips of 3890 words.
  - transition: feedback↔feedback 1, inconclusive:assignmentAmbiguous 212, inconclusive:lowConfidence 28, inconclusive:nucleusShort 37
  - the word's assigned nuclei moved under jitter: 71; the same nuclei: 207 (P, s_w or c_w (word timing) 29, exposure 1, other 177)
  - exposure changed under jitter: 10 words, 3 of them flipped (the gate's verdict reads raw d and e, so exposure alone never flips it)

### TTS-marker check (synthetic set, spec 26 `.nucleus` at ±40 ms)

TTS markers vs MFA on the same synthetic audio, 307 words (markers have 512-sample, about 23 ms, resolution):

| Edge | median abs Δ | p90 abs Δ | share over 40 ms |
|---|---|---|---|
| start | 24 ms | 43 ms | 12.1% |
| end | 25 ms | 54 ms | 19.2% |

±40 ms flips: words whose marker and MFA edges agree within 20 ms on both sides 3/35 (8.6%, Wilson [3.0, 22.4]); the rest 43/272 (15.8%, Wilson [12.0, 20.6]).

Under spec 25's `.nucleus` (recomputed): agreeing words 3/35 (8.6%, Wilson [3.0, 22.4]), the rest 17/272 (6.2%, Wilson [3.9, 9.8]).

The synthetic set is never dropped and its gate stays as written.

### Detection on held-out VCTK (never used to choose)

At the head's nucleus values, 16 held-out speakers, 299 clips, MFA words and phones: count-match (P ∈ N_w, not short) 2099/3994 (52.6%, Wilson [51.0, 54.1]); vowel-inside share 3069/3369 (91.1%, Wilson [90.1, 92.0]); median region–vowel IoU 0.500.

## `.span` under the same conditions (before column, reported)

- jitter ±40 ms, synthetic: n=307 value 0.0814 [0.0558, 0.1174] Wilson 95% (≤ 0.02): NOT MET; 25 of 307 words
- jitter ±40 ms, 2-syllable flips, synthetic: n=51 value 0.1765 [0.0957, 0.3025] Wilson 95% (≤ 0.02): NOT MET; 9 of 51 words
- jitter ±40 ms, 3-syllable flips, synthetic: n=15 value 0.3333 [0.1518, 0.5829] Wilson 95% (≤ 0.02): reported (n < 30); 5 of 15 words
- jitter ±40 ms, 4+-syllable flips, synthetic: n=7 value 0.5714 [0.2505, 0.8418] Wilson 95% (≤ 0.02): reported (n < 30); 4 of 7 words
- jitter ±40 ms, 1-syllable inconclusive rise, synthetic: n=234 value 0.0299 (no limit): REPORTED; oracle 9/234 [0.020, 0.071], candidate 16/234 [0.043, 0.108]; flips 7/234
- jitter ±40 ms, 2-syllable inconclusive rise, synthetic: n=51 value 0.0392 (≤ 0.02): NOT MET; oracle 2/51 [0.011, 0.132], candidate 4/51 [0.031, 0.185]; flips 9/51
- jitter ±40 ms, 3-syllable inconclusive rise, synthetic: n=15 value 0.0000 (≤ 0.02): reported (n < 30); oracle 1/15 [0.012, 0.298], candidate 1/15 [0.012, 0.298]; flips 5/15
- jitter ±40 ms, 4+-syllable inconclusive rise, synthetic: n=7 value 0.1429 (no limit): REPORTED; oracle 4/7 [0.250, 0.842], candidate 5/7 [0.359, 0.918]; flips 4/7
- jitter ±40 ms, unjittered inconclusive budget, synthetic: n=307 value 0.0521 [0.0323, 0.0830] Wilson 95% (≤ 0.10): MET; unjittered oracle 16/307 inconclusive
- jitter ±40 ms, inconclusive budget, synthetic: n=307 value 0.0847 [0.0584, 0.1212] Wilson 95% (≤ 0.10): MET; jittered 26/307 inconclusive (oracle 16/307, 5.2%)
- jitter ±40 ms, vctk-held-out: n=3890 value 0.1165 [0.1067, 0.1269] Wilson 95% (≤ 0.02): NOT MET; 453 of 3890 words
- jitter ±40 ms, 2-syllable flips, vctk-held-out: n=639 value 0.1221 [0.0989, 0.1497] Wilson 95% (≤ 0.02): NOT MET; 78 of 639 words
- jitter ±40 ms, 3-syllable flips, vctk-held-out: n=213 value 0.1784 [0.1328, 0.2354] Wilson 95% (≤ 0.02): NOT MET; 38 of 213 words
- jitter ±40 ms, 4+-syllable flips, vctk-held-out: n=117 value 0.1880 [0.1276, 0.2683] Wilson 95% (≤ 0.02): NOT MET; 22 of 117 words
- jitter ±40 ms, 1-syllable inconclusive rise, vctk-held-out: n=2921 value 0.1044 (no limit): REPORTED; oracle 243/2921 [0.074, 0.094], candidate 548/2921 [0.174, 0.202]; flips 315/2921
- jitter ±40 ms, 2-syllable inconclusive rise, vctk-held-out: n=639 value 0.0188 (≤ 0.02): MET; oracle 44/639 [0.052, 0.091], candidate 56/639 [0.068, 0.112]; flips 78/639
- jitter ±40 ms, 3-syllable inconclusive rise, vctk-held-out: n=213 value 0.0282 (≤ 0.02): NOT MET; oracle 33/213 [0.112, 0.210], candidate 39/213 [0.137, 0.240]; flips 38/213
- jitter ±40 ms, 4+-syllable inconclusive rise, vctk-held-out: n=117 value 0.0342 (no limit): REPORTED; oracle 40/117 [0.262, 0.432], candidate 44/117 [0.294, 0.466]; flips 22/117
- jitter ±40 ms, unjittered inconclusive budget, vctk-held-out: n=3890 value 0.0925 [0.0838, 0.1021] Wilson 95% (≤ 0.10): MET; unjittered oracle 360/3890 inconclusive
- jitter ±40 ms, inconclusive budget, vctk-held-out: n=3890 value 0.1766 [0.1649, 0.1889] Wilson 95% (≤ 0.10): NOT MET; jittered 687/3890 inconclusive (oracle 360/3890, 9.3%)

## ±20 and ±80 ms on `.nucleus` (reported)

- jitter ±20 ms, synthetic: n=307 value 0.0749 [0.0504, 0.1099] Wilson 95% (no limit): REPORTED; 23 of 307 words
- jitter ±80 ms, synthetic: n=307 value 0.2541 [0.2086, 0.3056] Wilson 95% (no limit): REPORTED; 78 of 307 words
- jitter ±20 ms, vctk-held-out: n=3890 value 0.0422 [0.0363, 0.0489] Wilson 95% (no limit): REPORTED; 164 of 3890 words
- jitter ±80 ms, vctk-held-out: n=3890 value 0.1347 [0.1243, 0.1458] Wilson 95% (no limit): REPORTED; 524 of 3890 words

## §6 Scope proposal (acceptance 1 failed; no further fallback)

Spec 26 §6, for CTO to route to Raph via CPO. Nothing is cut in code, and no parameter outside the grid and no threshold was changed after the frozen choice. Every number below is a suite's output with the cut applied after the fact.

### (a) Confident subset: per-word stress verdicts only on count-matched, unambiguous words (P ∈ N_w, not assignmentAmbiguous, not nucleus-short)

- synthetic, group pooled: subset 160/307 (52.12%, Wilson [46.54, 57.64]) of comparable words; ±40 ms flips in the subset 39/160 (24.38%, Wilson [18.37, 31.58]); subset inconclusive unjittered 1/160 (0.62%, Wilson [0.11, 3.45]), ±40 ms 39/160 (24.38%, Wilson [18.37, 31.58])
- synthetic, group 1: subset 119/234 (50.85%, Wilson [44.49, 57.19]) of comparable words; ±40 ms flips in the subset 27/119 (22.69%, Wilson [16.09, 31.00]); subset inconclusive unjittered 0/119 (0.00%, Wilson [0.00, 3.13]), ±40 ms 27/119 (22.69%, Wilson [16.09, 31.00])
- synthetic, group 2: subset 32/51 (62.75%, Wilson [49.03, 74.68]) of comparable words; ±40 ms flips in the subset 8/32 (25.00%, Wilson [13.25, 42.11]); subset inconclusive unjittered 1/32 (3.12%, Wilson [0.55, 15.74]), ±40 ms 9/32 (28.12%, Wilson [15.56, 45.37])
- synthetic, group 3: subset 7/15 (46.67%, Wilson [24.81, 69.88]) of comparable words; ±40 ms flips in the subset 3/7 (42.86%, Wilson [15.82, 74.95]); subset inconclusive unjittered 0/7 (0.00%, Wilson [0.00, 35.43]), ±40 ms 2/7 (28.57%, Wilson [8.22, 64.11])
- synthetic, group 4+: subset 2/7 (28.57%, Wilson [8.22, 64.11]) of comparable words; ±40 ms flips in the subset 1/2 (50.00%, Wilson [9.45, 90.55]); subset inconclusive unjittered 0/2 (0.00%, Wilson [0.00, 65.76]), ±40 ms 1/2 (50.00%, Wilson [9.45, 90.55])
- vctk-held-out, group pooled: subset 1226/3890 (31.52%, Wilson [30.08, 32.99]) of comparable words; ±40 ms flips in the subset 187/1226 (15.25%, Wilson [13.35, 17.37]); subset inconclusive unjittered 16/1226 (1.31%, Wilson [0.80, 2.11]), ±40 ms 201/1226 (16.39%, Wilson [14.43, 18.57])
- vctk-held-out, group 1: subset 962/2921 (32.93%, Wilson [31.25, 34.66]) of comparable words; ±40 ms flips in the subset 132/962 (13.72%, Wilson [11.69, 16.04]); subset inconclusive unjittered 13/962 (1.35%, Wilson [0.79, 2.30]), ±40 ms 144/962 (14.97%, Wilson [12.85, 17.36])
- vctk-held-out, group 2: subset 217/639 (33.96%, Wilson [30.39, 37.72]) of comparable words; ±40 ms flips in the subset 41/217 (18.89%, Wilson [14.24, 24.63]); subset inconclusive unjittered 3/217 (1.38%, Wilson [0.47, 3.99]), ±40 ms 44/217 (20.28%, Wilson [15.47, 26.12])
- vctk-held-out, group 3: subset 36/213 (16.90%, Wilson [12.47, 22.51]) of comparable words; ±40 ms flips in the subset 10/36 (27.78%, Wilson [15.85, 43.99]); subset inconclusive unjittered 0/36 (0.00%, Wilson [0.00, 9.64]), ±40 ms 9/36 (25.00%, Wilson [13.75, 41.07])
- vctk-held-out, group 4+: subset 11/117 (9.40%, Wilson [5.33, 16.05]) of comparable words; ±40 ms flips in the subset 4/11 (36.36%, Wilson [15.17, 64.62]); subset inconclusive unjittered 0/11 (0.00%, Wilson [0.00, 25.88]), ±40 ms 4/11 (36.36%, Wilson [15.17, 64.62])
- Starter phrases (spec 15, 14 phrases, every bundled voice, `.nucleus` at the head's values): – of the placement-applicable word recordings (words with an A(w)) are in the subset; 0 of 14 phrases have a placement-applicable word outside it in most voices: none.
- L2 recall (the stress-wrong words), `.nucleus` with the subset, after suppression: 0/134 (0.00%, Wilson [0.00, 2.79])
- L2 false positives, clean 1,400, `.nucleus` with the subset, after suppression: 39/1400 (2.79%, Wilson [2.04, 3.79])
- Positive set on `.nucleus` (EVALUABLE), with the subset: placement-diff pairs 7/281 (2.49%, Wilson [1.21, 5.05]); any-diff pairs 36/281 (12.81%, Wilson [9.40, 17.23]) (rows removed only)

### (b) v1 without per-word stress verdicts: keep the phrase-level rhythm and intonation rows (nPVI, weak length, band coverage, pitch range, final direction); drop placement and contrast

- Positive set on the shipped config (`.span`, EVALUABLE), placement, contrast and too-much-contrast rows dropped: any-diff pairs 69/281 (24.56%, Wilson [19.89, 29.91]); pairs keeping each row: roughTiming 43, weakLength 22, pitchRange 31, finalDirection 12 (rows removed only; a row hidden behind the 3-row cap is not surfaced)
- Positive-set row kept: Band coverage, median over pairs (spec 09): n 281, value 0.5294, fail
- Positive-set row kept: Weak length, largest |Δ| (spec 10): n 154, value 72.9379, fail
- Positive-set row kept: nPVI, largest |Δ| (spec 10): n 204, value 34.8782, fail
- Positive-set row kept: Pitch range ratio at or above minimum (spec 10): n 217, value 0.7742, fail
- Positive-set row kept: Final direction agreement (spec 10): n 114, value –, notEvaluated(n: 114, minimum: 150)
- Starter targets that lose their stress feedback (placement, and contrast for their phrase): 10 of 14 phrases: vctk-005: station.; vctk-006: sunlight, raindrops, rainbow.; vctk-007: division, beautiful; vctk-012: explained; vctk-013: physical, explanation.; vctk-014: universal; vctk-015: imagine; vctk-017: explain, phenomenon; vctk-018: Aristotle, reflection; vctk-020: complicated.

