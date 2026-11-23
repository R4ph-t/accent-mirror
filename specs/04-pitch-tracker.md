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

_(filled in by the agent)_
