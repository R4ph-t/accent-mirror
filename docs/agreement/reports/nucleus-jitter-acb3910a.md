# Nucleus jitter (spec 25 acceptance 1): NOT MET

Spec 11 §4b's oracle-boundary jitter test, `.nucleus` measurement with `.span` beside it (the before column). Oracle word boundaries: TTS markers on the synthetic set, MFA on the held-out VCTK speakers. Both edges of every comparable word moved by an independent uniform offset in ±R (seed 20261125, the VCTK split manifest's fold seed), clamped to the neighbours' oracle edges and the clip. Flips are counted against the unjittered oracle, anything↔inconclusive included. Pass: ≤ 2% flips at ±40 ms on each set, pooled and in every multi-syllable group (2, 3, 4+) with n ≥ 30; per-group inconclusive rise ≤ 2 points (2 and 3, n ≥ 30); jittered inconclusive share ≤ 10%. ±20 and ±80 ms are reported only.

| Identity | |
|---|---|
| configDigest | `acb3910a026c031276cc8414c71b36f077ae4f45f611c472228c2ac96d452d4c` |
| thresholdsVersion | 9 |
| algorithmVersion | 2 |
| evaluatedCommit | `32ede8ec65e4f7e1777fbb3de08d03fe66c1a159` |
| sourceTreeHash | `56dee1cfb428630aa09cc46ab0806431882ae4f720e6d4c22861b463897f3779` |
| cleanTree | true |
| generatedAt | 2026-11-24T14:53:13Z |
| shipped measurement | `span` |
| nucleus parameters (fixed, CTO markup 4) | minPeakDBFS -45.0, minProminenceDB 3.0, minSeparationMs 70.0, regionDropDB 6.0, skipCostMs 60.0, windowMs 30.0 |
| ASR (synthetic set: probabilities and matching only) | openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631 |

## Acceptance 1 checks (`.nucleus`)

- jitter ±40 ms, synthetic: n=307 value 0.0651 [0.0426, 0.0985] Wilson 95% (≤ 0.02): NOT MET; 20 of 307 words
- jitter ±40 ms, 2-syllable flips, synthetic: n=51 value 0.1176 [0.0551, 0.2338] Wilson 95% (≤ 0.02): NOT MET; 6 of 51 words
- jitter ±40 ms, 3-syllable flips, synthetic: n=15 value 0.1333 [0.0374, 0.3788] Wilson 95% (≤ 0.02): reported (n < 30); 2 of 15 words
- jitter ±40 ms, 4+-syllable flips, synthetic: n=7 value 0.0000 [0.0000, 0.3543] Wilson 95% (≤ 0.02): reported (n < 30); 0 of 7 words
- jitter ±40 ms, 1-syllable inconclusive rise, synthetic: n=234 value 0.0171 (no limit): REPORTED; oracle 55/234 [0.185, 0.293], candidate 59/234 [0.201, 0.311]; flips 12/234
- jitter ±40 ms, 2-syllable inconclusive rise, synthetic: n=51 value 0.0392 (≤ 0.02): NOT MET; oracle 14/51 [0.171, 0.409], candidate 16/51 [0.203, 0.450]; flips 6/51
- jitter ±40 ms, 3-syllable inconclusive rise, synthetic: n=15 value -0.0667 (≤ 0.02): reported (n < 30); oracle 7/15 [0.248, 0.699], candidate 6/15 [0.198, 0.643]; flips 2/15
- jitter ±40 ms, 4+-syllable inconclusive rise, synthetic: n=7 value 0.0000 (no limit): REPORTED; oracle 6/7 [0.487, 0.974], candidate 6/7 [0.487, 0.974]; flips 0/7
- jitter ±40 ms, inconclusive budget, synthetic: n=307 value 0.2834 [0.2359, 0.3362] Wilson 95% (≤ 0.10): NOT MET; jittered 87/307 inconclusive (oracle 82/307, 26.7%)
- jitter ±40 ms, vctk-held-out: n=3890 value 0.0447 [0.0387, 0.0517] Wilson 95% (≤ 0.02): NOT MET; 174 of 3890 words
- jitter ±40 ms, 2-syllable flips, vctk-held-out: n=639 value 0.0329 [0.0216, 0.0497] Wilson 95% (≤ 0.02): NOT MET; 21 of 639 words
- jitter ±40 ms, 3-syllable flips, vctk-held-out: n=213 value 0.0329 [0.0160, 0.0663] Wilson 95% (≤ 0.02): NOT MET; 7 of 213 words
- jitter ±40 ms, 4+-syllable flips, vctk-held-out: n=117 value 0.0085 [0.0015, 0.0468] Wilson 95% (≤ 0.02): MET; 1 of 117 words
- jitter ±40 ms, 1-syllable inconclusive rise, vctk-held-out: n=2921 value 0.0332 (no limit): REPORTED; oracle 1585/2921 [0.525, 0.561], candidate 1682/2921 [0.558, 0.594]; flips 145/2921
- jitter ±40 ms, 2-syllable inconclusive rise, vctk-held-out: n=639 value 0.0235 (≤ 0.02): NOT MET; oracle 376/639 [0.550, 0.626], candidate 391/639 [0.574, 0.649]; flips 21/639
- jitter ±40 ms, 3-syllable inconclusive rise, vctk-held-out: n=213 value 0.0141 (≤ 0.02): MET; oracle 172/213 [0.749, 0.855], candidate 175/213 [0.765, 0.867]; flips 7/213
- jitter ±40 ms, 4+-syllable inconclusive rise, vctk-held-out: n=117 value 0.0085 (no limit): REPORTED; oracle 109/117 [0.871, 0.965], candidate 110/117 [0.882, 0.971]; flips 1/117
- jitter ±40 ms, inconclusive budget, vctk-held-out: n=3890 value 0.6062 [0.5907, 0.6214] Wilson 95% (≤ 0.10): NOT MET; jittered 2358/3890 inconclusive (oracle 2242/3890, 57.6%)

**Nucleus jitter: NOT MET (stop; proposal written)**

## synthetic (oracle: tts-markers, 20 clips)

### ±40 ms

| Group | n | .span flips | .span Wilson 95% | .nucleus flips | .nucleus Wilson 95% | .nucleus inconclusive (oracle → ±40) |
|---|---|---|---|---|---|---|
| pooled | 307 | 25 (8.1%) | [5.6, 11.7] | 20 (6.5%) | [4.3, 9.8] | 26.7% → 28.3% (+1.6 pt) |
| 1 | 234 | 7 (3.0%) | [1.5, 6.0] | 12 (5.1%) | [3.0, 8.7] | 23.5% → 25.2% (+1.7 pt) |
| 2 | 51 | 9 (17.6%) | [9.6, 30.3] | 6 (11.8%) | [5.5, 23.4] | 27.5% → 31.4% (+3.9 pt) |
| 3 | 15 | 5 (33.3%) | [15.2, 58.3] | 2 (13.3%) | [3.7, 37.9] | 46.7% → 40.0% (-6.7 pt) |
| 4+ | 7 | 4 (57.1%) | [25.0, 84.2] | 0 (0.0%) | [0.0, 35.4] | 85.7% → 85.7% (+0.0 pt) |

### ±20 ms (reported)

| Group | n | .span flips | .nucleus flips |
|---|---|---|---|
| pooled | 307 | 11 (3.6%) [2.0, 6.3] | 19 (6.2%) [4.0, 9.5] |
| 1 | 234 | 5 (2.1%) [0.9, 4.9] | 11 (4.7%) [2.6, 8.2] |
| 2 | 51 | 2 (3.9%) [1.1, 13.2] | 7 (13.7%) [6.8, 25.7] |
| 3 | 15 | 2 (13.3%) [3.7, 37.9] | 1 (6.7%) [1.2, 29.8] |
| 4+ | 7 | 2 (28.6%) [8.2, 64.1] | 0 (0.0%) [0.0, 35.4] |

### ±80 ms (reported)

| Group | n | .span flips | .nucleus flips |
|---|---|---|---|
| pooled | 307 | 38 (12.4%) [9.2, 16.5] | 29 (9.4%) [6.7, 13.2] |
| 1 | 234 | 20 (8.5%) [5.6, 12.8] | 20 (8.5%) [5.6, 12.8] |
| 2 | 51 | 11 (21.6%) [12.5, 34.6] | 6 (11.8%) [5.5, 23.4] |
| 3 | 15 | 6 (40.0%) [19.8, 64.3] | 3 (20.0%) [7.0, 45.2] |
| 4+ | 7 | 1 (14.3%) [2.6, 51.3] | 0 (0.0%) [0.0, 35.4] |

### Near-edge diagnostic at ±40 ms (CTO markup 3)

A word is near an edge when a detected nucleus peak lies within 40 ms of either of its unjittered oracle edges.

| Measurement | Near-edge words | Their flips | Other words | Their flips |
|---|---|---|---|---|
| .span | 138 | 9 (6.5%) | 169 | 16 (9.5%) |
| .nucleus | 138 | 9 (6.5%) | 169 | 11 (6.5%) |

### Nucleus diagnostics on the oracle boundaries (reported)

| Group | n | P = N_w | Nucleus-short |
|---|---|---|---|
| 1 | 234 | 169 (72.2%) | 45 (19.2%) |
| 2 | 51 | 36 (70.6%) | 12 (23.5%) |
| 3 | 15 | 7 (46.7%) | 6 (40.0%) |
| 4+ | 7 | 1 (14.3%) | 5 (71.4%) |

## vctk-held-out (oracle: mfa, 299 clips)

### ±40 ms

| Group | n | .span flips | .span Wilson 95% | .nucleus flips | .nucleus Wilson 95% | .nucleus inconclusive (oracle → ±40) |
|---|---|---|---|---|---|---|
| pooled | 3890 | 453 (11.6%) | [10.7, 12.7] | 174 (4.5%) | [3.9, 5.2] | 57.6% → 60.6% (+3.0 pt) |
| 1 | 2921 | 315 (10.8%) | [9.7, 12.0] | 145 (5.0%) | [4.2, 5.8] | 54.3% → 57.6% (+3.3 pt) |
| 2 | 639 | 78 (12.2%) | [9.9, 15.0] | 21 (3.3%) | [2.2, 5.0] | 58.8% → 61.2% (+2.3 pt) |
| 3 | 213 | 38 (17.8%) | [13.3, 23.5] | 7 (3.3%) | [1.6, 6.6] | 80.8% → 82.2% (+1.4 pt) |
| 4+ | 117 | 22 (18.8%) | [12.8, 26.8] | 1 (0.9%) | [0.2, 4.7] | 93.2% → 94.0% (+0.9 pt) |

### ±20 ms (reported)

| Group | n | .span flips | .nucleus flips |
|---|---|---|---|
| pooled | 3890 | 225 (5.8%) [5.1, 6.6] | 93 (2.4%) [2.0, 2.9] |
| 1 | 2921 | 166 (5.7%) [4.9, 6.6] | 74 (2.5%) [2.0, 3.2] |
| 2 | 639 | 31 (4.9%) [3.4, 6.8] | 16 (2.5%) [1.5, 4.0] |
| 3 | 213 | 17 (8.0%) [5.0, 12.4] | 3 (1.4%) [0.5, 4.1] |
| 4+ | 117 | 11 (9.4%) [5.3, 16.1] | 0 (0.0%) [0.0, 3.2] |

### ±80 ms (reported)

| Group | n | .span flips | .nucleus flips |
|---|---|---|---|
| pooled | 3890 | 618 (15.9%) [14.8, 17.1] | 256 (6.6%) [5.8, 7.4] |
| 1 | 2921 | 361 (12.4%) [11.2, 13.6] | 209 (7.2%) [6.3, 8.1] |
| 2 | 639 | 157 (24.6%) [21.4, 28.1] | 37 (5.8%) [4.2, 7.9] |
| 3 | 213 | 62 (29.1%) [23.4, 35.5] | 9 (4.2%) [2.2, 7.8] |
| 4+ | 117 | 38 (32.5%) [24.7, 41.4] | 1 (0.9%) [0.2, 4.7] |

### Near-edge diagnostic at ±40 ms (CTO markup 3)

A word is near an edge when a detected nucleus peak lies within 40 ms of either of its unjittered oracle edges.

| Measurement | Near-edge words | Their flips | Other words | Their flips |
|---|---|---|---|---|
| .span | 1249 | 167 (13.4%) | 2641 | 286 (10.8%) |
| .nucleus | 1249 | 126 (10.1%) | 2641 | 48 (1.8%) |

### Nucleus diagnostics on the oracle boundaries (reported)

| Group | n | P = N_w | Nucleus-short |
|---|---|---|---|
| 1 | 2921 | 1374 (47.0%) | 1376 (47.1%) |
| 2 | 639 | 263 (41.2%) | 306 (47.9%) |
| 3 | 213 | 54 (25.4%) | 167 (78.4%) |
| 4+ | 117 | 27 (23.1%) | 101 (86.3%) |

## `.span` under the same conditions (before column, reported)

- jitter ±40 ms, synthetic: n=307 value 0.0814 [0.0558, 0.1174] Wilson 95% (≤ 0.02): NOT MET; 25 of 307 words
- jitter ±40 ms, 2-syllable flips, synthetic: n=51 value 0.1765 [0.0957, 0.3025] Wilson 95% (≤ 0.02): NOT MET; 9 of 51 words
- jitter ±40 ms, 3-syllable flips, synthetic: n=15 value 0.3333 [0.1518, 0.5829] Wilson 95% (≤ 0.02): reported (n < 30); 5 of 15 words
- jitter ±40 ms, 4+-syllable flips, synthetic: n=7 value 0.5714 [0.2505, 0.8418] Wilson 95% (≤ 0.02): reported (n < 30); 4 of 7 words
- jitter ±40 ms, 1-syllable inconclusive rise, synthetic: n=234 value 0.0299 (no limit): REPORTED; oracle 9/234 [0.020, 0.071], candidate 16/234 [0.043, 0.108]; flips 7/234
- jitter ±40 ms, 2-syllable inconclusive rise, synthetic: n=51 value 0.0392 (≤ 0.02): NOT MET; oracle 2/51 [0.011, 0.132], candidate 4/51 [0.031, 0.185]; flips 9/51
- jitter ±40 ms, 3-syllable inconclusive rise, synthetic: n=15 value 0.0000 (≤ 0.02): reported (n < 30); oracle 1/15 [0.012, 0.298], candidate 1/15 [0.012, 0.298]; flips 5/15
- jitter ±40 ms, 4+-syllable inconclusive rise, synthetic: n=7 value 0.1429 (no limit): REPORTED; oracle 4/7 [0.250, 0.842], candidate 5/7 [0.359, 0.918]; flips 4/7
- jitter ±40 ms, inconclusive budget, synthetic: n=307 value 0.0847 [0.0584, 0.1212] Wilson 95% (≤ 0.10): MET; jittered 26/307 inconclusive (oracle 16/307, 5.2%)
- jitter ±40 ms, vctk-held-out: n=3890 value 0.1165 [0.1067, 0.1269] Wilson 95% (≤ 0.02): NOT MET; 453 of 3890 words
- jitter ±40 ms, 2-syllable flips, vctk-held-out: n=639 value 0.1221 [0.0989, 0.1497] Wilson 95% (≤ 0.02): NOT MET; 78 of 639 words
- jitter ±40 ms, 3-syllable flips, vctk-held-out: n=213 value 0.1784 [0.1328, 0.2354] Wilson 95% (≤ 0.02): NOT MET; 38 of 213 words
- jitter ±40 ms, 4+-syllable flips, vctk-held-out: n=117 value 0.1880 [0.1276, 0.2683] Wilson 95% (≤ 0.02): NOT MET; 22 of 117 words
- jitter ±40 ms, 1-syllable inconclusive rise, vctk-held-out: n=2921 value 0.1044 (no limit): REPORTED; oracle 243/2921 [0.074, 0.094], candidate 548/2921 [0.174, 0.202]; flips 315/2921
- jitter ±40 ms, 2-syllable inconclusive rise, vctk-held-out: n=639 value 0.0188 (≤ 0.02): MET; oracle 44/639 [0.052, 0.091], candidate 56/639 [0.068, 0.112]; flips 78/639
- jitter ±40 ms, 3-syllable inconclusive rise, vctk-held-out: n=213 value 0.0282 (≤ 0.02): NOT MET; oracle 33/213 [0.112, 0.210], candidate 39/213 [0.137, 0.240]; flips 38/213
- jitter ±40 ms, 4+-syllable inconclusive rise, vctk-held-out: n=117 value 0.0342 (no limit): REPORTED; oracle 40/117 [0.262, 0.432], candidate 44/117 [0.294, 0.466]; flips 22/117
- jitter ±40 ms, inconclusive budget, vctk-held-out: n=3890 value 0.1766 [0.1649, 0.1889] Wilson 95% (≤ 0.10): NOT MET; jittered 687/3890 inconclusive (oracle 360/3890, 9.3%)

## ±20 and ±80 ms on `.nucleus` (reported)

- jitter ±20 ms, synthetic: n=307 value 0.0619 [0.0400, 0.0946] Wilson 95% (no limit): REPORTED; 19 of 307 words
- jitter ±80 ms, synthetic: n=307 value 0.0945 [0.0666, 0.1324] Wilson 95% (no limit): REPORTED; 29 of 307 words
- jitter ±20 ms, vctk-held-out: n=3890 value 0.0239 [0.0196, 0.0292] Wilson 95% (no limit): REPORTED; 93 of 3890 words
- jitter ±80 ms, vctk-held-out: n=3890 value 0.0658 [0.0584, 0.0740] Wilson 95% (no limit): REPORTED; 256 of 3890 words

## Proposal: no per-word stress-placement verdicts on 2–3-syllable words

Spec 25 §6, for CTO to route (CTO, then Raph via CPO). Nothing is cut in code, and no parameter or threshold was changed (CTO markup 4).

### ±40 ms per group: own flip rate and share of the pooled flips

| Set | Measurement | Group | n | Flips | Own flip rate | Wilson 95% | Share of pooled flips |
|---|---|---|---|---|---|---|---|
| synthetic | .span | 1 | 234 | 7 | 3.0% | [1.5, 6.0] | 28.0% |
| synthetic | .span | 2 | 51 | 9 | 17.6% | [9.6, 30.3] | 36.0% |
| synthetic | .span | 3 | 15 | 5 | 33.3% | [15.2, 58.3] | 20.0% |
| synthetic | .span | 4+ | 7 | 4 | 57.1% | [25.0, 84.2] | 16.0% |
| synthetic | .nucleus | 1 | 234 | 12 | 5.1% | [3.0, 8.7] | 60.0% |
| synthetic | .nucleus | 2 | 51 | 6 | 11.8% | [5.5, 23.4] | 30.0% |
| synthetic | .nucleus | 3 | 15 | 2 | 13.3% | [3.7, 37.9] | 10.0% |
| synthetic | .nucleus | 4+ | 7 | 0 | 0.0% | [0.0, 35.4] | 0.0% |
| vctk-held-out | .span | 1 | 2921 | 315 | 10.8% | [9.7, 12.0] | 69.5% |
| vctk-held-out | .span | 2 | 639 | 78 | 12.2% | [9.9, 15.0] | 17.2% |
| vctk-held-out | .span | 3 | 213 | 38 | 17.8% | [13.3, 23.5] | 8.4% |
| vctk-held-out | .span | 4+ | 117 | 22 | 18.8% | [12.8, 26.8] | 4.9% |
| vctk-held-out | .nucleus | 1 | 2921 | 145 | 5.0% | [4.2, 5.8] | 83.3% |
| vctk-held-out | .nucleus | 2 | 639 | 21 | 3.3% | [2.2, 5.0] | 12.1% |
| vctk-held-out | .nucleus | 3 | 213 | 7 | 3.3% | [1.6, 6.6] | 4.0% |
| vctk-held-out | .nucleus | 4+ | 117 | 1 | 0.9% | [0.2, 4.7] | 0.6% |

### Pooled, and without 2–3-syllable placement verdicts

| Set | Measurement | Pooled n | Pooled flips | Pooled rate | Without 2–3: n | Flips | Rate |
|---|---|---|---|---|---|---|---|
| synthetic | .span | 307 | 25 | 8.1% | 241 | 11 | 4.6% |
| synthetic | .nucleus | 307 | 20 | 6.5% | 241 | 12 | 5.0% |
| vctk-held-out | .span | 3890 | 453 | 11.6% | 3038 | 337 | 11.1% |
| vctk-held-out | .nucleus | 3890 | 174 | 4.5% | 3038 | 146 | 4.8% |

### What the cut removes

- Starter phrases (spec 15, 20 phrases): 67 of 74 placement-applicable words (≥ 2 syllables) have 2–3 syllables (90.5%); 19 phrases affected.
- Affected starter phrases and words (word, syllables): 003 (maybe 2, brother 2); 004 (also 2, plastic 2); 005 (into 2, Wednesday 2, station. 2); 006 (sunlight 2, raindrops 2, prism 2, rainbow. 2); 007 (rainbow 2, division 3, into 2, many 2, beautiful 3, colors. 2); 008 (above, 2, beyond 2, horizon. 3); 009 (according 3, legend, 2, boiling 2); 010 (People 2, ever 2); 011 (something 2, beyond 2, looking 2, rainbow. 2); 012 (Throughout 2, centuries 3, people 2, explained 2, rainbow 2, various 3); 013 (accepted 3, miracle 3, without 2, physical 3); 014 (Hebrews 2, token 2); 015 (imagine 3, foretell 2, heavy 2); 016 (Norsemen 2, considered 3, rainbow 2, over 2); 017 (Others 2, explain 2); 018 (rainbow 2, reflection 3); 019 (physicists 3, reflection, 3, raindrops 2, causes 2, rainbows. 2); 020 (Many 2, ideas 3, about 2, rainbow 2); 024 (very 2, common 2, showing 2, mainly 2, yellow, 2, little 2).
- L2 recall set (speechocean762 stress-wrong, intelligible, polysyllabic): 126 of 134 words have 2–3 syllables (94.0%): the recall the claim would lose.

### Positive-set and L2 rows with and without the cut

- Shipped config acb3910a (`.span` measurement, thresholds on main); the cut drops every placement flag and placement row on a word with 2–3 dictionary syllables, after the fact.
- L2 false positives, clean 1,400, after suppression: without the cut 150/1400 (10.71%, Wilson [9.20, 12.44]); with the cut 0/1400 (0.00%, Wilson [0.00, 0.27]) over all 1400 words, 0/19 (0.00%, Wilson [0.00, 16.82]) over the 19 words that keep a placement verdict
- L2 false positives, supplementary, after suppression: without the cut 188/1868 (10.06%, Wilson [8.78, 11.51]); with the cut 0/1868 (0.00%, Wilson [0.00, 0.21]) over all 1868 words, 0/29 (0.00%, Wilson [0.00, 11.70]) over the 29 words that keep a placement verdict
- L2 recall (stress-wrong words), after suppression: without the cut 5/134 (3.73%, Wilson [1.60, 8.44]); with the cut 0/134 (0.00%, Wilson [0.00, 2.79]) over all 134 words, 0/8 (0.00%, Wilson [0.00, 32.44]) over the 8 words that keep a placement verdict
- Positive set (EVALUABLE), placement-diff pairs: without the cut 6/281 (2.14%, Wilson [0.98, 4.58]); with the cut 0/281 (0.00%, Wilson [0.00, 1.35])
- Positive set, any-diff pairs: without the cut 94/281 (33.45%, Wilson [28.19, 39.16]); with the cut 92/281 (32.74%, Wilson [27.52, 38.43]) (rows removed only; the verdict's other rows are not re-ranked, so a row hidden behind the 3-row cap is not surfaced)
