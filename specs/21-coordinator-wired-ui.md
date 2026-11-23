# 21: Coordinator-wired UI: record, compare, play back

Status: Ready · Branch: – · Depends on: 11 (tuned config), 12 (pipeline, coordinator), 13 (entitlement, mic string;
by hand), 14 (live capture), 15 (starter library), 16 (take store), 20 (charts) · Estimate: 8–10 h agent run + 2 h
Raph review · Risk: high

Risk: high. This is the first build that uses the microphone, so Raph must try it before it merges (review verdict
`hold`). It also edits `project.yml` (a risky path) to bundle the pinned speech model. It must not touch
entitlements, the microphone string, `Resources/Models/` manifests, `Resources/Starter/` or `Thresholds.swift`.

Source: Designer spec v2 (Notion "Accent Mirror spec v2 (2026-11-23)") §6 (toolbar), §7 (detail states, Esc, take
problems never saved), §7.1 (too quiet is playable), §10 (diff rows and their play button), §11 (take problems vs app
problems), §12 (behaviour decisions), §13 items 1–3 and 9 (copy, banner and saveFailed notice, placement-only line,
voice switch), §14 (inspector), §15–16; Addenda r2–r5 (A4 close sentence, A6 quiet lines, A7 and B8 "LAST TRY · NOT
SAVED", B7 take-problem row; r5 wins). Designer spec v1 for what v2 calls "as in v1": §4.2 first run, §4.4 microphone
permission, §4.6 analysing (row only after 0.4 s), §5.3 playback and looping, §7 takes, §9 inspector (Model Voice and
Input pop-ups), §10 keyboard and menus, §11.1 announcements. Plan v2 §8 (requests, persistence display), §9.2 (voice
switch recomputes L2). Engineering review of spec v2 (Notion, 2026-11-23), proposed row 21. Spec 01's "UI fixture
drift" table (this spec maps or renames those names in one place).

## Goal

The first build Raph can test: pick a starter phrase, listen to the native speaker, record a take, and see your take
against the native recording (strip, pitch, what to change, inspector), then play both back, switch voices and go
through earlier takes. Everything on device.

## Behaviour

### App wiring

- An `AppModel` (`@MainActor`) owns spec 12's coordinator and model host, spec 15's starter library, spec 16's take
  store, spec 14's recorder and a playback engine (`AVAudioEngine` in the app target). The shell (specs 18–19) reads
  view state from one presenter that maps AMCore types to the existing fixture-shaped view state, including every
  rename in spec 01's drift table. `-UIFixture` and the Samples menu keep working unchanged.
- **Model bundling:** a `project.yml` build phase copies the verified pinned weights (`scripts/fetch-models.sh
  --verify`, from `MODELS_CACHE`) into `AccentMirror.app/Contents/Resources/Models/<model>/`. If they're absent (CI,
  or before `make fetch-models`), the phase prints a note and the build still succeeds with no new warning; the app
  then shows the `modelUnavailable` banner. The model loads and warms up at launch, off the main actor.
- **Sidebar** reads spec 15's manifest (packs, order, coming soon), replacing the fixture manifest outside fixture
  mode. **First run:** the first Stress Shifts phrase is selected (v1 §4.2).

### Recording (v2 §6–7, v1 §4.4–4.6)

- Record or Space (when no text field has focus) or ⌘R starts at once, no countdown. The button becomes Stop, the
  subtitle "● RECORDING 0:02" counts whole seconds, Model and You are disabled, card 1 shows the recording row, and
  the strip draws live bars from spec 14's envelope stream (spec 20).
- The take ends on Stop / Space, after 1.2 s of silence, or at 20 s. **Esc** cancels a recording or an analysis:
  nothing is kept and the previous result (or the empty state) comes back. Selecting another phrase or switching
  voice while recording does the same (Open question 1).
- **Analysing:** "Analysing your take…" appears only if analysis takes longer than 0.4 s; Record stays enabled and
  cancels it (v2 §7).
- **Microphone permission:** the first Record press shows macOS's own prompt; there is no pre-prompt of ours. Denied →
  the micDenied row with "Open System Settings…" (opens Privacy & Security ▸ Microphone); Record stays enabled and
  shows the row again. The app re-checks when it becomes active, so granting access clears the row with no restart.
  No input device → the noMicrophone row and Record disabled until a device appears.

### Results and problems

- `analysed` → the result state: card 1 "WHAT TO CHANGE" (1–3 rows, or close / noClearDifference / inconclusive with
  v2 §13.1 and Addendum A4 copy), the placement-only line (§13 item 3), the quiet lines (A6), the strip, the pitch
  card and the inspector (§14: measures with state and reason, STRESS lines, timing match, model recording
  attribution). Copy stays in the app's `Copy.swift`; AccentKit returns structured values only.
- `takeProblem` → card 1 "YOUR TAKE" with the first problem's row and Try Again (v2 §11.1, B7). Too quiet, clipped,
  too short and words don't match stay playable with You and the take menu reads "LAST TRY · NOT SAVED" (A7, B8)
  until the next take or a phrase change. Nothing is saved.
- `failed` → the banner above the cards (§13 item 2) with Retry (re-runs on the same audio), Rebuild, or Choose File…
  as listed; "Copy Details" in its context menu. The cards keep the last result or the empty state. A take-problem row
  never shows with a banner for the same take.
- `cancelled` → nothing. **saveFailed** → the result as normal plus one notice with Try Again Saving and a close
  button, once per take; an operational error wins the slot. **savedPruneFailed** → nothing, logged.
- VoiceOver announces "Recording" at start, "Analysing" at stop, then the first card-1 sentence (polite).

### Playback (v1 §5.3, v2 §9–10)

- Play Model (⌘L) and Play You (⇧⌘L) play the whole phrase; the same button or Esc stops. The playhead (spec 20)
  follows. You is disabled when there's no audio (empty state, noSpeech, noMicrophone, micDenied).
- A diff row's play button plays the model's slice, a 0.4 s pause, then yours, for that row's word (tooltip "Play the
  model, then your take, for '{word}'"). Clicking a word label loops model slice, 0.4 s pause, your slice, until Esc
  or a click on empty space. A missing word plays the model only (tooltip "Plays the model only"). Slices come from
  spec 09's playback lookup.

### Takes and voices

- The take menu lists saved takes newest first as "TAKE 03" (Geist Mono), with the time recorded; choosing one shows
  its stored result (L2 recomputed lazily by spec 16 if stale). ⌘[ and ⌘] move between takes. A new recording always
  shows the new take. Earlier-take ghosts come from `ghosts(before:)`.
- **Model Voice** pop-up in the inspector (v1 §9), listing the phrase's voices by speaker ID in manifest order. A
  switch recomputes L2 only (spec 12) and uses spec 20's ease; the subtitle updates at once.
- **Input** pop-up in the inspector lists spec 14's devices; the choice is used for the next take and remembered.

### Menus and keyboard (v1 §10, no number keys)

Take ▸ Record Take / Stop Recording (Space, ⌘R), Cancel (Esc), Play Model (⌘L), Play Your Take (⇧⌘L), Previous / Next
Take (⌘[ / ⌘]); View ▸ Previous / Next Phrase (⌥⌘↑ / ⌥⌘↓), Show Details (⌥⌘I), Show Sidebar (⌃⌘S); Edit ▸ Find (⌘F).
Every shortcut has its menu item.

## Defaults

- Thresholds are whatever is on main after spec 11.
- The selected voice per phrase is remembered across launches; the default is the manifest's headline voice.

## Guardrails

- No network at runtime (the no-network test from spec 12 stays green; the app adds no URL session).
- CI never launches the app or touches the mic; the app's unit tests use the file-backed capture source and fixture
  references. Screenshots run in the test VM only.
- The presenter is the only place AMCore names meet UI names (spec 01 drift table); views don't import AccentKit
  types beyond it.
- Never save a take problem, a failed or cancelled analysis, or an unsaved attempt.

## Out of scope

- **Clip import UI** (the New Phrase from Clip sheet, ⌘N, + NEW PHRASE, drop on window) and **editing a clip's
  transcript after import**, with NOT COMPARABLE takes. Designer spec v2 has no sheet design and doesn't say where the
  transcript is edited. They go to Designer, then a later UI spec on top of spec 17. "+ NEW PHRASE" stays exactly as
  spec 19 draws it and does nothing yet (no new copy or state invented; see Open question 3).
- Delete Take, Rename and Delete Phrase. Loop-slice and diff-row hover highlights, and the sounding-syllable outline
  (Designer gaps, see spec 20). An input level meter (v1's meter used red and yellow, which v2 bans; no v2 design).
- Signing, notarization, release builds (Raph).

## Open question (built with the default)

1. **Phrase or voice switch while recording.** Default: it cancels the take like Esc (nothing kept). The plan lists
   both as invalidations; the design doesn't say what the user sees. Same for quitting during analysis.
2. **Input device in the inspector without a level.** v1 §9 shows the live level next to the pop-up; v2 has no level
   design and bans v1's meter colours. Default: the pop-up only, no level.
3. **"+ NEW PHRASE" before clip import ships.** Default: unchanged from spec 19 (drawn, no action). Designer may want
   it hidden or marked; that's their call.

## How to test (Raph)

1. `make check` is green.
2. `make test-ui-vm` re-renders every spec 19/20 fixture with no visual change (fixture mode is untouched).
3. On the Mac: `make fetch-models`, then `make build` and open the app. It opens on the first Stress Shifts phrase.
   **pass/fail**
4. Press Space: macOS asks for the microphone (first time). Allow. Say the phrase, stop talking: recording ends after
   about 1.2 s and the result appears within about 2 s. **pass/fail**
5. The result shows your strip under the native one, your pitch line on the band, 1–3 rows or a close/neutral row,
   and the inspector's measures. **taste call (Raph)**
6. Play Model, Play You, a row's play button and a word click play the right audio with the playhead. **pass/fail**
7. Record two more takes; the take menu shows TAKE 03, ⌘[ shows TAKE 02's result, hovering the pitch card shows the
   earlier takes. Quit and relaunch: the takes are still there. **pass/fail**
8. Switch Model Voice in the inspector: the band stays drawn and re-times in one ease. **pass/fail**
9. Whisper a take: the too-quiet row, You plays it, the menu reads LAST TRY · NOT SAVED, and it isn't in the menu
   after the next take. Press Esc mid-recording: nothing kept. **pass/fail**
10. Deny the microphone in System Settings: the micDenied row with Open System Settings…; grant it again and the row
    clears when you come back. **pass/fail**

## Implementation notes

_(filled in by the agent)_
