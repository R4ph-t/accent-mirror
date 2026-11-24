# 28: Scoring off, show-don't-judge v1 (verdict paths gated out of the shipped app)

Status: Ready · Branch: – · Depends on: 10, 12, 15, 16, 19 (all Done; spike 27's NO-GO is the reason, report in docs PR #69) · Estimate: 6–8 h agent run + 2 h Raph review · Risk: high

Risk: high. This changes the analysis contract (`Verdict`, `AnalysisIdentity`), persisted takes, the package graph and the presenter. It merges only after CTO's review and Raph's Merge OK (review verdict `hold`). It must not touch `Thresholds.swift`, `project.yml`, entitlements, `Resources/Models/`, `Resources/Starter/` or the agreement corpus.

CTO reviewed fd70e76 on 2026-11-24 with 6 must-fixes (2–6 approved on 63073cf). A re-review of 63073cf found that must-fix 1, as first written, created a module cycle (`AMScoring` uses the moved symbols; `AMVerdicts` depending on `AMScoring` would cycle). The layout below (new leaf module `AMPlacement`) is the fix, folded in here.

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
- When `scoringMode == .off` and the take-problem gate (§1a) has passed:
  - `verdict` is `.notScored`;
  - `measures` and `applicability` are empty;
  - `stress` (the `[StressLine]`) is empty.
  - Overlay fields are computed in `AMPipeline`, not by the scorer: `model`, `you`, `timeMap`, `youPitchOnModel` (`warp.pitchOnModel`), `nativeBand`, `pitchAxis` and `timing` (`warp.timing`).
  - **`comparableCoverage`** is on `AnalysisResult` as `Double?` (the value already on `TimeWarp.comparableCoverage` / `DecisionInput`). Nil for takes saved before this change. Spec 29's low-coverage quiet line reads it.
- A `nil` `describe` is omitted from canonical JSON, not written as `null`, so the legacy golden re-encodes cleanly once `scoringMode` is stripped (CTO).

### 1a. Take-problem gate (shipped, not owned by the scorer)

`Scorer` today calls `decide()`, and steps 1–2 of that function (`DecisionProcedure.swift:104–116`) return `.takeProblem` for quality problems and for `wordsDontMatch` (`alignment.matchShare` below `minMatchShare`, or too many non-filler insertions). A `NoOpScorer` that always returned `.notScored` would draw unalignable takes as results.

- **Keep steps 1–2 on the shipped path**, as a gate function in `AMCore` or `AMPipeline` that the scorer doesn't own. Name it in Implementation notes (e.g. `TakeProblem.gate` or `decideTakeProblem`).
- Steps 3 onwards of `decide()` (inconclusive, diffs, close) stay with `VerdictScorer` in `AMVerdicts`.
- The shipped `Analyzer` runs the gate **before** calling the scorer. If it fires, the outcome is `.takeProblem` as today, and the scorer is not called.
- If it passes and `scoringMode == .off`, the outcome is `.analysed` with `.notScored`.
- **Test:** a words-don't-match take and a too-short take still come back `.takeProblem` under `NoOpScorer`. A clean take comes back `.notScored`.

### 2. Package split: the shipped app can't reach scoring

**Today:** the app links the `AMPipeline` product only (`project.yml`), and `AMPipeline` depends on `AMScoring`. The verdict path runs through four places:
- `PairScoring.score` and `Scorer.score`, called from `Analyzer`;
- `StressPlacementDetector.place` in full (observed stress, confidence, `placementDecision`, suppression);
- `placementDecision`, `PlacementDecision` and `PlacementSuppressionReason` (`AMProsody/Placement.swift:8–68`), `WordAcceptedSet` (`AcceptedSet.swift`) and `TakeProminence.observedStress(of:)` / `ObservedStress` (`ObservedStress.swift:71–123`);
- `PlacementWordResult.decision`, `.suppression` and `.observed`, which today are stored on `PlacementAnalysis` inside `L1Analysis`;
- `PlacementGolden`;
- `ResultAssembly`'s use of `Scoring`.

**Why not move those symbols into `AMVerdicts`:** `AMScoring` already imports and calls them. `ScoringInput.accepted` is a `WordAcceptedSet`, and `StressMeasures` holds `ObservedStress`, `PlacementDecision` and `PlacementSuppressionReason` and calls `placementDecision` (`StressMeasures.swift:20, 32–84`). Putting the symbols in `AMVerdicts` while `AMVerdicts` depends on `AMScoring` is a module cycle (CTO re-review of 63073cf).

**After this spec (CTO layout):**
- **New leaf module `AMPlacement`.** It holds `WordAcceptedSet`, `ObservedStress`, `TakeProminence.observedStress(of:)` (as a method or extension on `AMPlacement`, not left on `AMProsody`), `PlacementDecision`, `PlacementSuppressionReason`, `placementDecision`, and `StressPlacementDetector.place`. Don't leave a copy of any of these in `AMProsody` or `AMPipeline`. `AMPlacement` depends only on already-shipped modules (`AMCore`, `AMProsody`, `AMAlignment`, `AMPitch` as needed); it does not depend on `AMScoring`, `AMVerdicts` or `AMPipeline`.
- **`AMScoring` and `AMVerdicts` both depend on `AMPlacement`.** `AMScoring` keeps `Scorer`, `StressMeasures`, `ScoringInput` and the other scoring types, now importing the placement symbols from `AMPlacement` instead of `AMProsody`. `AMVerdicts` holds `PairScoring.score` / `PairScoring.input`, `PlacementGolden`, and `struct VerdictScorer: PairScorer`. `AMVerdicts` may depend on `AMScoring` and `AMPlacement`; there is no cycle.
- **Nothing on the shipped path depends on `AMPlacement`, `AMScoring` or `AMVerdicts`.** The app still links only the `AMPipeline` product (`project.yml` doesn't change). Remove `"AMScoring"` from `AMPipeline`'s entry in `Package.swift`'s `modules` and from `AMPipelineModule.dependencies`. Do not add `AMPlacement` or `AMVerdicts` there.
- **What stays in `AMPipeline` (and in `AMProsody` as a shipped dependency):**
  - L0/L1: voicing, pitch, word timings, alignment, syllables with share and prominence **display**;
  - the time map, `PairScoring.warp` (already in `AMPipeline`), the warp of your pitch onto model time (`warp.pitchOnModel`), `warp.timing`, and the native band;
  - the context-resolved expected stress (§4);
  - the take-problem gate (§1a) and `NoOpScorer`.
- **What moves down from `AMScoring` into `AMPipeline` (or `AMWarp` / `AMProsody`), because the shipped path still needs it after `youPitchOnModel` and `timing` come from `TimeWarp`:**
  Checked against main (`AMScoring/` and its uses in `AMPipeline/`):
  - `PitchDirection` and `PitchDirection.init(slope:thresholds:)` (`PitchMeasures.swift:12–20`) and `FinalWindow` (`PitchMeasures.swift:22–`), for §4a ending direction;
  - the pure measure helpers §4a reuses: P10–P90 (`PitchMeasures.range` / `percentile`), least-squares slope (`PitchMeasures.slope`), and nPVI (`StressMeasures.npvi`, today at `StressMeasures.swift:230`).
  - Don't copy them; `AMScoring` keeps calling the moved symbols.
  - **Does not move down** (verdict-only, stays in `AMScoring` / `AMVerdicts`): `Scorer`, `Scoring`, `TriggeredDiff`, `ScoringInput`, `ScoringWord`, `ScoringTake`, `WordPlacement`, `ScoringSuppression`, `StressMeasures` placement/contrast helpers, and `PairScoring.input` / `PairScoring.score` (they build `ScoringInput` and call `Scorer`). After the split, `ResultAssembly` no longer takes a `Scoring` value; it reads `warp.pitchOnModel`, `warp.timing`, `describe` and `comparableCoverage` from `AMPipeline`.
- **L1 stores no decision.** Remove `decision`, `suppression` and `observed` from the type stored in `L1Analysis` (today `PlacementWordResult` on `PlacementAnalysis`). L1 keeps alignment, segmentation, pitch and prominence display. Old L1 records still decode, because unknown keys are ignored; add a test that a pre-change L1 JSON with those keys decodes and the fields are gone on the new type.
- **In `AMPipeline`:**
  - `protocol PairScorer: Sendable { func score(_ input: PairScorerInput, thresholds: Thresholds) throws -> PairScore }` takes the inputs and returns verdict, measures, applicability and stress lines. It also exposes `var mode: ScoringMode`.
  - `struct NoOpScorer: PairScorer` has `mode == .off`. After the take-problem gate has passed, it returns `.notScored` and empties. It does not call `decide()`.
  - `struct VerdictScorer: PairScorer` has `mode == .on` and runs the existing scoring path.
  - **`ShippedConfig.scoring` is derived from `ShippedConfig.scorer.mode`**, so there's one source of truth (CTO). `ShippedConfig.scorer` is `NoOpScorer()`.
  - `Analyzer.Configuration` takes a `scorer`, defaulting to `ShippedConfig.scorer`, and writes `scorer.mode` into `AnalysisIdentity.scoringMode`.
- **Evaluation is pinned to `VerdictScorer`.** `am-eval`, every `AMEvaluation` runner and the `PlacementGolden` smoke tests pass `VerdictScorer()` explicitly and **fail on a `.notScored` result**. A test asserts `am-eval`'s analyzer has `scoringMode == .on`. Otherwise the harness would quietly report zero flags.
- **Milestone 2** turns scoring back on by having the app link `AMVerdicts` and pass `VerdictScorer()`. That one-line `project.yml` change is a risky path, so it waits for Raph's Merge OK.
- **Existing tests** of `placementDecision`, `observedStress` and `StressPlacementDetector.place` move to an `AMPlacementTests` target (or `AMVerdictsTests` if they go through `place` and scoring together). Tests of `Scorer`, PairScoring natives and smoke placement goldens move to `AMVerdictsTests`. They keep passing unchanged.
- **Fallback:** if the split turns out to cost more than one day of agent time, stop at the one-day checkpoint in Build order step 3, ship what is already green, and say so explicitly in Implementation notes ("module split not done: <reason, measured cost>") and in the PR body. The fallback still needs CTO's OK in review: a grep-only guard is not clean until this section's symbols are out of the shipped graph.

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

`ResultAssembly.speaker` today sets `SyllableMeasure.stress` from observed stress with `stressSource == .measured`, on both speakers (`ResultAssembly.swift:74–94`). With scoring off that's a "you stressed X" judgement in disguise, and native acoustics match the dictionary only 50–70% of the time.

- **Under `.off`, no syllable is `.measured` on either speaker.** Both speakers' `SyllableMeasure.stress` / `stressSource` read the context-resolved pattern (`stressSource == .dictionary`), or stay unstressed when the word is ambiguous. Add this assertion to `ScoringOffTests`.
- **Context selection already exists:** `PhraseInput`'s pronunciation from `PronunciationSelector` (spec 06). Reuse it. There is no new resolver.
- **`WordSpan.expectedStress: [SyllableStress]?`** is added (Open question 1, decided). Nil means `expectedAmbiguous`, and also decodes as nil for old takes. `SyllableMeasure.stress` isn't optional, so it can't express ambiguity on its own; don't try to overload it.
  - When `expectedStress` is non-nil, it has one entry per syllable, and those syllables use it with `stressSource == .dictionary`.
  - When it is nil, no syllable of that word is marked primary, and spec 29 draws no dot and no caps.
- **Test:** a phrase whose override or part of speech differs from CMUdict's first entry. Use any starter phrase with an override, or a test fixture built from `docs/agreement/spike27/heteronyms.json` once that's on main, or else a synthetic one. The resolved primary follows the override, not CMUdict's first entry. An `expectedAmbiguous` word has `expectedStress == nil`.
- **Caveat for every consumer:** native acoustics follow this pattern only 50–70% of the time (spike 27). It's the lexical pattern, not what the speaker did.

### 4a. Descriptive measures and the native range (AMPipeline)

v3 §4's inspector shows plain measures for you, next to the range across the phrase's native voices. These are measurements, not verdicts, so they live in `AMPipeline`, not in `AMVerdicts`.

- **Add `AnalysisResult.describe: DescribedMeasures?`**, nil for old takes, and omitted (not `null`) in canonical JSON.
- It holds:
  - `you`: length (s), syllables per second, pitch range P10–P90 (st), rhythm nPVI and ending direction, plus the raw final slope (st/s) next to the direction;
  - `native`: the min–max of each across the phrase's bundled native voices (spec 15's per-recording analyses), plus a count of ending directions ("5 falling, 3 rising") and the raw slopes used. For a single native take (an imported clip), it's that take's value.
- **One function, the same frames.** Compute your values and each native's with the same function over the same kind of frames. `AMScoring`'s "yours" is warped onto comparable model frames (`TimeWarp.pitchOnModel`); natives must be measured the same way (each native warped onto the selected model's comparable frames, or every speaker, you included, measured on the selected model timeline). Measuring natives on their own timelines would skew you against the range. Record the exact frame set in Implementation notes.
- **Value type:** use a distinct type (e.g. `DescribedValue`), not `MeasureState`, so spec 29's "no measure states in views" scan stays meaningful. A missing measure still carries a reason, for "—" plus a tooltip.
- **No comparison:** nothing here says whether you're inside the range.
- **Reuse the pure functions** (P10–P90, nPVI, final slope) by moving them from `AMScoring` down to `AMPipeline` or `AMWarp` / `AMProsody`, not by copying them. `AMScoring` keeps calling them.
- **Ending direction:** don't add a display constant. Move `PitchDirection.init(slope:thresholds:)` (`PitchMeasures.swift:15–20`, also called `FinalDirection(slope:)` in the review) down with the pure functions and read `Thresholds.current.finalDirection` (±5 st/s, `riseSemitonesPerSecond` / `fallSemitonesPerSecond`). No edit to `Thresholds.swift`.
- **Tests:** for two starter phrases, `you` and each native, run through that one function, equal the values `AMScoring` computes for the same frames; the native range covers every bundled voice.

### 5. Inverse lookup: reuse `TimeWarp.toYou` / `toModel` (tests only)

The inverse lookup already exists: `TimeWarp.toYou` and `TimeWarp.toModel` (`AMWarp/TimeWarp.swift:171–174`). They return nil in gaps, never bridge a missing or inserted word, and clamp to the edge within 50 ms.

- **Don't add** `yourTime` / `modelTime` on `PartialTimeMap`.
- **This section is tests only.** Add tests for:
  - round-trip within one hop on anchored spans, **excluding the 50 ms clamp zone**;
  - nil inside gaps, and nil for a missing or inserted word;
  - monotonic on each side of a gap.
- Spec 20's playhead uses these two methods.

### 6. Goldens and tests

- **Golden `analysed-legacy-scored.json`:** a take saved before this change, taken from a current golden as main has it today (no `scoringMode` key, no `describe`, no `comparableCoverage`). It decodes, keeps its old verdict, reads `scoringMode == .on`, and re-encodes byte-identically once the test strips the added `scoringMode` key. `describe` and `comparableCoverage` are omitted, not null.
- **Golden `analysed-not-scored.json`:** a `.notScored` take with `scoringMode: "off"`. It round-trips byte-identically through canonical JSON. `Versions.goldenDigests` gains its digest.
- **`ScoringOffTests`:**
  - the shipped `Analyzer` (default configuration) on every starter phrase's bundled analysis inputs yields `.notScored`, `scoringMode == .off`, empty `measures`, `applicability` and `stress`;
  - no syllable on either speaker has `stressSource == .measured`;
  - `timeMap`, `youPitchOnModel` and `nativeBand` equal a `VerdictScorer` run on the same inputs (not "equal to today's" as a loose phrase);
  - `comparableCoverage` is non-nil and equals `TimeWarp.comparableCoverage` for that pair;
  - there are no `DiffRow`s anywhere in the encoded result.
- **`ShippedGraphTests`:**
  - checks `AMPipeline`'s **transitive** closure (every module it links, directly or through `AMProsody`, `AMWarp`, `AMCore` and the rest), not just its direct dependencies, and fails if `AMPlacement`, `AMScoring` or `AMVerdicts` appears;
  - scans every `.swift` file under `Packages/AccentKit/Sources/AMPipeline/` and `AccentMirror/` (found from `#filePath`) and fails on `placementDecision(` or `observedStress(`;
  - the same scan of `AccentMirror/` fails on `import AMPlacement`, `import AMScoring` or `import AMVerdicts`.
  - It's a Swift test, not a Makefile change.
- **Presenter tests:** on `.notScored` and on a legacy scored take, the analysed state has card 1 "YOUR TAKE" with no rows. A source scan finds no reference to `Verdict`, `DiffRow` or `StressLine` in `ShellPresenter.swift` and `Copy.swift`.
- **The take store** (spec 16) reads the legacy golden and the new one from disk.

## Defaults

- `ShippedConfig.scorer` is `NoOpScorer()`; `ShippedConfig.scoring` equals `scorer.mode` (`.off`).
- A legacy take with no `scoringMode` key decodes as `.on`.
- The module name is `AMVerdicts`.
- **A stored take is never rewritten on open.** Opening a legacy scored take shows the stored record (the presenter ignores the verdict, §3). Re-analysis as `.notScored` happens the next time analysis itself runs (an L2 cache miss or a new request), from the L1 cache, because the L2 key now includes `scoringMode`.

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

1. **Resolved (CTO must-fix 2):** `WordSpan.expectedStress: [SyllableStress]?`, nil for `expectedAmbiguous` and for old takes. `SyllableMeasure.stress` stays non-optional and, under `.off`, follows that pattern or is unstressed when the pattern is nil.
2. On `.notScored`, the inspector's timing row (spec 29 renames it ALIGNMENT, "Clear / Rough", per Designer v3.1) reads the existing `TimingLevel` (`warp.timing`) only. Default: keep it, since it describes the alignment, not the speaker. This spec doesn't rename it.

## How to test (Raph)

1. `make review PR=<n>`, then `make check` and `make test-vm`. Everything passes, including `ScoringOffTests` (no `.measured` stress, overlay equals a `VerdictScorer` run, `comparableCoverage` present), `ShippedGraphTests` (transitive closure forbids `AMPlacement`, `AMScoring` and `AMVerdicts`; no `placementDecision(` / `observedStress(` under `AMPipeline` or `AccentMirror/`), the two new goldens, the take-problem gate tests, the `am-eval` `scoringMode == .on` test and the descriptive-measure tests. **pass/fail**
2. `rg -n 'import AM(Placement|Scoring|Verdicts)' AccentMirror` prints nothing. `rg -n 'placementDecision\(|observedStress\(' Packages/AccentKit/Sources/AMPipeline AccentMirror` prints nothing. `rg -n '"AMScoring"' Packages/AccentKit/Package.swift` shows it only in the `AMScoring` and `AMVerdicts` entries, and `"AMPlacement"` only in `AMPlacement`, `AMScoring` and `AMVerdicts`. **pass/fail**
3. Launch the app and open a few fixture results, both scored and not scored. Card 1 reads "YOUR TAKE" with no rows. There's no sentence about stress or closeness, and no STRESS lines or measure states in the inspector. The strip and pitch card are drawn. **pass/fail**
4. Open a take saved before this build, from the take store or a copied take folder. It opens without an error and shows the same unjudged screen. **pass/fail**

## Build order

Ordered commits, each leaving `make test` green (CTO):

1. Contract and goldens: `Verdict.notScored`, `scoringMode`, `comparableCoverage`, `WordSpan.expectedStress`, `describe` / `DescribedValue`, both goldens.
2. The take-problem gate, the `PairScorer` seam with `NoOpScorer`, evaluation pinned to `VerdictScorer()` (including the `am-eval` `scoringMode == .on` test).
3. The module split and `ShippedGraphTests` (this is the one-day checkpoint for the fallback).
4. The presenter.
5. §4 (no `.measured` stress, `expectedStress`), §4a (one function, same frames) and §5 tests (`TimeWarp.toYou` / `toModel`).

## Implementation notes

Hand build (Claude Code, 2026-11-24, on Raph's "go merge / no ci / just yolo"). `make test-vm` and CI were skipped on
Raph's instruction; the named tests ran on the host (`_cache-28/gate.sh`).

**Where things live now**
- `StressPlacementDetector.place` is in **`AMPlacement`**, file `Sources/AMPlacement/StressPlacementDetector.swift`:
  `StressPlacementDetector.place(_:alignment:segmentation:pitch:)` (instance) and
  `StressPlacementDetector.place(words:prosody:thresholds:)` (static, on a stored `TakeProsody`). The detector type,
  `PlacementAnalysis`, `PlacementWordResult` and `DetectorSuppression` moved there from `AMPipeline`.
- `placementDecision`, `PlacementDecision`, `PlacementSuppressionReason`: **`AMPlacement`**,
  `Sources/AMPlacement/Placement.swift` (moved from `AMProsody/Placement.swift`, history kept).
- `WordAcceptedSet`, `NativeReading`: `Sources/AMPlacement/AcceptedSet.swift`. `ObservedStress` and
  `TakeProminence.observedStress(of:)` (an extension on the `AMProsody` type): `Sources/AMPlacement/ObservedStress.swift`.
  No copy is left in `AMProsody` or `AMPipeline`; `TakeProminence` and `ComparableSyllable` stay in `AMProsody` (the
  prominence display).
- `AMVerdicts`: `PairScoring.input` / `PairScoring.score` (an extension of `AMPipeline`'s `PairScoring`),
  `VerdictScorer`, `PlacementGolden` / `SmokeVerdict`, and `EvaluationConfig` (what am-eval builds every analyzer with).
  It depends on `AMPipeline` because `VerdictScorer` conforms to `PairScorer`; `AMPipeline` doesn't depend on it.
- The take-problem gate is **`decideTakeProblem(takeProblems:alignment:thresholds:)`** in `AMCore`
  (`DecisionProcedure.swift`). `decide()` steps 1–2 now call it, so there is one copy. The analyzer runs it before
  the scorer and never calls the scorer when it fires.
- Shipped half of pair scoring: `PairScoring.warp` and `PairScoring.alignmentSummary` in `AMPipeline/PairWarp.swift`.
  The scorer seam (`PairScorer`, `PairScorerInput`, `PairScore`, `NoOpScorer`) is in `AMPipeline/PairScorer.swift`.
- The alignment and syllable stages (`TakeStages`, `PlacementTake`) and the new L1 type (`TakeProsody`: segmentation,
  alignment, pitch) are in `AMProsody/TakeStages.swift`. `L1Analysis.analysis` is a `TakeProsody`.
- Moved down from `AMScoring` (not copied): `PitchStatistics.range/percentile/slope/npvi` and `FinalWindow` in
  `AMProsody/PitchStatistics.swift`; `PitchDirection` (with `init(slope:thresholds:)`) in `AMCore/DescribedMeasures.swift`,
  because the contract's `describe` stores it. `AMScoring` calls them through one-line forwarders.

**Descriptive measures (§4a), frame set.** One function, `ProsodyDescription.speaker(_:warp:thresholds:)`
(`AMPipeline/Description.swift`), runs on you and on every native voice:
- pitch range P10–P90: the speaker's pitch warped onto the **selected model's timeline** (`TimeWarp.pitchOnModel`), voiced
  frames whose centre is in that warp's comparable model time. These are exactly the frames `AMScoring` reads for your
  range. The selected voice goes through its own identity warp, and every other native through its warp onto the
  selected voice (the band's warps);
- final slope and ending direction: the speaker's final window on their **own** timeline over their present words
  (`FinalWindow`), which is how `AMScoring` reads it for both you and the model;
- length (first to last present word), syllables per second and nPVI: the speaker's own present words and comparable
  syllables (nPVI is `AMScoring`'s rhythm over the same syllables).
`DescribedMeasuresTests` checks you and each native against `Scorer.score` on the same pair and frames (exact equality),
and checks that the native range covers every bundled voice.

**Tests**: `ScoringOffTests`, `ShippedGraphTests` and `DescribedMeasuresTests` are in AMPipelineTests;
`EvaluationPinTests` (am-eval `scoringMode == .on`) is in AMVerdictsTests; `InverseLookupTests` (§5) is in AMWarpTests;
`TakeStoreGoldenTests` is in AMLibraryTests. The presenter tests are `NotScoredFixtureTests` and `PresenterSourceTests`
(AccentMirrorTests, unhosted), plus `analysedTakeShowsYourTakeWithNoRows` and
`inspectorShowsNoMeasureStatesStressLinesOrReasons` (ShellContractTests, app-hosted: compiled on the host, not run).
`ShippedGraphTests` also reads `project.yml` (read only) and asserts that the app target `AccentMirror` links only the
`AMPipeline` package product. That holds today, so the assertion is strict.

**Deviations and spec gaps**
- Golden digest: the change is additive and the CTO ruled no version bump, so the new `GoldenDigest` record repeats
  (1, 8, 2). `GoldenDigestTests.recordsAreMonotonic` allows exactly that one repeated triple, and only as the last record.
- The existing goldens (`Golden/*.json`, `Golden/scoring/*.json`) were re-recorded. The only change is the added
  `"scoringMode": "on"` (21 lines). `fixtures/pipeline/analysis-golden.json` (spec 12) is now pinned to `VerdictScorer`.
  It was re-recorded and checked identical to main once the added keys (`scoringMode`, `comparableCoverage`, `describe`,
  `expectedStress`) are stripped.
- Bundled starter analyses: L1 no longer stores decisions, so a recomputed record's bytes differ from the bundled
  ones, and `Resources/Starter` is off limits. `BundledStarterTests` now falls back to value equality through the
  current L1 type when the bytes differ. Hand follow-up: rebuild `Resources/Starter` and restore the byte check.
- Take problems under `VerdictScorer`: the analyzer still returns `.takeProblem` without calling `score`. It asks the
  scorer's evaluation-only `evaluationMeasures` hook for the measures to log in L2, as L2 did before, so the agreement
  harness's tolerance rows don't move. `NoOpScorer` returns nil.
- Imported phrases (spec 17): an out-of-vocabulary polysyllable's stress used to be measured from the clip through
  observed stress, which is now outside the shipped graph. Such a word now stays ambiguous (`expectedStress == nil`).
- `ApplicabilityTable.empty` is added for `.notScored`. It decodes from `{}`; subscripting it traps, and nothing on the
  shipped path does.
- Test placement: the smoke placement golden and pair-scoring natives tests stay in AMPipelineTests, which also links
  `AMVerdicts` (test-only), because they share fixtures with the analyzer tests. AMScoringTests stay where they are.
  The observed-stress, accepted-set and detector tests moved to AMPlacementTests; `ProminenceTests` moved whole, since
  its prominence cases sit beside the observed-stress ones.
- Presenter: the verdict copy and row helpers moved to `AccentMirror/Fixtures/VerdictSentences.swift` and
  `VerdictPresentation.swift` (extensions, unused by views) so `Copy.swift` and `ShellPresenter.swift` reference no
  verdict type while ShellContractTests still compile. Twelve ShellContractTests and one LabelLayoutTests test assert
  verdict rows; they are `.disabled` with a spec-28 reason, for spec 29 to rewrite. The mistake marker is gone, and
  card 1's info lines (quiet note, placement-only) are dropped; quiet notes stay in the inspector's NOTES.
- Fixture states `result-not-scored` and `result-no-verdict` are added. The screenshot run will render them.
- The module split is done, so the fallback wasn't needed.
