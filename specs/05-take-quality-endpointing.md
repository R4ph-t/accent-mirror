# 05: Take quality and endpointing

Status: Draft · Branch: – · Depends on: 01 (contract v2; no dependency on 04) · Estimate: 3–4 h agent run + 1 h
Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §10 (two timestamps, provisional start-up, settling and retraction, `ACFVoicing`, E1–E17). E2–E12,
the noise floor, onset, endpoint and quiet-vs-no-speech rules are "as before" and come from the first v2 §10 (09:10
Europe/Paris). Problem order is Designer's (v1). Latency budgets are measured in spec 12.

## Goal

The pure, testable part of `AMCapture`: a streaming `Endpointer`, `TakeQuality.check`, and a streaming
`ACFVoicing` voicing detector behind a `VoicingSource` protocol. All tested on synthetic buffers. No microphone,
no `AVAudioEngine`, nothing under `AMCapture/Live/`.

## Behaviour

### Input

16 kHz mono Float32, processed in 10 ms frames. Frame RMS is in dBFS.

### Voicing: `ACFVoicing`

- `protocol VoicingSource: Sendable` in `AMCore` (so spec 07 can use voicing without importing `AMCapture`), with an
  `id` (`voicingID`, e.g. `acf-1`).
- `ACFVoicing`: streaming normalised autocorrelation, 40 ms window, 10 ms hop, lag range 2–16.7 ms (60–500 Hz). A
  frame is voiced if the normalised ACF peak is ≥ 0.45 **and** RMS > floor + 3 dB.
- It does not use spec 04. pYIN may replace it later only through a new `voicingID` and a version bump.

### Noise floor

- Provisional floor until settled: the device's last-session floor if the caller passes one, else −60 dBFS.
- Settling rule: (a) once 300 ms of non-speech frames exist, the floor is their 10th percentile; or (b) at 2.0 s
  elapsed without (a), if the last 2 s are stationary (frame-RMS P90 − P10 < 6 dB), the floor is the 10th percentile
  of all frames in that window. If neither holds, the floor stays provisional and tracking continues.
- After settling, the floor tracks the 10th percentile over a sliding 2 s window of non-speech frames, clamped to
  −70…−35 dBFS. Speech present from t = 0 never pollutes the floor.

### Onset, offset, endpoint

- Onset: frame RMS ≥ max(−50 dBFS, floor + 10 dB) for 3 consecutive frames, with ≥ 1 voiced frame within 100 ms.
  `t_onset` is backdated to the first frame of the qualifying run; `t_detect` is when the rule fires, so
  `t_detect − t_onset ≤ 100 ms` by construction.
- Retraction: onsets created in the provisional phase are re-checked when the floor settles. If their median RMS is
  below the settled floor + 10 dB, they are retracted: they don't arm the endpoint and don't count as speech.
- Offset: RMS below floor + 6 dB.
- Endpoint: 1.2 s of non-speech after the last speech frame, armed only once 0.3 s of speech has accumulated. Hard
  cap at 20.0 s. A manual stop ends the take at once. Cancel (Esc) ends with no outcome and nothing kept.
- Pre-roll: a 500 ms ring buffer; the kept audio starts at max(0, t_onset − 0.2 s).

### Take quality: `TakeQuality.check(samples:) -> TakeProblem?`

- `noSpeech`: neither detected speech of 0.15 s or more nor 0.3 s of voiced frames.
- `tooShort`: under 0.5 s of speech.
- `tooQuiet`: median RMS of speech frames below −40 dBFS; also `tooQuiet` (not `noSpeech`) when nothing crosses
  detection but there are at least 0.3 s of voiced frames.
- `clipped`: at least 0.5% of speech frames contain a run of 3 or more samples with |x| ≥ 0.999.
- Only the first problem in Designer's order is returned (`noMicrophone, micDenied, noSpeech, tooShort, tooQuiet,
  clipped, wordsDontMatch`; the first two come from spec 14, the last from alignment).

### Test cases (synthetic, generated in test code)

Speech-like signal: voiced bursts (harmonic complex with syllable-rate amplitude modulation) over controlled noise.

| Case | Input | Expected |
|---|---|---|
| E1 Immediate speech | speech from t = 0 over −60 dBFS noise | \|t_onset − truth\| ≤ 20 ms and t_detect − truth ≤ 110 ms; floor estimate not polluted (≤ −55 dBFS) |
| E2 Quiet speech | speech at −45 dBFS over −65 noise | detected, then `tooQuiet` |
| E3 Very quiet voiced | speech at −58 dBFS over −65 noise | `tooQuiet` through the voiced rule, not `noSpeech` |
| E4 Noise only | −50 dBFS pink noise, 3 s | `noSpeech` |
| E5 Changing noise | noise rises from −65 to −45 at 3 s with no speech, then speech at −30 | no false onset; speech detected; endpoint 1.2 s after the last speech |
| E6 Click | 100 ms broadband burst, no voicing | no onset |
| E7 Manual stop mid-speech | stop at 2.0 s while speaking | ends at 2.0 s with no 1.2 s wait |
| E8 Manual stop in trailing silence | stop 0.5 s after the last speech | ends at once |
| E9 Inner pause | pauses of 1.0 s and 1.3 s | 1.0 s continues; 1.3 s endpoints at the 1.2 s mark |
| E10 Cap | 25 s of continuous speech | stops at 20.0 s ± 10 ms |
| E11 Cancel | cancel at 1.5 s | no outcome; nothing kept |
| E12 Several problems | clipped and 0.3 s of speech | `tooShort` (Designer's order) |
| E13 Unvoiced burst | 150 ms broadband noise at −40 dBFS in the first 200 ms (ACF peak < 0.45 throughout), then a −65 floor | no onset is ever created; no false endpoint |
| E14 Voiced hum retracted | steady 120 Hz hum with harmonics at −48 dBFS from t = 0 for 3 s (voiced by ACF; P90 − P10 < 2 dB) | a provisional onset fires; at 2.0 s rule (b) settles the floor near −48.5; the onset is retracted; result `noSpeech`. Variant: speech at −30 dBFS over the hum from 2.5 s gives a kept onset at 2.5 s |
| E15 Early speech | speech starts at 150 ms (provisional phase), RMS fluctuating by more than 10 dB | not stationary, not retracted; kept; t_onset within 20 ms |
| E16 Pre-roll | any onset at t > 0.2 s | kept audio has 200 ms before t_onset |
| E17 Quiet vowel | voiced vowel at −55 dBFS over −65 | `ACFVoicing` marks it voiced; the take is `tooQuiet`, not `noSpeech` |

Every case asserts both `t_onset` and `t_detect` where an onset exists.

## Defaults

- All numbers come from `Thresholds` (spec 01), which carries the rev 4.1 values above. The old "speech frame
  max(−45, floor + 12)" row is replaced by the onset rule here.
- The `Endpointer` is a value-type state machine fed one frame at a time, so tests can drive it deterministically
  without clocks or sleeps.

## Guardrails

- No microphone, no `AVAudioEngine`, no file under `AMCapture/Live/` (a risky path, spec 14's).
- No AppKit or UIKit. Swift 6 strict concurrency.
- No entitlements, no `NSMicrophoneUsageDescription`.

## Out of scope

- Live capture, device selection, level metering UI, `noMicrophone` / `micDenied` (specs 13–14).
- L_stop and L_speech budgets (spec 12). `wordsDontMatch` (spec 06).

## Open question (built with the default)

1. **`noSpeech` vs the v1 "< 0.15 s of speech frames" row.** The first v2 says `noSpeech` only when there is neither
   detected speech nor 0.3 s of voicing; v1 had a 0.15 s floor. Default: both, as written above (`noSpeech` needs
   under 0.15 s of detected speech **and** under 0.3 s of voicing).

## How to test (Raph)

1. `make check` is green.
2. `swift test --package-path Packages/AccentKit --filter AMCaptureTests` passes E1–E17 by name, each test printing
   t_onset, t_detect and the outcome.
3. `rg -n "AVAudioEngine|AVCaptureDevice" Packages/AccentKit/Sources/AMCapture` prints nothing.

## Implementation notes

_(filled in by the agent)_
