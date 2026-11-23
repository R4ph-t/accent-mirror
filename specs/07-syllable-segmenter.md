# 07: Syllable segmenter and timing confidence

Status: Ready · Branch: – · Depends on: 03 (replayed word timings), 06 (syllable counts) · Estimate: 3–4 h agent
run + 1 h Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): row 07 ("as before; the real-speech boundary check uses MFA as a baseline; human boundary labels are
dropped", Raph 09:14), §2 (lengthening exposure), §5 and first v2 §5 (confidence), v1 `SyllableSegmenter`, CTO
decision 4 (~80 ms padding).

## Goal

Split each `present` word's span into its dictionary syllables, compute raw per-syllable duration and intensity,
mark lengthening-exposed syllables, and score word, syllable and take timing confidence. This is the L1
segmentation stage (§9.2). Runs on replayed word timings in CI.

## Behaviour

- Input: the take's 16 kHz samples, the `WordAlignment` (spec 06), each word's syllable count and phones (spec 06),
  word timings with probabilities (`FixtureTimestamper` from spec 03 in tests), and a `VoicingSource` (the protocol from spec 01; tests use a synthetic source, the pipeline wires spec 05's
  `ACFVoicing`).
- Only `present` words get syllables. `substituted` words keep their word edges only (anchors for spec 09) and are
  never measured.
- Padding: each Whisper word span is widened by about 80 ms on both sides before searching, clamped so it never
  crosses the neighbouring word's unpadded span or the take's ends.
- Boundaries: at intensity-envelope minima between voiced nuclei, constrained to the dictionary syllable count. If
  that fails, split proportionally to phone count. When the dictionary count and the number of energy peaks
  disagree, the dictionary count wins and confidence drops.
- Confidence (first v2 §5, "as before"):
  - word: c_w = min(ASR word probability, span sanity), span sanity 1.0 if the span is 60 ms–1.5 s and doesn't
    overlap its neighbours, else 0.3;
  - syllable split per word: s_w = 0.9 when energy valleys of 3 dB or more match the dictionary count exactly; 0.9 −
    0.3·k when count and peaks differ by k; 0.35 for the proportional fallback;
  - syllable: min(c_w, s_w); levels high ≥ 0.7, medium ≥ 0.45, else low;
  - take timing: share of comparable syllables at medium or above → Good ≥ 0.8, Rough ≥ 0.5, else Poor.
- Per syllable, raw features: duration d (seconds), mean RMS e in dBFS floored at −60. Peak F0 is added in spec 08
  from spec 04's track.
- Lengthening exposure (§2): a syllable is exposed if it is the last syllable before the end of the take or before a
  pause longer than 150 ms. The flag is part of L1; the discount itself is spec 08.
- L1 output is `Codable` with its identity key (L0 key + transcript revision + pronunciation hash +
  `algorithmVersion`) and a digest, so specs 08 and 10 can golden-test it.

## Defaults

- The synthetic pulse-train fixture (a 3 s train of known syllable envelopes over voiced carriers) is generated in
  test code, with matching synthetic word timings.
- Real-speech check (local, not `make check`): see Open question 1. Report at
  `docs/agreement/reports/syllable-boundaries-<configDigest8>.{json,md}` with the §6.6 identity header from spec
  02 when present.

## Guardrails

- DTW never produces syllable boundaries, durations or stress, and never raises a confidence (first v2 §5). This
  spec has no DTW.
- No ASR at test time; CI replays timings. No AppKit or UIKit. Never lower the boundary bars quietly.

## Out of scope

- Prominence, observed stress and the exposure discount (spec 08). Time map and DTW (spec 09). Live ASR (spec 03).

## Open question (built with the default)

1. **Real-speech bar with MFA instead of hand labels.** The first v2 asked for 200+ hand-labelled VCTK held-out
   boundaries from ≥ 6 speakers, median ≤ 30 ms and ≥ 80% within 50 ms, with calibrated confidence. Raph dropped hand
   labels (09:14) and the row now says "MFA as a baseline". Default: Montreal Forced Aligner phone alignments of
   the 12 held-out VCTK speakers' clips (from spec 02's manifest), syllabified with spec 06's syllabifier, are the
   reference; the first v2 bars and the calibration check (low-confidence syllables have larger error) apply; MFA
   version and model are pinned in the report. If MFA or spec 02's clips aren't available, the line is NOT
   EVALUATED, never a pass. A FAIL goes to CTO.

## How to test (Raph)

1. `make check` is green.
2. `swift test --package-path Packages/AccentKit --filter SyllableSegmenterTests` passes:
   - on the pulse train, every boundary is within 40 ms of truth;
   - a word whose energy shows one peak fewer than the dictionary count keeps the dictionary count and gets s_w =
     0.6;
   - a 1.8 s word span gets span sanity 0.3;
   - padding never crosses a neighbouring word;
   - a substituted word has edges but no syllables;
   - the last syllable and a syllable before a 200 ms pause are exposed; one before a 100 ms pause isn't;
   - a take with 60% of syllables at medium or above is Rough.
3. Optional, local: `scripts/eval-syllables.sh` writes the report or prints NOT EVALUATED.

## Implementation notes

_(filled in by the agent)_
