# UI-shell screenshots (specs 18–19)

Reviewed frames from `make screenshots`, shrunk for the repo (the full 2400 × 1600 set stays local, in the
git-ignored `screenshots/ui-shell/`).

- `result-feedback-{light,dark}.png`, `tooQuiet-{light,dark}.png`: two of the four primary states, full window at 1x
  (1200 × 800).
- `fixes/<fixture>-{light,dark}.png`: 1x crops of the region each Designer fix touches
  (`inc-requiredMeasureUnavailable-lowConfidence`, `ncd-insertionsPresent`, `tp-clipped`, `tp-wordsDontMatch`,
  `noVoicedFrames`).
- `contact-sheet-{light,dark}.png`: every fixture, 220 px tiles.

The `empty` and `recording` frames didn't change in the fixes and are byte-identical to the ones committed in
eb93fd1 (PR #4); they are in the contact sheets.

Rendered on the host Mac on 2026-11-23 (11:44–11:47 Paris), before the rule that keeps render steps off Raph's
desktop, from a tree whose sources, fixtures and fonts match commit 443bbe4. Downscaled with `sips`, cropped
losslessly, and re-encoded losslessly as 8-bit RGB PNG (zlib level 9, per-row filters). Future renders come from CI
or the test VM.
