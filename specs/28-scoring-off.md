# 28: Scoring off, show-don't-judge v1 (verdict paths gated out of the shipped app)

Status: Ready · Branch: – · Depends on: 10, 12, 15, 16, 19 (all Done; spike 27's NO-GO is the reason, report in docs PR #69) · Estimate: 6–8 h agent run + 2 h Raph review · Risk: high

Risk: high. This changes the analysis contract (`Verdict`, `AnalysisIdentity`), persisted takes, the package graph and the presenter. It merges only after CTO's review and Raph's Merge OK (review verdict `hold`). It must not touch `Thresholds.swift`, `project.yml`, entitlements, `Resources/Models/`, `Resources/Starter/` or the agreement corpus.

Source: Raph's decision at 18:42 Europe/Paris on 2026-11-24, relayed by CPO: "Yes, ship v1 as show-don't-judge, and merge #68". The plan "Accent Mirror v1 show-don't-judge integration plan (2026-11-24)" (Notion Bot Docs, https://app.notion.com/p/4220d0d4459281399adef9364a99bb69), which CTO approved with 8 changes (all folded in here). CTO decision record "Accent Mirror: stress and prosody reformulation" (https://app.notion.com/p/4220d0d445928128b258faf2852259c1). Spike 27 report `docs/agreement/reports/spike27-69675122.md` (NO-GO: on natives, the dictionary-stressed syllable is the longest, loudest or highest only 50–70% of the time).

## Goal

v1 shows the learner's pitch and timing against the native reference and never judges. No stress verdict, no phrase verdict, no diff rows, no "close" or "no clear difference" sentence.
- The verdict code stays in the repo, compiled and tested, so Milestone 2 can bring it back once a model clears spec 27's gates.
- The shipped app **can't** call it, because it doesn't link the verdict code. That's enforced by the package graph, not by a flag the app could flip.

## Behaviour

### 1. Verdict contract (AMCore)

- `Verdict` gains `case notScored`. Its JSON is `{"notScored": {}}`, in the same canonical form as the other cases.
- `AnalysisIdentity` gains `scoringMode: ScoringMode`, with `enum ScoringMode: String, Codable { case off, on }`.
  - When the key is missing (a take saved before this change), it decodes as `.on`, because those takes were scored.
  - Canonical JSON writes the key for every new take.
- **Versions:**
  - `algorithmVersion` and `thresholdsVersion` don't change. A bump would needlessly throw away L1 caches; CTO's call.
  - `contractVersion` stays at 2. The change is additive and old JSON still decodes.
  - The L2 cache key includes `scoringMode`, so an `.on` result is never served for an `.off` request, or the other way round. The L0 and L1 keys don't change.
- When `scoringMode == .off`:
  - `verdict` is `.notScored`;
  - `measures` and `applicability` are empty;
  - `stress` (the `[StressLine]`) is empty.
  - Everything else is computed exactly as today: `model`, `you`, `timeMap`, `youPitchOnModel`, `nativeBand`, `pitchAxis` and `timing`.

### 2. Package split: the shipped app can't reach scoring

**Today:** the app links the `AMPipeline` product only (`project.yml`), and `AMPipeline` depends on `AMScoring`. The verdict path runs through four places:
- `PairScoring.score` and `Scorer.score`, called from `Analyzer`;
- `StressPlacementDetector`'s decision tail (observed stress, confidence, `placementDecision`);
- `PlacementGolden`;
- `ResultAssembly`'s use of `Scoring`.

**After this spec:**
- **`AMPipeline` no longer depends on `AMScoring`.** Remove `"AMScoring"` from its entry in `Package.swift`'s `modules` and from `AMPipelineModule.dependencies`.
- **What stays in `AMPipeline`:**
  - L0/L1 (voicing, pitch, word timings, alignment, syllables with share and prominence);
  - the time map, the warp of your pitch onto model time, and the native band;
  - the context-resolved expected stress (§4).
  - Types `AMPipeline` needs from `AMScoring` move down: the warp and band inputs out of `ScoringInput`. Move them to `AMPipeline` or `AMWarp`; don't duplicate them.
- **New module `AMVerdicts`**, depending on `AMPipeline` and `AMScoring`. It holds:
  - `PairScoring.score`;
  - the decision tail of `StressPlacementDetector`: from observed stress onward, ending in `placementDecision`;
  - `PlacementGolden`;
  - `struct VerdictScorer: PairScorer`, the real scorer.
  - It's a product for evaluation (`am-eval`, `AMEvaluation`'s runners) and tests. **The app target doesn't link it**, and `project.yml` doesn't change.
- **In `AMPipeline`:**
  - `protocol PairScorer: Sendable { func score(_ input: PairScorerInput, thresholds: Thresholds) throws -> PairScore }` takes the inputs and returns verdict, measures, applicability and stress lines.
  - `struct NoOpScorer: PairScorer` returns `.notScored` and empties.
  - `ShippedConfig.scoring: ScoringMode = .off` and `ShippedConfig.scorer: any PairScorer = NoOpScorer()`.
  - `Analyzer.Configuration` takes a `scorer`, defaulting to `ShippedConfig.scorer`, and writes `scorer`'s mode into `AnalysisIdentity.scoringMode`.
- **Milestone 2** turns scoring back on by having the app link `AMVerdicts` and pass `VerdictScorer()`. That one-line `project.yml` change is a risky path, so it waits for Raph's Merge OK.
- **Existing tests** of `Scorer`, `placementDecision`, `StressPlacementDetector`, PairScoring natives and smoke placement goldens move to an `AMVerdictsTests` target and keep passing unchanged. `am-eval` links `AMVerdicts`.
- **Fallback:** if the split turns out to cost more than one day of agent time, stop the split and ship the guard test in §5 alone, with `NoOpScorer` selected by `ShippedConfig`. Say so explicitly in Implementation notes ("module split not done: <reason, measured cost>") and in the PR body. CTO expects the split, so the fallback needs his OK in review.

### 3. Presenter and copy (app)

On `.notScored`:
- **Card 1 ("WHAT TO CHANGE") isn't drawn on an analysed result.** No rows, no close / noClearDifference / inconclusive sentence, no placement-only line, no quiet line about measures.
  - Card 1 still appears for recording and for take problems ("YOUR TAKE" rows, Try Again).
  - Designer's neutral-comparison spec will replace this later.
- **The inspector** shows no measures with state or reason, and no STRESS lines. Timing match and model recording attribution stay.
- **Your row in the strip:** neutral `strip.you` bars, heights from measured share and prominence as today, **no Lime**. Measured stress isn't shown as stress.
- **The native row in the strip:** Lime only on syllables whose **context-resolved** expected stress is primary (§4), **never the raw CMUdict primary**, and never measured stress. `expectedAmbiguous` words get no Lime.
  - The legend or tooltip copy doesn't say the native "stressed" them. Spike 27: native acoustics follow the expected stress only 50–70% of the time, so the Lime marks the lexical pattern, not what the speaker did.
- **The native band is display-only.**
  - No copy, colour, icon or animation implies that pitch outside the band is wrong.
  - Your line keeps one colour inside and outside the band.
  - No "out of band" highlighting, no counts, no sentence about the band.
- VoiceOver doesn't announce a card-1 sentence for an analysed take. It announces "Result ready".
- The fixtures under `AccentMirror/Resources/Fixtures/` gain `.notScored` analysed states for the starter phrases. Existing scored fixtures stay, for Milestone 2.
- `Copy.swift` keeps its verdict sentences (unused on `.notScored`).

### 4. Context-resolved expected stress (AMPipeline)

- The model's syllables carry the expected stress pattern resolved in context:
  - the phrase's pronunciation override (spec 06/15) first;
  - then part of speech for known heteronyms;
  - then the dictionary.
- **`expectedAmbiguous`** words carry no expected pattern.
- **Where it goes:** reuse `SyllableMeasure.stress` with `stressSource == .dictionary` for the model side, populated from the resolved pattern, not the raw CMUdict primary. If that can't express ambiguity, add an optional `expectedStress` to `WordSpan`, decoding as nil for old takes. Record which in Implementation notes.
- **This moves into `AMPipeline`**, since it's no longer reached through `Scorer`'s `StressLine.expectedPattern`. One function is shared with `AMVerdicts`; don't copy it.
- **Test:** a phrase whose override or part of speech differs from CMUdict's first entry. Use any starter phrase with an override, or a test fixture built from `docs/agreement/spike27/heteronyms.json` once that's on main, or else a synthetic one. The native-row Lime follows the override.

### 5. Partial time map inverse lookup (investigate here, not in spec 20)

- Check whether `PartialTimeMap` can map model time to your time and back for any instant, as spec 20's playhead needs. Gaps return nil, never interpolate across a missing word.
- If it can't, add `func yourTime(atModel:) -> Double?` and `func modelTime(atYour:) -> Double?`, with tests:
  - round-trip within one hop on anchored spans;
  - nil inside gaps;
  - monotonic.
- If it already can, add the tests only.
- Record the finding in Implementation notes, so spec 20 builds on it.

### 6. Goldens and tests

- **Golden `analysed-legacy-scored.json`:** a take saved before this change, taken from a current golden as main has it today (no `scoringMode` key). It decodes, keeps its old verdict, reads `scoringMode == .on`, and re-encodes byte-identically, apart from the added `scoringMode` key, which the test strips before comparing.
- **Golden `analysed-not-scored.json`:** a `.notScored` take with `scoringMode: "off"`. It round-trips byte-identically through canonical JSON. `Versions.goldenDigests` gains its digest.
- **`ScoringOffTests`:**
  - the shipped `Analyzer` (default configuration) on every starter phrase's bundled analysis inputs yields `.notScored`, `scoringMode == .off`, empty `measures`, `applicability` and `stress`;
  - `timeMap`, `youPitchOnModel` and `nativeBand` are equal to today's for the same inputs;
  - there are no `DiffRow`s anywhere in the encoded result.
- **`ShippedGraphTests`:** `AMPipelineModule.dependencies` doesn't contain `AMScoring` or `AMVerdicts`. It also scans every `.swift` file under `AccentMirror/` (found from `#filePath`) and fails on `import AMScoring` or `import AMVerdicts`. It's a Swift test, not a Makefile change: the Makefile is a hand-spec path.
- **Presenter tests:**
  - on `.notScored`, card 1 isn't present in the analysed state;
  - the native row's Lime spans equal the context-resolved primaries;
  - your row has no `.stressed` fill;
  - no band-related copy exists.
- **The take store** (spec 16) reads the legacy golden and the new one from disk.

## Defaults

- `ShippedConfig.scoring = .off`, `ShippedConfig.scorer = NoOpScorer()`.
- A legacy take with no `scoringMode` key decodes as `.on`.
- The module name is `AMVerdicts`.
- The take store keeps showing legacy scored takes as they are. They're re-analysed as `.notScored` the next time they're opened, from the L1 cache (L2 recomputes because its key changed).

## Guardrails

- Never loosen or retune a gate. `Thresholds.swift` and `thresholdsVersion` are untouched, and `algorithmVersion` is unchanged.
- Delete no verdict code. Moving it is fine. Every existing scoring, placement and golden test keeps passing in its new target.
- No spec 25, 26 or 27 code. The nucleus detector, the classifier and `AMSpike27` stay on their branches. Whisper word timings stay the runtime source.
- No network, no TTS in the app (`scripts/check-no-tts-in-app.sh` stays green).
- No secrets or personal paths in code, comments, fixtures or the PR.

## Out of scope

- Designer's neutral comparison card (replaces card 1 in the analysed state): a later spec.
- Live strip, playhead and earlier takes (spec 20). Wiring the coordinator and microphone (spec 21).
- Any new prosody measure, and spike 27's per-prompt native envelope.
- Milestone 2 (linking `AMVerdicts` into the app).

## Open question (built with the default)

1. Expected stress lives in `SyllableMeasure.stress` (default) or a new `WordSpan.expectedStress`. Use the default unless it can't express `expectedAmbiguous`.
2. On `.notScored`, the inspector's TIMING row reads the existing timing level only. Default: keep it, since it describes the alignment, not the speaker.

## How to test (Raph)

1. `make review PR=<n>`, then `make check` and `make test-vm`. Everything passes, including `ScoringOffTests`, `ShippedGraphTests` and the two new goldens. **pass/fail**
2. `rg -n 'import AM(Scoring|Verdicts)' AccentMirror` prints nothing. `rg -n '"AMScoring"' Packages/AccentKit/Package.swift` shows it only in the `AMVerdicts` and `AMScoring` entries. **pass/fail**
3. Launch the app and open each starter phrase's fixture result. There's no "WHAT TO CHANGE" card, no sentence about stress or closeness, and no STRESS lines or measures in the inspector. The strip and pitch card are drawn. **pass/fail**
4. In the strip, your bars have no Lime. The native row's Lime sits on the expected stressed syllables, including the 2 Compound Nouns phrases (005 and 006: the first part of the compound). **taste call (Raph)**
5. In the pitch card, push your line outside the band (any fixture where it leaves the band). Nothing changes colour, and no copy appears. **pass/fail**
6. Open a take saved before this build, from the take store or a copied take folder. It opens without an error and, once re-analysed, shows the unjudged result. **pass/fail**

## Implementation notes

_(filled in by the agent)_
