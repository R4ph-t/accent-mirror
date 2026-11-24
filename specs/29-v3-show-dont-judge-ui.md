# 29: v3 show-don't-judge UI (YOUR TAKE, Play Both, strip, inspector, earlier takes; fixture-driven)

Status: Ready · Branch: – · Depends on: 28 (scoring off, expected stress, descriptive measures), 19 (fixture-driven UI shell; builds on top of PR #29, the specs 18–19 fixes round 5, which must be merged first and isn't folded in here) · Estimate: 8–10 h agent run + 2 h Raph review

Source: Designer spec v3 (Notion "Accent Mirror v1: show, don't judge", https://app.notion.com/p/4220d0d4459281d39d67d6fdc5d50dfc; mockups in `v3/` of the design folder: `mockup-result-{light,dark}-v3@2x.png`, `mockup-error-{light,dark}-v3@2x.png`, `inspector-this-take-{light,dark}-v3@2x.png`). v3 wins over Designer spec v2 and addenda r2–r6. It replaces v2's result design and keeps the rest. Designer's v3 changes as relayed to Accent Mirror Lead at 18:55 Europe/Paris on 2026-11-24 win where the Notion text differs (see Open question 1). The plan: https://app.notion.com/p/4220d0d4459281399adef9364a99bb69.

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
  1. low coverage;
  2. rough timing;
  3. inserted words.
  The copy is v3 §3.1's, word for word.
- Card 1's other states (no takes yet, recording with the E5 meter, analysing, take problems, unalignable) keep v2's layout with v3 §5's copy.
- No diff, close, noClearDifference or inconclusive row exists in any v1 state.

### 2. Strip (v3 §3.2, as revised)

- Two rows, NATIVE and YOU, each on its own timeline with pauses trimmed. The bars are each recording's real envelope.
- **Neutral bars in both rows, with no Lime fill.** Unstressed colours are as in B6, recording bars as in A3.
- **Dictionary-stress dot:** a **4 pt Lime dot under the syllable label, on the native row only**, on the syllable spec 28 gives as the context-resolved primary (starter override or part-of-speech variant). Never the raw CMUdict primary. Ambiguous words (OOV, or no single context pronunciation) get no dot and no caps. Their tooltip reads "This word can be said more than one way."
- **Labels:**
  - Both rows use the same labels: context-stressed syllables in bold caps, the rest lowercase secondary.
  - Your row doesn't follow what was heard, except for missing, substituted and inserted words (v3 §3.4).
  - No label ever gets a marker.
- **Legend** at the top right: the Lime dot glyph and "Dictionary stress".
- **Timing connectors:**
  - a 1 pt line in `text.tertiary` at 50% (100% with Increase Contrast), from the bottom of each native syllable label to the top of your matching syllable;
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

- As in v2 §9: the native band, your 2 pt line, breaks only at pauses over 250 ms and alignment gaps, HIGH/LOW, word labels, the faint native texture and the wash. The Lime baseline segments sit under the context-stressed syllables.
- **The native band is display-only and labelled "Native range".** No colour, icon, copy or motion implies that outside the band is wrong. Your line keeps one colour everywhere.
- **Earlier takes on by default:**
  - up to the 3 previous saved takes, as 1 pt lines in `pitch.you` at 30%, 20% and 12%, newest strongest;
  - hovering a take in the open take menu previews it as the only ghost;
  - unalignable takes are never drawn.
  - View ▸ Show Earlier Takes (⇧⌘G) toggles them. It's on by default, and the choice is remembered (UserDefaults).
- **Legend** at the top right, Geist 12 secondary: a 2 pt line "You", a soft ribbon "Native range" and a faint 1 pt line "Earlier takes".
- AXChartDescriptor series: Native range, You, Earlier takes.

### 4. Inspector (v3 §4)

- **THIS TAKE:** three columns, MEASURE, YOU and NATIVE RANGE, at 13 pt with 32 pt rows.
  - The rows are Length, Syllables per s, Pitch range (P10–P90), Rhythm (nPVI) and Ends, from spec 28's `describe`.
  - Ends shows a count for natives ("5 falling, 3 rising").
  - Under the table: "Native range shows the range across the {n} native voices for this phrase." A single native take shows that take's value.
- **A value outside the native range isn't marked:** no icon, colour or bold. A missing measure shows "—" with its reason in the tooltip.
- Rhythm tooltip: "How much syllable lengths change from one syllable to the next."
- **The rest of the inspector:**
  - TIMING MATCH reads Good or Rough, with the note "how closely your syllables lined up" and no icon.
  - MODEL RECORDING keeps the attribution and the voice pop-up (r6 E7, from spec 15's `accent`, `region` and `gender`).
  - INPUT and PHRASE are as in r6.
- **Gone:** STRESS lines, stress contrast, weak syllable length, pitch shape match, noClearDifference reasons and diff icons.

### 5. Tokens and copy (v3 §5–6)

- **`mistake` is retired but reserved:** it stays in the token file, and no v1 view references it.
- No new tokens. Connectors use `text.tertiary`, ghosts use `pitch.you`, and legends use existing tokens.
- **Copy:** v3 §5's table, word for word (result row, too short, too quiet with the icon in `text.secondary`, B7 captions, unalignable, modelUnavailable, inferenceFailed stages, the E2 note). VoiceOver after a result: "Result ready. Your take is drawn over the model's."
- **Banned words:** no v1 string contains wrong, mistake, correct, better, worse, stronger, softer, soften, should, make, "close to the model", "no clear difference", or a score.

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
- **New:** `result` (with 2 earlier takes), `result-earlier-takes-off`, `result-timing-rough`, `result-coverage-low`, `result-one-native`, `playing-both` (playhead in your half).
- Every fixture's analysed state is `.notScored`.

## Defaults

- Earlier takes are on.
- The dot sits on the native row only.
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

1. **Strip Lime.** The Notion v3 text (last edited 18:52 Europe/Paris) says Lime bars on the dictionary-stressed syllables in **both** rows, with criterion 13.3, "same syllables in both rows". Designer's v3 summary relayed at 18:55 says neutral bars in both rows and a **4 pt Lime dot under the native label only**. Default: the dot, native only, which also matches CTO's native-only rule. Designer confirms in review.
2. **The inspector's NATIVE RANGE column** next to your values (v3 §14 call for Raph). Default: shown, unmarked.
3. **Timing connectors and earlier takes on by default** (v3 §14 calls). Default: both on.

## How to test (Raph)

1. `make review PR=<n>`, then `make check` and `make test-ui-vm`. Every new and changed fixture renders in light and dark, and Reduce Motion. `scripts/check-screenshots.sh` finds no blank frame. **pass/fail**
2. A test over views and `Copy.swift` finds none of the banned words, no `mistake` token reference, and no triangle, dotted-underline or strike-through drawing. **pass/fail**
3. The `result` fixture matches `mockup-result-{light,dark}-v3@2x.png`: YOUR TAKE, the result row and Play Both; neutral bars, the Lime dot under native stressed labels only, and connectors; the legends; 2 earlier takes at 30% and 20%. **taste call (Raph)**
4. ⌥⌘L in the `playing-both` fixture: model, 0.4 s, you, with the playhead (injected clock). **pass/fail**
5. ⇧⌘G hides the earlier takes. Relaunch: still hidden. ⇧⌘G again shows them. **pass/fail**
6. `inspector-open` matches `inspector-this-take-*-v3@2x.png`. A value outside the native range looks like every other value. "—" has a tooltip. **taste call (Raph)**
7. `result-timing-rough` with insertions shows only the rough-timing line. `result-coverage-low` shows only the coverage line. **pass/fail**
8. Every retired fixture is gone from the Samples menu, and no `inc-*` or `ncd-*` file is left. **pass/fail**

## Implementation notes

_(filled in by the agent)_
