# 20: Charts: live strip, playhead, earlier takes and voice-switch ease

Status: Ready · Branch: – · Depends on: 19 (fixture-driven UI shell) · Estimate: 5–7 h agent run + 1.5 h Raph review

Source: Designer spec v2 (Notion "Accent Mirror spec v2 (2026-11-23)") §7 (recording and analysing rows of the state
table), §8 (strip), §9 (pitch: earlier takes on hover, playhead), §6 (take-menu hover preview), §13 items 7 and 9
(breaks at gaps; band re-timed on a voice switch in one 150 ms ease, never blanked), §15 and §16 criteria 6, 7 and
18; Addendum r2 A3 (recording bars in `strip.bar`, Lime only on the playhead and label) and B6; Addenda r3–r5 where
they touch the charts (r5 wins). Designer spec v1 §5.3 and §11 for what v2 calls "as in v1" (Reduce Motion keeps the
playhead moving). Engineering review of spec v2 (Notion, 2026-11-23), proposed row 20 and its Designer calls 1, 2 and
4 (Option only while the window is key and no menu is tracking; the ease starts only after L2 arrives). Specs 18 and
19 left exactly these items to spec 20.

## Goal

Finish the strip and pitch cards' motion and interaction, driven by fixture data and an injected clock, so spec 21
can feed them live data without touching the drawing. No audio, no microphone, no coordinator.

## Behaviour

### Live recording strip (§7, A3)

- While recording, your row draws bars from an **envelope stream** (per-10 ms RMS, the shape spec 14 publishes) in
  `strip.bar`, growing left to right up to a **2 pt Lime playhead**. No Lime on the bars. The native row stays drawn.
  Pitch is native only (no live pitch).
- Drawing uses `Canvas` with pre-binned bar geometry (1.5 pt bars on a 3 pt pitch). Only the new bins are added per
  frame; the budget is a steady 60 Hz (120 Hz on ProMotion) with no dropped frames over a 20 s take.
- **Analysing:** your bars stay grey (`strip.bar`) until the result arrives (§7).

### Playhead (§9, v1 §5.3)

- A 1 pt `text.primary` line across both the strip and the pitch plot while audio plays, on the model timeline.
  Playing your take moves it through spec 09's `PartialTimeMap` (`toModel`); across a youOnly stretch it holds at
  the gap edge.
- It's driven by a playback position the view is given (time and which take); this spec doesn't play audio.
- Reduce Motion: the playhead still moves (it carries information).

### Earlier takes (§9, §6, criterion 7)

- Hidden by default. Hovering the pitch card fades in up to the 3 previous takes over **120 ms** as 1 pt lines in
  `pitch.you` at 30%, newest strongest. Holding **Option** shows them too, only while the window is key and no menu
  is tracking. VoiceOver: a "Show earlier takes" action. Reduce Motion: no fade.
- Hovering a take in the open take menu previews it as the **only** ghost.
- Unalignable takes are never ghosts (§13 item 6).

### Voice switch (§13 item 9, criterion 18)

- When the selected voice changes, the subtitle shows the new voice at once and the old drawing stays. When the new
  L2 arrives, the band, your line and the strip re-time onto the new voice's timeline in **one 150 ms ease**; with
  Reduce Motion they swap at once. The band is never blanked. The ease isn't part of spec 12's 150 ms L2 budget.

### Pitch line and axis (§9, §13 item 7; already drawn statically in 19)

- Keep spec 19's continuity, breaks (pause > 250 ms, modelOnly, youOnly), round caps, 45% / 1.5 pt interpolated
  frames and the under-3-frames rule while animating. The axis grows in 6 st steps up to ±24 and never shrinks within
  a phrase, including across takes and voice switches.

### Driving it (`ChartModel`)

- One value type per card (strip, pitch) holding geometry on the model axis, plus inputs: recording envelope, playback
  position, hover and Option state, ghost list, current and pending voice. Fixtures (`-UIFixture`) and spec 21 both
  build it; views never read AMCore types directly.
- A fixture clock drives every animation, so screenshots and tests are deterministic. New fixtures: `recording-live`
  (envelope at 0.5 s, 2 s and 19.5 s), `playback-model` and `playback-you` (playhead mid-word, and at a youOnly gap),
  `ghosts-hover`, `ghosts-menu-preview`, `voice-switch` (before, 75 ms in, done), plus each with Reduce Motion.

## Defaults

- Tokens and fonts from spec 18 only; no new colour.
- Accessibility: the pitch card's `AXChartDescriptor` (Model, You, Native range series) updates with the drawn data;
  the strip keeps one element per syllable pair, as in 19.

## Guardrails

- No audio, microphone, file or network access in this spec. CI never launches the app; screenshots run in the test VM
  only (`make test-ui-vm`, AGENTS.md), never on the host.
- No AMCore or AccentKit imports in the chart views beyond what 19 already uses.

## Out of scope

- Wiring to live capture, playback, the coordinator or the take store (spec 21).
- **Loop-slice selection and diff-row hover highlights.** Designer v1 §5.3 and §6.1 drew them with `selection.fill`
  and an accent outline, tokens that spec v2 dropped, and v2 doesn't restate them. Their look goes to Designer and a
  later spec.
- The sounding-syllable outline during playback (v1 §5.3: a 2 pt outline on both rows). v2 doesn't restate it; it goes
  to Designer with the highlights.

## Open question (built with the default)

1. **Live bars' time scale.** v2 says your bars draw live up to the playhead but not how wide a second is before the
   take's length is known. Default: the model's timeline (x = elapsed ÷ model phrase duration × plot width); if the
   take runs longer than the model, the whole row compresses to fit, keeping the playhead at the right edge.
2. **⇧⌘G "Show Earlier Takes".** v1 has it as a View menu toggle (on by default); v2 hides earlier takes until hover or
   Option. Default: v2 wins; no toggle and no ⇧⌘G (the Option key and the VoiceOver action cover keyboard and
   screen-reader users).

## How to test (Raph)

1. `make check` is green; `ChartModel` unit tests cover ghost selection (3 previous, never unalignable, menu preview
   alone), the 120 ms and 150 ms ease curves at fixed clock times, playhead x for both takes including a youOnly gap,
   and the never-shrinking axis.
2. `make test-ui-vm` renders every new fixture in light and dark (and Reduce Motion), and `scripts/check-screenshots.sh`
   finds no blank frame. Running it twice gives identical PNGs.
3. In the screenshots: recording bars are `strip.bar` with Lime only on the playhead and the RECORDING label; the
   voice-switch frame at 75 ms is between the two timelines and the band is drawn in every frame.
4. Hand (Raph, any fixture via the Samples menu): hover the pitch card and hold Option to see earlier takes fade in;
   with Reduce Motion on, they appear at once.

## Implementation notes

_(filled in by the agent)_
