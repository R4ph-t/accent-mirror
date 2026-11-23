# UI-shell screenshots (specs 18–19)

Reviewed frames from the screenshot run, shrunk for the repo (the full 2400 × 1600 set stays out of git).

- `result-feedback-{light,dark}.png`, `tooQuiet-{light,dark}.png`: two of the four primary states, full window at 1x
  (1200 × 800).
- `narrow-inspector-open-{light,dark}.png`: the narrow-window regression fixture (fixes round 5), full window at 1x
  (960 × 680).
- `fixes/<fixture>-light.png`: 1x crops of the region each Designer fix touches
  (`inc-requiredMeasureUnavailable-lowConfidence`, `ncd-insertionsPresent`, `tp-clipped`, `tp-wordsDontMatch`,
  `noVoicedFrames`).
- `round3/<fixture>-light.png`: 1x crops for the fixes round 3 (Addendum r3): `inc-targetWordsMissing-two` and
  `tp-tooShort`. Their dark twins are in the contact sheet.
- `round4/<fixture>-light.png`: 1x crops of the five row fixtures, one row and one difference each (fixes round 4):
  `rows-contrast`, `rows-range`, `rows-final-direction-higher`, `rows-final-direction-lower`,
  `rows-too-much-contrast`. They replace round 3's row crops; their dark twins are in the contact sheet.
- `contact-sheet-{light,dark}.png`: every fixture, 220 px tiles (`SHEET_COLUMNS=8 SHEET_TILE_WIDTH=220`), each frame
  fitted to its tile without stretching.

Round 3 (2026-11-23) refreshed the contact sheets, `result-feedback-dark` (Addendum r3 B6, your bars' dark tone),
`fixes/noVoicedFrames-*` (B9), `fixes/tp-wordsDontMatch-*` (B7) and `fixes/inc-requiredMeasureUnavailable-lowConfidence-dark`
(B6), and added `round3/`. They come from the test VM (`make screenshots-vm`, Xcode 26.2), from two runs whose 124
PNGs were byte-identical. The other committed frames are unchanged from the fixes round (rendered on the host Mac on
2026-11-23, before the rule that keeps render steps off Raph's desktop).

Round 4 (2026-11-23) refreshed the contact sheets (now 64 fixtures) and replaced round 3's four row crops with
`round4/`, all from the test VM, from two runs whose 128 PNGs were byte-identical.

Round 5 (2026-11-23) refreshed every committed frame. Round 4's frames held a ~1020 × 684 pt window scaled up to
2400 × 1600, because the VM's screen shrank the window; every frame now shows the real 1200 × 800 pt window (or
the fixture's own size). Round 5 also added `narrow-inspector-open-*`, and dropped the `fixes/*-dark` crops to keep the folder
under 10 MiB (their dark twins are in the dark contact sheet). The crops cover the same regions in the new geometry:
`fixes/` and `round3/` are the detail column (x 240 to 1200 pt) from the top (`noVoicedFrames` from y 400, the pitch
card), and `round4/` is x 250 to 1190, y 60 to 780. All of them come from the test VM, and two runs gave
byte-identical PNGs (130 frames).

Round 5b (2026-11-23, Addendum r4) refreshed the contact sheets, `narrow-inspector-open-*` (now the real
960 × 680 pt window, C8), `round4/rows-too-much-contrast-light` (C4) and `round4/rows-final-direction-higher-light`
(C1), from two test-VM runs whose 130 PNGs were byte-identical. The other committed frames didn't change.

Frames are downscaled, cropped and re-encoded losslessly as 8-bit RGB PNG (zlib level 9, per-row filters). Up to
round 4 the downscale used `sips`; round 5 used Core Graphics with high-quality interpolation. Renders come only from CI or the test VM, never the host.
