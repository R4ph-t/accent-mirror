# Thresholds

Every tunable number in Accent Mirror, in one place.

**Status: initial values, plan v2 revision 4.1** (2026-11-23). They are tuned only on the tuning split (plan §2),
never on held-out clips. A change goes through a PR that says why and bumps `thresholdsVersion`. Never lower a
threshold quietly: a result under a bar goes back to CTO.

This file mirrors `Packages/AccentKit/Sources/AMCore/Thresholds.swift` (`Thresholds.current`). Each row holds one
number. **Key** is the Swift property path under `Thresholds`, and `ThresholdsMirrorTests` fails if a row's
**Value** and the Swift value disagree, or if a Swift value has no row here. Values are plain numbers in the stated
unit: write `-50`, not `−50 dBFS`. Shares are fractions (`0.8` = 80%), and "points" are percentage points as
fractions (`0.03` = 3 pp). **Plan** names the section the value comes from; "v1" is the v1 groundwork plan's
thresholds table and "first v2" the first v2 (09:10), both carried over "as before" by rev 4.1.

## Pitch

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Pitch window | `pitch.windowMs` | 40 | ms | v1 | 04 | YIN/pYIN analysis window |
| Pitch hop | `pitch.hopMs` | 10 | ms | v1 | 04 | |
| F0 search, low end | `pitch.minF0Hz` | 60 | Hz | v1 | 04 | |
| F0 search, high end | `pitch.maxF0Hz` | 500 | Hz | v1 | 04 | |
| Voicing probability | `pitch.voicingProbability` | 0.5 | pYIN probability | v1 | 04 | Frame is voiced at or above it |
| Minimum voiced run | `pitch.minVoicedRunMs` | 30 | ms | v1 | 04 | Shorter runs are dropped |
| Median filter | `pitch.medianFilterFrames` | 5 | frames | v1 | 04 | Then octave-jump repair |
| Pitch-line break | `pitch.lineBreakMs` | 250 | ms | v1 | 04 | Longer pauses break the line; shorter unvoiced gaps are bridged (`voiced = false`) |
| Pitch axis, initial | `pitch.axisInitialSemitones` | 12 | ± st | v1 | 04 | |
| Pitch axis, step | `pitch.axisStepSemitones` | 6 | st | v1 | 04 | Grows in steps; never shrinks within a phrase |
| Pitch axis, maximum | `pitch.axisMaxSemitones` | 24 | ± st | v1 | 04 | |

## Capture and takes

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Onset level, absolute | `capture.onsetMinimumDBFS` | -50 | dBFS | §10, first v2 §10 | 05 | Onset: RMS ≥ max(this, floor + `onsetAboveFloorDB`). Replaces v1's max(−45, floor + 12) |
| Onset level above floor | `capture.onsetAboveFloorDB` | 10 | dB | §10, first v2 §10 | 05 | |
| Onset run | `capture.onsetFrames` | 3 | 10 ms frames | §10 | 05 | Consecutive frames above the onset level |
| Onset voicing window | `capture.onsetVoicedWithinMs` | 100 | ms | §10 | 05 | ≥ 1 voiced frame within this; so t_detect − t_onset ≤ 100 ms |
| Offset level above floor | `capture.offsetAboveFloorDB` | 6 | dB | first v2 §10 | 05 | Speech ends below floor + this |
| Provisional floor | `capture.provisionalFloorDBFS` | -60 | dBFS | §10 | 05 | Until settled, unless the device's last-session floor is known |
| Settling: non-speech | `capture.settleNonSpeechMs` | 300 | ms | §10 | 05 | Rule (a): floor = P10 of these frames |
| Settling: stationary after | `capture.settleStationaryAfterS` | 2.0 | s | §10 | 05 | Rule (b), if the last 2 s are stationary |
| Settling: stationary spread | `capture.stationarySpreadDB` | 6 | dB | §10 | 05 | Frame-RMS P90 − P10 below this |
| Floor percentile | `capture.floorPercentile` | 10 | percentile | §10 | 05 | |
| Floor tracking window | `capture.floorWindowS` | 2.0 | s | first v2 §10 | 05 | Sliding window of non-speech frames after settling |
| Floor clamp, low | `capture.floorClampLowDBFS` | -70 | dBFS | first v2 §10 | 05 | |
| Floor clamp, high | `capture.floorClampHighDBFS` | -35 | dBFS | first v2 §10 | 05 | |
| Retraction level above floor | `capture.retractionAboveFloorDB` | 10 | dB | §10 | 05 | Provisional onsets with median RMS below settled floor + this are retracted |
| Pre-roll kept | `capture.preRollMs` | 200 | ms | §10 | 05 | Saved audio starts at max(0, t_onset − 0.2 s) |
| Pre-roll ring buffer | `capture.ringBufferMs` | 500 | ms | §10 | 05 | |
| End of take | `capture.endOfTakeS` | 1.2 | s | v1 | 05 | Trailing silence after speech |
| Endpoint arming | `capture.endpointArmSpeechS` | 0.3 | s | first v2 §10 | 05 | The end of take is armed only once this much speech has accumulated |
| Recording cap | `capture.recordingCapS` | 20 | s | v1 | 05 | Hard cap |
| No speech | `capture.noSpeechS` | 0.15 | s | v1 | 05 | Total speech below this |
| No speech: voicing | `capture.noSpeechVoicedS` | 0.3 | s | first v2 §10 | 05 | `noSpeech` also needs voiced frames below this; at or above it with no detected speech, the take is `tooQuiet` |
| Too short | `capture.tooShortS` | 0.5 | s | v1 | 05 | Speech below this |
| Too quiet | `capture.tooQuietDBFS` | -40 | dBFS | v1 | 05 | Median RMS of speech frames below this |
| Clipped | `capture.clippedShare` | 0.005 | share of speech frames | v1 | 05 | At or above this share of frames with a clip run |
| Clip run | `capture.clipRunSamples` | 3 | samples | v1 | 05 | Run of samples at or above the clip level |
| Clip level | `capture.clipLevel` | 0.999 | \|x\| | v1 | 05 | |
| Import limit | `capture.importLimitS` | 15 | s | v1 | 16 | First 15 s of speech, trimmed |

## Voicing (`ACFVoicing`)

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| ACF window | `voicing.windowMs` | 40 | ms | §10 | 05 | |
| ACF hop | `voicing.hopMs` | 10 | ms | §10 | 05 | |
| ACF lag, low end | `voicing.minLagMs` | 2 | ms | §10 | 05 | 500 Hz |
| ACF lag, high end | `voicing.maxLagMs` | 16.7 | ms | §10 | 05 | 60 Hz |
| ACF peak | `voicing.minPeak` | 0.45 | normalised ACF | §10 | 05 | Voiced at or above it, and RMS above floor + `aboveFloorDB` |
| Voicing level above floor | `voicing.aboveFloorDB` | 3 | dB | §10 | 05 | |

## Alignment

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| ASR word-span padding | `alignment.asrPaddingMs` | 80 | ms | CTO decision 4 | 07 | Both sides of each Whisper word span |
| Needleman–Wunsch match | `alignment.matchScore` | 2 | score | §4.3 | 06 | |
| Needleman–Wunsch mismatch | `alignment.mismatchScore` | -1 | score | §4.3 | 06 | |
| Needleman–Wunsch gap | `alignment.gapScore` | -1 | score | §4.3 | 06 | |

## Confidence

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Word / syllable confidence, high | `confidence.levelHigh` | 0.7 | 0–1 | first v2 §5 | 07 | c_w and min(c_w, s_w) |
| Word / syllable confidence, medium | `confidence.levelMedium` | 0.45 | 0–1 | first v2 §5 | 07 | Below it: low |
| Timing Good | `confidence.timingGood` | 0.8 | share of comparable syllables at ≥ medium | first v2 §5 | 07, 09 | |
| Timing Rough | `confidence.timingRough` | 0.5 | share of comparable syllables at ≥ medium | first v2 §5 | 07, 09 | Below it: Poor (DTW inside the segment). Replaces v1's "timing confidence < 0.5" row at the same cut |
| Contrast / weak-length confidence, high | `confidence.contrastHigh` | 0.9 | share of S∪U syllables at ≥ medium | first v2 §5 | 10 | |
| Contrast / weak-length confidence, medium | `confidence.contrastMedium` | 0.7 | share of S∪U syllables at ≥ medium | first v2 §5 | 10 | |
| Pitch-measure confidence, high | `confidence.pitchHigh` | 0.7 | voiced coverage of comparable frames | first v2 §5 | 10 | |
| Pitch-measure confidence, medium | `confidence.pitchMedium` | 0.5 | voiced coverage of comparable frames | first v2 §5 | 10 | |
| Final-direction confidence, high | `confidence.finalDirectionHighFrames` | 15 | voiced frames in window | first v2 §5 | 10 | |
| Final-direction confidence, medium | `confidence.finalDirectionMediumFrames` | 10 | voiced frames in window | first v2 §5 | 10 | |

## Prominence and stress

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Weight, duration | `prominence.durationWeight` | 0.4 | weight | §2 | 08 | Tuned on the fixed grid |
| Weight, energy | `prominence.energyWeight` | 0.3 | weight | §2 | 08 | |
| Weight, pitch | `prominence.pitchWeight` | 0.3 | weight | §2 | 08 | |
| z floor, duration | `prominence.durationFloorLn` | 0.05 | ln s | §2 | 08 | sd floor |
| z floor, energy | `prominence.energyFloorDB` | 1 | dB | §2 | 08 | |
| z floor, pitch | `prominence.pitchFloorSemitones` | 1 | st | §2 | 08 | |
| Energy floor | `prominence.energyMinimumDBFS` | -60 | dBFS | §2 | 08 | e_i is floored here |
| Pitch feature minimum | `prominence.pitchMinVoicedFrames` | 3 | voiced frames | §2 | 08 | Fewer: p_i missing |
| Lengthening discount λ | `prominence.lengtheningLambda` | 1.6 | ratio | §2 | 08 | d_i − ln λ for exposed syllables |
| Exposure pause | `prominence.exposurePauseMs` | 150 | ms | §2 | 07, 08 | Last syllable before a pause longer than this is exposed |
| τ_med, 2–4 syllables | `prominence.tauMedium.syllables2to4` | 0.25 | z | §2 | 08 | |
| τ_med, 5–8 syllables | `prominence.tauMedium.syllables5to8` | 0.25 | z | §2 | 08 | |
| τ_med, ≥ 9 syllables | `prominence.tauMedium.syllables9Plus` | 0.25 | z | §2 | 08 | |
| τ_high, 2–4 syllables | `prominence.tauHigh.syllables2to4` | 0.5 | z | §2 | 08 | |
| τ_high, 5–8 syllables | `prominence.tauHigh.syllables5to8` | 0.5 | z | §2 | 08 | |
| τ_high, ≥ 9 syllables | `prominence.tauHigh.syllables9Plus` | 0.5 | z | §2 | 08 | |
| Secondary stress | `prominence.secondaryStressShare` | 0.75 | × primary prominence | v1 | 08 | Not next to the primary |

## Applicability

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Placement word length | `applicability.placementMinSyllables` | 2 | syllables | §1.1 | 01 | A target or content word, not `expectedAmbiguous` |
| Contrast: stressed syllables | `applicability.contrastMinStressed` | 1 | \|S\| | §1.1 | 01 | Also too much contrast and weak length |
| Contrast: unstressed syllables | `applicability.contrastMinUnstressed` | 2 | \|U\| | §1.1 | 01 | |
| nPVI phrase length | `applicability.rhythmMinSyllables` | 3 | syllables | §1.1 | 01 | Inspector only |
| Pitch range and shape match | `applicability.pitchMinModelVoicedFrames` | 20 | model voiced frames | §1.1 | 01 | Optional measures |

## Final direction

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Window | `finalDirection.windowMs` | 200 | ms | §11 | 10 | Final voiced frames ending at the last voiced frame of comparable material |
| Extended window | `finalDirection.extendedWindowMs` | 300 | ms | §11 | 10 | When the window has too few voiced frames |
| Voiced frames needed | `finalDirection.minVoicedFrames` | 10 | voiced frames | §11, §1.1 | 10 | Also the model-side applicability rule |
| Rise | `finalDirection.riseSemitonesPerSecond` | 5 | st/s | §11 | 10 | Slope at or above. Replaces v1's "\|slope\| ≥ 1 st" |
| Fall | `finalDirection.fallSemitonesPerSecond` | -5 | st/s | §11 | 10 | Slope at or below; between rise and fall is level |

## Diffs and measures

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Contrast diff | `diffs.contrastBelowModelRatio` | 0.7 | × model's C | v1 | 10 | Yours below this × the model's |
| Contrast diff, model minimum | `diffs.contrastModelMinimum` | 1.3 | C | v1 | 10 | And the model's C at or above this |
| Too much contrast | `diffs.tooMuchContrastAboveModelRatio` | 2 | × model's C | v1 | 10 | Lowest priority; only with fewer than 3 higher-priority rows |
| Weak-length diff | `diffs.weakLengthPointsAboveModel` | 15 | points of W | v1 | 10 | Yours this many points above the model's |
| Pitch-range diff, ratio | `diffs.pitchRangeBelowModelRatio` | 0.6 | × model's range | v1 | 10 | |
| Pitch-range diff, width | `diffs.pitchRangeNarrowerSemitones` | 3 | st | v1 | 10 | And at least this much narrower |
| Shape match frames | `measures.shapeMatchMinOverlappingFrames` | 20 | overlapping voiced frames | §1.1, first v2 §11 | 10 | Fewer: `.unavailable(.tooFewOverlappingFrames)` |

## Native band

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Band, lower | `band.lowerPercentile` | 10 | percentile | v1 | 09 | Per aligned frame across native takes |
| Band, upper | `band.upperPercentile` | 90 | percentile | v1 | 09 | |
| Band, one take | `band.singleTakeHalfWidthSemitones` | 1.5 | ± st | v1 | 09 | Around the model |

## Decision

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Word match | `decision.minMatchShare` | 0.8 | share of content words | §1.2, §4.2 | 01, 06 | Below it: `wordsDontMatch` |
| Non-filler insertions | `decision.maxNonFillerInsertions` | 2 | words | §1.2 | 01, 06 | More: `wordsDontMatch` |
| Comparable coverage | `decision.minComparableCoverage` | 0.7 | share of model syllables | §1.2 | 01 | Below it: `inconclusive(.comparableCoverageLow)` |
| Close: shape match | `decision.closeMinShapeMatch` | 0.7 | Pearson r | §1.3 | 01 | When applicable; plus timing Good and nothing triggered |
| Max diff rows | `decision.maxDiffRows` | 3 | rows | §1, §5 | 01 | The rough-timing row counts toward the 3 |

## Agreement gates (`Thresholds.agreement`)

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Positive set, minimum pairs | `agreement.positiveMinPairs` | 150 | pairs | §6.2, §6.7 | 02, 10 | Below it: NOT EVALUATED |
| Positive set, held-out speakers | `agreement.positiveHeldOutSpeakers` | 12 | speakers | §6.1, §6.7 | 02 | |
| Any-diff pairs | `agreement.anyDiffPairsMax` | 0.05 | share of pairs | §6.7 | 10 | Point. Replaces v1's "false positives ≤ 5% of phrases" |
| Any-diff pairs, worst speaker | `agreement.anyDiffWorstSpeakerMax` | 0.15 | share | §6.7 | 10 | |
| Any-diff pairs, worst phrase | `agreement.anyDiffWorstPhraseMax` | 0.30 | share | §6.7 | 10 | |
| Placement-diff pairs | `agreement.placementDiffPairsMax` | 0.02 | share of pairs | §6.7 | 10 | Point |
| Placement-diff pairs, worst speaker | `agreement.placementDiffWorstSpeakerMax` | 0.07 | share | §6.7 | 10 | |
| Inconclusive pairs | `agreement.inconclusivePairsMax` | 0.10 | share of pairs | §6.7 | 10 | Abstention |
| Evaluation coverage | `agreement.evaluationCoverageMin` | 0.90 | evaluated ÷ applicable | §6.7 | 10 | Per required measure |
| Contrast ratio, low | `agreement.contrastRatioLow` | 0.7 | C_T/C_R | §6.7 (first v2) | 10 | |
| Contrast ratio, high | `agreement.contrastRatioHigh` | 1.43 | C_T/C_R | §6.7 (first v2) | 10 | |
| Contrast ratio, share within | `agreement.contrastRatioWithinShareMin` | 0.90 | share of pairs | §6.7 (first v2) | 10 | |
| Weak length tolerance | `agreement.weakLengthMaxDeltaPoints` | 15 | \|Δ\| points | §6.7 (first v2) | 10 | |
| nPVI tolerance | `agreement.npviMaxDelta` | 15 | \|Δ\| | §6.7 (first v2) | 10 | |
| Pitch range ratio | `agreement.pitchRangeRatioMin` | 0.6 | ratio | §6.7 (first v2) | 10 | |
| Pitch range, share at ratio | `agreement.pitchRangeRatioShareMin` | 0.95 | share of pairs | §6.7 (first v2) | 10 | |
| Band coverage | `agreement.bandCoverageMedianMin` | 0.80 | median over pairs | §6.7 (first v2) | 09 | |
| Final direction agreement | `agreement.finalDirectionAgreementMin` | 0.90 | share | §6.7 (first v2) | 10 | |
| L2 recall | `agreement.l2RecallMin` | 0.80 | pooled out-of-fold recall after suppression | §6.7 | 11 | ≥ 108/134; measures the procedure. Takes over the old "stress-detection bar, owner 03" row |
| L2 recall, Wilson lower bound | `agreement.l2RecallWilsonLowerMin` | 0.70 | share | §6.7 | 11 | Plus the §6.5 rule |
| L2 false positives | `agreement.l2FalsePositiveMax` | 0.02 | share of words | §6.7 | 11 | After suppression, shipped config, clean 1,400 / 90 |
| L2 false positives, worst speaker | `agreement.l2FalsePositiveWorstSpeakerMax` | 0.10 | share | §6.7 | 11 | |
| Which-syllable accuracy | `agreement.whichSyllableAccuracyMin` | 0.80 | share | §6.7 | 22 | Synthetic, clear; plus the §6.5 rule vs B0/B1 |
| Synthetic controls | `agreement.syntheticControlDiffsMax` | 0.02 | share with diffs | §6.7 | 22 | |
| Unintelligible words | `agreement.unintelligiblePlacementDiffsMax` | 0 | placement diffs | §6.7 | 02, 11 | Of 157; every one inconclusive or unscored |
| End-to-end recall gap | `agreement.endToEndRecallWithinPoints` | 0.10 | points | §6.7 | 22 | Within this of the shared-detector recall |
| End-to-end false positives | `agreement.endToEndFalsePositiveMax` | 0.02 | share | §6.7 | 22 | On the clean 1,400 |
| Smoke set run time | `agreement.smokeSetMaxSeconds` | 60 | s | §6.7 | 02 | Under it; never a rate gate |
| Reference anomaly review | `agreement.referenceAnomalyReviewShare` | 0.20 | share of takes per phrase | §6.7 | 10 | At or above: override review; the rate is reported |
| Baseline: shortfall | `agreement.baselineMaxShortfallPoints` | 0.03 | points | §6.5 | 02 | D ≥ B* − this |
| Baseline: bootstrap lower bound | `agreement.baselineBootstrapLowerPoints` | -0.05 | points | §6.5 | 02 | Paired clustered-bootstrap lower bound of D − B* at or above this |
| Baseline: ceiling | `agreement.baselineCeiling` | 0.85 | share | §6.5 | 02 | Below it, D − B* ≥ min(lift cap, (1 − B*)/2) |
| Baseline: lift cap | `agreement.baselineMinLiftCapPoints` | 0.10 | points | §6.5 | 02 | |
| Baseline: FP mirror | `agreement.baselineFalsePositiveMaxExcessPoints` | 0.01 | points | §6.5 | 02 | D ≤ B* + this |
| Bootstrap resamples | `agreement.bootstrapResamples` | 2000 | resamples | §6.6 | 02 | Seed in the manifest |

## Word timestamps (`Thresholds.wordTimestamps`)

Spec 03's feasibility bars (CTO ruling 2026-11-23 13:00): absolute error per boundary on unpadded WhisperKit word
starts and ends against the MFA word baseline (MFA 3.4.4, english_mfa v3.1.0). Starts and ends are judged
separately, each against every row below; a side that misses fails the gate. Padding (`alignment.asrPaddingMs`) is
spec 07's and is not applied here. Under a bar, the report goes to CTO.

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| Word-boundary median error | `wordTimestamps.medianErrorMaxMs` | 40 | ms | first v2 | 03 | Per side: median absolute error of unpadded starts, and of unpadded ends |
| Word-boundary tolerance | `wordTimestamps.withinToleranceMs` | 80 | ms | first v2 | 03 | The "within 80 ms" of the next row |
| Word boundaries within tolerance | `wordTimestamps.withinToleranceShareMin` | 0.85 | share of one side's comparable boundaries | first v2 | 03 | Per side: at least 85% of unpadded starts, and of unpadded ends, within 80 ms |

## Performance

| Name | Key | Value | Unit | Plan | Owner spec | Notes |
|---|---|---|---|---|---|---|
| End-to-end budget | `performance.endToEndBudgetS` | 2 | s | v1 | 11 | 3 s take on M1, model warm; hand check (`make bench`) |
| Non-ASR stages | `performance.nonASRStagesMs` | 500 | ms | v1 | 11 | CI gate on the runner |
| ASR (warm) | `performance.asrWarmMs` | 900 | ms | v1 | 03 | `tiny.en` is the fallback if base.en goes over |
