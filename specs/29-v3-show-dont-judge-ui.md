# 29: v3/v3.1 show-don't-judge UI (YOUR TAKE, Play Both, strip, inspector, earlier takes; fixture-driven)

Status: Ready · Branch: – · Depends on: 28 (scoring off, expected stress, descriptive measures), 19 (fixture-driven UI shell; builds on top of PR #29, the specs 18–19 fixes round 5, which must be merged first and isn't folded in here) · Estimate: 8–10 h agent run + 2 h Raph review

Source: Designer spec v3 (Notion "Accent Mirror v1: show, don't judge", https://app.notion.com/p/4220d0d4459281d39d67d6fdc5d50dfc; mockups in `v3/` of the design folder: `mockup-result-{light,dark}-v3@2x.png`, `mockup-error-{light,dark}-v3@2x.png`, `inspector-this-take-{light,dark}-v3@2x.png`). v3 wins over Designer spec v2 and addenda r2–r6, and replaces v2's result design while keeping the rest. **The v3.1 addendum** ("Addendum 2026-11-24 (v3.1)", V1–V6, at the end of the same page) wins over v3. Its mockups are `mockup-result-{light,dark}-v3.1@2x.png`, `mockup-error-{light,dark}-v3.1@2x.png` and `inspector-this-take-{light,dark}-v3.1@2x.png` in the design folder's `v3/`, and they replace the v3 mockups for this spec. The plan: https://app.notion.com/p/4220d0d4459281399adef9364a99bb69.

Reviews: the screens are taste calls, so the review verdict is `hold` and Raph tries the build before it merges. It must not touch `Thresholds.swift`, `project.yml`, entitlements, `Resources/Models/` or `Resources/Starter/`.

**If PR #29 isn't merged on main when the build starts,** report `Blocked: needs #29 merged` and stop. Don't fold #29's changes in.

## Goal

The fixture-driven app shows v3's result screen. Your pitch and timing are drawn over the native reader's, along with the native range, your earlier takes and plain measures. There's no right or wrong anywhere. Live data and audio arrive in spec 21. This spec draws them from fixtures, with an injected clock.

## Behaviour

### 1. Card 1: always YOUR TAKE (v3 §3.1)

- The title is always "YOUR TAKE". "WHAT TO CHANGE" doesn't appear in any v1 state.
- **Result row:**
  - a 16 pt overlay icon (two waves, one soft and one thin, `text.secondary`);
  - "Your take is drawn over the model's. Play them back to back, then try another take." in Geist 13;
  - at the right, a **Play Both** ghost button (`surface.well`, 28 tall, radius 6, play triangle), with the tooltip "Play the model, then your take".
- **Play Both** plays the model's phrase, a 0.4 s pause, then your take, with the playhead. It's also in the menu as Take ▸ Play Model, Then You (⌥⌘L). Play Model (⌘L) and Play You (⇧⌘L) are unchanged. Here it runs on the injected clock; spec 21 wires the audio.
- **At most one quiet line**, Geist 12 secondary with `info.circle`. It's never counted as a row. The first that applies shows:
  1. low coverage: when `AnalysisResult.comparableCoverage` (added in spec 28, CTO must-fix 3) is non-nil and low
     (the `result-coverage-low` fixture encodes this; live wiring in spec 21 reads the same field). Don't invent a
     second coverage field;
  2. rough timing (`timing == .rough`);
  3. inserted words.
  The copy is v3 §3.1's, word for word.
- Card 1's other states (no takes yet, recording with the E5 meter, analysing, take problems, unalignable) keep v2's layout with v3 §5's copy.
- No diff, close, noClearDifference or inconclusive row exists in any v1 state.

### 2. Strip (v3 §3.2, with v3.1 V1–V3)

- Two rows, NATIVE and YOU, each on its own timeline with pauses trimmed. The bars are each recording's real envelope.
- **Neutral bars in both rows (V1):** every Native and You bar is `strip.bar`, at the speaker's real envelope height, with no Lime fill and no stress scaling. The You row doesn't use `youBar`. Recording bars are as in A3.
- **Dictionary-stress dot (V2), native row only:**
  - a 4 pt dot (2 pt radius) in `lime`, centred under the syllable label, with its centre 19 pt below the label's top;
  - on the syllable spec 28 gives as the context-resolved primary (starter override or part-of-speech variant), never the raw CMUdict primary.
  - Native labels on those syllables stay **bold caps**, so the dot is never the only cue.
  - A dot on a short bar is expected, and nothing changes when the dot and the tallest bar disagree.
  - Ambiguous words (OOV, or no single context pronunciation) get no dot and no caps. Tooltip: "This word can be said more than one way."
- **Learner row is neutral (V3):** your labels are all lowercase, regular weight, `text.tertiary`. No dot, no caps, no Lime. Missing, substituted and inserted words follow v3 §3.4.
- **Legend** at the top right: the dot, then "Dictionary stress" (Geist 12, `text.secondary`).
- **Timing connectors:**
  - a 1 pt line in `text.tertiary` at 50% (100% with Increase Contrast), from each native syllable to the top of your matching syllable. It starts at `label top + 17`, or `label top + 23` (4 pt below the dot) for a dotted syllable (V2);
  - none for missing or inserted words.
  - Matching comes from spec 28's alignment and syllables. The presenter doesn't do new matching.
- **Words (v3 §3.4):**
  - **Substituted:** `strip.bar` bars and the heard word in italic quotes. Tooltip: "Heard "photograph" here."
  - **Missing:** the dashed 24 pt slot, the expected word tertiary with **no strike-through**, and the tooltip "Not in your take." Clicking it plays the model only.
  - **Inserted:** grey bars and "+ so", not drawn on the pitch chart.
- **Interaction (v3 §3.5):**
  - Clicking a label loops model, 0.4 s, you until Esc, with the `highlight` box and "Looping "{word}" · Esc to stop".
  - The syllable being played gets an outline (r6 E4).
  - There's no diff-row hover.

### 3. Pitch card (v3 §3.3)

- As in v2 §9: the native band, your 2 pt line, breaks only at pauses over 250 ms and alignment gaps, HIGH/LOW, word labels, the faint native texture and the wash.
- **No Lime segments on the pitch baseline (V5).** The baseline is a plain hairline, so dictionary stress has one mark in one place: the strip dot. Lime on the result screen is only the Record button, the sidebar selection, the wash, the strip dots and the legend dot.
- **The native band is display-only (V4).** Its legend label is "Native range", and the end label on the right stays "Native". No colour, icon, copy or motion changes when your line is outside the band. Your line keeps one colour everywhere.
- **Earlier takes on by default:**
  - up to the 3 previous saved takes, as 1 pt lines in `pitch.you` at 30%, 20% and 12%, newest strongest;
  - hovering a take in the open take menu previews it as the only ghost;
  - unalignable takes are never drawn.
  - View ▸ Show Earlier Takes (⇧⌘G) toggles them. It's on by default, and the choice is remembered (UserDefaults).
- **Legend** at the top right, Geist 12 secondary: a 2 pt line "You", a soft ribbon "Native range" and a faint 1 pt line "Earlier takes".
- AXChartDescriptor series: Native range, You, Earlier takes.

### 4. Inspector (v3 §4)

- **THIS TAKE:** three columns, MEASURE, YOU and NATIVE RANGE (V4 header), at 13 pt with 32 pt rows.
  - The rows are Length, Syllables per s, Pitch range (P10–P90), Rhythm (nPVI) and Ends, from spec 28's `describe`.
  - Ends shows a count for natives ("5 falling, 3 rising").
  - Under the table (V4): "Native range is the spread across the {n} native voices for this phrase." A single native take shows that take's value.
- **A value outside the native range isn't marked:** no icon, colour or bold. A missing measure shows "—" with its reason in the tooltip.
- Rhythm tooltip: "How much syllable lengths change from one syllable to the next."
- **The rest of the inspector:**
  - **ALIGNMENT** reads **Clear** or **Rough**, with the note "how closely your syllables lined up" and no icon. This renames v3's TIMING MATCH "Good / Rough" (Designer, v3.1). The v3.1 inspector mockup still shows the old label; the text wins.
  - MODEL RECORDING keeps the attribution and the voice pop-up (r6 E7, from spec 15's `accent`, `region` and `gender`).
  - INPUT and PHRASE are as in r6.
- **Gone:** STRESS lines, stress contrast, weak syllable length, pitch shape match, noClearDifference reasons and diff icons.

### 5. Tokens and copy (v3 §5–6)

- **`mistake` is retired but reserved:** it stays in the token file, and no v1 view references it.
- No new tokens. Connectors use `text.tertiary`, ghosts use `pitch.you`, and legends use existing tokens.
- **Copy:** v3 §5's table, word for word (result row, too short, too quiet with the icon in `text.secondary`, B7 captions, unalignable, modelUnavailable, inferenceFailed stages, the E2 note). VoiceOver after a result: "Result ready. Your take is drawn over the model's."
- **Banned words:** no v1 string (copy, tooltip or VoiceOver) contains wrong, mistake, correct, better, worse, stronger, softer, soften, should, make, "close to the model", "no clear difference", or a score, nor (V4) target or outside.

### 6. Fixtures (v3 §10)

- **Retire (delete):**
  - `result-feedback`, `rough-timing-first`, `rows-contrast`, `rows-range`, `rows-final-direction-higher`, `rows-final-direction-lower`, `rows-too-much-contrast`;
  - `feedback-too-much-contrast-last`, `feedback-quiet-priority`, `feedback-partial`, `feedback-nonTargetWordsIncomplete`;
  - `close-all`, `close-placement-only`, `close-stress-rhythm`, `placement-only-too-few-unstressed`;
  - every `inc-*` (8) and `ncd-*` (6);
  - `stress-match-p311`, `stress-like-p311`, `stress-differs-but-accepted`, `stress-lowConfidence`, `words-referenceAnomaly`.
- **Change:**
  - `tooQuiet`, `tp-tooShort`, `unalignable`, `words-missing`, `words-substituted`, `words-expectedAmbiguous`;
  - `feedback-insertions` and `feedback-two-insertions`, renamed `result-insertions` and `result-two-insertions`;
  - `inspector-open`, `narrow-inspector-open`, `op-modelUnavailable`, `op-inferenceFailed`.
- **New:** `result` (with 2 earlier takes), `result-earlier-takes-off`, `result-timing-rough`, `result-coverage-low`, `result-one-native`, `playing-both` (playhead in your half), and **`stress-dot-short-bar`** (v3.1). In that one, the native final syllable is dotted while its bars are shorter than an undotted syllable's, and the snapshot shows no other change.
- **Re-rendered for the dot (v3.1):** `result`, `result-earlier-takes-off`, `tooQuiet`, `words-expectedAmbiguous`.
- Every fixture's analysed state is `.notScored`.

## Defaults

- Earlier takes are on.
- The dot sits on the native row only (v3.1 V2).
- The band label is "Native range".
- The quiet-line order is coverage, then timing, then insertions.

## Guardrails

- No view reads `Verdict`, `DiffRow`, `StressLine` or measure states (spec 28's source scan stays green).
- No red, yellow, amber, gold or purple. No triangles, dotted underlines or strike-throughs.
- No new tokens. Reduce Motion and Increase Contrast behave as in v2 and r6.
- No secrets or personal paths.

## Out of scope

- Live microphone, audio playback and coordinator wiring (spec 21). The live strip, playhead motion and voice-switch ease (spec 20).
- Milestone 2's slots (v3 §9).

## Open question (built with the default)

1. **Resolved by v3.1 (V1, V2, V6):** neutral bars in both rows, and a Lime dot under native labels only, from context-resolved stress, with bold caps kept on those labels. v3.1's acceptance criterion 3 replaces v3's: "Lime in the strip appears only as dots under native labels on context-resolved stressed syllables; no strip bar uses Lime; your row has no caps or dot".
2. **The inspector's NATIVE RANGE column** next to your values (v3 §14 call for Raph). Default: shown, unmarked.
3. **Timing connectors and earlier takes on by default** (v3 §14 calls). Default: both on.

## How to test (Raph)

1. `make review PR=<n>`, then `make check` and `make test-ui-vm`. Every new and changed fixture renders in light and dark, and Reduce Motion. `scripts/check-screenshots.sh` finds no blank frame. **pass/fail**
2. A test over views and `Copy.swift` finds none of the banned words (target and outside included), no `mistake` token reference, and no triangle, dotted-underline or strike-through drawing. **pass/fail**
3. The `result` fixture matches `mockup-result-{light,dark}-v3.1@2x.png`:
   - YOUR TAKE, the result row and Play Both;
   - neutral `strip.bar` bars in both rows;
   - the Lime dot under the bold-caps native stressed labels only, and your labels lowercase tertiary;
   - connectors;
   - no Lime on the pitch baseline;
   - the legends ("Dictionary stress", "Native range");
   - 2 earlier takes at 30% and 20%.
   **taste call (Raph)**
4. `stress-dot-short-bar`: the dotted native final syllable has shorter bars than an undotted one, and nothing else differs. **pass/fail**
5. ⌥⌘L in the `playing-both` fixture: model, 0.4 s, you, with the playhead (injected clock). **pass/fail**
6. ⇧⌘G hides the earlier takes. Relaunch: still hidden. ⇧⌘G again shows them. **pass/fail**
7. `inspector-open` matches `inspector-this-take-*-v3.1@2x.png` (header NATIVE RANGE, v3.1 note), except ALIGNMENT "Clear / Rough" replaces the mockup's TIMING MATCH "Good". A value outside the native range looks like every other value. "—" has a tooltip. **taste call (Raph)**
8. `result-timing-rough` with insertions shows only the rough-timing line. `result-coverage-low` shows only the coverage line. **pass/fail**
9. Every retired fixture is gone from the Samples menu, and no `inc-*` or `ncd-*` file is left. **pass/fail**

## Implementation notes

Hand build (Claude Code, 2026-11-24, on Raph's "go merge / no ci / just yolo"). CI, `make test-vm` and the UI/screenshot
tests (`make test-ui-vm`) were skipped on Raph's instruction. `make build`, `make check-corpus` and
`make check-ui-frameworks` pass on the host, and the named unit tests pass there (`_cache-29/gate.sh`, 42 tests).
`AccentMirrorScreenshots` (app-hosted) compiles with `build-for-testing` but wasn't run.

**Where things live**
- `AccentMirror/Fixtures/ResultLogic.swift` holds the v3/v3.1 rules as pure functions of fixture values, with no SwiftUI and
  no AMCore: `StressMarks` (the dot and caps go on the word's single context-resolved primary from `expectedStress`,
  and a word without one is ambiguous), `ResultQuietLine` (coverage, then timing, then insertions),
  `EarlierTakes` (30/20/12 %, at most 3, never unalignable) and `EarlierTakesPreference` (UserDefaults key
  `ShowEarlierTakes`, on by default). It also has `PlaybackSchedule`, `PlaybackRun` and `PlaybackClock` (Play Model,
  Play You, Play Both, and the label loop, all on an injected clock), plus `TimingConnectors` and `ThisTake` (the
  inspector table). `AccentMirrorTests/ResultLogic.swift` is a **symlink** to it, so the unhosted test target compiles
  the same file without a `project.yml` change (see Hand follow-up).
- `ShellPresenter` now has card 1's result row (overlay icon, Play Both) with at most one quiet line. The strip has
  neutral bars, native dots and caps, your plain labels and connectors. The pitch card has earlier takes, a plain
  baseline and no stressed spans. The inspector is now a struct (`InspectorPresentation`). Low coverage means below
  `Thresholds.current.decision.minComparableCoverage`: the presenter imports `AMCore` (already linked through
  `AMPipeline`) and adds no second coverage field.
- `ShellModel` holds the loaded fixture, the ⇧⌘G state, the playback run and the looping word, and posts the VoiceOver
  announcement "Result ready. Your take is drawn over the model's." when a result is applied. Menus: View ▸ Show
  Earlier Takes (⇧⌘G), and Take ▸ Play Model (⌘L), Play You (⇧⌘L), Play Model, Then You (⌥⌘L) and Stop (Esc).
- Views: `CardOneView` (overlay glyph, Play Both ghost button, quiet line), `StripCard` ("Dictionary stress" legend,
  `StressDot`, `Connectors`, `Playhead`, label click to loop, missing word click to play the model, no strike-through),
  `PitchCard` (legend, earlier takes, plain hairline baseline, `AXChartDescriptor` with Native range, You and Earlier
  takes) and `InspectorContent` (THIS TAKE grid, ALIGNMENT, MODEL RECORDING, TAKE).
- `VerdictSentences.swift` and `VerdictPresentation.swift` are deleted, and so are the fixture model's
  `DiffRow`, `MeasureState`, `StressLine`, `Inconclusive`, `QuietNotes` and the `mistake` label. `Verdict` decodes
  `notScored` only.

**Fixtures**: the 20 named retired states, every `inc-*` (8) and every `ncd-*` (6) are deleted. `feedback-insertions` and
`feedback-two-insertions` are renamed `result-*`. The new states are `result`, `result-earlier-takes-off`,
`result-timing-rough`, `result-coverage-low`, `result-one-native`, `playing-both` and `stress-dot-short-bar` (phrase
`photography-looks-short`: only LOOKS's envelope drops, to 0.2, below the undotted syllables'). The new takes are
`photography-take02` and `photography-take01`: synthetic earlier takes, take 03's pitch flattened. Every analysed state
is `{"notScored": {}}` (`result-no-verdict` keeps no verdict) and carries `describe`. Phrases carry `expectedStress`
(from the old caps labels; ambiguous words get none), and syllables lose `stressed` and `label`. Takes and phrases
that no state uses any more are deleted. The schema is in `Fixtures/SCHEMA.md`.

**Tests**: `AccentMirrorTests/ShowDontJudgeTests.swift` has `V3FixtureTests`, `BannedWordTests` (string literals in every
app Swift file against v3 §5 plus target, should and outside, no `.mistake` outside the token file, no `"triangle`
symbol, strike-through or underline, no hard-coded colours), `StressDotTests`, `QuietLineTests`, `EarlierTakesTests`
(with relaunch persistence through a fresh `UserDefaults` suite), `PlayBothTests`, `ConnectorTests` and
`ThisTakeTests`. `FixtureLibraryTests` checks that every analysed fixture is not scored. `ShellContractTests` (app-hosted)
is rewritten for v3, and its verdict-era tests are deleted.

**Spec gaps (least-committal defaults)**
1. `inferenceFailed`'s v2 frame "Something went wrong inside Accent Mirror while {stage}" breaks the ban on "wrong".
   It now reads "Accent Mirror ran into a problem while {stage}. This isn't about your take." Designer to confirm.
2. The note under THIS TAKE for a single native take has no copy ("8 native voices" doesn't fit one), so it's left
   out and the column shows that take's values.
3. The tooltip reasons for a missing measure ("—") have no written copy. These were written, neutral:
   "No pitch was found where this measure reads.", "This needs at least 3 syllables.", "Too little pitch at the end
   of the take to read its direction." and "None of the phrase's words were heard."
4. There's no `highlight` token on main (r6 E3 was never built) and no new tokens are allowed, so label hover and the
   loop box aren't drawn, and neither is r6 E4's outline on the syllable being played. The loop itself works (model
   slice, 0.4 s, your slice, until Esc), with its caption at the strip's top right.
5. Hovering a take in the open take menu to preview it: `EarlierTakes.preview` exists, but the toolbar's SwiftUI
   `Menu` gives no item hover, so it isn't wired (spec 21's live take menu).
6. INPUT and PHRASE (r6) were never built in this shell, so they aren't added. The MODEL RECORDING voice pop-up is a
   fixture-only menu that lists the voices.
7. Inspector row names follow the v3.1 mockup ("Pitch range"), not the spec text's "Pitch range (P10–P90)".
8. Substituted words get connectors, since only missing and inserted words are excluded. Words with
   `referenceAnomaly` have no `expectedStress`, so they get no dot and show the ambiguous tooltip.
9. The playhead is a 2 pt `text.primary` line on the row that is playing (Lime is reserved; no token is named).
10. `stripBarYou` is unused now (V1) but stays in the token table. `mistake` stays reserved.
11. `result-not-scored` and `result-no-verdict` (spec 28) stay. They show the v3 result too.

**Hand follow-up for Raph**
- `project.yml`: add `AccentMirror/Fixtures/ResultLogic.swift` to the `AccentMirrorTests` sources and delete the
  `AccentMirrorTests/ResultLogic.swift` symlink. Also delete the `Fixture result-feedback`,
  `Fixture inc-requiredMeasureUnavailable-lowConfidence` and `Fixture ncd-insertionsPresent` schemes, whose fixtures
  are retired (maybe add `Fixture result`).
- Run `make test-ui-vm` for the screenshots (light, dark, Reduce Motion) and the app-hosted `ShellContractTests`.
