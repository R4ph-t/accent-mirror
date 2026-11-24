# 20: Charts: live strip, playhead, earlier takes and voice-switch ease

Status: Done · Branch: – · Depends on: 19 (fixture-driven UI shell), 29 (v3 result screen, Designer spec v3), 28 (scoring off; was 11, then 27; repointed 2026-11-24 after spike 27's
NO-GO and Raph's v1 show-don't-judge decision) · Estimate: 6–8 h agent run + 1.5 h Raph review

Source: Designer spec v2 (Notion "Accent Mirror spec v2 (2026-11-23)") §7 (recording and analysing rows of the state
table), §8 (strip), §9 (pitch: earlier takes on hover, playhead), §6 (take-menu hover preview), §13 items 7 and 9
(breaks at gaps; band re-timed on a voice switch in one 150 ms ease, never blanked), §15 and §16 criteria 6, 7 and
18; Addendum r2 A3 (recording bars in `strip.bar`, Lime only on the playhead and label) and B6; Addenda r3–r5 where
they touch the charts (r5 wins). Designer spec v1 §5.3 and §11 for what v2 calls "as in v1" (Reduce Motion keeps the
playhead moving). Engineering review of spec v2 (Notion, 2026-11-23), proposed row 20 and its Designer calls 1, 2 and
4 (Option only while the window is key and no menu is tracking; the ease starts only after L2 arrives). Specs 18 and
19 left exactly these items to spec 20. Designer spec v2 Addendum r6 (Notion "Accent Mirror spec v2 (2026-11-23)", end of page; mockups `v2/specs11-21/specs11-21-board-{light,dark}@2x.png`): E3 (`highlight` token, hover and loop boxes), E4 (outline on the
syllable being played, "Playing …" header), E9 (live-bar time scale and no ⇧⌘G confirmed). r6 wins over earlier
text.

**v1 show-don't-judge and Designer spec v3 (re-scoped 2026-11-24).** Raph decided at 18:42 Europe/Paris (relayed by CPO)
to ship v1 without stress or phrase verdicts; plan https://app.notion.com/p/4220d0d4459281399adef9364a99bb69 (CTO
approved). Designer spec v3 (Notion "Accent Mirror v1: show, don't judge", https://app.notion.com/p/4220d0d4459281d39d67d6fdc5d50dfc) wins over v2 and addenda r2–r6. Spec 28 removes verdicts from the shipped app; spec 29 draws v3's static result screen from
fixtures (strip, legends, connectors, inspector, earlier-take ghosts, ⇧⌘G). This spec adds the motion and live
interaction on top. Where the text below conflicts with this block, this block wins:

- **Earlier takes (v3 §3.3) are on by default**, not on hover or Option: up to the 3 previous saved takes as 1 pt
  `pitch.you` lines at 30/20/12%, newest strongest; unalignable takes never drawn; View ▸ Show Earlier Takes (⇧⌘G)
  toggles them, on by default and remembered (r6 E9's "no ⇧⌘G" is superseded). Spec 29 draws them; this spec makes
  them fade in over 150 ms when a new take saves (the oldest drops out) and keeps hovering a take in the open take
  menu as a preview that shows that take as the only ghost (see "Earlier takes" below, rewritten for v3).
- **No diff rows exist in v1**, so "Hover on a diff row", its hover box and the `row-hover` frame are out. Label hover
  and loop boxes (r6 E3) and the played-syllable outline (r6 E4) stay.
- **Strip (v3.1 addendum V1–V3, end of the v3 page):** neutral `strip.bar` bars in both rows; the 4 pt Lime
  dictionary-stress dot under native labels only (spec 29) is static and never animates; your labels stay lowercase
  tertiary; **no Lime segments on the pitch baseline (V5)**; recording bars keep A3 (Lime only on the playhead and label). The 1 pt timing
  connectors (spec 29) re-time with the voice-switch ease, like the band.
- **The native band ("Native range") is display-only:** no colour change, copy or motion implies outside the band is
  wrong; it re-times on a voice switch in one 150 ms ease as before.
- **Playhead time mapping** uses `TimeWarp.toYou` / `toModel` (`AMWarp/TimeWarp.swift:171–174`; spec 28 §5 is
  tests only, no new `PartialTimeMap` lookup). Gaps and missing or inserted words return nil, so there is no
  playhead on the other row rather than interpolating. Play Both's playhead (model half, pause, your half) is
  drawn here on the injected clock.

## Goal

Finish the strip and pitch cards' motion and interaction, driven by fixture data and an injected clock, so spec 21
can feed them live data without touching the drawing. No audio, no microphone, no coordinator.

## Behaviour

### Live recording strip (§7, A3, Addendum r6 E9)

- While recording, your row draws bars from an **envelope stream** (per-10 ms RMS, the shape spec 14 publishes) in
  `strip.bar`, growing left to right up to a **2 pt Lime playhead**. No Lime on the bars. The native row stays drawn.
  Pitch is native only (no live pitch).
- Drawing uses `Canvas` with pre-binned bar geometry (1.5 pt bars on a 3 pt pitch). Only the new bins are added per
  frame; the budget is a steady 60 Hz (120 Hz on ProMotion) with no dropped frames over a 20 s take.
- **Time scale** (confirmed in E9): x = elapsed ÷ the model phrase duration × plot width. If the take runs longer than
  the model, the whole row compresses to fit and the playhead stays at the right edge. When the result arrives, your
  row moves onto your own timeline as in v2.
- **Analysing:** your bars stay grey (`strip.bar`) until the result arrives (§7).

### Playhead (§9, v1 §5.3)

- A 1 pt `text.primary` line across both the strip and the pitch plot while audio plays, on the model timeline.
  Playing your take moves it through `TimeWarp.toModel` (spec 09's warp, spec 28 §5); across a youOnly stretch it holds at
  the gap edge.
- It's driven by a playback position the view is given (time and which take); this spec doesn't play audio.
- Reduce Motion: the playhead still moves (it carries information).

### Syllable being played (Addendum r6 E4)

- While Model, You, Play Both or a loop plays, the syllable being played gets a **1 pt `text.secondary` outline**,
  radius 4, 3 pt outside its bars, on both strip rows (the matching syllable in the other row too, through the
  syllable pairs). It jumps from syllable to syllable with no animation, together with the 1 pt playhead.
- The strip card header shows ▶ "Playing the model" or "Playing your take" in Geist 12 `text.secondary` while audio
  plays. The loop label (below) wins while looping.
- Inputs: the playback position already given to the playhead, plus which take is playing. No audio here.

### Hover and loop highlights (Addendum r6 E3)

- New token **`highlight`**, neutral (never Lime or blue): `text.primary` at 5% (light) / 6% (dark) for hover, 9% /
  11% for a looping slice. It's added to spec 18's token set next to the others, with both appearances.
- *(Out in v1: no diff rows; see the v1 block above.)* **Hover on a diff row** (card 1): the row gets a `surface.well` background (radius 6, 8 pt side inset; its play
  button sits on `surface.card`). The row's word gets a **hover box**: one rounded rectangle (radius 4, 4 pt outset)
  behind its syllables across both strip rows, and the same fill as a full-height column in the pitch plot over that
  word's model time.
- **Hover on a word or syllable label:** the same box, and the pointing-hand cursor.
- **Looping slice:** the same box at the stronger fill, plus a label at the right of the strip card header: the
  `repeat` SF Symbol and "Looping "{word}" · Esc to stop" in Geist 12 `text.secondary`. No outline or accent colour on
  the bars.
- The boxes fade in over 120 ms; with Reduce Motion they appear at once.
- Inputs: hovered word, looping word (or none). Starting and ending a loop (Esc, a click on empty space, another
  selection) is spec 21's; this spec draws whatever state it's given.

### Earlier takes (§9, §6, criterion 7)

- **Shown by default (Designer spec v3 §3.3; supersedes the hover/Option rule and E9's "no ⇧⌘G").** Up to the 3
  previous saved takes as 1 pt lines in `pitch.you` at 30%, 20% and 12%, newest strongest; unalignable takes never
  drawn. View ▸ Show Earlier Takes (⇧⌘G) toggles them, on by default and remembered. Toggling fades them over
  **120 ms**; a newly saved take fades in over 150 ms as the oldest drops out. VoiceOver: the menu item's state.
  Reduce Motion: no fade. There is no hover or Option reveal.
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
  position and playing take, playing syllable, hovered and looping word, earlier-takes toggle (⇧⌘G), ghost list, current and
  pending voice. Fixtures (`-UIFixture`) and spec 21 both
  build it; views never read AMCore types directly.
- A fixture clock drives every animation, so screenshots and tests are deterministic. New fixtures: `recording-live`
  (envelope at 0.5 s, 2 s and 19.5 s), `playback-model` and `playback-you` (playhead mid-word, and at a youOnly gap),
  `ghosts-hover`, `ghosts-menu-preview`, `voice-switch` (before, 75 ms in, done), `row-hover`, `word-loop`,
  `playing-syllable-model` and `playing-syllable-you`, plus each with Reduce Motion.

## Defaults

- Tokens and fonts from spec 18 only, plus the one new neutral `highlight` token from E3. No other new colour.
- Accessibility: the pitch card's `AXChartDescriptor` (Model, You, Native range series) updates with the drawn data;
  the strip keeps one element per syllable pair, as in 19.

## Guardrails

- No audio, microphone, file or network access in this spec. CI never launches the app; screenshots run in the test VM
  only (`make test-ui-vm`, AGENTS.md), never on the host.
- No AMCore or AccentKit imports in the chart views beyond what 19 already uses.

## Out of scope

- Wiring to live capture, playback, the coordinator or the take store (spec 21).
- The input level meter (spec 21, Addendum r6 E5).

## Open question (built with the default)

None. Addendum r6 E9 confirmed the live-bar time scale and dropping ⇧⌘G.

## How to test (Raph)

1. `make check` is green; `ChartModel` unit tests cover ghost selection (3 previous, never unalignable, menu preview
   alone), the 120 ms and 150 ms ease curves at fixed clock times, playhead x for both takes including a youOnly gap,
   and the never-shrinking axis.
2. `make test-ui-vm` renders every new fixture in light and dark (and Reduce Motion), and `scripts/check-screenshots.sh`
   finds no blank frame. Running it twice gives identical PNGs.
3. In the screenshots: recording bars are `strip.bar` with Lime only on the playhead and the RECORDING label; the
   voice-switch frame at 75 ms is between the two timelines and the band is drawn in every frame. `word-loop` and
   the two `playing-syllable` frames match (`row-hover` is out in v1: no diff rows) the r6 board (sections 3 and 4): neutral boxes only, no
   Lime or accent on the bars, the "Looping …" and "Playing …" labels in the strip header.
4. Hand (Raph, any fixture via the Samples menu): earlier takes show by default at 30/20/12%; ⇧⌘G fades them out
   and back in, and the choice survives a relaunch; with Reduce Motion on, they change at once.

## Implementation notes

_(filled in by the agent)_
