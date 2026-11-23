# 19: Fixture-driven UI shell

Status: Done · Branch: factory/18-19-ui-shell (PR #4), fixes on factory/18-19-fixes (PR #11) and factory/18-19-fixes-r3 · Depends on: 18 (UI foundation) · Estimate: 6–8 h agent run + 1.5 h Raph review

Source: Designer spec v2 (Notion "Accent Mirror spec v2 (2026-11-23)"), including Addendum 2026-11-23 (r2), Addendum 2026-11-23 (r3, items B1–B11) and Addendum 2026-11-23 (r4, items C1–C9). r4 wins over r3, r2 and spec v2 wherever they differ; r3 wins over r2 and spec v2; r2 wins over spec v2. Engineering review proposing rows 18–21. Plan v2, approved 2026-11-23 09:56 Europe/Paris. Reference mockups: `mockup-{result,empty,recording,error}-{light,dark}-final2@2x.png` (2400 × 1600 px for a 1200 × 800 pt window). This spec does not depend on spec 11 (scoring).

## Goal

Render every milestone-1 UI state from Designer's spec v2 and Addenda r2 and r3, driven only by committed JSON fixtures, and capture scripted native light and dark screenshots of each state from a test target. No hand-clicking, no microphone, no live analysis, no scoring.

## Behaviour

### Fixture-driven rendering

- Every state below is produced by loading a named JSON fixture and rendering the spec 18 shell with that data. The app does not record, import, or analyse audio to show these states.
- Fixtures live in the app target (for example `AccentMirror/Fixtures/`). They use the plan v2 contract names (`feedback`, `close`, `noClearDifference`, `inconclusive`, `partial`, take problems, operational errors, `MeasureState`, `AlignedWordPair`, and so on). When spec 01 later freezes those types, any drift is fixed by updating the fixtures, not by inventing a parallel UI model.
- A launch argument `-UIFixture <name>` (and a "render all" entry point for the screenshot runner) selects the fixture. Appearance is forced light or dark by the runner, not by clicking the system control.
- The selected sidebar phrase in the four mocked states is "Photography is harder than it looks." under My Phrases, subtitle "My Phrases · From demo-talk.m4a", as in the final2 mockups.

### Addendum rules that win over earlier sections

**Addendum r3 (wins over everything below where they differ):**

- **B1 inferenceFailed:** "Something went wrong inside Accent Mirror while {stage}. This isn't about your take." (§13 item 2).
- **B2 italics:** the real bundled Geist Italic, never a synthetic slant. Geist Mono Italic is not used or bundled.
- **B3 mistakes in card-1 sentences (§10):** bold caps in mistake blue only, no triangle and no dotted underline; the
  word order carries it ("Stress TOG, not PHO"). The triangle and dotted underline go only on strip row labels. This
  narrows §4.3.
- **B4 placement marker:** only on a high-confidence result with your stress outside the accepted set (A5); never on
  inconclusive or noClearDifference, where your row follows what was heard with no marker.
- **B5 noClearDifference:** the first §13 item 1 reason that applies (in the order pitchShapeBelowClose,
  optionalMeasuresUnavailable, mediumConfidenceOnly, timingRough) gives its full sentence. Only when none applies is it
  the bare "No clear difference in stress or rhythm.". Always `equal.circle` in secondary, the first row in card 1,
  above any A6 quiet line.
- **B6 your unstressed bars:** `strip.you`, rgba(28,26,23,0.50) light and rgba(247,244,238,0.58) dark (final2 values).
  Native unstressed bars and inserted words stay `strip.bar`.
- **B7 take-problem YOU row:** a flat waveform, one cluster per syllable, with a caption centred under it in Geist 12 /
  400 secondary: too quiet "Too quiet to measure", clipped "Too loud to measure" (bars cut flat at the top), too short
  "Too short to measure", words don't match "Words didn't match the phrase". Too short and words don't match use the
  same near-silent waveform as too quiet.
- **B8 wordsDontMatch:** playable but not saved; the take menu reads "LAST TRY · NOT SAVED" (extends A7).
- **B9 no pitch:** "No pitch to show for this take" has no backing. It is centred horizontally in the pitch plot, its
  baseline 8 pt above the bottom of the plot, in Geist 12 / 400 secondary, in both themes.
- **B10 final-direction icons:** `arrow.up.right` for "End higher, the way the model does." and `arrow.down.right` for
  "End lower, the way the model does.".
- **B11 fixtures:** each row fixture's charts show its own difference, from its own take (never the close-match take):
  range a flatter line, final direction a different ending, contrast weaker or stronger stressed bars. Missing-word
  copy uses words from the fixture's own phrase.

**Addendum r2:**

- **Recording bars (A3):** while recording, live bars use `strip.bar` (neutral). Lime appears only on the 2 pt playhead, the "● RECORDING 0:02" label, and the Stop button itself. The card 1 mic icon is secondary. This supersedes "bars draw live in Lime" in Designer spec v2 §7.
- **Close sentence (A4):** the close row names only what was actually evaluated for this take. It never claims a dimension that was `notApplicable` or `unavailable`.
  - Stress, rhythm and pitch shape all evaluated: "Close to the model. Stress, rhythm and pitch shape all match."
  - Pitch shape not evaluated: "Close to the model. Stress and rhythm match."
  - Placement only (a one-word, two-syllable phrase): "Close to the model. Stress is in the right place."
- **Quiet lines (A6):** one quiet line in card 1, under the rows, in Geist 12 secondary with `info.circle`. It does not count toward the 3 rows. Only one quiet line shows; the most specific one wins in this order: `insertionsPresent`, then `nonTargetWordsIncomplete`, then the partial count line. The inspector lists all of them.
  - `nonTargetWordsIncomplete`: "Some words weren't clear enough to compare. Feedback covers the rest."
  - `insertionsPresent`, one word: "You added *“so”*. It's left out of the comparison." The inserted word is set in italics. Two insertions: "You added *“so”* and *“really”*."
  - Partial feedback: "Feedback covers 6 of 8 words." (the counts come from the fixture).
- **Insertions in the strip (A6):** in your strip row the inserted word shows as grey `strip.bar` bars with no Lime, labelled "+ so" in italics, secondary. It is not drawn on the pitch chart (`youOnly`).
- **Take menu for an unsaved attempt (A7):** when You plays an unsaved too-quiet, clipped, or too-short attempt, the take menu reads **"LAST TRY · NOT SAVED"** in Geist Mono 12 secondary with its chevron. The menu widens to fit and the toolbar buttons move left. The menu shows the saved takes as usual, plus the last try at the top as a **non-selectable** label. Once the next take starts or the phrase changes, the last try is gone and the menu goes back to "TAKE 03" or "TAKES".
- **Sidebar selection** follows spec 18 / Addendum A1 (Raph's pick B). It is not a placeholder.
- **A(w) display (A5, and plan v2 §3.3):** flag only outside A(w) at high confidence, name the nearest accepted pattern ("you match p311", "like p311 says it"), and never say "wrong". See Open question for the wording gap between the addendum and the plan; fixtures follow the plan's rule.

### States the shell must render

Each bullet is at least one fixture. Light and dark screenshots are required for every fixture.

**Primary mocked states** (must match the eight final2 mockups within 2 pt for layout, and the §4 / Addendum tokens exactly):

1. `empty` — "YOUR TAKE": mic icon (secondary), "Listen to the model, then press Space to record your take." Native strip drawn; your row is a dashed placeholder, "Your take appears here." Pitch is native only. You disabled, take menu "TAKES".
2. `recording` — "YOUR TAKE": secondary mic, "Recording. Press Space when you're done." Your bars in `strip.bar` up to a 2 pt Lime playhead. Pitch is native only (no live pitch). Stop; Model and You disabled. Subtitle "● RECORDING 0:02" in `lime.text`.
3. `result-feedback` — "WHAT TO CHANGE" with the three mockup rows (placement "Stress TOG, not PHO: phoTOGraphy.", contrast "Make HAR and LOOKS stronger…", reduction "Keep the small syllables short and light: ra, phy, der, than."). Both strip rows and the pitch chart as in the result mockups. Take menu "TAKE 03". The stressed-syllable legend reads **"Stressed"** (written spec), even if a mockup typo shows "Stresed".
4. `tooQuiet` — "YOUR TAKE" with speaker.wave.1 in mistake blue, "That take was too quiet to hear clearly. Move closer to the mic or speak up.", Try Again. Your strip row is a flat near-silent waveform with "Too quiet to measure". You enabled. Take menu **"LAST TRY · NOT SAVED"** as specified above. Pitch is native only.

**Coordinator / in-flight:**

5. `analysing` — "Analysing your take…". Your bars in grey. Native pitch only. Record enabled (it would cancel; no live cancel in this spec).

**Close (Addendum A4):**

6. `close-all` — "Close to the model. Stress, rhythm and pitch shape all match."
7. `close-stress-rhythm` — "Close to the model. Stress and rhythm match."
8. `close-placement-only` — "Close to the model. Stress is in the right place." plus the placement-only info line for a one-word, two-syllable phrase: "This phrase gets stress placement feedback only: one word with two syllables has nothing else to compare."

**Feedback extras:**

9. `feedback-partial` — feedback rows plus the quiet count line "Feedback covers 6 of 8 words."
10. `feedback-insertions` — quiet line "You added *“so”*. It's left out of the comparison." and the "+ so" strip treatment.
11. `feedback-two-insertions` — "You added *“so”* and *“really”*."
12. `feedback-nonTargetWordsIncomplete` — "Some words weren't clear enough to compare. Feedback covers the rest."
13. `feedback-quiet-priority` — a take that has insertions, incomplete non-target words, and a partial count; only the insertions line shows in card 1; the inspector lists all three.
14. `placement-only-too-few-unstressed` — info line "This phrase gets stress placement feedback only. It's too short to compare strong and weak syllables."

**noClearDifference** (card 1 titled "WHAT TO CHANGE", icon `equal.circle`, secondary). Show the first §13 item 1 reason's full sentence; the bare "No clear difference in stress or rhythm." only when none applies (r3 B5). The inspector lists all present:

15. `ncd-pitchShapeBelowClose` — "No clear difference in stress or rhythm. Your pitch moves a little differently from the model's, but not in one place we can point to."
16. `ncd-optionalMeasuresUnavailable` — "No clear difference in stress or rhythm. Some pitch measures couldn't be taken on this take."
17. `ncd-mediumConfidenceOnly` — "Nothing stood out clearly enough to point at. Try another take to check."
18. `ncd-timingRough` — "No clear difference, but the timing match was rough, so small differences may be hidden."
19. `ncd-nonTargetWordsIncomplete` — uses the A6 quiet line (this reason has no separate §13.1 sentence).
20. `ncd-insertionsPresent` — uses the A6 quiet line.

**inconclusive** (icon `questionmark.circle`, secondary; Try Again unless noted; no blue, no take-problem styling):

21. `inc-targetWordsMissing-one` — "We didn't hear "harder", so we can't check its stress. Say the whole phrase and try again." Your strip has a missing slot for "harder" (r3 B11).
22. `inc-targetWordsMissing-two` — two words, "harder" and "looks", each with its missing slot.
23. `inc-targetWordsMissing-many` — "some of the key words" (photography, harder and looks are missing from the take).
24. `inc-timingUnreliable` — "We couldn't line your take up with the model well enough to compare. Try again at an even pace."
25. `inc-comparableCoverageLow` — "Only part of your take lined up with the model (about 55%). Say the whole phrase in one go." The % is rounded to 5 and comes from the fixture.
26. `inc-requiredMeasureUnavailable` — "We couldn't measure stress on this take. Try again a little louder and closer to the mic."
27. `inc-requiredMeasureUnavailable-lowConfidence` — "We couldn't tell your stress clearly on this take. Try again a little slower."
28. `inc-noApplicableStressMeasure` — "This phrase has no word long enough to check stress on. The charts still show your rhythm and pitch." No button.

**Take problems** (card 1 titled "YOUR TAKE"; only the first problem in plan order). Copy and icons as Designer spec v2 §11.1:

29. `tp-noMicrophone` — Record disabled, no Try Again.
30. `tp-micDenied` — "Open System Settings…" (the button may be inert in fixtures).
31. `tp-noSpeech`
32. `tp-tooShort` — You enabled if the fixture says audio is present; take menu "LAST TRY · NOT SAVED". Your row is the too-quiet near-silent waveform captioned "Too short to measure" (r3 B7).
33. `tp-clipped` — same unsaved-attempt menu rule.
34. `tp-wordsDontMatch` — playable, take menu "LAST TRY · NOT SAVED" (r3 B8); your row is the too-quiet near-silent waveform captioned "Words didn't match the phrase" (r3 B7).

(`tooQuiet` is already item 4.)

**Operational banners** (inline banner above the cards, never inside card 1, never blue, never Try Again; cards keep the last result or the empty state). Copy as Designer spec v2 §13.2:

35. `op-modelUnavailable`
36. `op-inferenceFailed` — one fixture is enough; the sentence includes the stage from the fixture.
37. `op-referenceCacheCorrupt`
38. `op-audioUnreadable-clip` and `op-audioUnreadable-take`
39. `op-saveFailed` — result plus the save notice. Button: Try Again Saving, plus a close button.
40. `op-error-wins-over-saveFailed` — an operational error and saveFailed together; only the error banner shows.
41. `op-savedPruneFailed` and `cancelled` — render the underlying result or empty state with **no** banner and no take-problem row. A screenshot of that frame is enough.

**Words, stress naming, and chart edge cases:**

42. `words-substituted` — grey `strip.bar` bars, italic quoted label, tooltip "You said "photograph" here, not "photography"."
43. `words-missing` — 24 pt dashed slot, struck-through expected word, pitch breaks (`modelOnly`).
44. `words-expectedAmbiguous` — all-lowercase secondary labels, Lime bars still show measured prominence, never flagged. Tooltip: "Stress isn't checked on this word. It can be said more than one way."
45. `words-referenceAnomaly` — treated like ambiguous in both rows; inspector: "p225 stresses this word differently from the dictionary, so it isn't compared."
46. `stress-match-p311` — inspector "photography: you match p311 (phoTOGraphy)." (or the selected-voice / dictionary variants in Designer spec v2 §13.5). The result mockup is the selected-voice case and needs no "like p311" in the row.
47. `stress-like-p311` — placement row "Stress TOG, not PHO: phoTOGraphy, like p311 says it." Marker only on the syllable after "not".
48. `stress-lowConfidence` — no row, no marker; inspector "photography: not clear enough to check."
49. `unalignable` — take menu "TAKE 02" plus "NOT COMPARABLE" in Geist Mono tertiary; card 1 "This take was recorded for the old wording, so it can't be compared." No Try Again. Your strip is plain grey bars with no labels; pitch is native only. Play You looks enabled.
50. `noVoicedFrames` — native band as usual, "No pitch to show for this take" with no backing, centred horizontally, its baseline 8 pt above the bottom of the plot, in Geist 12 / 400 secondary (r3 B9). Inspector pitch measures show "—", never zero, with "Not measured: too little voicing".
51. `rough-timing-first` — rough-timing row first, at most 3 rows in total.
52. `inspector-open` — Details inspector visible, listing measure states (`evaluated` / `unavailable` / `notApplicable` with reasons), STRESS lines, and save state when the take is not saved.
53. `coming-soon-expanded` — Noun and Verb Pairs expanded to the non-selectable "No phrases yet…" line.

Diff-row kinds, order, icons and sentences that are not already covered by the result mockup (contrast, range, final direction, too much contrast) each have a `rows-*` fixture so their copy can be screenshotted. Each `rows-*` fixture carries exactly one row and draws its own take, which differs from the close-match take only in that row's dimension, so the charts show one difference and agree with the sentence (r3 B11, Designer round 4): `rows-contrast` smaller HAR and LOOKS bars ("Make HAR and LOOKS stronger."); `rows-range` only a flatter YOU line; `rows-final-direction-higher` the question "Is photography harder than it looks?", whose native really rises at the end, with your ending falling; `rows-final-direction-lower` the statement, whose native falls, with your ending rising; `rows-too-much-contrast` bigger HAR and LOOKS bars ("You can soften HAR and LOOKS a little."). The too-much-contrast sentence names every syllable that's over, joined like the other rows ("A", "A and B", "A, B and C"). Row order and the 3-row cap have their own fixtures: `rough-timing-first` (rough timing first; four rows in the result, three shown) and `feedback-too-much-contrast-last` (too much contrast listed first in the result, shown last after reduction). The final-direction icon is `arrow.up.right` for "End higher" and `arrow.down.right` for "End lower" (r3 B10).

Hover ghosts, Option-to-show-earlier-takes, and the 150 ms voice-switch ease may be still in 19 (a fixture that *would* show ghosts is enough if the still cannot animate). They are finished in spec 20. The recording playhead must be visible in the `recording` screenshots. Interpolated pitch (45% opacity, 1.5 pt) and breaks at pauses over 250 ms / `modelOnly` / `youOnly` should already follow Designer spec v2 §9 and §13.7 when the fixture provides that geometry, so the written states are honest.

### Scripted screenshots

- Add a screenshot **test target** (or an equivalent test-hosted runner) that, for each fixture × {light, dark}, opens a 1200 × 800 pt window, seeds that fixture, and writes a PNG at 2× (2400 × 1600). One command regenerates the whole set. Running it twice produces the same images. A fixture may name another window size (`window`, at least the 960 pt minimum width); its frame is 2× that size. Every frame shows exactly that window's content area, never a smaller window scaled up (fixes round 5).
- No hand-clicking, no cursor, no dev overlays, no live user data. No microphone, no network, no WhisperKit.
- **This target is not run by CI and is not part of `make check`.** AGENTS.md stands: CI never launches the app, never uses the microphone, never runs UI tests. Implementation of this spec may add a local `make screenshots` target; it must not be called from `.github/workflows/ci.yml`.
- Output goes to a gitignored or reviewed-artifact folder (for example `screenshots/ui-shell/`), named `<fixture>-{light,dark}@2x.png`. The four primary states are compared against the final2 mockups. The other states are the set sent back to Designer.

### Narrow and short windows (fixes rounds 5 and 5b, Addendum r4 C4 to C8)

- **Labels keep 4 pt apart (C6).** The syllable labels under each strip row, and the word labels under the pitch
  plot, keep at least 4 pt between neighbouring labels that show.
- **Hide order (C6).** When labels collide they hide lowest priority first: (1) unstressed syllable labels and
  non-target word labels; (2) heard-word labels (a substitution, "+ so") and missing-word labels; (3) never:
  stressed syllable labels, mistake labels and target word labels always show. Within a priority labels are placed
  left to right, and one shows only if it keeps the gap to every label already showing.
- **Target words (C6).** A word with a stressed native syllable, a word named in a card-1 diff row, or a word named
  in the card-1 sentence (for example the missing words of targetWordsMissing). A starter manifest's `targets` add
  to this set and never replace it.
- **Nothing is lost.** A hidden label keeps its hover area and tooltip, and VoiceOver still reads every syllable and
  every word.
- **Tested rules.** `LabelLayout.visibility` (which labels show), `LabelLayout.syllablePriority` /
  `missingWordPriority` / `wordPriority` (the hide order) and `ShellPresenter.namedTargetWords` (the target set)
  are pure and covered by Swift Testing cases.
- **Toolbar (C7).** See spec 18, Toolbar.
- **Too-much-contrast strip (C4).** Your over-contrast syllables (HAR, LOOKS) stand at full height. Each unstressed
  neighbour is at most half as tall, relative to them, as the native's neighbour is to the native's stressed
  syllable. Syllables the row doesn't name (TOG) keep native's relative height; they are never shrunk to fake
  contrast. This applies to `rows-too-much-contrast` and `feedback-too-much-contrast-last`, and a data test checks it.
- **Question rise (C1).** In `rows-final-direction-higher` the native line dips low at the start of LOOKS, then
  rises in a concave-up curve through the last ~60% of the word, ends near the TOG peak (85–90% of the plot
  height), flattens slightly at the very end and stays inside the plot. No straight ramp, no kink before LOOKS.
  Yours falls. A shape test checks it.
- **Short windows (C8).** The minimum window is 960 × 680 pt with the inspector open too; no panel widens. On a
  short window the pitch plot shrinks first, down to a 120 pt plot height (`Metrics.pitchPlotMinHeight`). If the
  cards still don't fit, the card column scrolls vertically and the toolbar stays fixed. Card 1 is not tightened;
  its rows may wrap to two lines.
- **Regression fixture.** `narrow-inspector-open` is `inspector-open` in a 960 × 680 pt window, light and dark.

### Visual and copy rules already in spec 18 that this shell must keep

Tokens, fonts, grain, sidebar selection (pick B), secondary pack headers, contrast, no red/purple/gold/amber, disabled buttons as no fill plus tertiary text, and the wordmark all still apply. On a strip row label a mistake is always blue + triangle + dotted underline together; inside a card-1 sentence it is bold caps in mistake blue only, as in §10 (r3 B3). Dictionary / accepted stress is caps labels; measured prominence is bar height and Lime.

## Defaults

- Screenshot runner: a dedicated test target driven by `-UIFixture` (and a "all fixtures" entry), invoked locally by `make screenshots`. If a full XCUITest pass is awkward to keep out of CI, a test-hosted window renderer in that same target is fine, as long as the PNGs are native SwiftUI at 1200 × 800 pt, 2×, and CI never launches it.
- Fixture schema: a documented JSON shape next to the fixtures, using plan v2 names. Do not generate a second domain model in the view layer.
- Play and Record controls in fixtures are visual only; they must not open the microphone or play sound in the screenshot run.

## Guardrails

- Same on-device, no-network, no-mic, no-entitlements, no-signing rules as spec 18.
- AccentKit still has no AppKit or UIKit. Fixture decoding that is UI-free may live in the app target; do not pull SwiftUI into the package.
- `make check` stays green and does not run the screenshot target.
- Colour is never the only cue. Every meaning in Designer spec v2 §15 still reads in a grayscale screenshot.
- No personal paths, secrets, or team IDs. Designer mockups are not copied into the repo unless their licence is already cleared; this spec compares against them locally.

## Out of scope

- Wiring controls to live capture, playback, the take store, or real persistence (spec 21).
- Finishing hover/Option ghosts, voice-switch ease, and playhead motion beyond the stills needed to match mockups and written states (spec 20).
- Scoring, threshold tuning, WhisperKit, microphone permission strings, entitlements, signing, iOS.
- Flipping this spec to Ready (a later spec PR, after Raph's approval).
- Editing `.factory/`, `.github/`, or CI so that it launches the app.

## Open question (built with the default)

Addendum A5 says: "A(w) = the context-compatible dictionary pronunciation plus the patterns of this phrase's native readers." Plan v2 rev 3 §3.3 says: "A(w) = {the primary of the **context-compatible pronunciation**} ∪ {the high-confidence observed primaries of native readers of **this phrase**}." Fixtures and inspector copy follow the **plan** (primary of the context-compatible pronunciation, plus high-confidence observed primaries actually produced). Display rules otherwise match Addendum A5 and Designer spec v2 §13.5. Do not stop to ask, and do not accept other CMUdict variants.

## How to test (Raph)

1. `make check` is green and CI has not grown an app-launch or UI-test step.
2. `make screenshots` (or the command named in the implementation notes) writes light and dark 2400 × 1600 PNGs for every fixture, including the four primary states and every other state listed above, without anyone clicking the UI.
3. Side-by-side, the result / empty / recording / too-quiet shots match the eight final2 mockups within 2 pt, in both themes, including: selected row (glyph, lime text, no fill); recording bars in `strip.bar` with Lime only on the playhead and RECORDING label; too-quiet take menu "LAST TRY · NOT SAVED"; secondary pack headers; light secondary #69645C.
4. Open three unmocked fixtures in the app via `-UIFixture` (a close-placement-only result, an insertions quiet line, and an operational banner). Copy, placement, and banner-above-cards match this spec.
5. Confirm You does not need the microphone in any fixture, and that cancelled / savedPruneFailed show no banner.

## Implementation notes

- **Command.** `make screenshots` is local only: it is not called by `make check` or `.github/workflows/ci.yml`. It
  regenerates the project and runs the `AccentMirrorScreenshots` scheme (a unit-test bundle hosted by the app; the
  `AccentMirror` scheme that CI builds does not include it). It writes `screenshots/ui-shell/<fixture>-{light,dark}@2x.png`
  (git-ignored), then runs `scripts/check-screenshots.sh`, which fails on a wrong size, a missing light/dark twin or a
  near-uniform frame. Two runs give byte-identical PNGs (SHA-256 of all 124 frames compared).
- **Renderer.** `WindowRenderer` builds a real 1200 × 800 pt `NSWindow` with the app's own chrome and `ShellView`,
  forces Aqua or Dark Aqua on the window, and draws the window's frame view into a 2400 × 1600 bitmap with
  `cacheDisplay`. That is native SwiftUI, not a screen grab: no cursor, no overlays, nothing else on screen. The
  test host never becomes the active app, so the traffic lights always render in their inactive (grey) state.
  That keeps the frames deterministic.
- **Fixtures.** The JSON is in `AccentMirror/Resources/Fixtures/` (`states/`, `phrases/`, `takes/`, documented in
  `SCHEMA.md`) and is bundled as a folder reference. `-UIFixture <name>` picks one at launch; without it the app shows
  `empty`. There are 64 states: the 53 listed above (with `op-audioUnreadable-clip/-take` and
  `op-savedPruneFailed`/`cancelled` as separate files), plus `rows-contrast`, `rows-range`,
  `rows-final-direction-lower/-higher`, `rows-too-much-contrast`, `feedback-too-much-contrast-last`,
  `stress-differs-but-accepted`, `tp-first-in-plan-order` and `pitch-interpolated-and-breaks` (round 4 added
  `rows-contrast` and `feedback-too-much-contrast-last`).
- **No second domain model.** AMCore has no contract types yet (spec 01), so the Decodable types in
  `AccentMirror/Fixtures/FixtureModel.swift` use the plan v2 names and are the only model. `ShellPresenter` maps them
  to what each card draws, and `Copy` holds every sentence. Both are pure and UI-free; the views only draw. When
  spec 01 lands, the fixtures and this decoding layer move to the AMCore types.
- **Tests.** `AccentMirrorScreenshots/ShellContractTests.swift` checks that every fixture decodes, the copy rules (A4
  close, A6 quiet-line priority, rough row first and the 3-row cap, banner precedence, never "wrong", "like p311"),
  the toolbar rules (recording, LAST TRY · NOT SAVED) and the token contrast guardrails. It needs the app target, so
  it runs with `make screenshots`, not in CI.
- **Drawing.** Strip bars are drawn from each syllable's span and measured prominence, with a seeded per-bar jitter.
  The pitch lines are Catmull-Rom curves through the fixture points. The band is the P10 to P90 ribbon unioned with a
  7 pt round-capped stroke. Bridged frames are drawn at 45%, 1.5 pt. Breaks are wherever the fixture's segments
  break, and a segment under 3 points is not drawn. Hover ghosts and voice-switch easing are left to spec 20.
- **Controls.** Play, Record, Try Again and the banner buttons are visual only: no microphone, no audio, no network.
- **Fixes (2026-11-23).** After the Designer's review of PR #4:
  - The mistake marker only shows on the syllable a displayed placement row names. `ShellPresenter` enforces it,
    and the inc, ncd and rows fixtures now use clean takes.
  - noClearDifference always has its `equal.circle` row. When only quiet-line reasons are present it uses the
    shared §13.1 stem, "No clear difference in stress or rhythm.", and the quiet line sits under it.
  - Your unstressed bars use the new `stripBarYou` token: rgba(28,26,23,0.50) light, rgba(242,239,233,0.60) dark,
    sampled from `mockup-result-dark-final2` (dark replaced by the r3 B6 value in round 3).
  - A take problem with audio draws the take grouped by syllable: near-silent for too quiet ("Too quiet to
    measure"), cut flat for clipped ("Too loud to measure"), plain grey for too short and words don't match (both near-silent and captioned since round 3). The
    take menu reads LAST TRY · NOT SAVED.
  - "No pitch to show for this take" sits on a card-coloured backing (removed in round 3, r3 B9).
  - Heard words use the real Geist italics, and the inferenceFailed stage is typed. (Round 3 dropped the unused Geist
    Mono italic.)
  - The `AccentMirror` scheme's Test action runs `AccentMirror.xctestplan` (the AccentKit unit tests, the shell
    contract tests and the screenshot renderer). It launches the app as a test host, so it runs in CI or the test
    VM, never on Raph's desktop.
  - The "Fixture <name>" schemes run the app on one fixture. A pre-build phase fails with "project.yml changed:
    run make generate" when the generated project is stale.
  - Committed screenshots shrank from 29.4 MiB to 6.9 MiB (`docs/screenshots/ui-shell/README.md`).
- **Fixes round 3 (2026-11-23).** After the Designer's final batch and Addendum r3 (B1–B11):
  - noClearDifference: the first applicable §13 item 1 reason's full sentence wins; the bare stem only when none
    applies (B5). The code already did this; `ShellContractTests` now pins each reason alone, the order when several
    apply, and the none-applies case.
  - "No pitch to show for this take" has no backing: centred, baseline 8 pt above the bottom of the plot
    (`Metrics.noPitchBaselineInset`), Geist 12 secondary (B9).
  - Too short and words don't match draw the too-quiet near-silent waveform, captioned "Too short to measure" and
    "Words didn't match the phrase" (B7). Captions stay secondary.
  - `GeistMono-Italic[wght].ttf` is deleted with every reference to it; mono labels stay upright (B2).
  - Card-1 sentences show a mistake as bold blue caps only; the triangle and dotted underline stay on strip labels
    (B3). The code already did this; a test pins it.
  - Dark `stripBarYou` is rgba(247,244,238,0.58) (B6).
  - The final-direction icon follows the direction (B10).
  - Row fixtures draw their own takes (B11): `photography-take04-flat` (rows-range), `-end-falls` with the phrase
    variant `photography-rising-end` (rows-final-direction-higher), `-end-rises` (rows-final-direction-lower) and
    `-strong-contrast` (rows-too-much-contrast). There is no separate too-little-contrast fixture: the contrast row
    ("Make HAR and LOOKS stronger…") shows in `result-feedback` (take 03, already its own take) and `rows-range`.
  - The targetWordsMissing fixtures name words of "Photography is harder than it looks." and their takes have the
    matching missing slots and pitch breaks: "harder" (`-missing-harder`), "harder" and "looks"
    (`-missing-harder-looks`), and photography, harder and looks for `-many` (`-missing-three`).
  - Renders come from the test VM (`make screenshots-vm`), never the host. Two runs gave byte-identical PNGs.
  - The screenshot run tears each window down after its capture (`WindowRenderer.dispose`), which leaves the frames
    unchanged. AppKit's excessive-live-window warning still shows once per run: a shown window isn't freed in the
    async test (see the PR's open points). `scripts/check-screenshots.sh` skips its git step outside a work tree, so
    the VM no longer prints "fatal: not a git repository".
- **Fixes round 4 (2026-11-23).** The Designer's answers to round 3's open points:
  - "End higher" moved to a phrase whose native really rises: `phrases/photography-question` ("Is photography
    harder than it looks?", under My Phrases in that fixture's sidebar) with the take
    `photography-question-take04-end-falls`. The `photography-rising-end` variant is gone.
  - Too much contrast names every over-contrast syllable with the shared joiner: "You can soften HAR and LOOKS a
    little. The model doesn't push them as hard." ("it" for one syllable). Tests cover one, two and three.
  - One row per `rows-*` fixture. `rows-range` keeps only the range row and its take only the flatter line;
    `rows-final-direction-lower` and `rows-too-much-contrast` lose their reduction rows, and their takes keep the
    close-match small syllables. A data test checks each row take changes only its own dimension.
  - New `rows-contrast` (take `photography-take04-weak-contrast`: smaller HAR and LOOKS bars, nothing else).
  - "Too much contrast is always last" lost its only fixture, so `feedback-too-much-contrast-last` (take
    `photography-take04-strong-contrast-unreduced`, the round-3 strong-contrast take) now covers it.
    `rough-timing-first` still covers rough-first and the 3-row cap.
  - `inc-targetWordsMissing-many` is unchanged.
  - This supersedes round 3's notes on `photography-rising-end`, on `rows-range` carrying the contrast row, and on
    there being no too-little-contrast fixture.
- **Fixes round 5 (2026-11-23).** The Designer's follow-ups after PR #21:
  - **1200 × 800 pt reference frames.** Round 4's frames held a window of about 1020 × 684 pt drawn into
    2400 × 1600 px. The test VM's screen is narrower than 1200 pt, and AppKit shrinks a window that doesn't fit its
    screen when the window is ordered front (`constrainFrameRect`). The renderer's window now keeps the size it is
    given (`WindowRenderer.RenderWindow`), and the capture throws `wrongSize` unless the frame view and content view
    are exactly the requested size. Measured against `mockup-*-final2@2x.png`: the sidebar edge, card edges, card 1
    top and pitch card bottom now land within 2 px (1 pt) of the mockups (they were 10–28 px off).
  - **Narrow windows.** The label rule lives in `AccentMirror/Design/LabelLayout.swift`, and its tests in
    `AccentMirrorScreenshots/LabelLayoutTests.swift`. Widths come from `TextMeasure` (the role's bundled face, size
    and tracking). Round 5's toolbar order (Model and You as play icons first) is superseded by r4 C7 (round 5b).
  - **Fixture `window`.** States can name their window size (`SCHEMA.md`). `scripts/check-screenshots.sh` reads
    each fixture's size. Round 5 rendered `narrow-inspector-open` at 960 × 732 and blamed card 1's wrapped rows for
    the extra height. That was wrong (see round 5b): something keeps 680 pt below the 52 pt title bar.
  - **One test case per frame.** `ScreenshotTests.render` is parameterised over every fixture × appearance, so each
    case builds, captures and tears down its own window. Its frames were byte-identical (SHA-256 of all 128) to
    round 4's last run. The "excessive live window count" warning still shows once per run: the log line per case
    shows no window is freed before the next one, even after a second's wait (an open point).
  - 65 states now (64 plus `narrow-inspector-open`), 130 frames.
- **Fixes round 5b (2026-11-23).** The Designer's review of PR #29, built against Addendum r4 (C1–C9):
  - **C4.** `photography-take04-strong-contrast` and `-unreduced`: HAR and LOOKS 1.0, TOG back to 1.0 (native's
    relative height; round 4 had shrunk it to 0.72), is 0.11, der 0.10 and it 0.07 (the 2× limits are 0.122, 0.111
    and 0.075); everything else as the close-match take. In `feedback-too-much-contrast-last` the reduction row now
    names ra, phy and than: der is HAR's neighbour, which C4 lowers, so it can't also read as unreduced.
    `ShellContractTests.tooMuchContrastStripShowsMoreContrast` checks the ratios on both fixtures.
  - **C1.** `phrases/photography-question`'s band from HARDER's end: an easing descent to a −3.5 st dip at
    t 0.81 (start of LOOKS), then a concave-up rise to 8.8 st (87% of the ±12 st plot; TOG peaks at 7.6 st, 82%),
    with the last span flatter. `questionRiseHasTheR4Shape` checks the dip, the concave-up slopes, the flattening,
    the end height and that the descent has no kink.
  - **C6.** The target set and the hide order are as above; `LibraryManifest.Phrase` gained optional `targets`.
  - **C7.** `ToolbarCompaction.decide` (pure: available width, the title's natural width and the controls' widths
    in; level, title width and whether it fits out) and `ToolbarView.controlWidths` (measured from the same faces and
    symbols). `ToolbarCompactionTests` covers each step, the title giving way before Model and You change, the
    gaps never shrinking, and logs the real numbers at 960 pt with the inspector open: 408 pt available; controls
    at their most compact 238 pt (Model 54, Record dot 40, You 39, take-menu chevron 28, toggle 28, gaps 8, 8, 17
    and 16), plus the 16 pt title gap and the 160 pt title, is 414 pt. So it doesn't fit by 6 pt, and the title gets
    154 pt (an open point for Designer).
  - **C8.** `DetailContent` puts the cards in a `ViewThatFits`: as they are when they fit, else in a vertical
    `ScrollView` (the toolbar is outside it). The pitch plot's `GeometryReader` has a minimum of 120 pt plus the
    22 pt word-label row. `ShellView` now applies its 960 × 680 minimum before `ignoresSafeArea`, and `WindowChrome`
    leaves the 52 pt title bar out of `contentMinSize`. Even so, the renderer's 960 × 680 window still comes out
    960 × 732. The size error now reports `contentMinSize` 0 × 0, `minSize` 0 × 0 and a `contentLayoutRect` of
    960 × 680, so 680 pt is held below the title bar by something else. Open, see PR #29.
  - **C5** is round 5's geometry fix, unchanged. **C9:** the window-count warning stays an open point; it doesn't
    block design sign-off.
  - The last full render run is `20261123-144014` (everything passed except `narrow-inspector-open`). The test VM's
    disk then filled up (ENOSPC under `wg-results` in run `20261123-144236`), so this round has no final pair of
    runs and the committed frames are round 5's.
