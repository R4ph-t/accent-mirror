# 05: Take quality and endpointing

Status: Done · Branch: factory/05-take-quality-endpointing · Depends on: 01 (contract v2; no dependency on 04) · Estimate: 3–4 h agent run + 1 h
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

- `ACFVoicing` implements spec 01's `VoicingSource` protocol (in `AMCore`), with `id` (`voicingID`) `acf-1`.
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

Built 2026-11-23 on `factory/05-take-quality-endpointing` (hand build, Claude Code on Opus).

**What's in `AMCapture`** (all value types, Foundation and Accelerate only, no microphone, nothing under `Live/`):

- `FrameAnalyzer` (internal): per 10 ms frame, the RMS in dBFS (20·log10 rms, so a full-scale sine is −3 dBFS;
  silence reads −120), the ACF peak and a clip-run flag. The ACF uses a causal 40 ms window that ends with the
  frame, so it streams with no look-ahead. It is the mean-removed normalised cross-correlation (1 for a periodic
  window), and the peak is the highest *local maximum* for lags 2–16.7 ms. A monotonic decay, as pink noise gives,
  has no local maximum, so it scores 0. Frames before the first full window (the first 30 ms) are unvoiced.
- `ACFVoicing` (`acf-1`): the `VoicingSource`. `isVoiced` is the streaming rule. `voicedFrames(samples:sampleRate:)`
  runs the endpointer's detector over the take for its floor.
- `NoiseFloor` (internal): the provisional floor (last-session floor or −60) and settling rules (a) and (b). After
  settling it tracks the P10 of non-speech frames over a sliding 2 s window and is clamped to −70…−35.
- `SpeechDetector` (internal): onset, offset and retraction. `Endpointer` (public): the frame-fed state machine.
  It adds the endpoint, the cap, `stop()`, `cancel()` and the kept audio, and emits `onset`, `floorSettled`,
  `retracted` and `ended` events.
- `TakeAnalysis` / `TakeQuality.check(samples:)`: one batch pass of the same detector (no endpoint, no cap), then the
  first problem in Designer's order.

**Decisions where the spec left room** (the least-committal reading in each case, also listed in the PR):

1. Two numbers in the spec were missing from `Thresholds`: 0.3 s of voicing (`noSpeech` / `tooQuiet` voiced rule)
   and 0.3 s of speech to arm the endpoint. Added as `capture.noSpeechVoicedS` and `capture.endpointArmSpeechS`
   (0.3 each, plan values, not tuned), with rows in `docs/thresholds.md`. `Versions.thresholdsVersion` is now 2,
   the goldens were re-recorded (only `thresholdsVersion` changed in them) and a digest was appended.
   `IdentityTests.versions` now checks the config against `Versions` rather than the literal 1.
2. "Nothing crosses detection" is read as under `noSpeechS` of detected speech. Such a take is `tooQuiet` when it has
   ≥ 0.3 s of voicing and `noSpeech` otherwise; it is never `tooShort`. E3 and E17 need this: in Designer's order,
   `tooShort` would otherwise win.
3. Onset window: the 3-frame run, its voiced frame and `t_detect` all sit within 100 ms of `t_onset`. When a run grows
   past 100 ms with no voicing, its start slides forward, so `t_onset` is the first frame of the run that qualifies.
4. After an offset, speech resumes only through a new onset (hysteresis), so a take can have several onsets.
   `Take.onsets` lists the kept ones, and the endpoint counts from the last speech frame of any kept segment.
5. Rule (b) is checked on every frame from 2.0 s on (over the last 2 s), not only once at 2.0 s.
6. Frames an onset backdates over are removed from the non-speech set. Frames of a retracted segment are not added
   back to it.
7. Take-quality voicing uses the floor as finally known: frames heard before the floor settled are judged against
   the settled value. Without this, E14's hum is voiced on the provisional −60 floor and the take reads `tooQuiet`.
8. Kept audio: from max(0, first kept `t_onset` − 0.2 s). A take that ends (stop or cap) with no kept onset keeps
   all its audio, so `TakeQuality` can still apply the voiced rule. To allow that, the endpointer holds the whole
   take (at most 20 s by the cap) rather than a literal 500 ms ring. `ringBufferMs` bounds the pre-roll.

**Tests** (`Tests/AMCaptureTests/EndpointingTests.swift`, signals from `Synth.swift`, seeded): E1–E17 by name, the
E14 variant, plus clipped, clean, last-session floor, 0.3 s arming and the `VoicingSource` contract. Each case
prints `t_onset`, `t_detect` and the outcome. Margins checked across ten other seeds: −50 dBFS pink noise
reads at most 0.14 s voiced (bar 0.3 s); E13's burst has an ACF peak ≤ 0.28 (bar 0.45); E3 reads ≥ 0.8 s voiced.
