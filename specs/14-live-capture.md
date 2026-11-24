# 14: Live microphone capture (macOS)

Status: Done · Branch: – · Depends on: 05 (endpointer, take quality, voicing; spec 13's entitlement is needed only
for the hand test) · Estimate: 3–4 h agent run + 1 h Raph review · Risk: high

Risk: high. The capture code lives in `Packages/AccentKit/Sources/AMCapture/Live/`, a risky path, so the PR waits for
Raph's Merge OK. It must not edit entitlements, `Info.plist` keys or the microphone string (spec 13, Raph).

Source: Plan v1 (Notion "Accent Mirror v1 groundwork plan (2026-11-23)"): `MicRecorder` (an `AVAudioEngine` input tap
to 16 kHz mono Float32, a level stream, starts within 100 ms, cancel discards), the platform rule (platform code only
in `AMCapture/Live/`), the capture acceptance row (no mic → `.noMicrophone`, denied → `.micDenied`, 1.2 s end of take).
Plan v2 §7 row 14 ("as in v1, plus L_stop timing hooks") and §10 (two onset timestamps, 500 ms pre-roll ring buffer,
saved audio from max(0, t_onset − 0.2 s)). Designer spec v2 §7 (recording ends after 1.2 s of silence or at 20 s; Esc
cancels and keeps nothing) and v1 §9 (Input device pop-up in the inspector). Addendum r6 E5 (Notion "Accent Mirror spec v2 (2026-11-23)", end of page): the level stream feeds spec 21's
meter during a take only.

Why it doesn't wait for 13: CI never uses the microphone, and every automated test here runs on a file-backed source.
Only the hand test needs the entitlement, so spec 13 must be Done before Raph tries it (spec 21 depends on 13).

## Goal

Record a take from the Mac's microphone into the same 16 kHz mono buffer that spec 05's endpointer and take-quality
checks already accept, end it automatically or by hand, and hand the result to the pipeline. No UI.

## Behaviour

- **`MicRecorder`** (macOS file in `AMCapture/Live/`, `#if os(macOS)`), behind a `CaptureSource` protocol in
  `AMCapture` (outside `Live/`) so tests and spec 21's fixtures can inject a file-backed source.
  - `start(device:)` taps the input with `AVAudioEngine`, converts to 16 kHz mono Float32, and returns within
    **100 ms** of the call (measured, see How to test).
  - Feeds every frame to spec 05's streaming `Endpointer` (provisional floor, settling rules, retraction,
    `ACFVoicing`). The take ends on its own after **1.2 s** of trailing silence after speech, or at the **20 s** cap.
  - Keeps a **500 ms pre-roll ring buffer**. The saved audio starts at max(0, t_onset − 0.2 s) (§10, E16).
  - `stop()` ends the take by hand; `cancel()` discards every sample and returns nothing (Esc).
  - Publishes: an input **level stream** (`AsyncStream<InputLevel>`, one value per 10 ms frame: RMS dBFS and sample
    peak dBFS, both clamped to −60…0) and an envelope stream (per-frame RMS for spec 20's live bars), both ending when
    the take ends. Spec 21's meter (Addendum r6 E5) reads the level stream: RMS for the fill, peak for the 1 s peak
    tick and the "Too loud" check (peak ≥ −1 dBFS). The streams exist only during a take; nothing opens the mic just
    to show a level.
  - Returns a `CapturedTake`: the samples, their SHA-256, `t_onset`, `t_detect`, the last speech frame time and the
    **stop timestamp** (endpoint decision or manual stop), which spec 12's L_stop / L_speech measurement reads.
- **Permission and devices:**
  - Authorization through `AVCaptureDevice.authorizationStatus(for: .audio)` / `requestAccess`. Denied or restricted →
    `.micDenied`. No input device → `.noMicrophone`. Both reach the app as `TakeProblem`s, which already rank first in
    Designer's order.
  - Lists input devices (name, stable ID, is-default) and notifies when the list changes, for the inspector's Input
    pop-up and for "Record is disabled until a mic appears".
  - If the device in use disappears mid-take, the take ends with nothing kept, and the next state is `.noMicrophone`
    if no device is left.
- No file is written. Saving is the take store's job (spec 16), after analysis.

## Defaults

- The default input device is the system default; spec 21 passes the inspector's choice.
- Level and envelope streams are informational only; nothing in AMScoring reads them.

## Guardrails

- Only `AMCapture/Live/` imports AVFoundation's capture APIs. AMCapture still builds for iOS 26 (the macOS file is
  compiled out); `make check-ui-frameworks` stays green.
- Nothing leaves the device; no network; no audio is kept after `cancel()` (a test checks the buffers are released).
- CI never instantiates `MicRecorder`; tests use the file-backed `CaptureSource`.

## Out of scope

- Entitlements and the microphone string (spec 13). The Record button, the recording UI and the permission rows
  (spec 21). The live strip drawing (spec 20). iOS capture (`AVAudioSession`, interruptions; Milestone 2).

## Open question (built with the default)

1. **Device removed mid-take.** Neither the plan nor the design says what happens on macOS. Default: end the take,
   keep nothing, show nothing extra (the next Record press gets `.noMicrophone` if no device is left), like Esc.

## How to test (Raph)

1. `make check` is green. `swift test --package-path Packages/AccentKit --filter AMCaptureTests` covers, through the
   file-backed source: auto-stop at 1.2 s, the 20 s cap, cancel returns nothing, the 200 ms pre-roll (E16), the
   problem order for a take that is both clipped and too short, and the stop timestamp.
2. After spec 13 is Done, on the Mac only: `scripts/capture-check.sh` (added here, runs no UI) records one take from
   the default mic, prints start latency (≤ 100 ms), `t_onset`, the stop reason (silence or cap) and the take's
   `TakeAnalysis`, and saves nothing. With mic access denied in System Settings it prints `micDenied`.

## Implementation notes

Built 2026-11-24 on `factory/14-live-capture` (factory, Claude Code on Opus).

**What's in `AMCapture`:**

- `CaptureSource` (protocol, `CaptureSource.swift`): `inputDevices()`, `deviceChanges()` (an `AsyncStream` of the
  list, starting with the current one), `authorization()`, `start(device:lastSessionFloorDBFS:)` (and `start()`), and
  `availability()`, the shared preflight: no device → `noMicrophone`, else denied or restricted → `micDenied`
  (Designer's order, so no device wins over denied). Also the value types: `InputLevel`, `EnvelopeFrame`,
  `InputDevice`, `MicAuthorization`, `CaptureError` (`noMicrophone`, `micDenied`, `inputFailed`), `CapturedTake` and
  `CaptureOutcome` (`recorded`, `cancelled`, `deviceLost`).
- `CaptureSession` (`CaptureSession.swift`): one take, shared by every source. The source pushes 16 kHz mono samples
  in any chunk size; the session cuts 10 ms frames, feeds spec 05's `Endpointer`, publishes `levels` and `envelope`
  (both finish when the take ends) and ends on the endpoint, the cap, `stop()`, `cancel()` or a lost device. Thread-safe
  (a `Mutex`), so the tap thread feeds it while the app stops or cancels it.
- `FileCaptureSource`: plays samples (or any file AVFAudio reads) into a session, `immediate`, `realTime` or `manual`
  (`advance(by:)`). The end of the recording counts as Stop. `setDevices` and `setAuthorization` simulate unplugging and
  System Settings. Every automated test uses it.
- `SampleConverter`: `AVAudioConverter` from any PCM format to 16 kHz mono Float32, keeping the first channel. Shared by
  the mic tap and `FileCaptureSource(contentsOf:)`.
- `Live/MicRecorder.swift` (`#if os(macOS)`): the only AMCapture file importing AVFoundation and Core Audio. A fresh
  `AVAudioEngine` per take, an input tap (50 ms buffers) through `SampleConverter` into a `CaptureSession`; the
  engine stops and the tap is removed as soon as the take ends. Devices come from `AVCaptureDevice.DiscoverySession`
  (`.microphone`, `.external`), IDs are Core Audio UIDs, and a non-default choice is set on the input unit with
  `kAudioOutputUnitProperty_CurrentDevice`. The list re-publishes on connect, disconnect and default-input changes.
- `am-capture` (executable, never linked into the app) and `scripts/capture-check.sh`: the hand check.

**Decisions where the spec left room:**

1. Pre-roll: spec 05's `Endpointer` already keeps the take's audio and trims it to max(0, t_onset − 0.2 s), with the
   pre-roll capped at `ringBufferMs` (500 ms). Live capture reuses it rather than adding a second buffer, so the kept
   audio is the endpointer's, byte for byte (E16 test).
2. Times in `CapturedTake` are seconds from the take's first frame (`onsetTime`, `detectTime`, `lastSpeechTime`,
   `stopTime`, `audioStartTime`), plus `stoppedAt`, the stop on the continuous clock, taken when the endpoint fired or
   `stop()` was called (where L_stop starts). `lastSpeechAt` derives L_speech's start from it. `Endpointer.Take` gained
   `lastSpeechEndTime` for this.
3. The take's SHA-256 is over the samples as little-endian Float32 bytes, lowercase hex (no convention existed).
4. Multi-channel inputs keep the first channel (an interface's input 1), not a mixdown, so a mic on input 1 of a
   two-channel interface isn't read 6 dB quiet.
5. A requested device that is gone falls back to the system default, then to the first device listed.
6. Device lost (open question 1, built with the default): `CaptureOutcome.deviceLost`, nothing kept. The same outcome
   covers an `AVAudioEngineConfigurationChange` mid-take (the engine has stopped, so the take can't go on).
7. Starting a take while one runs cancels the running one.
8. The engine failing to start is `CaptureError.inputFailed`, which maps to no `TakeProblem`: spec 21 decides what it
   shows.
9. The script is committed without its executable bit (the factory can't `chmod`): run it as
   `bash scripts/capture-check.sh`.
