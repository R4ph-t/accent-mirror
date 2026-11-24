# 08: Prominence and observed stress

Status: Done · Branch: factory/08-prominence-observed-stress · Depends on: 02 (harness), 04 (pitch), 07 (syllables) · Estimate: 4–5 h agent run + 1 h
Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §2 (prominence, contrast, exposure discount, margins, worked examples), §3.2–§3.5 (observed stress,
contextual A(w), matched-pattern S and U), §5 (suppression), §6.3 (shared-detector mode, which uses this spec's
`placementDecision`).

## Goal

In `AMProsody`: per-syllable prominence over the comparable set, the lengthening discount, observed stress per word
with n-bucket margins and confidence, the contextual accepted set A(w), matched-pattern S and U sets, contrast C and
weak length W, and the one `placementDecision` function the app and the shared-detector validation mode both call.
Commit `tools/worked_examples.py` and reproduce it to 2 decimals.

## Behaviour

### Prominence (§2)

- d_i = ln(duration_i); for a lengthening-exposed syllable (spec 07), d_i − ln(λ), λ ≥ 1 (initial 1.6). e_i = mean
  RMS in dBFS floored at −60. p_i = peak F0 in st relative to the speaker's median (spec 04), missing if fewer than 3
  voiced frames.
- z_k,i = (x_k,i − mean_k) / max(sd_k, floor_k), floors 0.05 / 1 dB / 1 st, population sd, **over the comparable
  syllable set** passed in by the caller (reference-dependent, so L2 in §9.2).
- P_i = Σ w_k·z_k,i / Σ w_k over the features present, w = (0.4, 0.3, 0.3) initially.
- Degenerate cases: fewer than 2 values for a feature → that feature drops out; n < 2 syllables → unavailable; the sd
  floor prevents division by zero.

### Observed stress

- Per word with ≥ 2 syllables: primary = argmax P within the word; margin m = P(top) − P(second).
- Margins depend on n, the number of comparable syllables in the take: buckets {2–4, 5–8, ≥ 9}, τ_med and τ_high per
  bucket (initial 0.25 / 0.5 everywhere). Stress confidence = high if m ≥ τ_high(n), medium if m ≥ τ_med(n), else
  low; then min with the syllable confidence level (spec 07).
- Secondary: a second peak in the word at ≥ 0.75 of the primary's display prominence and not next to the primary.
  Display prominence is P min-max normalised to 0–1 within the take (for the strip bars).

### Accepted set A(w) and S/U (§3.3)

- A(w) = {the primary of the context-compatible pronunciation (spec 06: override, or the POS-selected persisted
  variant)} ∪ {the **high-confidence** observed primaries of native readers of **this phrase**}. Other CMUdict
  variants are not accepted.
- Native readers are the bundled voices for starter phrases. In evaluation, held-out speakers are never in A(w)
  (spec 02 guarantees the inputs; a test checks the function never adds the test speaker).
- A model voice whose own observed primary is outside A(w) at high confidence is logged `referenceAnomaly` and gives
  no diff.
- `expectedAmbiguous` words: no placement decision and excluded from S and U.
- S and U per word come from the accepted pattern you matched: the context pronunciation, or the native alternative
  (its observed primary and, where present, secondary as S, the rest as U). If you matched none, the context
  pronunciation is used. The model's C uses the same per-word S and U.
- Nearest accepted pattern for a row: closest primary index; ties go to the selected voice. If your primary ∈ A(w),
  the inspector names the native pattern you match ("like p311").

### `placementDecision(observed:accepted:confidence:exposure:)`

The single placement rule, used by the app (spec 10) and by spec 02's shared-detector runner. It raises a placement
flag only when your observed primary ∉ A(w), your stress confidence is **high**, and your syllable confidence is ≥
medium (§3.3, §5). A word with an exposed syllable needs a high margin, which the high-confidence rule already
implies; the exposure argument stays so the rule is explicit and tested. It returns the decision and the
before/after-suppression facts the harness counts.

### Contrast and weak length (§2)

C = median(A over S) / median(A over U), A_i = dur_i × 10^(e_i/20); W = median dur(U) / median dur(S). Both use
**raw** durations; the discount applies to prominence only. Triggering diffs is spec 10.

### Worked examples

`tools/worked_examples.py` is committed exactly as in the appendix (pure Python 3, no dependencies), with one change
noted below. `ProminenceTests` reproduce its output to 2 decimals for A–E at λ = 1.6, and the λ = 1.0 numbers as
explicit tests of the undiscounted path:

| Case | P at λ = 1.6 | Primary, margin | λ = 1.0 |
|---|---|---|---|
| A model "photography" | −0.07, 1.65, −0.75, −0.83 | TOG, 1.72 high; C 4.19, W 50.0% | −0.21, 1.61, −0.93, −0.46 (TOG 1.82) |
| B you, PHO | 1.46, 0.32, −0.67, −1.11 | PHO, 1.14 high; C 1.65, W 85.7% | 1.52, 0.21, −0.94, −0.79 (PHO 1.31) |
| C as B, "ra" unvoiced | 1.37, 0.26, −0.68, −1.15 | PHO, 1.12 high | 1.43, 0.14, −1.07, −0.83 (PHO 1.29) |
| D flat | 0.23, 0.29, 0.23, −0.75 | TOG, 0.06 low; C 1.0 | 0.00, 0.06, 0.00, −0.06 (TOG 0.06) |
| E native "I love photography." | −0.71, 0.70, −1.50, 0.54 | TOG, 0.16 low | −0.72, 0.56, −1.46, 0.81 (PHY 0.25 medium, not flaggable) |

### Wiring into the harness

- Spec 02's `PlacementDetector` gets the real implementation. `scripts/agreement.sh --suite l2-shared` can then run
  locally on speechocean762; it is reported, not gated (gating is spec 11).
- **Positive set (CTO ruling, 2026-11-23 14:18):** no gate in this spec consumes spec 02's VCTK positive-set result.
  The `l2-shared` run is speechocean762 and is reported only, and the VCTK CV estimate this detector enables is "CV
  estimate, not shipped", reported only. If a gate that reads the positive set is ever added here, it is blocked on
  spec 24 while the positive set reads NOT EVALUATED, never waived.
- The 157 unintelligible words run through it: every one inconclusive or unscored, never a placement diff.
- Smoke set goldens added: per item, the L1 digest and the placement decision before and after suppression.

## Defaults

- All tunables (w, floors, λ, τ per bucket, exposure pause) come from `Thresholds` (spec 01). No tuning here; the
  fixed-grid fit is spec 11.
- **Script change:** the plan's script computes `flaggable` as "high, or medium with no exposed syllable", which is
  the rev 3 rule. Rev 4.1 §3.3 and §5 require high stress confidence for any placement flag. The committed script
  uses the §3.3 rule; none of the plan's printed P, margin, C or W numbers change.

## Guardrails

- `AMProsody` imports `AMCore`, `AMAlignment`, `AMPitch` only. No AppKit or UIKit.
- One placement function; no second copy in the harness or the app.
- Tuning only on the tuning split, never on held-out clips.

## Out of scope

- Measures, verdict and diff rows (spec 10). The time map and band (spec 09). Tuning and the validation run (spec 11).

## Open question (built with the default)

1. **Display prominence for the secondary rule.** v1's "≥ 0.75 × primary prominence" assumed prominence in 0–1; rev
   4.1's P is a z-score. Default: apply the rule to the min-max normalised display prominence; secondary feeds S only
   for native alternatives, so it never triggers a diff on its own.

## How to test (Raph)

1. `make check` is green.
2. `python3 tools/worked_examples.py` prints the table above.
3. `swift test --package-path Packages/AccentKit --filter ProminenceTests` reproduces A–E at both λ to 2 decimals,
   and the degenerate cases (n < 2, all pitch missing, zero variance) are table-tested.
4. `swift test --filter AcceptedSetTests`: "record" in "a new record" with a verb-stress take is flagged; the same
   take is not flagged when a bundled native of this phrase produced verb stress at high confidence; an
   `expectedAmbiguous` word is never flagged; a model voice outside A(w) logs `referenceAnomaly`.
5. Optional, local: `scripts/agreement.sh --suite l2-shared` prints before/after-suppression counts and "157
   unintelligible: 0 placement diffs".

## Appendix: `tools/worked_examples.py`

```python
#!/usr/bin/env python3
"""Accent Mirror worked examples: prominence, observed stress, contrast, weak length.
Commit-ready reference for ProminenceTests (spec 08). Pure Python 3, no dependencies.
Algorithm (plan v2 rev 4.1, section 2):
  d_i = ln(dur_i) - ln(lambda) if syllable i is lengthening-exposed (last syllable of the take
        or before a pause > 150 ms), else ln(dur_i)
  e_i = mean RMS dBFS floored at -60 ; p_i = peak F0 in st re speaker median (None if < 3 voiced frames)
  z_k,i = (x_k,i - mean_k) / max(sd_k, floor_k), population sd over the comparable syllables where k present
  P_i = sum(w_k z_k,i) / sum(w_k) over present features; w = (0.4, 0.3, 0.3); floors = (0.05, 1.0, 1.0)
  Placement (per word): primary = argmax P within the word; margin m = P(top) - P(second)
    conf = high if m >= tau_high else medium if m >= tau_med else low. A placement flag needs high
    confidence (section 3.3); a word with an exposed syllable therefore also needs high.
    Initial tau_med = 0.25, tau_high = 0.5 (tuned later).
  Contrast C = median(A over S) / median(A over U), A_i = dur_i * 10^(e_i/20), RAW durations
  (the discount applies to prominence only). Weak length W = median dur(U) / median dur(S).
"""
import math, statistics as st

W = {"d": 0.4, "e": 0.3, "p": 0.3}
FLOOR = {"d": 0.05, "e": 1.0, "p": 1.0}

def prominence(sylls, lam):
    feats = {"d": [], "e": [], "p": []}
    for s in sylls:
        d = math.log(s["dur"]) - (math.log(lam) if s.get("exposed") else 0.0)
        feats["d"].append(d); feats["e"].append(max(s["db"], -60.0)); feats["p"].append(s.get("p"))
    z = {}
    for k, xs in feats.items():
        pres = [x for x in xs if x is not None]
        if len(pres) < 2:
            z[k] = [None] * len(xs); continue
        m, sd = st.mean(pres), max(st.pstdev(pres), FLOOR[k])
        z[k] = [None if x is None else (x - m) / sd for x in xs]
    out = []
    for i in range(len(sylls)):
        num = sum(W[k] * z[k][i] for k in W if z[k][i] is not None)
        den = sum(W[k] for k in W if z[k][i] is not None)
        out.append(num / den)
    return out

def placement(P, idx, labels, exposed, tau_med=0.25, tau_high=0.5):
    sub = sorted(((P[i], i) for i in idx), reverse=True)
    m = sub[0][0] - sub[1][0]
    conf = "high" if m >= tau_high else "medium" if m >= tau_med else "low"
    flaggable = conf == "high"  # section 3.3: placement needs high stress confidence
    return labels[sub[0][1]], round(m, 2), conf, flaggable

def contrast(sylls, S, U):
    A = [s["dur"] * 10 ** (max(s["db"], -60) / 20) for s in sylls]
    C = st.median([A[i] for i in S]) / st.median([A[i] for i in U])
    Wl = st.median([sylls[i]["dur"] for i in U]) / st.median([sylls[i]["dur"] for i in S]) * 100
    return round(C, 2), round(Wl, 1)

def word(durs, dbs, ps, final=True):
    return [{"dur": d, "db": e, "p": p, "exposed": (final and i == len(durs) - 1)}
            for i, (d, e, p) in enumerate(zip(durs, dbs, ps))]

PH = ["pho", "tog", "ra", "phy"]
CASES = {
 "A model, 'photography' (take = the word)": word([.10, .20, .08, .12], [-24, -18, -27, -26], [1, 6, -1, -2]),
 "B you, stress on PHO":                     word([.20, .14, .10, .12], [-19, -22, -25, -25], [5, 2, 0, -1]),
 "C as B, 'ra' unvoiced":                    word([.20, .14, .10, .12], [-19, -22, -25, -25], [5, 2, None, -1]),
 "D flat take":                              word([.15] * 4, [-22] * 4, [0, .2, 0, -.2]),
}
# E: full sentence 'I love photography.'; normalisation over all 6 comparable syllables
E = [{"dur": .09, "db": -22, "p": 1}, {"dur": .20, "db": -18, "p": 3}] + \
    word([.10, .18, .08, .28], [-24, -21, -27, -20], [0, 2, -1, 1])
S, U = [1], [0, 2, 3]   # expected: tog stressed; pho, ra, phy unstressed (secondary on pho ignored for S here)

if __name__ == "__main__":
    for lam in (1.6, 1.0):
        print(f"=== lambda = {lam} ===")
        for name, sy in list(CASES.items()) + [("E native, 'I love photography.' (6 syllables)", E)]:
            P = prominence(sy, lam)
            idx = list(range(len(sy) - 4, len(sy)))
            ex = [s.get("exposed", False) for s in sy]
            pri, m, conf, fl = placement(P, idx, {i: PH[j] for j, i in enumerate(idx)}, ex)
            Cc, Wl = contrast(sy[-4:], S, U)
            print(f"{name}: P(word) = {[round(P[i], 2) for i in idx]}; primary {pri.upper()}, "
                  f"margin {m} ({conf}), flaggable={fl}; C = {Cc}, W = {Wl}%")
```

## Implementation notes

Built by hand on 2026-11-23 (Claude Code, Opus) on `factory/08-prominence-observed-stress`.

**Layout.** `AMProsody` holds the pure rules: `Prominence.swift` (P over the caller's comparable set, λ discount,
floors, degenerate cases, display prominence), `ObservedStress.swift` (`ComparableSyllable`, `TakeProminence`,
`ObservedStress`: primary, margin, n-bucket confidence capped by syllable confidence, secondary),
`AcceptedSet.swift` (`WordAcceptedSet`: A(w), matched pattern, nearest pattern, S and U, `isReferenceAnomaly`),
`Placement.swift` (`placementDecision(observed:accepted:confidence:exposure:)`, the one rule) and `Contrast.swift`
(C and W on raw durations). `AMPipeline/StressPlacementDetector.swift` runs the §6.3 stages (replayed word timings →
spec 06 aligner → spec 07 segmenter → spec 04 pYIN → prominence → `placementDecision`) and reports before/after
suppression. `am-eval` adapts it to spec 02's `PlacementDetector` (`Detector.swift`), records Whisper timings once
(`record-timings`), and checks the smoke goldens (`smoke-detector`, `Smoke.swift`). AMEvaluation stays AMCore-only:
the detector can't live there, and the app never links it. `tools/worked_examples.py` is the appendix verbatim.

**Thresholds.** None added or changed: every value this spec reads was already in `Thresholds.prominence` (spec 01).
`thresholdsVersion` stays 4 and no golden digest was appended.

**Choices the spec left open (least-committal; listed in the PR as spec gaps).**
1. *`referenceAnomaly`* is checked against A(w) without the model voice's own reading. With its own reading in A(w)
   the rule could never fire. Another native of the phrase at high confidence on the same syllable clears it.
2. *S from the context pronunciation* is its primary and secondary syllables (a native alternative's S is its
   observed primary and secondary, as written). Monosyllables and words with no observed stress use the context
   pattern. Which words spec 10 pools into C and W is spec 10's.
3. *Primary ties* go to the earlier syllable (margin 0, so low). The script's sort would pick the later one; no worked
   example ties.
4. *Secondary* is the most prominent syllable not next to the primary, if its display prominence is ≥ 0.75 × the
   primary's. A take whose P are all equal displays 0 everywhere and has no secondary.
5. *A zero-length syllable* gets ln(1 ms) so P stays finite (algorithm constant `Prominence.minimumDurationS`).
6. *`placementDecision`* returns nil for an empty A(w) (no decision). Its suppressions, checked in order:
   `lowSyllableConfidence`, `exposedSyllable` (exposed and stress below high), `stressConfidenceBelowHigh`. Spec 02's
   `PlacementSuppression` gained `stressConfidenceBelowHigh`, because rev 4.1 suppresses any medium or low mismatch and
   the enum had no case for it. The shared mode checks Poor timing, then low word confidence, then the rule's own
   reasons. `missingTarget` stays unused: an absent word is `present: false`, never a suppressed flag.
7. *Pronunciations in the shared mode*: the label fixture's ref-phones for decided words, else the corpus
   `resource/text-phone`, else CMUdict's first variant, else one schwa per spelling syllable. The corpus has one vowel
   with no stress digit ("HERE", `HH IH AH0`), which doesn't parse, so it falls through to CMUdict.
8. *Smoke inputs*: speechocean762 items decide the manifest's labelled words, with A(w) from spec 02's rule
   (ref-phones, else the POS-selected CMUdict variant). VCTK items decide every polysyllabic word under the starter
   rule (overrides only, no tagger), so stress-shift words are `expectedAmbiguous` and undecided. The inputs are
   committed, so CI never runs the tagger.
9. *`harnessConfig()`* now names `acf-1` voicing (the detector runs it), so report config digests change.
10. *VCTK CV estimate*: not computed. It is a positive-set number, the positive set is NOT EVALUATED (blocked on spec
    24), and the fold-tuned run is spec 11. `am-eval suite --suite positive` says so instead of "until spec 08".

**Smoke goldens** (`fixtures/smoke/detector/`: `inputs.json`, `timestamps/` from `openai_whisper-base.en` at the
pinned commit, `goldens.json`; 292 KB, smoke folder 4.5 MB of 5). `SmokePlacementGoldenTests` replays them in
`make test`. Release-built `am-eval` and the debug test agree on every L1 digest. With the initial (untuned)
thresholds: 53 items, 129 decided words, 108 present; 70 flagged before suppression, 11 after (9 of the 100
stress-correct words, 2 of the 20 stress-wrong ones). Never a rate gate.

**l2-shared (reported, not gated; initial thresholds, untuned).** Word timings were recorded once with
`am-eval record-timings --set l2-shared` (1,178 utterances, `openai_whisper-base.en`, into the git-ignored
`eval-cache/speechocean762-timings`), then `scripts/agreement.sh --suite l2-shared` replays them:
- recall: 134 words, 41 present; 23 flagged before suppression, **5 after (3.7%)**.
- clean 1,400: 1,091 present; 701 flagged before suppression, **150 after (10.7%, Wilson [9.2%, 12.4%])**. The plan's
  bar for the shipped config is ≤ 1.6%, so these initial values are far off it. That is spec 11's tuning question and
  goes to CTO. Nothing was tuned or lowered here.
- **157 unintelligible: 0 placement diffs.** Whisper hears none of them as the transcript word, so all are absent
  (inconclusive), and 4 have no A(w).
- Most recall words are absent because Whisper base.en transcribes a stress-wrong L2 word as a different word, so
  the aligner marks it substituted. The detector never sees those words, which caps recall whatever the thresholds.
  Worth a look in spec 11 or 23.
