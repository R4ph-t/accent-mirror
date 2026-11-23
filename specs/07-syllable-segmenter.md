# 07: Syllable segmenter and timing confidence

Status: Ready · Branch: – · Depends on: 06 (syllable counts; word boundaries are injected, and the real-speech gates
wait on 23) · Estimate: 3–4 h agent run + 1 h Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): row 07 ("as before; the real-speech boundary check uses MFA as a baseline; human boundary labels are
dropped", Raph 09:14), §2 (lengthening exposure), §5 and first v2 §5 (confidence), v1 `SyllableSegmenter`, CTO
decision 4 (~80 ms padding). Amended by CTO's ruling on spec 03 (2026-11-23 13:00): word boundaries are injected (spec
23 refines them after Whisper), padding is this spec's analysis-window choice, the synthetic gate runs on TTS marker
timings, and only the real-speech gates wait for spec 23.

## Goal

Split each `present` word's span into its dictionary syllables, compute raw per-syllable duration and intensity,
mark lengthening-exposed syllables, and score word, syllable and take timing confidence. This is the L1
segmentation stage (§9.2). It builds against an injected word-boundary source, so it needs neither spec 03's ASR
code nor spec 23's refiner.

## Behaviour

- Input: the take's 16 kHz samples, the `WordAlignment` (spec 06), each word's syllable count and phones (spec 06),
  **injected word boundaries** (one `WordSpan` per phrase word, with start, end and the ASR word probability) and a
  `VoicingSource` (the protocol from spec 01; tests use a synthetic source, the pipeline wires spec 05's `ACFVoicing`).
- `WordSpan` is a small value type this spec defines next to the segmenter (start and end in seconds, probability
  0–1). It doesn't import spec 03 or spec 23. The pipeline (spec 12) maps spec 03's `WordTimestamp`, after spec 23's
  `WordBoundaryRefiner`, onto it. Tests inject spans directly.
- Only `present` words get syllables. `substituted` words keep their word edges only (anchors for spec 09) and are
  never measured.
- Padding (this spec's analysis window, moved here from spec 03 by CTO's ruling): each injected word span is widened
  by about 80 ms on both sides before searching, clamped so it never crosses the neighbouring word's unpadded span or
  the take's ends. The padding is a search window only. Reported word and syllable boundaries are never the padded
  edges.
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
- **Synthetic gate (TTS markers are the boundary truth).** A set of short phrases is spoken by an on-device
  `AVSpeechSynthesizer` English voice with `write(_:toBufferCallback:toMarkerCallback:)`. The word markers' sample
  offsets are the word boundaries, injected as `WordSpan`s with probability 1, and they're the truth for this gate.
  The gate: every word boundary the segmenter reports stays within 10 ms of the injected marker (padding never moves
  it), and syllable counts match the dictionary. Syllable-boundary truth isn't available from TTS, so syllable
  accuracy stays with the pulse train. The phrases and the voice identifier are pinned in the test. Audio is
  generated at test time, never committed, and nothing is fetched. If no English voice is installed, the test is
  skipped with that reason and the PR says NOT RUN.
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

0. **Real-speech gates wait on spec 23.** The speechocean762 recall check and the VCTK false-positive check (spec 02's
   sets), and the MFA syllable-boundary bar below, run only once spec 23 has shipped a refiner. Until then, the report
   prints those lines as NOT EVALUATED (waiting on spec 23), which is not a pass. The code paths and the report shape
   are built now.
   **CTO ruling, 2026-11-23 14:05:** the boundaries these gates run on are spec 23's b2 (`ctc-w2v2b960-1`), through
   the same injected `WordSpan` source. A word below b2's CTC confidence threshold arrives with probability 0, so
   it is inconclusive under the existing c_w rule. The oracle-vs-b2 comparison harness (the downstream ship gate for
   b2) is in **spec 23**, which runs this segmenter. This spec doesn't import spec 23, and nothing here changes in
   code.
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
   - padding never crosses a neighbouring word, and reported word boundaries are never the padded edges;
   - the TTS marker gate: reported word boundaries stay within 10 ms of the injected markers (or the test is
     skipped with "no English voice");
   - a substituted word has edges but no syllables;
   - the last syllable and a syllable before a 200 ms pause are exposed; one before a 100 ms pause isn't;
   - a take with 60% of syllables at medium or above is Rough.
3. Optional, local: `scripts/eval-syllables.sh` writes the report. The real-speech lines print NOT EVALUATED
   (waiting on spec 23) until spec 23 ships.

## Implementation notes

Built 2026-11-23 on `factory/07-syllable-segmenter` (hand build, Claude Code).

- **Where.** `AMProsody`: `SyllableSegmenter.swift` (the segmenter, its nested `WordSpan` and `Input`) and
  `Segmentation.swift` (the L1 output: `SyllableSegmentation` with its `Key` and `digest()`, `SegmentedWord`,
  `SyllableSplit`, `SegmentedSyllable`, and the level and timing rules). `WordSpan` is nested as
  `SyllableSegmenter.WordSpan` because AMCore already has a public `WordSpan` (the contract's display word).
- **Word edges.** Reported word edges are the injected span, clamped to the take. The first syllable starts at the
  word start and the last ends at the word end, so word timing is the union of its syllables. The padded window
  (`alignment.asrPaddingMs`, clamped at neighbours' unpadded spans and the take's ends, never narrower than the span)
  is recorded per word as `searchWindow` and used only to find nuclei: a peak counts if it is a local maximum within
  the window and lies inside the unpadded span.
- **Split.** 10 ms frame RMS (vDSP) smoothed over 5 frames; voiced nuclei are voiced local maxima, neighbours merged
  across valleys shallower than `confidence.splitValleyMinDB` (3 dB), giving the peak count P. Boundaries are the
  N − 1 deepest envelope minima inside the span (each at least 0.5 dB below both sides), keeping every syllable at
  least 40 ms long and voiced. If that can't give N − 1 boundaries, the split is proportional to phone count. s_w =
  max(0, 0.9 − 0.3·|P − N|) on the valley path, 0.35 on the fallback.
- **Features.** d = syllable duration; e = RMS over the syllable's samples in dBFS, floored at −60
  (`prominence.energyMinimumDBFS`). Exposure: no syllable, substituted word or inserted word follows, or the next one
  starts more than `prominence.exposurePauseMs` after the syllable ends.
- **Timing.** The share of all segmented syllables at medium or above (`SyllableSegmenter.timing(of:thresholds:)`).
  An empty take is Poor.
- **Key.** `l0Key` (opaque string from the caller), `transcriptRevision`, `pronunciationHash` (SHA-256 of the
  canonical JSON of `[{word, arpabet}]` sorted by word) and `algorithmVersion`. `digest()` is the SHA-256 of the
  output's canonical JSON.
- **Thresholds.** Added `confidence.spanSanityMinMs` 60, `.spanSanityMaxMs` 1500, `.spanSanityFailed` 0.3,
  `.splitValleyMinDB` 3, `.splitExact` 0.9, `.splitPerMismatch` 0.3, `.splitFallback` 0.35 and
  `syllableBoundaries.medianErrorMaxMs` 30, `.withinToleranceMs` 50, `.withinToleranceShareMin` 0.80 (first v2
  values, not tuned). `thresholdsVersion` 3 → 4 with a new golden record.
- **TTS gate.** `TTSMarkerGateTests`: voice `com.apple.voice.compact.en-US.Samantha` (on this Mac and on the
  macos-26 runner, so the gate runs in CI), three pinned phrases with pinned ARPAbet. Each phrase is spoken as SSML
  with a named bookmark `w<N>` before each word. Bookmarks are read from both the `write` marker callback and the
  delegate's `willSpeak marker:` (macOS 26 voices use only the delegate) and kept once per name. Synthesis ends at
  the zero-length final buffer plus `didFinish`. Phrases are synthesized one at a time (`.serialized`): concurrent
  synthesizers lost markers on the runner (fix round 1). A missing, extra or out-of-order bookmark fails the test.
  A marker's `byteSampleOffset` is divided by the buffer's bytes per frame. Its resolution is the synthesizer's
  512-sample buffer (about 23 ms at 22.05 kHz), which doesn't matter because the marker is the truth by definition.
  Each word span runs from its bookmark to the next (the last to the end of the audio). Audio is resampled to
  16 kHz in memory.
- **Report.** `AMSyllableEval` + `am-syllables` + `scripts/eval-syllables.sh` (sandboxed, no network, reads no
  corpus) write `syllable-boundaries-<configDigest8>.{json,md}`. The MFA reference groups MFA phones into syllables
  by position, using spec 06's syllabifier on the segmenter's pronunciation, so english_mfa's non-ARPAbet phones
  need no mapping; a word whose phone count differs is excluded. All five real-speech lines print NOT EVALUATED
  (waiting on spec 23).
