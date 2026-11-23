# 19: Fixture-driven UI shell

Status: Draft · Branch: – · Depends on: 18 (UI foundation) · Estimate: 6–8 h agent run + 1.5 h Raph review

Source: Designer spec v2 (Notion "Accent Mirror spec v2 (2026-11-23)"), including Addendum 2026-11-23 (r2), which wins wherever it differs. Engineering review proposing rows 18–21. Plan v2, approved 2026-11-23 09:56 Europe/Paris. Reference mockups: `mockup-{result,empty,recording,error}-{light,dark}-final2@2x.png` (2400 × 1600 px for a 1200 × 800 pt window). This spec does not depend on spec 11 (scoring).

## Goal

Render every milestone-1 UI state from Designer's spec v2 and Addendum r2, driven only by committed JSON fixtures, and capture scripted native light and dark screenshots of each state from a test target. No hand-clicking, no microphone, no live analysis, no scoring.

## Behaviour

### Fixture-driven rendering

- Every state below is produced by loading a named JSON fixture and rendering the spec 18 shell with that data. The app does not record, import, or analyse audio to show these states.
- Fixtures live in the app target (for example `AccentMirror/Fixtures/`). They use the plan v2 contract names (`feedback`, `close`, `noClearDifference`, `inconclusive`, `partial`, take problems, operational errors, `MeasureState`, `AlignedWordPair`, and so on). When spec 01 later freezes those types, any drift is fixed by updating the fixtures, not by inventing a parallel UI model.
- A launch argument `-UIFixture <name>` (and a "render all" entry point for the screenshot runner) selects the fixture. Appearance is forced light or dark by the runner, not by clicking the system control.
- The selected sidebar phrase in the four mocked states is "Photography is harder than it looks." under My Phrases, subtitle "My Phrases · From demo-talk.m4a", as in the final2 mockups.

### Addendum rules that win over earlier sections

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

**noClearDifference** (card 1 titled "WHAT TO CHANGE", icon `equal.circle`, secondary). Show the first reason; inspector lists all present:

15. `ncd-pitchShapeBelowClose` — "No clear difference in stress or rhythm. Your pitch moves a little differently from the model's, but not in one place we can point to."
16. `ncd-optionalMeasuresUnavailable` — "No clear difference in stress or rhythm. Some pitch measures couldn't be taken on this take."
17. `ncd-mediumConfidenceOnly` — "Nothing stood out clearly enough to point at. Try another take to check."
18. `ncd-timingRough` — "No clear difference, but the timing match was rough, so small differences may be hidden."
19. `ncd-nonTargetWordsIncomplete` — uses the A6 quiet line (this reason has no separate §13.1 sentence).
20. `ncd-insertionsPresent` — uses the A6 quiet line.

**inconclusive** (icon `questionmark.circle`, secondary; Try Again unless noted; no blue, no take-problem styling):

21. `inc-targetWordsMissing-one` — "We didn't hear "explained", so we can't check its stress. Say the whole phrase and try again."
22. `inc-targetWordsMissing-two` — two words, "explained" and "rainbow".
23. `inc-targetWordsMissing-many` — "some of the key words".
24. `inc-timingUnreliable` — "We couldn't line your take up with the model well enough to compare. Try again at an even pace."
25. `inc-comparableCoverageLow` — "Only part of your take lined up with the model (about 55%). Say the whole phrase in one go." The % is rounded to 5 and comes from the fixture.
26. `inc-requiredMeasureUnavailable` — "We couldn't measure stress on this take. Try again a little louder and closer to the mic."
27. `inc-requiredMeasureUnavailable-lowConfidence` — "We couldn't tell your stress clearly on this take. Try again a little slower."
28. `inc-noApplicableStressMeasure` — "This phrase has no word long enough to check stress on. The charts still show your rhythm and pitch." No button.

**Take problems** (card 1 titled "YOUR TAKE"; only the first problem in plan order). Copy and icons as Designer spec v2 §11.1:

29. `tp-noMicrophone` — Record disabled, no Try Again.
30. `tp-micDenied` — "Open System Settings…" (the button may be inert in fixtures).
31. `tp-noSpeech`
32. `tp-tooShort` — You enabled if the fixture says audio is present; take menu "LAST TRY · NOT SAVED".
33. `tp-clipped` — same unsaved-attempt menu rule.
34. `tp-wordsDontMatch`

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
50. `noVoicedFrames` — native band as usual, "No pitch to show for this take" centred in Geist 12 secondary. Inspector pitch measures show "—", never zero, with "Not measured: too little voicing".
51. `rough-timing-first` — rough-timing row first, at most 3 rows in total.
52. `inspector-open` — Details inspector visible, listing measure states (`evaluated` / `unavailable` / `notApplicable` with reasons), STRESS lines, and save state when the take is not saved.
53. `coming-soon-expanded` — Noun and Verb Pairs expanded to the non-selectable "No phrases yet…" line.

Diff-row kinds, order, icons and sentences that are not already covered by the result mockup (range, final direction, too much contrast) each have a fixture so their copy can be screenshotted.

Hover ghosts, Option-to-show-earlier-takes, and the 150 ms voice-switch ease may be still in 19 (a fixture that *would* show ghosts is enough if the still cannot animate). They are finished in spec 20. The recording playhead must be visible in the `recording` screenshots. Interpolated pitch (45% opacity, 1.5 pt) and breaks at pauses over 250 ms / `modelOnly` / `youOnly` should already follow Designer spec v2 §9 and §13.7 when the fixture provides that geometry, so the written states are honest.

### Scripted screenshots

- Add a screenshot **test target** (or an equivalent test-hosted runner) that, for each fixture × {light, dark}, opens a 1200 × 800 pt window, seeds that fixture, and writes a PNG at 2× (2400 × 1600). One command regenerates the whole set. Running it twice produces the same images.
- No hand-clicking, no cursor, no dev overlays, no live user data. No microphone, no network, no WhisperKit.
- **This target is not run by CI and is not part of `make check`.** AGENTS.md stands: CI never launches the app, never uses the microphone, never runs UI tests. Implementation of this spec may add a local `make screenshots` target; it must not be called from `.github/workflows/ci.yml`.
- Output goes to a gitignored or reviewed-artifact folder (for example `screenshots/ui-shell/`), named `<fixture>-{light,dark}@2x.png`. The four primary states are compared against the final2 mockups. The other states are the set sent back to Designer.

### Visual and copy rules already in spec 18 that this shell must keep

Tokens, fonts, grain, sidebar selection (pick B), secondary pack headers, contrast, no red/purple/gold/amber, disabled buttons as no fill plus tertiary text, and the wordmark all still apply. A mistake is always blue + triangle + dotted underline together. Dictionary / accepted stress is caps labels; measured prominence is bar height and Lime.

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

_(filled in by the agent)_
