# Word-boundary gate diagnostics (spec 23, CTO decision on #27, 2026-11-23)

Generated 2026-11-23T21:55:16Z from commit `fe6a0db86e03` (clean tree: yes). **Measures only**: no shipped behaviour, threshold or aligner decision changes. Same harness (`DownstreamHarness`: spec 07's `SyllableSegmenter` with `ACFVoicing`, spec 06's bundled selector), same verdict function (`WordVerdict`), same thresholds (`ctcConfidenceMin` 0.5, untuned), same sets and comparability rules as the gate in `docs/agreement/reports/word-boundaries-cfd62cd8.json`. Machine-readable: `word-boundaries-diagnostics-2026-11-23.json`.

Verdict parts are listed inconclusive / syllableCount / longestSyllable / loudestSyllable; a word counts once per part that differs.

## 1. Control: two good references (TTS markers vs MFA on TTS)

| Pair | Comparable words | Verdicts differ n (%) | Per part | Inconclusive oracle → candidate | Against 2.0% |
|---|---|---|---|---|---|
| **Control of record**: markers vs MFA, gate's comparable words | 307 | 42 (13.7%) | 10 / 0 / 27 / 15 | 5.2% → 5.9% (+0.7 points) | **> 2.0%** |
| Sensitivity: all marker∩MFA words, probability 1 | 312 | 42 (13.5%) | 10 / 0 / 27 / 15 | 5.1% → 5.8% (+0.6 points) | **> 2.0%** |

The control is **> 2.0%** (13.7%): two references about 25 ms apart (median, the cfd62cd8 report's reference-error table) already disagree on 42 of 307 verdicts.
- The control of record: the gate's comparable words (the live Whisper words match them too), each carrying that Whisper word's probability on both sides, as the gate's oracle run does.
- Sensitivity only: every phrase word both the markers and MFA time, probability 1 on both sides (no Whisper in the loop).

## 2. Ranking: oracle vs candidate, same columns as the gate

| Set (oracle) | Candidate | Comparable words | Verdicts differ n (%) | Per part | Inconclusive oracle → candidate |
|---|---|---|---|---|---|
| Synthetic (TTS) (TTS markers) | `whisper` | 307 | 75 (24.4%) | 32 / 0 / 40 / 34 | 5.2% → 9.8% (+4.6 points) |
| Synthetic (TTS) (TTS markers) | `dsp-snap-1` | 307 | 90 (29.3%) | 49 / 0 / 41 / 42 | 5.2% → 16.6% (+11.4 points) |
| Synthetic (TTS) (TTS markers) | `ctc-w2v2b960-1` | 307 | 69 (22.5%) | 34 / 0 / 29 / 34 | 5.2% → 16.3% (+11.1 points) |
| VCTK (MFA word baseline) | `whisper` | 2382 | 634 (26.6%) | 356 / 0 / 302 / 317 | 8.7% → 11.4% (+2.7 points) |
| VCTK (MFA word baseline) | `dsp-snap-1` | 2382 | 669 (28.1%) | 444 / 0 / 270 / 270 | 8.7% → 17.7% (+9.0 points) |
| VCTK (MFA word baseline) | `ctc-w2v2b960-1` | 2382 | 537 (22.5%) | 348 / 0 / 199 / 190 | 8.7% → 18.9% (+10.2 points) |

Synthetic: Whisper base.en live on the TTS audio (the words that seed b2 in the gate); `dsp-snap-1` and b2 refine those. VCTK: spec 03's committed replay `fixtures/timestamps/openai_whisper-base.en`.

## 3. Breakdown of the flips (b2 on both sets; control alongside)

| Breakdown | Group | b2, Synthetic (TTS) | b2, VCTK | control, Synthetic (TTS) |
|---|---|---|---|---|
| Whisper-unmatched | substituted / deleted (excluded) | 5 / 0 | 47 / 0 | 5 / 0 |
| Diff after exclusion | verdicts differ | 69 / 307 (22.5%) | 537 / 2382 (22.5%) | 42 / 307 (13.7%) |
| Cue | inconclusive | 34 (only cue: 20) | 348 (only cue: 243) | 10 (only cue: 8) |
| Cue | syllable count | 0 (only cue: 0) | 0 (only cue: 0) | 0 (only cue: 0) |
| Cue | duration (longestSyllable) | 29 (only cue: 11) | 199 (only cue: 73) | 27 (only cue: 18) |
| Cue | intensity (loudestSyllable) | 34 (only cue: 13) | 190 (only cue: 53) | 15 (only cue: 6) |
| Cue | pitch | not a verdict part in spec 07 | not a verdict part in spec 07 | not a verdict part in spec 07 |
| Syllables (oracle) | 1 | 15 / 234 (6.4%) | 175 / 1816 (9.6%) | 8 / 234 (3.4%) |
| Syllables (oracle) | 2 | 35 / 51 (68.6%) | 219 / 397 (55.2%) | 22 / 51 (43.1%) |
| Syllables (oracle) | 3 | 13 / 15 (86.7%) | 100 / 114 (87.7%) | 10 / 15 (66.7%) |
| Syllables (oracle) | 4+ | 6 / 7 (85.7%) | 43 / 55 (78.2%) | 2 / 7 (28.6%) |
| Transition | feedback↔close (decided↔decided) | 30 / 69 (43.5%) | 154 / 537 (28.7%) | 29 / 42 (69.0%) |
| Transition | anything↔inconclusive | 39 / 69 (56.5%) | 383 / 537 (71.3%) | 13 / 42 (31.0%) |
| Boundary error | 0–20 ms | 1 / 17 (5.9%) | 6 / 107 (5.6%) | 3 / 35 (8.6%) |
| Boundary error | 20–40 ms | 6 / 44 (13.6%) | 39 / 403 (9.7%) | 23 / 183 (12.6%) |
| Boundary error | 40–80 ms | 18 / 135 (13.3%) | 161 / 817 (19.7%) | 9 / 68 (13.2%) |
| Boundary error | 80–160 ms | 18 / 61 (29.5%) | 172 / 710 (24.2%) | 1 / 2 (50.0%) |
| Boundary error | >160 ms | 26 / 50 (52.0%) | 159 / 345 (46.1%) | 6 / 19 (31.6%) |

- Cells are flipped / words (flip %), except the transition rows (flipped of that type / all flipped words) and the cue rows (a word counts once per part that differs; "only cue": words where it is the sole differing part).
- Whisper-substituted words: the gate pairs words by exact normalised text (`Tokens.match`), so a phrase word Whisper heard as something else is never comparable. They are already outside every diff; the row counts them (substituted: an unmatched Whisper word sits in the gap; deleted: none does), and b2's diff after the exclusion is the gate's diff, unchanged.
- Boundary error: max(|start error|, |end error|) of the candidate's span against the oracle's; bins have inclusive upper edges.
- Pitch: not a verdict part in spec 07 (the verdict is inconclusive, syllable count, longest syllable, loudest syllable).

## 4. b2's inconclusive rise: CTC confidence gate vs verdict margins

| Set | Comparable words | Oracle inconclusive | b2 inconclusive | b2, gate bypassed | Full rise | From the confidence gate | From margins | Words gated |
|---|---|---|---|---|---|---|---|---|
| Synthetic (TTS) | 307 | 16 | 50 | 47 | +11.1 points (34 words) | +1.0 points (3 words) | +10.1 points (31 words) | 11 |
| VCTK | 2382 | 207 | 451 | 435 | +10.2 points (244 words) | +0.7 points (16 words) | +9.6 points (228 words) | 51 |

The gate is bypassed in the diagnostic path only (b2's spans keep Whisper's probability); `Thresholds.swift` and the shipped default are untouched. Rise from the gate = full rise − rise with the gate bypassed; rise from margins = the rest.

## Which branch of CTO's decision rule

CTO's rule, verbatim:

- control > 2% → the gate re-runs on spec 11's tuned thresholds (held-out), same ≤ 2% / ≤ 2-point limits for b2 vs oracle, and spec 11 also reports the control on its tuned thresholds;
- control ≤ 2% and b2 still > 2% after spec 11's tuning → rework b2, guided by the cue breakdown;
- Whisper-only beats b2 on the diff → drop b2.

**The numbers point to the first branch** (control 13.7% > 2.0%): the gate re-runs on spec 11's tuned thresholds (held-out), and spec 11 also reports the control on them. The second branch's precondition (control ≤ 2%) does not hold. Third branch does not hold: Whisper-only does not beat b2 on the diff on any set (Synthetic (TTS): whisper 24.4% vs b2 22.5%; VCTK: whisper 26.6% vs b2 22.5%). Reported, not applied: the decision is CTO's.

## Gate reproduced

| Set | Gate (cfd62cd8): differ / words, gated | This run | Same |
|---|---|---|---|
| Synthetic (TTS) | 69 / 307, 11 | 69 / 307, 11 | yes |
| VCTK | 537 / 2382, 51 | 537 / 2382, 51 | yes |

## Identity

- Evaluated commit: `fe6a0db86e0355e3784b91a52fedef00e3211aef`; clean tree: yes
- `sourceTreeHash`: `f931fce899bb1c31ab95d7b0241d8aa04d5b58afff2d5e034f094ee900a217ac`
- Shipped aligner's `configDigest` (`whisper`): `cfd62cd8badc5191fd60fa2a903ff229ff1b5d7b75a2710aba19bde5f095af00`
  - `ctc-w2v2b960-1`: `1ba658bf703db9db51e2c8bb0b9e9c59ad31f2a8e2ab2dcc405632a1ddb65314`
  - `dsp-snap-1`: `fbce8e403fb2a9397828bd5e4e54c7546428528e58e59ffa21013f3926d9e323`
  - `whisper`: `cfd62cd8badc5191fd60fa2a903ff229ff1b5d7b75a2710aba19bde5f095af00`
- VCTK corpus manifest hash: `1ba061d2ca470e64ae96b6aeab93251255e0505226348eb962f423fc0723e716`; label (MFA word baseline) `fixtures/vctk/mfa-word-baseline.json`: `e2751a293ac6a886775d0ae1bd608d6d27ef9c48a0c1f09362859899ec8dcb59`
- Whisper: `openai_whisper-base.en@0f63a7800b00dd0226abd051b906c246e1907482#a59b5631`; VCTK replay `fixtures/timestamps/openai_whisper-base.en`; live on TTS from `Resources/Models/openai_whisper-base.en/manifest.json`
- b2 package SHA-256: `9ae95d751153f85e2282590668e2ab1ffd4db3b1a10292ccdd3660b50f7ee4d8`
- Synthetic set (git-ignored `.cache/reference/`, not regenerated by this run): markers.json `db09a3a74ec1c9562c4033367508cb67c86494c5392868f8b6693d57bb86cefe`, mfa-alignment.json `4d5cb66b63fc1773177bc62691bec27fd0d726fd1d356723026b8422eb02787c`, TTS audio hash `2d6be10e3636cfe4145f534aacac2c5d58d2bf96d04187f03e37c5ee0fa41e89`
- Thresholds read, not changed: `ctcConfidenceMin` 0.5, `verdictDiffMax` 0.02, `inconclusiveRiseMaxPoints` 0.02
- Toolchain: Xcode 26.2 build 17C52; swift-driver version: 1.127.14.1 Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2); macOS 26.3 (25D125); Apple M3 Max, Mac15,11

## Reproduce

```sh
git checkout fe6a0db86e0355e3784b91a52fedef00e3211aef
scripts/eval-word-boundaries.sh --dev                 # once, if .cache/reference/ is missing: TTS + MFA on TTS
scripts/eval-word-boundary-diagnostics.sh             # release run: clean tree, writes this report
scripts/eval-word-boundary-diagnostics.sh --dev       # any tree, report under .cache/reports/
```

## Appendix: `make check` at fe6a0db

Added by hand after the run (the tool doesn't write it). Clean tree, before the release run above:

```text
** BUILD SUCCEEDED **
Build complete! (3.93s)
✔ Test run with 271 tests in 50 suites passed after 6.595 seconds.
check-local-corpus: OK, no local-only corpus files tracked.
check-no-ui-frameworks: OK, AccentKit imports neither AppKit nor UIKit.
test-check-local-corpus: all passed
```

No warnings from our code (the only `WARNING` line is xcodebuild's "Using the first of multiple matching destinations"). No VM run: package code only.
