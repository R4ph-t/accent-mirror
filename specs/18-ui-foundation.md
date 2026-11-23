# 18: UI foundation

Status: Done · Branch: factory/18-19-ui-shell (PR #4), fixes on factory/18-19-fixes · Depends on: 00 (project skeleton) · Estimate: 3–5 h agent run + 1 h Raph review

Source: Designer spec v2 (Notion "Accent Mirror spec v2 (2026-11-23)", including Addendum 2026-11-23 (r2), Addendum 2026-11-23 (r3) and Addendum 2026-11-23 (r4, C1–C9); r4 wins over r3, r2 and spec v2, and r3 over r2 and spec v2, wherever they differ). Engineering review proposing rows 18–21. Plan v2, approved 2026-11-23 09:56 Europe/Paris. Reference mockups: `mockup-{result,empty,recording,error}-{light,dark}-final2@2x.png` (2400 × 1600 px).

## Goal

Replace the placeholder window with a native SwiftUI app shell that uses Accent Mirror's own visual identity: design tokens, bundled fonts, the grain tile, solid (non-glass) chrome, the sidebar, the toolbar and the wordmark. No analysis, no microphone, no scoring.

## Behaviour

### Window and chrome

- The app is a single `WindowGroup` for macOS 26, Swift 6, strict concurrency. Default size 1200 × 800 pt, minimum 960 × 680 pt. Resizing changes only the detail plot width and the pitch plot height (the pitch card fills what is left). A later spec draws those plots; this spec leaves a token-coloured empty detail surface that respects the card column.
- Layout is a sidebar (240 pt), a detail area, and a trailing Details inspector, closed by default. Prefer SwiftUI `NavigationSplitView`. All surfaces are solid. macOS 26 glass for the sidebar and the toolbar is turned off and replaced by the tokens below. No vibrancy, no blur. If `NavigationSplitView` cannot be made fully opaque, fall back to an AppKit split view with opaque `NSView` backgrounds and a custom toolbar surface (see Defaults).
- Toolbar height is 52 pt, drawn on `surface.base` (no separate bar fill). Outer padding 16 pt, inner padding and card gaps 8 pt. Card column x 256 to 1184, card inner content x 272 to 1168, plot column x 336 to 1112 (776 wide), row-label column x 272 to 336, end-label column x 1120 to 1168. Radii: card 10, controls and pills 6, small marks and chips 4.
- There is no sidebar toggle button in the chrome. View ▸ Hide Sidebar and ⌃⌘S hide and show the sidebar.
- No number-key shortcuts (AZERTY). Keyboard map as in Designer spec v2 §6 / v1 §10.

### Tokens

Ship a single token table in the app target (not in AccentKit). Views use the tokens; they do not hard-code hex, rgba, or typography values. Light and dark are both required. Increase Contrast and Reduce Transparency / Reduce Motion hooks are wired even if later specs fill more states.

#### Surfaces and ink

| Token | Light (warm paper) | Dark (graphite) |
| --- | --- | --- |
| surface.base (window, toolbar) | #EFECE6 | #171615 |
| surface.card | #FAF8F4 | #211F1D |
| surface.sidebar | #E6E2DA | #121110 |
| surface.well (search, ghost buttons) | #E2DDD4 | #2A2825 |
| hairline | #DCD6CB | #2F2D2A |
| text.primary | #1C1A17 | #F2EFE9 |
| text.secondary | **#69645C** (Addendum A2; was #6B665D) | #A39D93 |
| text.tertiary (labels only, never the only carrier of meaning) | #9C968B | #6E6961 |
| strip.bar (unstressed) | rgba(70,64,56,0.24) | rgba(240,235,225,0.20) |
| pitch.native (band) | rgba(120,113,102,0.38) | rgba(165,158,147,0.40) |
| pitch.you | #1C1A17 | #F7F4EE |
| pitch.texture (native waveform behind) | rgba(70,64,56,0.055) | rgba(240,235,225,0.045) |
| baseline | #D3CDC1 | #34322E |
| row.hover (sidebar hover tint) | rgba(60,50,35,0.03) | rgba(255,255,255,0.025) |

Increase Contrast: tertiary text becomes secondary, secondary becomes #5F5A52 (light) and #C2BCB2 (dark), hairlines get 1 pt and one step darker, the grain and the faint pitch texture are hidden.

#### Lime and mistakes

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| lime.1 | #23891C (leaf) | #C8F03C (lime) | gradient start, stressed bars core |
| lime.2 | #86C400 (lime) | #5BE3A6 (mint) | gradient end, bar tips |
| lime.text | #2F7A0E | #C6EE4A | Lime words in sentences, recording subtitle |
| lime.sidebarText | **#2A6E0C** (4.9:1 on the sidebar) | #C6EE4A (14.1:1 on #121110) | selected sidebar row text only; Addendum A1. Do not use lime.text in light on the sidebar (#2F7A0E is only 4.2:1 on #E6E2DA) |
| button.A to button.B | #7ED321 to #C2EA2E | #C8F03C to #5BE3A6 | Record and Stop, diagonal |
| onLime | #122405 | #10200A | text on the button |
| wash | lime.2 at 7% fading to 0 at 70% height | lime.2 at 9%, same fade | pitch card top |
| mistake | #2457E6 (5.5:1 on card) | #86A8FF (7.1:1 on card) | mistakes only, never red. In a card-1 sentence: bold caps in this blue only; the triangle and dotted underline are for strip labels only (Addendum r3 B3, §10) |

Gradients: horizontal for the accent (lime.1 to lime.2), vertical for stressed bars (lime.2 at the tips, lime.1 at the centre line, lime.2 at the other tip), diagonal for the button. The button gets a white highlight on its top half at 22%.

The old pill tokens (pill.A, pill.B, pill.edge) are **not used**. Addendum A1 supersedes the gradient selection pill in Designer spec v2 §5.

Red, purple, gold and amber are not used anywhere, in either theme.

#### Type

All three fonts are bundled in the app, unmodified, under the SIL Open Font License 1.1. They are not relicensed as GPL. Keep each official `OFL.txt` next to the font files in the app bundle, credit them in About, and add them to `THIRD_PARTY_NOTICES.md`. Bundle the official releases. Weights: Geist 400/600/700, Geist Mono 500, Funnel Display 600, plus the real Geist Italic (variable) for heard words. Geist Mono Italic is not used or bundled, and nothing gets a synthetic slant (Addendum r3 B2).

- Geist and Geist Mono: Copyright 2023 Vercel, in collaboration with basement.studio. Official `LICENSE.txt` declares no Reserved Font Name after the copyright line.
- Funnel Display: Copyright 2024 The Funnel Project Authors (`https://github.com/Dicotype/Funnel`). The Google Fonts `OFL.txt` also declares no Reserved Font Name.

No system-font fallback is needed in the shipped app. Fonts load from the bundle with no network access.

| Role | Font | Size and weight |
| --- | --- | --- |
| Phrase title (toolbar) | Funnel Display | 16 / 600, tracking −0.1 |
| UI text, diff sentences, sidebar rows | Geist | 13 / 400; selected row 13 / 600 |
| Secondary text, subtitles, syllable labels | Geist | 12 / 400; stressed syllable labels 12 / 700 caps |
| Section headers, card titles, row labels, take menu, axis labels | Geist Mono | 12 / 500, all caps, tracking 0.6 |

#### Grain

A pre-rendered tiling fractal-noise image, **256 × 256 pt**, exported at 256, 512 and 768 px for 1×, 2× and 3× (Addendum A8). Opacity 4.5% in light and 5% in dark. Composite the grain on surfaces, under text, not as one window overlay on top of everything (a single overlay cannot skip text). Do not use a live `CIFilter` or SwiftUI noise. Hidden under Reduce Transparency and Increase Contrast.

### Sidebar

- **Top:** the square-cut wordmark (mark plus "ACCENT MIRROR" in Geist Mono) next to the traffic lights.
- **Search:** a well field with a magnifier and a "⌘F" hint at the right.
- **Groups:** Geist Mono caps headers in **text.secondary** (Addendum A2; not tertiary): MY PHRASES, then STRESS SHIFTS, NOUN AND VERB PAIRS, COMPOUND NOUNS, WEAK FORMS. Their chevrons use text.secondary too. Expanded groups show their rows; collapsed ones show a chevron before the header. Rows are 32 pt tall, truncate with an ellipsis, and the full phrase is in the tooltip. Group header to first row 24 pt, between groups 16 pt. Sidebar padding 8 pt.
- **Noun and Verb Pairs** is shown collapsed, with "Coming soon" under the header in Geist 12 / 400 secondary. It cannot be selected and has no rows, no count badge, no lock icon and no upsell. Clicking it or pressing Return expands it to one non-selectable line: "No phrases yet. Native recordings for noun and verb pairs are coming in a later update." VoiceOver: "Noun and Verb Pairs, coming soon, no phrases yet." This state is driven by a pack having zero phrases, not by a hard-coded pack name. This spec may use a static manifest stub; spec 15 supplies the real one.
- **Bottom:** "+ NEW PHRASE" in Geist Mono, secondary. The button does not have to import a clip yet; it must be present and styled.
- **Selected row (Raph's pick B; Addendum A1, final, not a placeholder):** no fill, no border, no left bar. A six-bar lime waveform glyph (bars 1.6 pt wide on a 3 pt pitch, heights 4, 9, 13, 7, 11 and 5 pt, with the vertical Lime bar gradient) sits at x 16, and the row text starts at x 38. Selected text is Geist 13 / 600 in `lime.sidebarText`.
- **Hover:** must always look lighter than selected. A hovered unselected row keeps 13 / 400, its text goes from secondary to primary, and it gets the `row.hover` tint, radius 6, inset 8 pt. It never gets the glyph, lime, or bold.
- **Keyboard focus:** a 2 pt focus ring around the row area, radius 6.
- **VoiceOver:** the selected row reads "{phrase}, selected". The glyph is decorative.

For this spec, the sidebar may be filled from a small static list that includes the imported phrase "Photography is harder than it looks." under My Phrases and a few Stress Shifts rows, so the chrome can be judged against the final2 mockups. Interactive phrase loading is out of scope.

### Toolbar

From the right: the inspector toggle, the take menu, You, Record, Model.

- **Model** and **You:** ghost buttons in surface.well with a play triangle, 28 tall, radius 6. Disabled is shown as no fill and tertiary text, never colour alone. In this spec they do not play audio; they must still look right in enabled and disabled states.
- **Record:** 104 wide, the Lime button gradient with onLime text and a filled dot. The recording appearance (Stop with a filled square, same Lime, plus "● RECORDING 0:02" in lime.text Geist Mono) is styled here; live capture waits for a later spec.
- **Take menu:** "TAKE 03" in Geist Mono with a chevron, or "TAKES" when there are none. Unsaved-attempt labelling is spec 19.
- **Title block:** the phrase in Funnel Display 16 / 600, with a subtitle in Geist 12 secondary: "{pack} · Native speaker {voice}, VCTK" for starter phrases and "My Phrases · From {file name}" for clips. The Photography fixture uses "My Phrases · From demo-talk.m4a".
- **Narrow windows (Addendum r4 C7):** the title block keeps at least 160 pt; the subtitle truncates first, then the title. When the controls don't fit next to the full title they compact in this order: (1) the take menu becomes its chevron, with "Takes" or "Take 03" as tooltip and VoiceOver label; (2) Record becomes its dot, 40 pt wide, still in the Lime button, with "Record (Space)" as tooltip and VoiceOver label (the Stop square while recording); then the title gives up its extra width, down to 160 pt; (3) Model and You drop the play triangle and keep their words, with 8 pt side padding. Model and You never become icon-only. The gaps between controls never shrink: if step 3 still doesn't fit, the numbers go to Designer.
- **Minimum window (Addendum r4 C8):** 960 × 680 pt, with the inspector open too.

### App target

- Tokens, fonts, grain, views and the About credits live in `AccentMirror/`. AccentKit still imports no AppKit or UIKit (`make check-ui-frameworks` stays green).
- No new SPM dependency. No entitlements, no `NSMicrophoneUsageDescription`, no team ID, no signing changes.
- `project.yml` may gain resource entries for fonts, OFL files and the grain images, and may stay a single unsigned macOS app target.

## Defaults

- Start with SwiftUI `NavigationSplitView` and solid token backgrounds. If glass, vibrancy or blur cannot be fully turned off, switch to the AppKit split-view fallback in the same spec, and say so in the implementation notes.
- The selected sidebar phrase in the static list is "Photography is harder than it looks."
- The inspector is closed.
- Grain images are generated once, committed as 1×/2×/3× assets, and not produced at runtime.

## Guardrails

- On-device only: fonts and assets load from the bundle; no network at runtime; tests must not need the network.
- Contrast: primary and secondary text, `lime.text`, and `lime.sidebarText` meet 4.5:1 on their surfaces in both themes; onLime meets 4.5:1 on both ends of the button gradient. Pack headers, "Coming soon" and "+ NEW PHRASE" use text.secondary and meet 4.5:1 on the sidebar.
- Colour is never the only cue (Designer spec v2 §15). Meaning still reads in a grayscale screenshot of the chrome.
- Reduce Transparency and Increase Contrast hide the grain. Reduce Motion has a hook (no hover fade), even if later specs add more motion.
- UI work is `@MainActor`. No new warnings. `make check` stays green. CI still does not launch the app, use the microphone, or run UI tests.
- No secrets, team IDs, or personal paths in the repo.

## Out of scope

- Rendering contract states, JSON fixtures, and scripted screenshots (spec 19).
- Live strip and pitch behaviour, hover ghosts, voice-switch ease (spec 20).
- Live capture, playback, the take store, clip import, persistence banners wired to real errors (spec 21).
- Scoring, WhisperKit, microphone permission strings, entitlements, signing, notarization, the iOS target.
- Editing `.factory/`, `.github/`, or the Makefile, except that this spec may list a future `make screenshots` target for spec 19 to add.

## Open question (built with the default)

If `NavigationSplitView` fights solid chrome on macOS 26, use the AppKit split-view fallback rather than shipping glass. Do not stop to ask.

## How to test (Raph)

1. `make check` is green (generate, unsigned macOS build, package tests, corpus guard, no AppKit/UIKit in AccentKit). No new warnings from our code.
2. Launch the app (local, not CI). Default window is 1200 × 800 pt. Light and dark both use the token surfaces, the grain (unless Increase Contrast or Reduce Transparency is on), bundled fonts, and no glass or blur on the sidebar or toolbar.
3. The selected sidebar row is a six-bar lime glyph plus bold `lime.sidebarText`, with no fill. Hovering another row uses primary text at 13 / 400 on the faint neutral tint, with no glyph and no lime.
4. Pack headers, "Coming soon" and "+ NEW PHRASE" are secondary, not tertiary, and remain readable on the sidebar.
5. Record / Stop and the wordmark match the final2 mockups in typography and colour. There is no red, purple, gold or amber.
6. About (or the credits surface) and `THIRD_PARTY_NOTICES.md` name Geist, Geist Mono and Funnel Display and include the OFL.
7. Increase Contrast hides the grain, steps secondary/tertiary as specified, and thickens hairlines.

## Implementation notes

- **Split view: the AppKit fallback.** On macOS 26, `NavigationSplitView` always draws its sidebar as a floating Liquid
  Glass panel. The only opt-out is an Info.plist key, which agents may not touch. Following the Open question, the
  window uses `ShellSplitView`, a plain `NSSplitViewController` whose three items (sidebar 240 pt, detail, inspector
  280 pt) are ordinary items, not `.sidebar` items. They host opaque SwiftUI roots, with no vibrancy, blur or glass,
  and a zero-width divider. The inspector item starts collapsed.
- **Chrome.** `WindowChrome` hides the title, makes the title bar transparent over a full-size content view, and adds
  an empty `NSToolbar` (unified) only so the title bar is 52 pt tall and the traffic lights sit over the sidebar. The
  toolbar itself is SwiftUI, drawn on `surface.base` (`ToolbarView`). A hit test confirms clicks reach the SwiftUI
  controls under the empty toolbar.
- **Tokens.** `AccentMirror/Design/Palette.swift` is the single token table (light, dark, Increase Contrast, Reduce
  Transparency). It is injected per split pane by `ThemeRoot`. Hex values appear only in that file. Type roles are in
  `Typography.swift`, measurements in `Metrics` (`Surface.swift`).
- **Increase Contrast.** "One step darker" for hairlines is read as the next ink step, `baseline` (#D3CDC1 / #34322E),
  at 1 pt. See the PR's spec gaps.
- **Fonts.** The official TTFs and each family's `OFL.txt` are in `AccentMirror/Resources/Fonts/<Family>/`, bundled as
  a folder reference so each licence stays next to its fonts. They are registered at launch with
  `CTFontManagerRegisterFontsForURL` (process scope, from the bundle, no network). The About panel lists the families
  and shows both OFL texts. Sources and hashes are in `THIRD_PARTY_NOTICES.md`.
- **Grain.** `scripts/make-grain.swift` generated the tiling Perlin noise once (seeded, 218 lattice cells per 256 pt
  tile, about 0.85 per pt, 2 octaves). It is committed as `Assets.xcassets/Grain.imageset` at 256, 512 and 768 px.
  `SurfaceBackground` composites it on each surface (sidebar, base, cards), under that surface's text, at 4.5% / 5%.
  It is hidden with Reduce Transparency or Increase Contrast.
- **Sidebar.** The static manifest stub is `LibraryManifest.stub`. Noun and Verb Pairs is "coming soon" because it has
  zero phrases. The selected row is the Addendum A1 glyph plus Geist 13 / 600 in `lime.sidebarText`. Hover uses the
  `row.hover` tint at 13 / 400, primary. The focus ring is 2 pt, radius 6. The Reduce Motion hook drops the hover fade.
- **Commands.** View ▸ Hide Sidebar (⌃⌘S) replaces the system sidebar command. There is no sidebar button in the
  chrome and no number-key shortcuts.
- **Fixes round 5 (2026-11-23).** The toolbar title kept 160 pt with round 5's compaction order, which round 5b
  replaced.
- **Fixes round 5b (2026-11-23).** Toolbar per Addendum r4 C7: `ToolbarCompaction.decide` is the pure decision, and
  `ToolbarView` measures the controls and draws the chosen level. At 960 pt with the inspector open the controls
  need 6 pt more than there is (414 pt for 408), so the title gets 154 pt; see spec 19's round 5b note. Minimum
  window per C8: 960 × 680 pt for the whole window, title bar included. The window takes its minimum from
  `ShellView`'s minimum frame (`.windowResizability(.contentMinSize)`), which SwiftUI measures below the 52 pt
  title bar, so that frame asks for 960 × 628; asking for 680 there held windows at 732 pt.
