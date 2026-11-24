# Tuning log

Every re-tune of the prominence weights, λ and τ (plan §2) gets one entry here, newest first, in the PR that changes
`Thresholds.swift` and `docs/thresholds.md`. Tuning runs only on the tuning split (the 18 VCTK tuning speakers and the
speechocean762 tuning pools of `fixtures/splits/`), never on held-out clips. Run with `scripts/tune.sh`.

Each entry: date, commit, `configDigest` before and after, the grid slice evaluated, the chosen point and its
metrics (recall, VCTK placement FP, any-diff FP, shared-detector FP, synthetic which-syllable accuracy if present),
the number of feasible points, and why.

## Entries

### 2026-11-24: spec 11 §2, FALLBACK: nucleus-anchored syllable segmentation needed (for CTO)

- **Outcome:** FALLBACK (§4c). No grid point is feasible, so `Thresholds.swift` and `docs/thresholds.md` are
  unchanged and there is no retune. This goes to CTO first.
- **Commit:** tuning run on branch `factory/11-stress-validation-tuning` at 02259c2 (`scripts/tune.sh`, 4 jobs).
- **configDigest:** before `4fc683ef4fee3c0d5c2aa632f56b0e12cdc13e73c8f256d932ba48dc6b13bab6`, after the same
  (unchanged).
- **Grid slice:** the whole fixed grid of spec 02: 36 weight points × 11 λ × 117³ (τ_med, τ_high) pairs per n-bucket
  = 634,238,748 points, searched exactly (per-unit tables, verified against the real detector and analyzer at the
  initial point and at 60 random points: 915 of 915 unit outcomes match).
- **Pool:** 134 stress-wrong L2 words, 1,705 train-half correct words, 24 VCTK tuning speakers (476 scored pairs of
  512 takes; 35 noUsableReference, 1 too quiet).
- **Feasible points:** 0 meet the selection rule's constraints (placement FP ≤ 1.6%, any-diff ≤ 4%, shared FP ≤
  1.6%), 0 also the 10% inconclusive budget, 0 also the guard.
- **Initial point** w = (0.4, 0.3, 0.3), λ = 1.6, τ = (0.25, 0.50) in every bucket: recall 5/134, VCTK placement FP
  9/476, any-diff 140/476, shared FP 159/1,705, inconclusive 207/476.
- **Closest points** (by total constraint excess; ties then by grid order), e.g. #453436405 w = (0.4, 0.5, 0.1),
  λ = 1.8, τ = (0.10, 0.85) (0.10, 1.00) (0.40, 1.00): recall 2/134, VCTK placement FP 6/476, any-diff 140/476,
  shared FP 75/1,705, inconclusive 207/476, violation 0.617 (initial 0.669). Any-diff (29%) and inconclusive (43%)
  don't move anywhere on the grid: they don't depend on the tuned keys.
- **§1 nested CV:** all 5 inner fits infeasible, so every outer fold keeps the initial thresholds; pooled
  out-of-fold recall after suppression 5/134 (before 23/134). VCTK CV (6 folds): all infeasible.
- **Guard on tuning data** (VCTK tuning speakers, MFA oracle; the same at every grid point because `WordVerdict`
  doesn't read the tuned keys): b2 flips 1,599/6,824 (23.4%), inconclusive 10.5% → 18.8% (+8.3 points); jitter
  ±40 ms flips 830/6,824 (12.2%); per group 2-syllable 14.8% (n 1,139), 3-syllable 22.0% (n 373), 4+ 23.1% (n 186).
  NOT MET.
- **§4–§4b on held-out data** (shipped = initial thresholds):

  | Comparison | Synthetic (307 words) | VCTK held-out (3,890 words) |
  |---|---|---|
  | Control (TTS markers vs MFA) | 42 (13.7%), inconclusive 16 → 18 | – |
  | b2 vs oracle | 69 (22.5%), inconclusive 16 → 50 | 915 (23.5%), inconclusive 360 → 666 |
  | Jitter ±20 ms | 11 (3.6%) | 225 (5.8%) |
  | Jitter ±40 ms | 25 (8.1%) | 453 (11.6%) |
  | Jitter ±80 ms | 38 (12.4%) | 618 (15.9%) |

- **Why (CTO's reasoning, verbatim):** "multi-syllable splits come from the word edges, so boundary error moves
  duration and intensity between syllables, which margins alone can't fix."
- **Next (not started here):** a nucleus-anchored segmentation spec (vowel nuclei from intensity and voicing peaks,
  or phone-level CTC once b2 is in), gated on §4b's jitter test, then a re-run of spec 23's gate. CTO's call.
