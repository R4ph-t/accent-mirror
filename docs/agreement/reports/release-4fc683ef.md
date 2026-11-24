# Agreement report: release

| Identity | Value |
|---|---|
| Generated | `2026-11-24T15:23:25Z` |
| Release report | `yes` |
| configDigest | `4fc683ef4fee3c0d5c2aa632f56b0e12cdc13e73c8f256d932ba48dc6b13bab6` |
| ConfigIdentity | `algorithm 1, thresholds 8, contract 2, ASR replayed-word-timings, pitch pyin-1, voicing acf-1` |
| Corpus manifest hash | `3297cc445e6e46a9012f06c6b82cc4314298b0e36321bea0349c7e94ec0ce3ac` |
| Label hash | `11f6e133d91d53f45347d13319d997152573e0e2b179d7a508cd8aef81caa040` |
| Split manifest hash | `cd021cf29163d619c8515e9e6b9eb5aa0d513435dce3bfcf47c5331a670d78d0` |
| Split seed | `20261125` |
| sourceTreeHash | `d642e26c5e4b060ae4c4b9f4f1bf45513d32698e474872e9c6fce41c84c877fd` |
| Evaluated commit | `aa480911372d5d75d6e16dc127d90395ac3f9133` |
| Clean tree | `yes` |
| Xcode | `Xcode 26.2` |
| Swift | `Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)` |
| macOS | `Version 26.3 (Build 25D125)` |
| Runner image | `local` |
| syntheticReference | `mac-premium-fallback (no key; no Premium English voice installed: NOT EVALUATED)` |

## CV estimate, not shipped

| Metric | n | Value | Gate | Status | Interval | Worst speaker | Worst phrase |
|---|---|---|---|---|---|---|---|
| L2 recall, CV estimate, after suppression | 134 | 0.0373 | ≥ 0.8 (`agreement.l2RecallMin`) | FAIL | [0.0160, 0.0844] descriptive (ignores clustering) | 9643 0.0000 (n=10) | – |
| L2 recall, CV estimate, Wilson lower bound | 134 | 0.0160 | ≥ 0.7 (`agreement.l2RecallWilsonLowerMin`) | FAIL | [0.0160, 0.0844] descriptive (ignores clustering) | – | – |
| L2 recall, CV estimate, §6.5 baseline rule (best of B1, B2) | 134 | -0.1567 | – | FAIL | [-0.2369, -0.0959] paired speaker-clustered bootstrap, 2000 resamples | – | – |
| L2 recall, CV estimate, before suppression | 134 | 0.1716 | – | REPORTED (no gate) | [0.1172, 0.2444] descriptive (ignores clustering) | – | – |
| L2 recall, CV estimate, adults | 108 | 0.0463 | – | REPORTED (no gate) | [0.0199, 0.1038] descriptive (ignores clustering) | 1407 1.0000 (n=2) | – |
| L2 recall, CV estimate, children | 26 | 0.0000 | – | REPORTED (no gate) | [0.0000, 0.1287] descriptive (ignores clustering) | 1419 0.0000 (n=2) | – |
| L2 recall, CV estimate, ≥ 4 of 5 raters | 42 | 0.0714 | – | REPORTED (no gate) | [0.0246, 0.1901] descriptive (ignores clustering) | 0813 1.0000 (n=1) | – |
| L2 recall, CV estimate, final syllable lengthening-exposed | 18 | 0.0556 | – | REPORTED (no gate) | [0.0099, 0.2576] descriptive (ignores clustering) | 1407 1.0000 (n=1) | – |

## shipped-config check

| Metric | n | Value | Gate | Status | Interval | Worst speaker | Worst phrase |
|---|---|---|---|---|---|---|---|
| Band coverage, median over pairs (spec 09) | 281 | 0.5294 | ≥ 0.8 (`agreement.bandCoverageMedianMin`) | FAIL | – | p323 0.2437 (n=15) | – |
| Any-diff pairs (spec 10) | 281 | 0.3345 | ≤ 0.05 (`agreement.anyDiffPairsMax`) | FAIL | [0.2819, 0.3916] descriptive (ignores clustering); [0.1790, 0.4782] two-way clustered bootstrap (speakers × source prompts), 2000 resamples | p270 0.5556 (n=18) | 008 1.0000 (n=1) |
| Any-diff pairs, worst speaker (spec 10) | 281 | 0.5556 | ≤ 0.15 (`agreement.anyDiffWorstSpeakerMax`) | FAIL | – | p270 0.5556 (n=18) | 008 1.0000 (n=1) |
| Any-diff pairs, worst phrase (spec 10) | 281 | 1.0000 | ≤ 0.3 (`agreement.anyDiffWorstPhraseMax`) | FAIL | – | p270 0.5556 (n=18) | 008 1.0000 (n=1) |
| Placement-diff pairs (spec 10) | 281 | 0.0214 | ≤ 0.02 (`agreement.placementDiffPairsMax`) | FAIL | [0.0098, 0.0458] descriptive (ignores clustering); [0.0000, 0.0618] two-way clustered bootstrap (speakers × source prompts), 2000 resamples | p301 0.1000 (n=20) | 022 0.5000 (n=4) |
| Placement-diff pairs, worst speaker (spec 10) | 281 | 0.1000 | ≤ 0.07 (`agreement.placementDiffWorstSpeakerMax`) | FAIL | – | p301 0.1000 (n=20) | 022 0.5000 (n=4) |
| Inconclusive pairs (spec 10) | 281 | 0.3808 | ≤ 0.1 (`agreement.inconclusivePairsMax`) | FAIL | [0.3260, 0.4388] descriptive (ignores clustering); [0.1922, 0.6000] two-way clustered bootstrap (speakers × source prompts), 2000 resamples | p336 0.5882 (n=17) | 002 1.0000 (n=16) |
| Evaluation coverage (spec 10) | 265 | 0.5878 | ≥ 0.9 (`agreement.evaluationCoverageMin`) | FAIL | – | – | – |
| Contrast ratio within tolerance (spec 10) | 154 | 0.6234 | ≥ 0.9 (`agreement.contrastRatioWithinShareMin`) | FAIL | [0.5447, 0.6960] descriptive (ignores clustering); [0.4697, 0.7750] two-way clustered bootstrap (speakers × source prompts), 2000 resamples | p323 0.3750 (n=8) | 021-a 0.2000 (n=5) |
| Weak length, largest |Δ| (spec 10) | 154 | 72.9379 | ≤ 15.0 (`agreement.weakLengthMaxDeltaPoints`) | FAIL | – | p314 72.9379 (n=1) | 006 72.9379 (n=1) |
| nPVI, largest |Δ| (spec 10) | 204 | 34.8782 | ≤ 15.0 (`agreement.npviMaxDelta`) | FAIL | – | p310 34.8782 (n=1) | 010 34.8782 (n=1) |
| Pitch range ratio at or above minimum (spec 10) | 217 | 0.7742 | ≥ 0.95 (`agreement.pitchRangeRatioShareMin`) | FAIL | [0.7141, 0.8248] descriptive (ignores clustering); [0.5942, 0.9035] two-way clustered bootstrap (speakers × source prompts), 2000 resamples | p271 0.2000 (n=5) | 008 0.0000 (n=1) |
| Final direction agreement (spec 10) | 114 | – | ≥ 0.9 (`agreement.finalDirectionAgreementMin`) | NOT EVALUATED (n=114, min=150) | – | – | – |
| Positive-set placement false positives (synthetic references) (spec 22) | 0 | – | ≤ 0.02 (`agreement.placementDiffPairsMax`) | NOT EVALUATED (n=0, min=150) | – | – | – |
| Reference anomaly rate, worst phrase (reported) (spec 10) | 281 | 1.0000 | ≤ 0.2 (`agreement.referenceAnomalyReviewShare`) | REPORTED (no gate) | – | – | 008 1.0000 (n=1) |
| L2 false positives, clean 1,400, after suppression | 1400 | 0.1071 | ≤ 0.02 (`agreement.l2FalsePositiveMax`) | FAIL | [0.0920, 0.1244] descriptive (ignores clustering) | 3214 0.4286 (n=7) | – |
| L2 false positives, clean 1,400, worst speaker (≥ 10 words) | 74 | 0.2727 | ≤ 0.1 (`agreement.l2FalsePositiveWorstSpeakerMax`) | FAIL | – | 9612 0.2727 (n=11) | – |
| Unintelligible words with a placement diff (count) | 157 | 0.0000 | ≤ 0.0 (`agreement.unintelligiblePlacementDiffsMax`) | PASS | – | – | – |

Per-row accounting (§3a):

| Metric | Pairs | Reference speakers | Prompts | Lost | Lost by reason |
|---|---|---|---|---|---|
| Band coverage, median over pairs (spec 09) | 281 | 6 | 21 | 18 | noUsableReference 18 |
| Any-diff pairs (spec 10) | 281 | 6 | 21 | 18 | noUsableReference 18 |
| Any-diff pairs, worst speaker (spec 10) | 281 | 6 | 21 | 18 | noUsableReference 18 |
| Any-diff pairs, worst phrase (spec 10) | 281 | 6 | 21 | 18 | noUsableReference 18 |
| Placement-diff pairs (spec 10) | 281 | 6 | 21 | 18 | noUsableReference 18 |
| Placement-diff pairs, worst speaker (spec 10) | 281 | 6 | 21 | 18 | noUsableReference 18 |
| Inconclusive pairs (spec 10) | 281 | 6 | 21 | 18 | noUsableReference 18 |
| Evaluation coverage (spec 10) | 281 | 6 | 21 | 18 | noUsableReference 18 |
| Contrast ratio within tolerance (spec 10) | 154 | 4 | 12 | 145 | contrast not applicable (tooFewExpectedUnstressed) 19; contrast unavailable (lowConfidence) 108; noUsableReference 18 |
| Weak length, largest |Δ| (spec 10) | 154 | 4 | 12 | 145 | noUsableReference 18; weakLength not applicable (tooFewExpectedUnstressed) 19; weakLength unavailable (lowConfidence) 108 |
| nPVI, largest |Δ| (spec 10) | 204 | 6 | 18 | 95 | noUsableReference 18; rhythm unavailable (lowConfidence) 77 |
| Pitch range ratio at or above minimum (spec 10) | 217 | 5 | 20 | 82 | noUsableReference 18; pitchRange unavailable (lowConfidence) 64 |
| Final direction agreement (spec 10) | 114 | 3 | 10 | 185 | finalDirection not applicable (modelHasNoFinalVoicing) 134; finalDirection unavailable (lowConfidence) 31; finalDirection unavailable (wordMissing) 2; noUsableReference 18 |
| Positive-set placement false positives (synthetic references) (spec 22) | 0 | 0 | 0 | 299 | no verified synthetic reference (spec 22) 281; noUsableReference 18 |

## descriptive, not a gate

| Metric | n | Value | Gate | Status | Interval | Worst speaker | Worst phrase |
|---|---|---|---|---|---|---|---|
| L2 false positives, clean 1,400, adults | 693 | 0.0981 | – | REPORTED (no gate) | [0.0781, 0.1225] descriptive (ignores clustering) | 9612 0.2727 (n=11) | – |
| L2 false positives, clean 1,400, childs | 707 | 0.1160 | – | REPORTED (no gate) | [0.0944, 0.1417] descriptive (ignores clustering) | 3214 0.4286 (n=7) | – |
| Clean 1,400: Whisper-substituted or deleted words (never reach the detector) | 1400 | 306.0000 | – | REPORTED (no gate) | – | – | – |
| L2 false positives, supplementary 1,868, after suppression | 1868 | 0.1006 | – | REPORTED (no gate) | [0.0878, 0.1151] descriptive (ignores clustering) | 9629 1.0000 (n=1) | – |

## Folds (one config per fold, every path under it)

| Fold | configDigest | Held-out speakers | Paths |
|---|---|---|---|
| 0 | `4fc683ef4fee3c0d…` | 15 | B1, B2, shared-detector |
| 1 | `4fc683ef4fee3c0d…` | 15 | B1, B2, shared-detector |
| 2 | `4fc683ef4fee3c0d…` | 14 | B1, B2, shared-detector |
| 3 | `4fc683ef4fee3c0d…` | 14 | B1, B2, shared-detector |
| 4 | `4fc683ef4fee3c0d…` | 14 | B1, B2, shared-detector |

Pooled out-of-fold recall, B1: 26 / 134
Pooled out-of-fold recall, B2: 26 / 134
Pooled out-of-fold recall, shared-detector: 5 / 134
Paired per word, shared-detector vs B1: 0 wins, 21 losses, McNemar p = 0.0000
Paired per word, shared-detector vs B2: 1 wins, 22 losses, McNemar p = 0.0000
Paired per word, B1 vs B2: 8 wins, 8 losses, McNemar p = 1.0000

## Spec 11 guard (§4c): NOT MET (FALLBACK)

### Condition 1: TTS-vs-MFA control ≤ 2% (§4): NOT MET

| Check | Set | n | Value | Limit | Interval | Status | Detail |
|---|---|---|---|---|---|---|---|
| TTS-vs-MFA control | synthetic | 307 | 0.1368 | ≤ 0.02 | [0.1028, 0.1798] | NOT MET | 42 of 307 words |
| TTS-vs-MFA control, inconclusive rise | synthetic | 307 | 0.0065 | – | – | REPORTED | inconclusive 5.2% → 5.9% |
| TTS-vs-MFA control, 1-syllable inconclusive rise | synthetic | 234 | 0.0085 | – | – | REPORTED | oracle 9/234 [0.020, 0.071], candidate 11/234 [0.026, 0.082]; flips 8/234 |
| TTS-vs-MFA control, 2-syllable inconclusive rise | synthetic | 51 | 0.0196 | ≤ 0.02 | – | MET | oracle 2/51 [0.011, 0.132], candidate 3/51 [0.020, 0.159]; flips 22/51 |
| TTS-vs-MFA control, 3-syllable inconclusive rise | synthetic | 15 | 0.0000 | ≤ 0.02 | – | reported (n < 30) | oracle 1/15 [0.012, 0.298], candidate 1/15 [0.012, 0.298]; flips 10/15 |
| TTS-vs-MFA control, 4+-syllable inconclusive rise | synthetic | 7 | -0.1429 | – | – | REPORTED | oracle 4/7 [0.250, 0.842], candidate 3/7 [0.158, 0.750]; flips 2/7 |

### Condition 2: inconclusive rate inside the 10% budget: NOT MET

| Check | Set | n | Value | Limit | Interval | Status | Detail |
|---|---|---|---|---|---|---|---|
| inconclusive pairs, positive set | vctk-held-out | 281 | 0.3808 | ≤ 0.10 | [0.3260, 0.4388] | NOT MET | agreement.inconclusivePairsMax |

### Condition 3: b2 vs oracle ≤ 2% flips and ≤ 2 points of inconclusive rise (§4a): NOT MET

| Check | Set | n | Value | Limit | Interval | Status | Detail |
|---|---|---|---|---|---|---|---|
| b2 vs oracle | synthetic | 307 | 0.2248 | ≤ 0.02 | [0.1816, 0.2747] | NOT MET | 69 of 307 words |
| b2 vs oracle, inconclusive rise | synthetic | 307 | 0.1107 | ≤ 0.02 | – | NOT MET | inconclusive 5.2% → 16.3% |
| b2 vs oracle, 1-syllable inconclusive rise | synthetic | 234 | 0.0641 | – | – | REPORTED | oracle 9/234 [0.020, 0.071], candidate 24/234 [0.070, 0.148]; flips 15/234 |
| b2 vs oracle, 2-syllable inconclusive rise | synthetic | 51 | 0.1569 | ≤ 0.02 | – | NOT MET | oracle 2/51 [0.011, 0.132], candidate 10/51 [0.110, 0.325]; flips 35/51 |
| b2 vs oracle, 3-syllable inconclusive rise | synthetic | 15 | 0.6000 | ≤ 0.02 | – | reported (n < 30) | oracle 1/15 [0.012, 0.298], candidate 10/15 [0.417, 0.848]; flips 13/15 |
| b2 vs oracle, 4+-syllable inconclusive rise | synthetic | 7 | 0.2857 | – | – | REPORTED | oracle 4/7 [0.250, 0.842], candidate 6/7 [0.487, 0.974]; flips 6/7 |
| b2 vs oracle | vctk-held-out | 3890 | 0.2352 | ≤ 0.02 | [0.2222, 0.2488] | NOT MET | 915 of 3890 words |
| b2 vs oracle, inconclusive rise | vctk-held-out | 3890 | 0.0787 | ≤ 0.02 | – | NOT MET | inconclusive 9.3% → 17.1% |
| b2 vs oracle, 1-syllable inconclusive rise | vctk-held-out | 2921 | 0.0353 | – | – | REPORTED | oracle 243/2921 [0.074, 0.094], candidate 346/2921 [0.107, 0.131]; flips 301/2921 |
| b2 vs oracle, 2-syllable inconclusive rise | vctk-held-out | 639 | 0.1205 | ≤ 0.02 | – | NOT MET | oracle 44/639 [0.052, 0.091], candidate 121/639 [0.161, 0.222]; flips 343/639 |
| b2 vs oracle, 3-syllable inconclusive rise | vctk-held-out | 213 | 0.3662 | ≤ 0.02 | – | NOT MET | oracle 33/213 [0.112, 0.210], candidate 111/213 [0.454, 0.587]; flips 172/213 |
| b2 vs oracle, 4+-syllable inconclusive rise | vctk-held-out | 117 | 0.4103 | – | – | REPORTED | oracle 40/117 [0.262, 0.432], candidate 88/117 [0.667, 0.822]; flips 99/117 |

### Condition 4: jitter ±40 ms ≤ 2% flips on each set, pooled and per multi-syllable group (§4b): NOT MET

| Check | Set | n | Value | Limit | Interval | Status | Detail |
|---|---|---|---|---|---|---|---|
| jitter ±40 ms | synthetic | 307 | 0.0814 | ≤ 0.02 | [0.0558, 0.1174] | NOT MET | 25 of 307 words |
| jitter ±40 ms, 2-syllable flips | synthetic | 51 | 0.1765 | ≤ 0.02 | [0.0957, 0.3025] | NOT MET | 9 of 51 words |
| jitter ±40 ms, 3-syllable flips | synthetic | 15 | 0.3333 | ≤ 0.02 | [0.1518, 0.5829] | reported (n < 30) | 5 of 15 words |
| jitter ±40 ms, 4+-syllable flips | synthetic | 7 | 0.5714 | ≤ 0.02 | [0.2505, 0.8418] | reported (n < 30) | 4 of 7 words |
| jitter ±40 ms, inconclusive rise | synthetic | 307 | 0.0326 | – | – | REPORTED | inconclusive 5.2% → 8.5% |
| jitter ±40 ms, 1-syllable inconclusive rise | synthetic | 234 | 0.0299 | – | – | REPORTED | oracle 9/234 [0.020, 0.071], candidate 16/234 [0.043, 0.108]; flips 7/234 |
| jitter ±40 ms, 2-syllable inconclusive rise | synthetic | 51 | 0.0392 | ≤ 0.02 | – | NOT MET | oracle 2/51 [0.011, 0.132], candidate 4/51 [0.031, 0.185]; flips 9/51 |
| jitter ±40 ms, 3-syllable inconclusive rise | synthetic | 15 | 0.0000 | ≤ 0.02 | – | reported (n < 30) | oracle 1/15 [0.012, 0.298], candidate 1/15 [0.012, 0.298]; flips 5/15 |
| jitter ±40 ms, 4+-syllable inconclusive rise | synthetic | 7 | 0.1429 | – | – | REPORTED | oracle 4/7 [0.250, 0.842], candidate 5/7 [0.359, 0.918]; flips 4/7 |
| jitter ±40 ms | vctk-held-out | 3890 | 0.1165 | ≤ 0.02 | [0.1067, 0.1269] | NOT MET | 453 of 3890 words |
| jitter ±40 ms, 2-syllable flips | vctk-held-out | 639 | 0.1221 | ≤ 0.02 | [0.0989, 0.1497] | NOT MET | 78 of 639 words |
| jitter ±40 ms, 3-syllable flips | vctk-held-out | 213 | 0.1784 | ≤ 0.02 | [0.1328, 0.2354] | NOT MET | 38 of 213 words |
| jitter ±40 ms, 4+-syllable flips | vctk-held-out | 117 | 0.1880 | ≤ 0.02 | [0.1276, 0.2683] | NOT MET | 22 of 117 words |
| jitter ±40 ms, inconclusive rise | vctk-held-out | 3890 | 0.0841 | – | – | REPORTED | inconclusive 9.3% → 17.7% |
| jitter ±40 ms, 1-syllable inconclusive rise | vctk-held-out | 2921 | 0.1044 | – | – | REPORTED | oracle 243/2921 [0.074, 0.094], candidate 548/2921 [0.174, 0.202]; flips 315/2921 |
| jitter ±40 ms, 2-syllable inconclusive rise | vctk-held-out | 639 | 0.0188 | ≤ 0.02 | – | MET | oracle 44/639 [0.052, 0.091], candidate 56/639 [0.068, 0.112]; flips 78/639 |
| jitter ±40 ms, 3-syllable inconclusive rise | vctk-held-out | 213 | 0.0282 | ≤ 0.02 | – | NOT MET | oracle 33/213 [0.112, 0.210], candidate 39/213 [0.137, 0.240]; flips 38/213 |
| jitter ±40 ms, 4+-syllable inconclusive rise | vctk-held-out | 117 | 0.0342 | – | – | REPORTED | oracle 40/117 [0.262, 0.432], candidate 44/117 [0.294, 0.466]; flips 22/117 |

## L2 false-flag split, clean 1,400 (reported, not gated; `lowAsrConfidenceBelow: 0.45`)

| Thresholds | Group | Flagged | Words | Rate | Wilson 95% |
|---|---|---|---|---|---|
| initial | Whisper-substituted or deleted | 0 | 306 | 0.0000 | [0.0000, 0.0124] |
| initial | low ASR confidence | 0 | 70 | 0.0000 | [0.0000, 0.0520] |
| initial | clean matched | 150 | 1021 | 0.1469 | [0.1265, 0.1700] |
| tuned (FALLBACK: the initial thresholds ship) | Whisper-substituted or deleted | 0 | 306 | 0.0000 | [0.0000, 0.0124] |
| tuned (FALLBACK: the initial thresholds ship) | low ASR confidence | 0 | 70 | 0.0000 | [0.0000, 0.0520] |
| tuned (FALLBACK: the initial thresholds ship) | clean matched | 150 | 1021 | 0.1469 | [0.1265, 0.1700] |

## Tuning (§1, §2)

- §2 fit: 634238748 grid points; 0 meet the selection rule, 0 also the 10% budget, 0 also the guard on tuning data; outcome: FALLBACK (no grid point meets the selection rule's constraints on the tuning pool; the guard on tuning data (b2 vs MFA, ±40 ms jitter) is not met, and no tuned key reaches spec 07's verdicts)
- pool: correctWords 1705, recallWords 134, vctkPairs 476, vctkTuningSpeakers 24
- initial point on the pool: w=(0.4, 0.3, 0.3) λ=1.6 τ=(0.25, 0.50) (0.25, 0.50) (0.25, 0.50): recall 5/134, VCTK placement FP 9/476, any-diff 140/476, shared FP 159/1705, inconclusive 207/476, violation 0.6692
- closest by constraint violation: w=(0.4, 0.5, 0.1) λ=1.8 τ=(0.10, 0.85) (0.10, 1.00) (0.40, 1.00): recall 2/134, VCTK placement FP 6/476, any-diff 140/476, shared FP 75/1705, inconclusive 207/476, violation 0.6170
- closest by constraint violation: w=(0.4, 0.5, 0.1) λ=1.8 τ=(0.10, 0.85) (0.10, 1.00) (0.45, 1.00): recall 2/134, VCTK placement FP 6/476, any-diff 140/476, shared FP 75/1705, inconclusive 207/476, violation 0.6170
- closest by constraint violation: w=(0.4, 0.5, 0.1) λ=1.8 τ=(0.10, 0.85) (0.10, 1.00) (0.50, 1.00): recall 2/134, VCTK placement FP 6/476, any-diff 140/476, shared FP 75/1705, inconclusive 207/476, violation 0.6170
- closest by constraint violation: w=(0.4, 0.5, 0.1) λ=1.8 τ=(0.10, 0.85) (0.15, 1.00) (0.40, 1.00): recall 2/134, VCTK placement FP 6/476, any-diff 140/476, shared FP 75/1705, inconclusive 207/476, violation 0.6170
- closest by constraint violation: w=(0.4, 0.5, 0.1) λ=1.8 τ=(0.10, 0.85) (0.15, 1.00) (0.45, 1.00): recall 2/134, VCTK placement FP 6/476, any-diff 140/476, shared FP 75/1705, inconclusive 207/476, violation 0.6170
- guard on tuning data: b2 vs MFA, vctk-tuning: n=6824 value 0.2343 [0.2244, 0.2445] Wilson 95% (≤ 0.02): NOT MET; 1599 of 6824 words
- guard on tuning data: b2 vs MFA, inconclusive rise, vctk-tuning: n=6824 value 0.0826 (≤ 0.02): NOT MET; inconclusive 10.5% → 18.8%
- guard on tuning data: b2 vs MFA, 1-syllable inconclusive rise, vctk-tuning: n=5126 value 0.0412 (no limit): REPORTED; oracle 472/5126 [0.084, 0.100], candidate 683/5126 [0.124, 0.143]; flips 559/5126
- guard on tuning data: b2 vs MFA, 2-syllable inconclusive rise, vctk-tuning: n=1139 value 0.1185 (≤ 0.02): NOT MET; oracle 85/1139 [0.061, 0.091], candidate 220/1139 [0.171, 0.217]; flips 597/1139
- guard on tuning data: b2 vs MFA, 3-syllable inconclusive rise, vctk-tuning: n=373 value 0.4075 (≤ 0.02): NOT MET; oracle 77/373 [0.168, 0.250], candidate 229/373 [0.564, 0.662]; flips 292/373
- guard on tuning data: b2 vs MFA, 4+-syllable inconclusive rise, vctk-tuning: n=186 value 0.3548 (no limit): REPORTED; oracle 85/186 [0.387, 0.529], candidate 151/186 [0.750, 0.861]; flips 151/186
- guard on tuning data: jitter ±40 ms, vctk-tuning: n=6824 value 0.1216 [0.1141, 0.1296] Wilson 95% (≤ 0.02): NOT MET; 830 of 6824 words
- guard on tuning data: jitter ±40 ms, 2-syllable flips, vctk-tuning: n=1139 value 0.1484 [0.1289, 0.1702] Wilson 95% (≤ 0.02): NOT MET; 169 of 1139 words
- guard on tuning data: jitter ±40 ms, 3-syllable flips, vctk-tuning: n=373 value 0.2198 [0.1808, 0.2646] Wilson 95% (≤ 0.02): NOT MET; 82 of 373 words
- guard on tuning data: jitter ±40 ms, 4+-syllable flips, vctk-tuning: n=186 value 0.2312 [0.1764, 0.2968] Wilson 95% (≤ 0.02): NOT MET; 43 of 186 words
- guard on tuning data: jitter ±40 ms, inconclusive rise, vctk-tuning: n=6824 value 0.0844 (no limit): REPORTED; inconclusive 10.5% → 19.0%
- guard on tuning data: jitter ±40 ms, 1-syllable inconclusive rise, vctk-tuning: n=5126 value 0.0999 (no limit): REPORTED; oracle 472/5126 [0.084, 0.100], candidate 984/5126 [0.181, 0.203]; flips 536/5126
- guard on tuning data: jitter ±40 ms, 2-syllable inconclusive rise, vctk-tuning: n=1139 value 0.0299 (≤ 0.02): NOT MET; oracle 85/1139 [0.061, 0.091], candidate 119/1139 [0.088, 0.124]; flips 169/1139
- guard on tuning data: jitter ±40 ms, 3-syllable inconclusive rise, vctk-tuning: n=373 value 0.0670 (≤ 0.02): NOT MET; oracle 77/373 [0.168, 0.250], candidate 102/373 [0.231, 0.321]; flips 82/373
- guard on tuning data: jitter ±40 ms, 4+-syllable inconclusive rise, vctk-tuning: n=186 value 0.0269 (no limit): REPORTED; oracle 85/186 [0.387, 0.529], candidate 90/186 [0.413, 0.555]; flips 43/186
- guard on tuning data: guard on tuning data: NOT MET
- §1 fold 0 (15 speakers): 0 feasible; no feasible point: initial thresholds (FALLBACK); config 4fc683ef
- §1 fold 1 (15 speakers): 0 feasible; no feasible point: initial thresholds (FALLBACK); config 4fc683ef
- §1 fold 2 (14 speakers): 0 feasible; no feasible point: initial thresholds (FALLBACK); config 4fc683ef
- §1 fold 3 (14 speakers): 0 feasible; no feasible point: initial thresholds (FALLBACK); config 4fc683ef
- §1 fold 4 (14 speakers): 0 feasible; no feasible point: initial thresholds (FALLBACK); config 4fc683ef
- verification: initial point, recall: table flags 5 after / 23 before suppression; shared-detector run 5 / 23: identical
- verification: initial point, tuning-correct: table flags 159 after / 865 before suppression; shared-detector run 159 / 865: identical
- verification: initial point, VCTK pairs: rescoring reproduces the analyzer's diff/inconclusive outcome on 476 of 476 pairs
- verification: 60 random grid points evaluated directly: 915 of 915 unit outcomes match the tables
- verification: §1 out-of-fold flags: tables and the real shared-detector path with each fold's config agree on all 134 words

## Reported only (never asserted)

- Whisper-substituted or deleted words on the clean 1,400: 306: 000030067#4 SWIMMING, 000030079#0 LAYLA, 000030119#1 TINA, 000440021#0 MANDY, 000440021#4 AUSTRALIAN, 000440082#0 LILLY, 000440089#0 SANDY, 000440104#1 LAYLA, 000440126#0 TEDDY, 000440126#3 CUMBER, 000440132#0 ANDY, 000440147#0 LILLY, 000440147#3 CAIRO, 000920009#1 ALICE, 000920055#2 LANTERN, 000920074#0 SANDY, 000920092#2 LYNDA'S, 000920129#4 POTATO, 000920173#2 MANY, 000930005#0 BILLY, 000930051#3 ZERO, 000930089#0 DORA, 000930099#0 JACKIE, 000930101#2 MARY'S, 000930111#0 BOBBY, 000930148#4 USUAL, 000930155#2 ANY, 000930162#3 PARROT, 000940012#0 LILLY, 000940021#0 LYNDA, 000940074#2 ROWING, 000940102#3 RAINCOAT, 000940133#0 JAYME, 000960002#0 LISA, 000960066#1 LILLY, 000960066#4 BASEBALL, 000960071#0 ANDY, 000960071#2 HANDBALL, 000960073#0 SANDY, 000960084#2 PETER, 001110056#2 SCIENTIST, 001110114#2 WALKING, 001110114#4 BATHROOM, 001110122#1 ANDY, 001110122#5 RESTROOM, 001110135#0 DORA, 001110137#0 ALICE, 001110137#5 POLICE, 001110141#0 ANDY, 001110141#4 FRIDAY, 001120013#0 LAYLA, 001120063#0 TURKEYS, 001120063#1 HOLIDAY, 001120119#1 ALICE, 001120119#3 INTO, 001120119#5 LIVING, 001120130#0 ANDY, 001120141#2 TODAY, 001130019#4 ZEBRA, 001130023#0 ANDY, …
- Clean-1,400 FP after suppression: 10.7% (150 of 1400) on the shipped config, next to spec 08's 10.7% (150 of 1,400) on the initial thresholds
- L2 split (initial): 3 words have no A(w) and get no decision (never flagged)
- L2 split (tuned (FALLBACK: the initial thresholds ship)): 3 words have no A(w) and get no decision (never flagged)
- §1 baseline B1: recall 26/134 (0.194); detector vs B1 paired: 0 wins, 21 losses, McNemar p = 0.0000
- §1 baseline B2: recall 26/134 (0.194); detector vs B2 paired: 1 wins, 22 losses, McNemar p = 0.0000
- §6.5 rule (best baseline B1): FAIL: D below B* − 0.03; paired bootstrap lower bound of D − B* below -0.05; B* below the ceiling and D − B* below min(lift cap, (1 − B*)/2) = 0.1
- jitter ±20 ms, synthetic: n=307 value 0.0358 [0.0201, 0.0630] Wilson 95% (no limit): REPORTED; 11 of 307 words
- jitter ±20 ms, vctk-held-out: n=3890 value 0.0578 [0.0509, 0.0656] Wilson 95% (no limit): REPORTED; 225 of 3890 words
- jitter ±80 ms, synthetic: n=307 value 0.1238 [0.0915, 0.1653] Wilson 95% (no limit): REPORTED; 38 of 307 words
- jitter ±80 ms, vctk-held-out: n=3890 value 0.1589 [0.1477, 0.1707] Wilson 95% (no limit): REPORTED; 618 of 3890 words
- shipped thresholds, synthetic, control: 42 of 307 words differ (13.7%), inconclusive 16 → 18; spec 23 on the initial thresholds: 13.7% (42 / 307)
-   synthetic control by cue (duration = longestSyllable, intensity = loudestSyllable; pitch is not a spec 07 verdict part): inconclusive 10 (only 8), longestSyllable 27 (only 18), loudestSyllable 15 (only 6), syllableCount 0 (only 0)
-   synthetic control by syllables: 1: 8/234, inconclusive 9 → 11; 2: 22/51, inconclusive 2 → 3; 3: 10/15, inconclusive 1 → 1; 4+: 2/7, inconclusive 4 → 3
-   synthetic control by transition: feedback↔close (decided↔decided) 29, anything↔inconclusive 13
-   synthetic control by boundary error: 0–20 ms 3/35; 20–40 ms 23/183; 40–80 ms 9/68; 80–160 ms 1/2; >160 ms 6/19
- shipped thresholds, synthetic, b2: 69 of 307 words differ (22.5%), inconclusive 16 → 50; spec 23: 22.5%, +11.1 points
-   synthetic b2 by cue (duration = longestSyllable, intensity = loudestSyllable; pitch is not a spec 07 verdict part): inconclusive 34 (only 20), longestSyllable 29 (only 11), loudestSyllable 34 (only 13), syllableCount 0 (only 0)
-   synthetic b2 by syllables: 1: 15/234, inconclusive 9 → 24; 2: 35/51, inconclusive 2 → 10; 3: 13/15, inconclusive 1 → 10; 4+: 6/7, inconclusive 4 → 6
-   synthetic b2 by transition: feedback↔close (decided↔decided) 30, anything↔inconclusive 39
-   synthetic b2 by boundary error: 0–20 ms 1/17; 20–40 ms 6/44; 40–80 ms 18/135; 80–160 ms 18/61; >160 ms 26/50
-   synthetic b2 inconclusive rise 34 words: from the CTC confidence gate 3, from the margins 31 (11 words gated)
- shipped thresholds, synthetic, jitter-20: 11 of 307 words differ (3.6%), inconclusive 16 → 19
- shipped thresholds, synthetic, jitter-40: 25 of 307 words differ (8.1%), inconclusive 16 → 26
-   synthetic jitter-40 by cue (duration = longestSyllable, intensity = loudestSyllable; pitch is not a spec 07 verdict part): inconclusive 10 (only 8), longestSyllable 9 (only 6), loudestSyllable 10 (only 8), syllableCount 0 (only 0)
-   synthetic jitter-40 by syllables: 1: 7/234, inconclusive 9 → 16; 2: 9/51, inconclusive 2 → 4; 3: 5/15, inconclusive 1 → 1; 4+: 4/7, inconclusive 4 → 5
-   synthetic jitter-40 by transition: feedback↔close (decided↔decided) 13, anything↔inconclusive 12
-   synthetic jitter-40 by boundary error: 0–20 ms 5/165; 20–40 ms 20/142; 40–80 ms 0/0; 80–160 ms 0/0; >160 ms 0/0
- shipped thresholds, synthetic, jitter-80: 38 of 307 words differ (12.4%), inconclusive 16 → 35
- shipped thresholds, synthetic: Whisper-substituted 5, deleted 0 (kept out of every diff); 20 clips
- shipped thresholds, vctk-held-out, b2: 915 of 3890 words differ (23.5%), inconclusive 360 → 666; spec 23 (bundled starter clips): 22.5%, +10.2 points
-   vctk-held-out b2 by cue (duration = longestSyllable, intensity = loudestSyllable; pitch is not a spec 07 verdict part): inconclusive 544 (only 378), longestSyllable 385 (only 151), loudestSyllable 341 (only 82), syllableCount 0 (only 0)
-   vctk-held-out b2 by syllables: 1: 301/2921, inconclusive 243 → 346; 2: 343/639, inconclusive 44 → 121; 3: 172/213, inconclusive 33 → 111; 4+: 99/117, inconclusive 40 → 88
-   vctk-held-out b2 by transition: feedback↔close (decided↔decided) 318, anything↔inconclusive 597
-   vctk-held-out b2 by boundary error: 0–20 ms 13/190; 20–40 ms 96/650; 40–80 ms 212/1298; 80–160 ms 309/1165; >160 ms 285/587
-   vctk-held-out b2 inconclusive rise 306 words: from the CTC confidence gate 30, from the margins 276 (74 words gated)
- shipped thresholds, vctk-held-out, jitter-20: 225 of 3890 words differ (5.8%), inconclusive 360 → 523
- shipped thresholds, vctk-held-out, jitter-40: 453 of 3890 words differ (11.6%), inconclusive 360 → 687
-   vctk-held-out jitter-40 by cue (duration = longestSyllable, intensity = loudestSyllable; pitch is not a spec 07 verdict part): inconclusive 341 (only 329), longestSyllable 71 (only 44), loudestSyllable 74 (only 50), syllableCount 0 (only 0)
-   vctk-held-out jitter-40 by syllables: 1: 315/2921, inconclusive 243 → 548; 2: 78/639, inconclusive 44 → 56; 3: 38/213, inconclusive 33 → 39; 4+: 22/117, inconclusive 40 → 44
-   vctk-held-out jitter-40 by transition: feedback↔close (decided↔decided) 82, anything↔inconclusive 371
-   vctk-held-out jitter-40 by boundary error: 0–20 ms 97/2043; 20–40 ms 356/1847; 40–80 ms 0/0; 80–160 ms 0/0; >160 ms 0/0
- shipped thresholds, vctk-held-out, jitter-80: 618 of 3890 words differ (15.9%), inconclusive 360 → 759
- shipped thresholds, vctk-held-out: Whisper-substituted 102, deleted 2 (kept out of every diff); 299 clips
- End-to-end check (ii): NOT EVALUATED (no verified synthetic reference: no ElevenLabs key, and no Premium English voice installed for the Mac fallback; spec 22 never downloads voices)
- Synthetic set which-syllable accuracy and controls: NOT EVALUATED (spec 22's synthetic negative set needs a verified synthetic reference)
- 3-take stability (weak length, pitch range, final direction): NOT EVALUATED (speechocean762: 0 speaker × utterance texts with 3 or more takes among the labelled utterances; VCTK: one take per speaker per prompt); the flags stay on, the call goes to CPO
- referenceAnomaly: Reference anomaly rate, worst phrase (reported) (spec 10): n 281, value 1.000, gate ≤ 0.2, interval –, worst speaker –, worst phrase 008 1.000 (n 1): REPORTED (no gate)
- VCTK CV estimate, not shipped (6 folds over the tuning speakers): placement diffs 9/476, any-diff 140/476, inconclusive 207/476; 6 of 6 folds had no feasible point (initial thresholds)

## Notes

- pipeline: spec 12 Analyzer, word timings replayed from openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631, pYIN pitch, spec 10 scoring; references: fixtures/vctk/reference-lists.json (§3a), first listed reference usable for every phrase word; natives (A(w), band) = the phrase's analysed references but the take's speaker
- references serving pairs: p225 207, p226 55, p227 3, p232 1, p233 13, p334 2
- references skipped before the one used (first unusable word's reason): asrSubstitution 75, lowAsrConfidence 34
- reference list short (§3a minimum 3): 019: 2 references (< 3): only 2 non-held-out speakers have a kept 2–6 s take
- evaluation coverage, stressPlacement: 1.000 of 265 applicable
- evaluation coverage, contrast: 0.588 of 262 applicable
- evaluation coverage, tooMuchContrast: 0.588 of 262 applicable
- evaluation coverage, weakLength: 0.588 of 262 applicable
- override review (referenceAnomaly ≥ 20%): 008, 021-b, 024
- pairs measured: scoring 281, band coverage 281 of 299 held-out takes (feedback 94, inconclusive 107, noClearDifference 76, takeProblem(wordsDontMatch) 4); thresholds digest 4fc683ef
- not scored: 18 noUsableReference

## Limitations

- The shipped config's L2 recall is never measured on unseen speakers; the only L2 recall number is the CV estimate of the tuning procedure.

## Summary

    Negative set: FAIL (5 of 6 rows not PASS)
    Positive set: FAIL (14 of 14 rows not PASS)
    Spec 11 guard: NOT MET (FALLBACK)
    Release gate: NOT MET
