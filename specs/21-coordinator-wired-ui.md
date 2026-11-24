# 21: Coordinator-wired UI: record, compare, play back

Status: Ready · Branch: – · Depends on: 29 (v3 result screen, Designer spec v3), 28 (scoring off; was 11, then 27; repointed 2026-11-24 after spike 27's NO-GO and Raph's v1
show-don't-judge decision), 12 (pipeline, coordinator), 13 (entitlement, mic string;
by hand), 14 (live capture), 15 (starter library), 16 (take store), 20 (charts) · Estimate: 10–12 h agent run + 2 h
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
drift" table (this spec maps or renames those names in one place). Designer spec v2 Addendum r6 (Notion, end of the
v2 page; mockups `v2/specs11-21/specs11-21-board-{light,dark}@2x.png`): E3–E4 (wired here, drawn by spec 20), E5
(level meter), E6 (sidebar before import ships), E7 (voice names), E8 (switching while recording). r6 wins over
earlier text.

**Designer's calls Raph may overrule:** E5 (showing a level meter at all), E6 (hiding "+ NEW PHRASE" and MY PHRASES)
and the F/M gender tag in E7's pop-up rows. They're built as Designer wrote them; if Raph overrules one in review, the
agent changes that item only.

**v1 show-don't-judge and Designer spec v3 (re-scoped 2026-11-24).** Raph decided at 18:42 Europe/Paris (relayed by CPO)
to ship v1 without stress or phrase verdicts; plan https://app.notion.com/p/4220d0d4459281399adef9364a99bb69 (CTO
approved). Designer spec v3 (Notion "Accent Mirror v1: show, don't judge", https://app.notion.com/p/4220d0d4459281d39d67d6fdc5d50dfc) wins over v2 and addenda r2–r6. Spec 28 gates scoring out of the shipped app (`Verdict.notScored`) and provides the descriptive
measures and native range; spec 29 draws v3's screens from fixtures. This spec wires them to live data and audio.
Where the text below conflicts with this block, this block wins:

- **Results (v3 §3.1, §4, §7):** an analysed take shows card 1 **"YOUR TAKE"** with v3's result row and **Play Both**,
  plus at most one quiet line (low coverage, then rough timing, then inserted words, from the live result), the strip,
  the pitch card with the earlier takes on by default, and the inspector's MEASURE / YOU / NATIVE RANGE table from
  spec 28's `describe` (no marking; "—" with a reason). No WHAT TO CHANGE, no diff / close / noClearDifference /
  inconclusive rows, no placement-only line, no STRESS lines, no diff icons. Card 1 keeps the recording row, the E5
  level meter and take problems ("YOUR TAKE", Try Again) with v3 §5's copy. Problem priority: take problems in v2
  §11.1 order, then the result; no verdict ranking; a missing target word is just a missing word.
- **Playback (v3 §3.5):** Play Model (⌘L), Play You (⇧⌘L) and **Play Both (⌥⌘L**, Take ▸ Play Model, Then You; the
  card-1 button): model phrase, 0.4 s pause, your take, with the playhead. Clicking a word or syllable label loops
  model, 0.4 s, yours until Esc. Clicking a missing word plays the model only. There's no diff-row play button.
- **VoiceOver** after a result: "Result ready. Your take is drawn over the model's."
- **Voices (r6 E7 stays):** the Model Voice pop-up and subtitle use spec 15's per-recording `accent`, `region` and
  `gender`; the inspector note counts the phrase's native voices ("across the {n} native voices"). The STRESS-lines
  bullet of E7 is gone.
- **Copy:** v3 §5 word for word, and none of v3's banned words (spec 29's test covers it).
- The 2 Compound Nouns starter phrases stay and show the overlay like every other phrase.

## Goal

The first build Raph can test: pick a starter phrase, listen to the native speaker, record a take, and see your take
against the native recording (strip, pitch, inspector; no verdicts in v1, Designer spec v3), then play both back, switch voices and go
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
- **Before clip import ships (E6, Designer's call):** outside fixture mode, "+ NEW PHRASE" is hidden and the MY
  PHRASES group is hidden while it's empty, so the sidebar starts at the first starter pack. No dead control and no
  empty section. Fixture mode keeps both exactly as spec 19 draws them, so the reference frames don't change.

### Recording (v2 §6–7, v1 §4.4–4.6)

- Record or Space (when no text field has focus) or ⌘R starts at once, no countdown. The button becomes Stop, the
  subtitle "● RECORDING 0:02" counts whole seconds, Model and You are disabled, card 1 shows the recording row, and
  the strip draws live bars from spec 14's envelope stream (spec 20). The Model Voice pop-up is disabled too, with
  the tooltip "Stop recording to change the voice" (E8).
- **Level meter (E5, Designer's call)**, only while recording, at the right end of card 1's recording row (where a
  row's play button sits), fed by spec 14's level stream:
  - A 96 × 6 pt track in `surface.well`, radius 3. The fill uses the Lime gradient (lime.1 to lime.2) from −60 to
    0 dBFS on the frame's RMS. A 2 pt `text.primary` peak tick holds for 1 s.
  - **Too loud:** when a frame's peak reaches −1 dBFS or more, the fill reaches the end with a square end instead of
    a round one, a 4 × 10 pt `text.primary` stop bar appears just past the track, and `speaker.wave.3` plus "Too
    loud" in Geist 12 / 500 `text.primary` appear before the meter. They stay until 1.5 s after the last such frame.
    No colour change: no red, yellow or amber.
  - Reduce Motion: the meter still moves. VoiceOver doesn't announce the meter continuously; "Too loud" is announced
    once per take (polite).
  - The mic is never opened just to show a level; there's no meter outside a take.
- The take ends on Stop / Space, after 1.2 s of silence, or at 20 s. **Esc** cancels a recording or an analysis:
  nothing is kept and the previous result (or the empty state) comes back.
- **Phrase switch while recording (E8):** selecting another phrase (click, ⌥⌘↑/↓ or search) cancels the take like
  Esc: nothing is kept, Stop turns back into Record at once, the "● RECORDING" subtitle goes away, and VoiceOver
  announces "Recording cancelled". No alert or toast. A voice switch can't happen while recording (the pop-up is
  disabled). Quitting during an analysis keeps nothing.
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
- *(Out in v1: no diff rows; see the v1 block.)* A diff row's play button plays the model's slice, a 0.4 s pause, then yours, for that row's word (tooltip "Play the
  model, then your take, for '{word}'"). Clicking a word label loops model slice, 0.4 s pause, your slice, until Esc,
  a click on empty space or another selection. A missing word plays the model only (tooltip "Plays the model only").
  Slices come from spec 09's playback lookup.
- **Highlights and the syllable being played (E3, E4):** this spec feeds spec 20's `ChartModel` the hovered word (diff
  row or word/syllable label hover, with the pointing-hand cursor on labels), the looping word, which take is playing
  and the current playback position. Spec 20 draws the neutral `highlight` boxes, the "Looping "{word}" · Esc to
  stop" label, the outline on the syllable being played and the "Playing the model" / "Playing your take" header.

### Takes and voices

- The take menu lists saved takes newest first as "TAKE 03" (Geist Mono), with the time recorded; choosing one shows
  its stored result (L2 recomputed lazily by spec 16 if stale). ⌘[ and ⌘] move between takes. A new recording always
  shows the new take. Earlier-take ghosts come from `ghosts(before:)`.
- **Model Voice** pop-up in the inspector (v1 §9; E7), from spec 15's per-recording `accent`, `region`, `gender`:
  - Rows in manifest order: "{region} ({accent})" in Geist 13, e.g. "Southern England (English)", with "p225 · F"
    right-aligned in Geist Mono 12 `text.tertiary` (the F/M tag is Designer's call). The selected voice is checked.
  - Closed state: "Southern England · p225".
  - Toolbar subtitle: "{pack} · Native speaker from {region}, VCTK", e.g. "Stress Shifts · Native speaker from
    Southern England, VCTK". The inspector's attribution keeps speaker ID, corpus and licence. The STRESS lines keep
    the speaker ID ("you match p311").
  - A switch recomputes L2 only (spec 12) and uses spec 20's ease; the subtitle updates at once.
- **Input** pop-up in the inspector lists spec 14's devices; the choice is used for the next take and remembered.
  No level next to it (E5: the meter lives in the recording row only).

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

- **Clip import UI**: Addendum r6 E1 (New Phrase from Clip sheet and entry points) and E2 (Edit Transcript sheet,
  the inspector PHRASE section, NOT COMPARABLE takes). A later UI spec on top of spec 17 adds them and brings back
  "+ NEW PHRASE" and MY PHRASES with E6's empty row.
- Delete Take, Rename and Delete Phrase.
- Drawing the highlights, the outline on the syllable being played and the playback header (spec 20).
- Signing, notarization, release builds (Raph).

## Open question (built with the default)

None. Addendum r6 E5–E8 answered the switching, level and "+ NEW PHRASE" questions.

## How to test (Raph)

1. `make check` is green.
2. `make test-ui-vm` re-renders every spec 19/20 fixture with no visual change (fixture mode is untouched, including
   "+ NEW PHRASE" and MY PHRASES). New fixtures `recording-level` and `recording-too-loud` match the r6 board
   (section 5), and `voice-popup-open` matches its voice pop-up.
3. On the Mac: `make fetch-models`, then `make build` and open the app. It opens on the first Stress Shifts phrase;
   the sidebar has no "+ NEW PHRASE" and no MY PHRASES. **pass/fail**
4. Press Space: macOS asks for the microphone (first time). Allow. Say the phrase, stop talking: recording ends after
   about 1.2 s and the result appears within about 2 s. While you talk, the level meter moves; clap close to the
   mic and "Too loud" shows. **pass/fail**
5. The result shows card 1 "YOUR TAKE" with the result row and Play Both, your strip under the native one with
   timing connectors, your pitch line on the native range with earlier takes behind it, and the inspector's
   MEASURE / YOU / NATIVE RANGE table with nothing marked. No WHAT TO CHANGE, no stress sentence, no STRESS lines.
   **taste call (Raph)**
6. Play Model, Play You, Play Both (⌥⌘L: model, 0.4 s, you) and a word click play the right audio with the playhead, the outlined
   syllable and the "Playing …" header; a word click shows "Looping …" until Esc. **pass/fail**
7. Record two more takes; the take menu shows TAKE 03, ⌘[ shows TAKE 02's result, the pitch card shows up to 3 earlier
   takes, and ⇧⌘G hides them. Quit and relaunch: the takes are still there. **pass/fail**
8. Switch Model Voice in the inspector (rows read "Southern England (English)  p225 · F"): the band stays drawn and
   re-times in one ease, and the subtitle reads "Native speaker from {region}, VCTK". **pass/fail**
9. Whisper a take: the too-quiet row, You plays it, the menu reads LAST TRY · NOT SAVED, and it isn't in the menu
   after the next take. Press Esc mid-recording: nothing kept. Mid-recording, the voice pop-up is disabled, and
   ⌥⌘↓ cancels the take with nothing kept. **pass/fail**
10. Deny the microphone in System Settings: the micDenied row with Open System Settings…; grant it again and the row
    clears when you come back. **pass/fail**

## Implementation notes

_(filled in by the agent)_
