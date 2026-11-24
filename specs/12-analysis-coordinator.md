# 12: Analysis pipeline and coordinator

Status: Ready · Branch: – · Depends on: 03 (WhisperKit, cancellation), 05 (take quality, endpointing), 10 (verdict
path) · Estimate: 6–8 h agent run + 1.5 h Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §8.1–8.3 (requests, cancellation, persistence status), §9 (identity, cache levels, L2 recompute
budget), §10 (latency, "budgets as before"), §7 row 12. The first v2 (2026-11-23 09:10) for what rev 4.1 calls "as
before": the coordinator sketch, what cancels, stale rejection, the L_stop / L_speech definitions and budgets. Plan
v1 for the `Analyzer` actor, warm-up and the no-network test (CTO decision 2).

## Goal

One end-to-end analysis in `AMPipeline`: your take's audio plus a phrase and a native reference in, one
`AnalysisResponse` out, with request identity, cancellation, stale rejection, operational errors, caches and measured
latency. This is what the app (spec 21) and the agreement harness (spec 11) both call. No UI, no microphone, no
files on disk except the caches below.

## Behaviour

### Analyzer (actor)

- `analyse(take: TakeAudio, phrase: PhraseInput, reference: ReferenceSet, voice: RecordingID) async ->
  AnalysisResponse`. Stages, each behind its existing module API: decode → take quality (spec 05; the first
  `TakeProblem` in Designer's order wins) → ASR word timings (`WordTimestamper`) concurrently with pitch and voicing
  (`async let`) → word alignment and normalisation (spec 06; `wordsDontMatch`) → syllables (spec 07) → prominence
  and observed stress (spec 08) → time map and band (spec 09) → measures and verdict (spec 10).
- The reference side is never recomputed during a take. `ReferenceSet` (a protocol defined here, implemented by
  spec 15 and by test fixtures) provides each native recording's L0/L1 analysis and identity.
- **Module boundary:** the L0/L1/L2 value types and their encoding belong to `AMPipeline`. Storage modules
  (`AMLibrary`, specs 15–17) only hold `DerivedRecord`s, an identity key plus encoded bytes, which `AMPipeline`
  encodes and decodes, so `AMLibrary` keeps depending on `AMCore` alone. `ReferenceSet` and `TakePersisting` are
  declared in `AMLibrary` over those records, and `AMPipeline` adapts them.
- Each stage emits an `os_signpost`. A stage that throws becomes `failed(.inferenceFailed(stage:))` with the stage
  from `AMCore.Stage`; nothing is ever reported as a `TakeProblem` that isn't one.
- Word boundaries come from the aligner on main (Whisper spans, spec 03 padding, spec 07 segmenter) through one
  injected boundary source, so spec 23 can swap it; its ID goes into the analysis identity.

### Speech model host

- Loads the WhisperKit model from a folder URL it is given (the app passes its bundle path in spec 21; tools pass
  `MODELS_CACHE`), checks the manifest's aggregate SHA-256 (`ModelManifest`, spec 03), then runs a 1 s silent
  warm-up off the main actor.
- Failures map to `modelUnavailable(.notInstalled | .checksumMismatch | .loadFailed)`. Policy (plan §1): the next
  request retries the load once; a second failure is reported.
- `referenceCacheCorrupt(recording)` from the `ReferenceSet` triggers one silent rebuild request; only a second
  failure is reported.

### Coordinator (`@MainActor`)

- `submit(_:)` issues an `AnalysisRequest` with a new `RequestID` and an increasing `generation`, cancels the
  in-flight task, and records `current = (id, inputs)`. `invalidate(_ reason)` cancels and clears it. Reasons: a new
  recording starting, a phrase switch, a voice switch, a transcript-edit commit, an importer selection change,
  closing the importer, app termination.
- **Stale rejection:** a response is delivered only if its `requestID == current.id`, its `identity.inputs ==
  current.inputs` and the task wasn't cancelled. Anything else is dropped with a `stale-dropped` signpost.
- **Order of publication:** the `AnalysisResponse` first, then `PersistenceStatus` updates for the same request ID
  (§8.3). Saving goes through a `TakePersisting` protocol (spec 16 implements it; here an in-memory fake). Only
  `analysed` responses are offered for saving. `takeProblem`, `failed` and `cancelled` give
  `notSaved(takeProblem | failed | cancelled)` and write nothing.
- **Voice switch:** recomputes **L2 only** from cached L0/L1, never re-running ASR or pitch on your take.

### Cancellation (§8.2)

- WhisperKit runs inside `withTaskCancellationHandler`; its early-stop callback returns `false` (spec 03 confirmed the
  signature on the pinned version).
- `Task.isCancelled` is checked between stages, between feature-extraction chunks, every 50 pYIN frames and every 100
  DTW rows. A cancelled request returns `.cancelled` and writes nothing.
- Cancel 100 ms into a request: the response arrives within about 300 ms and the model isn't torn down. Outside
  ASR, a cancel is seen within one stage (≤ 50 ms).

### Caches (§9.2)

- **L0** (frame RMS, pitch, voicing, ASR words): key `takeAudioSHA256 + featureVersion + asrModelID +
  pitchTrackerID + voicingID`. **L1** (alignment, syllable spans, raw d/e/p): L0 key + `transcriptRevision +
  pronunciationHash + algorithmVersion`. **L2** (comparison, verdict): L1 key + `ReferenceIdentity +
  thresholdsVersion`.
- Here: an in-memory cache keyed exactly so, plus `Codable` L0/L1/L2 values that carry their identity, so spec 16
  can persist them and treat a mismatch as a miss. A miss recomputes; it's never an error.

### Held-out pairs through the pipeline (unblocks specs 09, 10 and 11)

- `am-eval suite --suite positive` scores each held-out pair through the `Analyzer` (replayed word timings, real
  pitch, real scoring), so spec 10's positive gates and spec 09's band-coverage gate print measured numbers instead
  of NOT EVALUATED (n=0). Numbers are on the thresholds on main; a FAIL goes to CTO and nothing is tuned here.
- Word timings for the eval-speaker clips are recorded once with the existing `am-eval record-timings` path on the
  Mac (real WhisperKit, local, never CI) into the git-ignored eval cache, the same way spec 08 recorded l2-shared.
- **The build does this itself, with no hand run (Raph, 2026-11-24).** The agent fetches the corpora with the
  existing pinned fetchers if the cache is missing, records the timings, runs `scripts/agreement.sh --suite
  positive`, and commits the report under `docs/agreement/reports/positive-<configDigest8>.{json,md}` (identity as
  in spec 02). A fetch or record failure is reported in the PR as a must-fix for the build, never left for Raph.
  A gate FAIL here doesn't block this spec (thresholds are untuned); spec 11's gate does.

### Latency (first v2 §10, "as before")

- **L_stop:** from the recording stop (endpoint decision or manual stop) to the outcome being delivered. Budgets (M1,
  model warm): ≤ 2.0 s for a 3 s take, ≤ 3.0 s for 15 s, ≤ 3.5 s for 20 s.
- **L_speech:** from the last speech frame to the outcome; for auto-endpoint, 1.2 s plus L_stop, with the 1.2 s wait
  reported on its own line.
- **L2 recompute** (voice switch): median and max over 10 runs on 3 s and 15 s takes; budget ≤ 150 ms median on M1.
- `scripts/bench.sh` prints L_stop, L_speech and L2 recompute for 3, 15 and 20 s fixture takes, 10 runs each, median
  and max, and names the limiting stage. A package benchmark test prints per-stage times without ASR and fails CI
  only if the non-ASR stages exceed a generous 500 ms on the runner.

## Defaults

- `TakeAudio` is 16 kHz mono Float32 plus its SHA-256 (the capture format of spec 14).
- No speculative ASR (start after 0.4 s of silence). It's a measured option only if L_speech is over budget; if it
  is, the PR reports the numbers and stops there.
- Latency budgets live in the bench report, not in `Thresholds.swift`.

## Guardrails

- No network: one test runs the full pipeline with a `URLProtocol` that fails every request and asserts no socket
  opens, and still gets a result (CTO decision 2). WhisperKit never downloads anything; a missing model is
  `modelUnavailable(.notInstalled)`.
- ASR never runs in CI; tests use `FixtureTimestamper`.
- `@MainActor` only for the coordinator; analysis runs in the actor. No `@unchecked Sendable` without a written
  reason. No AppKit or UIKit in AccentKit.
- Don't touch `Thresholds.swift`, `project.yml`, `Resources/` or any risky path.

## Out of scope

- The take store on disk (spec 16). The bundled starter references (spec 15). Live capture (spec 14). Clip import
  (spec 17). Wiring into the app and bundling the model in the app (spec 21). Tuning (spec 11).

## Open question (built with the default)

1. **Where the first-launch warm-up runs if the model is still loading when a take ends.** Default: the request
   waits for the load (the app shows "Analysing your take…" as usual); a load failure is `modelUnavailable`.

## How to test (Raph)

1. `make check` is green.
2. `swift test --package-path Packages/AccentKit --filter AMPipelineTests` covers: stale responses dropped for each
   invalidation reason; cancel at 100 ms answers within about 300 ms; each `OperationalError` injected at each stage
   is surfaced as itself; the model retry-once policy; the reference rebuild-once policy; response before
   persistence status; a voice switch recomputes L2 only (L0/L1 call counts unchanged); the no-network test.
3. An end-to-end golden: a fixture take and a fixture reference give the committed `AnalysisResult` JSON.
4. On the Mac: `scripts/bench.sh` prints L_stop / L_speech / L2 recompute per length with medians, maxima and the
   limiting stage, and says PASS or FAIL against each budget.
5. Local: `scripts/agreement.sh --suite positive` prints measured n for every spec 10 line (no longer n=0). The
   build ran it and committed the report; this step only re-reads it.

## Implementation notes

_(filled in by the agent)_
