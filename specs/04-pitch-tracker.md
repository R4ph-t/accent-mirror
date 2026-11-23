# 04: Pitch tracker

Status: Ready · Branch: – · Depends on: 01 (contract v2) · Estimate: 3–4 h agent run + 1 h Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris). Row 04 is "as before", so the behaviour comes from v1's `AMPitch` section and spec row 04, with the
first v2's row 04 change (no-voiced-frames handling; the band test moved to spec 09). Cancellation is §8.2. CTO
decision 3: pitch is our own YIN/pYIN behind `PitchTracker`.

## Goal

A `PitchTracker` in `AMPitch` that turns 16 kHz mono audio into one pitch line per speaker in semitones relative to
the speaker's median F0, with a voiced flag on every frame, interpolated bridges, pause breaks and the axis-extent
rule. Our own YIN/pYIN on Accelerate/vDSP. No third-party pitch code.

## Behaviour

- `protocol PitchTracker: Sendable` with an `id` (`pitchTrackerID`, e.g. `pyin-1`) and an async `track(_ samples:
  sampleRate:) -> PitchTrack`. One implementation, `PYINTracker`. A later tracker (for example CREPE via Core ML) is
  a new type with a new ID and a version bump, not a change to this one.
- Analysis: 40 ms window, 10 ms hop, F0 search 60–500 Hz. A frame is voiced when the pYIN voicing probability is ≥
  0.5. Voiced runs shorter than 30 ms are dropped. A 5-frame median filter and octave-jump repair run on the voiced
  frames.
- Output frames are 10 ms apart, in semitones relative to the speaker's median F0 over voiced frames, and carry
  `voiced: Bool`. `medianF0Hz` is returned.
- Unvoiced stretches up to 250 ms are bridged by interpolation with `voiced = false`. The line breaks only at a pause
  longer than 250 ms: a 200 ms gap is bridged, a 300 ms gap starts a new `PitchSegment`.
- Axis extent: ±12 st, growing in steps of 6 st up to ±24 st, never shrinking within a phrase. A pure function
  `PitchAxis.extent(previous:segments:)` holds the rule.
- **No voiced frames:** the track is empty and says so (`isEmpty`), `medianF0Hz` is nil, and callers report pitch
  measures as `.unavailable(.noVoicedFrames)` (spec 10). It never returns 0 st or NaN.
- Per-syllable helper for spec 08: `peakSemitones(in: TimeRange) -> Double?` returns nil when the range has fewer
  than 3 voiced frames (plan §2).
- Cancellation: `Task.isCancelled` is checked every 50 frames (§8.2); a cancelled call throws `CancellationError`
  and returns no partial track.
- Performance: 300 frames (a 3 s take) in ≤ 120 ms on an M1 (v1 budget), printed by a benchmark test. CI only prints
  it; the gate is local.

## Defaults

- Synthetic test signals are generated in test code (sine, harmonic complex, glides, vibrato, an octave trap,
  silence, noise). No audio file is committed by this spec.
- The real-clip check (Open question 1) is a local script, not part of `make check`.

## Guardrails

- Accelerate/vDSP only. Never AudioKit, never Essentia, no new SPM dependency.
- `AMPitch` imports `AMCore` and Apple frameworks only; no AppKit or UIKit.
- Swift 6 strict concurrency; the tracker is a value type or an actor, no shared mutable state.
- Values come from `Thresholds` (spec 01); nothing hard-coded twice.

## Out of scope

- Native band and pitch-in-band coverage (spec 09). Pitch measures and diffs (spec 10). Voicing for endpointing
  (spec 05's `ACFVoicing`; it does not depend on this spec). CREPE.

## Open question (built with the default)

1. **"A few real clips pass."** v1 names no clips and no pass rule. Default: on 3 VCTK clips (one low, one mid, one
   high voice, from spec 02's cache when present), compare against Praat's autocorrelation pitch (offline tool,
   version recorded) on frames both call voiced; pass if gross pitch error (more than 20% off) is under 5% and voicing
   agreement is at least 90%. If Praat or the clips are missing, the line prints NOT EVALUATED, which is not a pass.
   A FAIL goes to CTO; thresholds aren't changed to pass.

## How to test (Raph)

1. `make check` is green.
2. `swift test --package-path Packages/AccentKit --filter AMPitchTests` passes:
   - steady tones at 80, 150, 220 and 400 Hz and 1 s glides read within ±0.3 st of truth on voiced frames;
   - a 220 Hz tone reads as 0 st against a 220 Hz median;
   - the octave trap (a frame run that jumps one octave for 30 ms) is repaired;
   - a 200 ms unvoiced gap is bridged with `voiced = false`, a 300 ms gap splits the line;
   - the axis grows 12 → 18 → 24 and never shrinks within a phrase;
   - silence and pure noise give an empty track and a nil median;
   - a cancelled task stops within 50 frames.
3. Optional, local: `scripts/pitch-real-clips.sh` prints the real-clip table, or NOT EVALUATED.

## Implementation notes

Built by hand through Claude Code (Opus), 2026-11-23, on `factory/04-pitch-tracker`.

**What's there (`AMPitch`, imports `AMCore`, Foundation and Accelerate only):**

- `PitchTracker` (protocol, `Sendable`): `id` and `track(_:sampleRate:) async throws -> PitchTrack`.
  `PitchTrackingError.unsupportedSampleRate` for a rate that isn't finite or can't reach 500 Hz.
- `PYINTracker` (`pyin-1`, a struct holding `Thresholds.Pitch`). It works per 10 ms cell, the same cells as
  `VoicingSource` (frame `i` is `[i·10 ms, (i+1)·10 ms)`). A 40 ms window gives YIN's difference function: `vDSP_convD`
  for the lag products, prefix sums for the energies, then cumulative-mean normalisation over lags for 60–500 Hz.
  pYIN stage one follows: a Beta(2, 18) prior over thresholds 0.01…1.00, each threshold's weight going to the first
  dip under it (or 1% of it to the absolute minimum). The voicing probability is the total, voiced at ≥ 0.5. F0 is
  the most probable dip, refined parabolically. It checks `Task.checkCancellation()` every 50 frames and once before
  returning, so a cancelled call throws and returns nothing.
- `PitchTrack`: `segments: [PitchSegment]` (AMCore's types), `medianF0Hz: Double?`, `hopSeconds`, `isEmpty`,
  `voicedFrameCount`, `peakSemitones(in:minVoicedFrames:)` (nil under 3 voiced frames; the default comes from
  `Thresholds.prominence.pitchMinVoicedFrames`). `PitchTrack(frameF0Hz:thresholds:)` is the post-processing every
  tracker shares, so a later tracker (CREPE) reuses it, and spec 08/09 tests can build tracks from per-frame F0
  without audio. Its steps: drop voiced runs under 30 ms, a 5-frame median per run (the window shrinks symmetrically
  at run ends so glides keep their end points), octave repair, median F0 over voiced frames, then semitones, bridges
  (linear, `voiced = false`) for gaps up to 250 ms and a new segment above.
- `PitchAxis.extent(previous:segments:) -> ClosedRange<Double>`, which plugs straight into
  `AnalysisResult.pitchAxis`.
- No `Thresholds` value added or changed; no version bump.

**Choices worth a look:**

- **pYIN's HMM (stage two) is not used.** The spec defines smoothing as the median filter plus octave repair, and
  voicing as "probability ≥ 0.5", which is stage one's per-frame probability. An HMM would be a second, unspecified
  decision rule.
- **Octave repair:** a voiced frame within 3 st of one octave from the median of the voiced frames within ±10 frames
  (±100 ms) moves by an octave. Neighbours count across unvoiced frames, because the tracker can split a trap off
  into its own short run. These two numbers and the pYIN prior (Beta(2, 18), 100 thresholds, p_a = 0.01) are
  `pyin-1` algorithm constants in code, not `Thresholds` rows (see Spec gaps in the PR).
- **Window placement:** the stretch a lag compares is `[start, start + w + τ)`. The window starts so that stretch is
  centred on the cell for mid-range voices (within ±4 ms for any lag). At the ends of the audio the window is shifted
  inside it, so the first and last 20 ms read up to 20 ms early or late.
- A numerical guard (window energy under about −120 dBFS per sample, or not finite) makes a frame unvoiced. It isn't
  a tunable.
- **Pause length** is the number of unvoiced frames × 10 ms: 25 frames (250 ms) bridge, 26 break.

**Measured (this Mac, M3 Max):** 300 frames (3 s glide) in 2.1 ms with `swift test -c release`, and about 65 ms in
the debug build `make test` uses, against the 120 ms M1 budget. The benchmark test prints the time;
`AM_PITCH_BENCH_GATE=1` turns it into a gate for a local run. On synthetic signals, the 200 ms silence gives 22
bridged frames, and with the 300 ms silence the line breaks between 0.49 s and 0.81 s.

**Real clips (Open question 1):** `scripts/pitch-real-clips.sh` and `scripts/pitch-real-clips.praat`. Praat resamples
each clip to 16 kHz mono and writes its `To Pitch (ac)` track (10 ms, 60–500 Hz, otherwise Praat defaults). The gated
Swift Testing suite `RealClipComparison` (enabled only by `AM_PITCH_REAL_CLIPS_MANIFEST`, which the script sets)
runs `pyin-1` and compares frame by frame. The pass rule is applied per clip. Exit codes: 0 PASS, 1 FAIL, 2 NOT
EVALUATED. On this Mac it prints NOT EVALUATED: no Praat, and spec 02's VCTK cache doesn't exist yet. Clips come
from `AM_PITCH_CLIPS="low=… mid=… high=…"` or `eval-cache/pitch-clips/{low,mid,high}.wav`. The plumbing was
smoke-tested with a stand-in Praat on synthetic WAVs (not committed).
