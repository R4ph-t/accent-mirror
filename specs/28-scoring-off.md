# 28: Scoring off, show-don't-judge v1 (verdict paths gated out of the shipped app)

Status: Ready · Branch: – · Depends on: 10, 12, 15, 16, 19 (all Done; spike 27's NO-GO is the reason, report in docs PR #69) · Estimate: 6–8 h agent run + 2 h Raph review · Risk: high

Risk: high. This changes the analysis contract (`Verdict`, `AnalysisIdentity`), persisted takes, the package graph and the presenter. It merges only after CTO's review and Raph's Merge OK (review verdict `hold`). It must not touch `Thresholds.swift`, `project.yml`, entitlements, `Resources/Models/`, `Resources/Starter/` or the agreement corpus.

Source: Designer spec v3 (Notion "Accent Mirror v1: show, don't judge", https://app.notion.com/p/4220d0d4459281d39d67d6fdc5d50dfc), §7 ("AccentKit may still compute verdicts for evaluation, but the presenter drops them") and §4 (inspector measures with the native range); v3 wins over v2 and addenda r2–r6. This spec is the engine and contract side only. The v3 UI (card 1 YOUR TAKE and Play Both, strip, inspector, earlier takes, connectors, legends, fixtures, the banned-word test) is spec 29. Raph's decision at 18:42 Europe/Paris on 2026-11-24, relayed by CPO: "Yes, ship v1 as show-don't-judge, and merge #68". The plan "Accent Mirror v1 show-don't-judge integration plan (2026-11-24)" (Notion Bot Docs, https://app.notion.com/p/4220d0d4459281399adef9364a99bb69), which CTO approved with 8 changes (all folded in here). CTO decision record "Accent Mirror: stress and prosody reformulation" (https://app.notion.com/p/4220d0d445928128b258faf2852259c1). Spike 27 report `docs/agreement/reports/spike27-69675122.md` (NO-GO: on natives, the dictionary-stressed syllable is the longest, loudest or highest only 50–70% of the time).

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

### 3. The presenter ignores verdicts (app, minimal)

Spec 29 does the v3 UI. This spec only makes sure no view reads a verdict.

- `ShellPresenter` and `Copy.swift` stop reading `Verdict` (every case), `DiffRow`, `StressLine`, `NeutralReason`, `InconclusiveReason` and measure states.
  - On any analysed result, scored legacy takes included, card 1 shows the title "YOUR TAKE" and no rows. Spec 29 adds the result row and Play Both.
  - The inspector shows no measure states, no STRESS lines and no diff icons.
  - The strip and pitch card are drawn as they are today. Spec 29 changes how they look.
- The fixture schema (`AccentMirror/Resources/Fixtures/SCHEMA.md`, `FixtureModel.swift`) accepts `verdict: {"notScored": {}}` and a missing verdict. The existing verdict fixtures still decode, and spec 29 retires them (v3 §10).
- The verdict copy functions in `Copy.swift` are deleted only if nothing else calls them. Otherwise they're left unused for spec 29 to remove with its banned-word test.
- VoiceOver doesn't announce a card-1 sentence for an analysed take. Spec 29 adds v3's "Result ready. Your take is drawn over the model's."

### 4. Context-resolved expected stress (AMPipeline)

This is the data behind spec 29's dictionary-stress mark (v3 §3.2). This spec provides it but draws nothing.

- The model's syllables carry the expected stress pattern resolved in context:
  - the phrase's pronunciation override (spec 06/15) first;
  - then part of speech for known heteronyms;
  - then the dictionary.
- **`expectedAmbiguous`** words carry no expected pattern.
- **Where it goes:** reuse `SyllableMeasure.stress` with `stressSource == .dictionary` for the model side, populated from the resolved pattern, not the raw CMUdict primary. If that can't express ambiguity, add an optional `expectedStress` to `WordSpan`, decoding as nil for old takes. Record which in Implementation notes.
- **This moves into `AMPipeline`**, since it's no longer reached through `Scorer`'s `StressLine.expectedPattern`. One function is shared with `AMVerdicts`; don't copy it.
- **Test:** a phrase whose override or part of speech differs from CMUdict's first entry. Use any starter phrase with an override, or a test fixture built from `docs/agreement/spike27/heteronyms.json` once that's on main, or else a synthetic one. The resolved primary follows the override, not CMUdict's first entry.
- **Caveat for every consumer:** native acoustics follow this pattern only 50–70% of the time (spike 27). It's the lexical pattern, not what the speaker did.

### 4a. Descriptive measures and the native range (AMPipeline)

v3 §4's inspector shows plain measures for you, next to the range across the phrase's native voices. These are measurements, not verdicts, so they live in `AMPipeline`, not in `AMVerdicts`.

- **Add `AnalysisResult.describe: DescribedMeasures`**, optional so it decodes as nil for old takes. It holds:
  - `you`: length (s), syllables per second, pitch range P10–P90 (st), rhythm nPVI and ending direction (`rising`, `falling` or `level`);
  - `native`: the min–max of each across the phrase's bundled native voices (spec 15's per-recording analyses), plus a count of ending directions ("5 falling, 3 rising"). For a single native take (an imported clip), it's that take's value.
- Each value is a `MeasureState`-style value-or-reason, so a missing measure shows "—" with a reason.
- **No thresholds and no comparison:** nothing here says whether you're inside the range.
- **Reuse the pure functions** (P10–P90, nPVI, final slope) by moving them from `AMScoring` down to `AMPipeline` or `AMProsody`, not by copying them. `AMScoring` keeps calling them.
- **The ending-direction cut-off** is a display constant here, not a `Thresholds` key. Record its value in Implementation notes.
- **Tests:** the values on two starter phrases equal the ones `AMScoring` computes for the same inputs today, and the native range covers every bundled voice.

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
- **Presenter tests:** on `.notScored` and on a legacy scored take, the analysed state has card 1 "YOUR TAKE" with no rows. A source scan finds no reference to `Verdict`, `DiffRow` or `StressLine` in `ShellPresenter.swift` and `Copy.swift`.
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

- The whole v3 UI: card 1's result row and Play Both, the strip's bars, dictionary-stress mark, labels and timing connectors, legends, the inspector's MEASURE / YOU / NATIVE RANGE table, earlier takes on by default with ⇧⌘G, retiring the `mistake` token from views, the v3 fixture set, and the banned-word test. That's spec 29.
- Live strip, playhead and earlier takes (spec 20). Wiring the coordinator and microphone (spec 21).
- Any new prosody measure, and spike 27's per-prompt native envelope.
- Milestone 2 (linking `AMVerdicts` into the app).

## Open question (built with the default)

1. Expected stress lives in `SyllableMeasure.stress` (default) or a new `WordSpan.expectedStress`. Use the default unless it can't express `expectedAmbiguous`.
2. On `.notScored`, the inspector's TIMING row reads the existing timing level only. Default: keep it, since it describes the alignment, not the speaker.

## How to test (Raph)

1. `make review PR=<n>`, then `make check` and `make test-vm`. Everything passes, including `ScoringOffTests`, `ShippedGraphTests`, the two new goldens and the descriptive-measure tests. **pass/fail**
2. `rg -n 'import AM(Scoring|Verdicts)' AccentMirror` prints nothing. `rg -n '"AMScoring"' Packages/AccentKit/Package.swift` shows it only in the `AMVerdicts` and `AMScoring` entries. **pass/fail**
3. Launch the app and open a few fixture results, both scored and not scored. Card 1 reads "YOUR TAKE" with no rows. There's no sentence about stress or closeness, and no STRESS lines or measure states in the inspector. The strip and pitch card are drawn. **pass/fail**
4. Open a take saved before this build, from the take store or a copied take folder. It opens without an error and shows the same unjudged screen. **pass/fail**

## Implementation notes

_(filled in by the agent)_
