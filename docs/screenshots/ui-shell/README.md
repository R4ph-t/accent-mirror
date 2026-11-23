# UI-shell screenshots (specs 18–19)

Reviewed frames from the screenshot run, shrunk for the repo (the full 2400 × 1600 set stays out of git).

- `result-feedback-{light,dark}.png`, `tooQuiet-{light,dark}.png`: two of the four primary states, full window at 1x
  (1200 × 800).
- `fixes/<fixture>-{light,dark}.png`: 1x crops of the region each Designer fix touches
  (`inc-requiredMeasureUnavailable-lowConfidence`, `ncd-insertionsPresent`, `tp-clipped`, `tp-wordsDontMatch`,
  `noVoicedFrames`).
- `round3/<fixture>-light.png`: 1x crops for the fixes round 3 (Addendum r3): the four row fixtures with their own
  takes (`rows-range`, `rows-final-direction-higher`, `rows-final-direction-lower`, `rows-too-much-contrast`),
  `inc-targetWordsMissing-two` and `tp-tooShort`. Their dark twins are in the contact sheet.
- `contact-sheet-{light,dark}.png`: every fixture, 220 px tiles (`SHEET_COLUMNS=8 SHEET_TILE_WIDTH=220`).

Round 3 (2026-11-23) refreshed the contact sheets, `result-feedback-dark` (Addendum r3 B6, your bars' dark tone),
`fixes/noVoicedFrames-*` (B9), `fixes/tp-wordsDontMatch-*` (B7) and `fixes/inc-requiredMeasureUnavailable-lowConfidence-dark`
(B6), and added `round3/`. They come from the test VM (`make screenshots-vm`, Xcode 26.2), from two runs whose 124
PNGs were byte-identical. The other committed frames are unchanged from the fixes round (rendered on the host Mac on
2026-11-23, before the rule that keeps render steps off Raph's desktop).

Frames are downscaled with `sips`, cropped losslessly, and re-encoded losslessly as 8-bit RGB PNG (zlib level 9,
per-row filters). Renders come only from CI or the test VM, never the host.
