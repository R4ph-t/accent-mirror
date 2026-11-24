# Agreement report: positive

| Identity | Value |
|---|---|
| Generated | `2026-11-24T11:17:10Z` |
| Release report | `no` |
| configDigest | `4fc683ef4fee3c0d5c2aa632f56b0e12cdc13e73c8f256d932ba48dc6b13bab6` |
| ConfigIdentity | `algorithm 1, thresholds 8, contract 2, ASR replayed-word-timings, pitch pyin-1, voicing acf-1` |
| Corpus manifest hash | `a8a28ea55fef50217c9af1cfd720b3af0f0c83b4409b289326429f297fa53a32` |
| Label hash | `5ff2368165c0608bab2a90776bf5f39ba31c7fbd5dbecda7f04498627dd1d850` |
| Split manifest hash | `cd021cf29163d619c8515e9e6b9eb5aa0d513435dce3bfcf47c5331a670d78d0` |
| Split seed | `20261125` |
| sourceTreeHash | `567d7a21adf4395edafcf907184900f0c18d944da670268d33f4157a462b06b4` |
| Evaluated commit | `7a2faa13c488bacde27e07aaf7a1e7fee792726f` |
| Clean tree | `yes` |
| Xcode | `Xcode 26.2` |
| Swift | `Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)` |
| macOS | `Version 26.3 (Build 25D125)` |
| Runner image | `local` |
| syntheticReference | `none` |

## shipped-config check

| Metric | n | Value | Gate | Status | Interval | Worst speaker | Worst phrase |
|---|---|---|---|---|---|---|---|
| Band coverage, median over pairs (spec 09) | 219 | 0.5342 | ≥ 0.8 (`agreement.bandCoverageMedianMin`) | FAIL | – | p323 0.2437 (n=13) | – |
| Any-diff pairs (spec 10) | 219 | 0.3105 | ≤ 0.05 (`agreement.anyDiffPairsMax`) | FAIL | [0.2529, 0.3746] descriptive (ignores clustering); [0.1704, 0.4640] two-way clustered bootstrap (speakers × source prompts), 2000 resamples | p270 0.4667 (n=15) | 004 0.8000 (n=15) |
| Any-diff pairs, worst speaker (spec 10) | 219 | 0.4667 | ≤ 0.15 (`agreement.anyDiffWorstSpeakerMax`) | FAIL | – | p270 0.4667 (n=15) | 004 0.8000 (n=15) |
| Any-diff pairs, worst phrase (spec 10) | 219 | 0.8000 | ≤ 0.3 (`agreement.anyDiffWorstPhraseMax`) | FAIL | – | p270 0.4667 (n=15) | 004 0.8000 (n=15) |
| Placement-diff pairs (spec 10) | 219 | 0.0183 | ≤ 0.02 (`agreement.placementDiffPairsMax`) | PASS | [0.0071, 0.0460] descriptive (ignores clustering); [0.0000, 0.0556] two-way clustered bootstrap (speakers × source prompts), 2000 resamples | p238 0.0769 (n=13) | 015 0.1667 (n=12) |
| Placement-diff pairs, worst speaker (spec 10) | 219 | 0.0769 | ≤ 0.07 (`agreement.placementDiffWorstSpeakerMax`) | FAIL | – | p238 0.0769 (n=13) | 015 0.1667 (n=12) |
| Inconclusive pairs (spec 10) | 219 | 0.4703 | ≤ 0.1 (`agreement.inconclusivePairsMax`) | FAIL | [0.4053, 0.5364] descriptive (ignores clustering); [0.2639, 0.6785] two-way clustered bootstrap (speakers × source prompts), 2000 resamples | p336 0.6923 (n=13) | 002 1.0000 (n=16) |
| Evaluation coverage (spec 10) | 203 | 0.4926 | ≥ 0.9 (`agreement.evaluationCoverageMin`) | FAIL | – | – | – |
| Contrast ratio within tolerance (spec 10) | 100 | – | ≥ 0.9 (`agreement.contrastRatioWithinShareMin`) | NOT EVALUATED (n=100, min=150) | – | – | – |
| Weak length, largest |Δ| (spec 10) | 100 | – | ≤ 15.0 (`agreement.weakLengthMaxDeltaPoints`) | NOT EVALUATED (n=100, min=150) | – | – | – |
| nPVI, largest |Δ| (spec 10) | 147 | – | ≤ 15.0 (`agreement.npviMaxDelta`) | NOT EVALUATED (n=147, min=150) | – | – | – |
| Pitch range ratio at or above minimum (spec 10) | 167 | 0.7365 | ≥ 0.95 (`agreement.pitchRangeRatioShareMin`) | FAIL | [0.6649, 0.7975] descriptive (ignores clustering); [0.5442, 0.8962] two-way clustered bootstrap (speakers × source prompts), 2000 resamples | p271 0.0000 (n=4) | 015 0.2000 (n=10) |
| Final direction agreement (spec 10) | 99 | – | ≥ 0.9 (`agreement.finalDirectionAgreementMin`) | NOT EVALUATED (n=99, min=150) | – | – | – |
| Positive-set placement false positives (synthetic references) (spec 22) | 0 | – | ≤ 0.02 (`agreement.placementDiffPairsMax`) | NOT EVALUATED (n=0, min=150) | – | – | – |
| Reference anomaly rate, worst phrase (reported) (spec 10) | 219 | 0.0000 | ≤ 0.2 (`agreement.referenceAnomalyReviewShare`) | REPORTED (no gate) | – | – | 002 0.0000 (n=16) |

## Notes

- pipeline: spec 12 Analyzer, word timings replayed from openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631 (recorded once with am-eval record-timings --set positive), pYIN pitch, spec 10 scoring, natives = the phrase's bundled readers
- evaluation coverage, stressPlacement: 1.000 of 203 applicable
- evaluation coverage, contrast: 0.493 of 203 applicable
- evaluation coverage, tooMuchContrast: 0.493 of 203 applicable
- evaluation coverage, weakLength: 0.493 of 203 applicable
- pairs measured: scoring 219, band coverage 219 of 274 headline pairs (feedback 68, inconclusive 103, noClearDifference 44, takeProblem(wordsDontMatch) 4); thresholds are initial and untuned
- not scored: 8 failed at mapTime: reference p225 incomplete for 005
- not scored: 13 failed at mapTime: reference p225 incomplete for 021-b
- not scored: 4 failed at mapTime: reference p225 incomplete for 022
- not scored: 15 failed at mapTime: reference p225 incomplete for 023-a
- not scored: 15 failed at mapTime: reference p225 incomplete for 023-c

## Limitations

- The shipped config's L2 recall is never measured on unseen speakers; the only L2 recall number is the CV estimate of the tuning procedure.

## Summary

    Negative set: NOT EVALUATED
    Positive set: EVALUABLE
    Release gate: NOT MET
