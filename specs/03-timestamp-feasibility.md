# 03: Timestamp feasibility

Status: Ready · Branch: – · Depends on: 00 (project skeleton; the plan table listed 01, but
Raph allowed 03 to proceed after the skeleton) · Estimate: 3–4 h agent run + 1 h Raph review
· Risk: high

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)",
approved 2026-11-23 09:56 Europe/Paris). Word-boundary bars are taken verbatim from the
first v2 (09:10 Europe/Paris), which later revisions call "as before". Cancellation is
§8.2. Report identity is §6.6. The evaluation set is CPO's 20 VCTK phrases and 8 bundled
voices (§6.1).

## Goal

Prove, on device, that the SHA-pinned WhisperKit `openai_whisper-base.en` model produces
word timings accurate enough to build the rest of the pipeline on. Record replay timings
for later CI. Make `make fetch-models`, `make eval` and `make agreement-record` real.
No stress claims.

## Behaviour

### Model and fetch

- The shipped ASR model is WhisperKit (MIT) with official `openai_whisper-base.en` Core ML
  weights (about 150 MB). Weights are fetched at build time (or by `make fetch-models`),
  never committed, never Git LFS, never pinned to `main`. The manifest under
  `Resources/Models/` records the WhisperKit package version or the Argmax models-repo
  commit, and the SHA-256 of the weights. A hash mismatch fails the fetch and the build.
  Each model's LICENSE/NOTICE lives next to the manifest.
- The exact package version and weight hash are not in the plan. See Open question 1.
- `tiny.en` is the fallback if warm `base.en` goes over the 900 ms ASR budget (performance
  table in the plan and `docs/thresholds.md`). If the fallback is used, the accuracy gate
  is re-run on `tiny.en`, and the report names the model that would ship.
- Apple SpeechAnalyzer is an optional comparator only, off the v1 path. It runs in `make
  eval` only when AssetInventory reports its assets already installed. The app and the
  eval tools never call download or install. If the assets are missing, the report says
  `comparator not present` and still evaluates WhisperKit.
- `asrModelID` follows the plan's form: `openai_whisper-base.en@<commit>#<sha256-8>`.

### On-device only

- Word timing at runtime uses only bundled or already-fetched weights. No network, no
  analytics, no accounts. A test of the core path with networking denied must still be
  able to replay fixtures and must not open a socket.
- `make eval` and `make agreement-record` run on a Mac, with the speech model on disk.
  They may fetch weights and VCTK source audio only as explicit tool steps, never from
  the app.
- PR CI never runs ASR. Tests in `make check` replay recorded word-timestamp JSON
  (`FixtureTimestamper`). CI never launches the app, uses the microphone, or runs UI
  tests.

### Evaluation set

- CPO's starter set: the 20 unique VCTK 0.92 shared-text utterances
  [002, 003, 004, 005, 006, 007, 008, 009, 010, 011, 012, 013, 014, 015, 016, 017, 018,
  019, 020, 024], from the [phrase set](https://app.notion.com/p/4210d0d44592819b987acd628b878eb0).
- Bundled voices, unchanged from CPO: p225, p226, p227, p233, p241, p252, p311 and p345,
  mic1. Never p315. No p225 for 015 (use the other seven voices for that phrase). That is
  **159 clips** (20 × 8 − 1).
- Official file form: `{speaker}_{text_id}_mic1.flac`. Transcripts are the official VCTK
  0.92 texts (keep the stray space in 009).
- Extraction and the 2–6 s trim are owned by specs 02 and 15. This spec evaluates the
  official mic1 utterances as published. If a later shared trim exists by the time this
  is built, use that same cut for every speaker and say so in the report. Do not invent
  trim points.
- VCTK is CC BY 4.0. Do not commit the full archive. A local fetch cache is git-ignored.
  Trimmed clips may be committed later by specs 02 and 15, with attribution. The VCTK
  0.92 archive SHA-256 is not in the plan (it is listed as a spec 02 pin). See Open
  question 2.
- The 30 eval-only VCTK speakers, speechocean762, and any synthetic audio are out of this
  gate. They belong to specs 02 and 11.

### Word-boundary acceptance (plan numbers, verbatim)

From the first v2, which later revisions call "as before":

> On held-out hand-labelled word boundaries: median error ≤ 40 ms and at least 85% within
> 80 ms (with 80 ms padding applied); word probability is calibrated (the low-confidence
> bin has more error than the high bin). **No stress claims.** Under the bar, it goes back
> to CTO.

Apply those bars to the 159 clips above. Do not invent other thresholds (no worst-voice
or worst-phrase cap, no ECE number, no minimum n beyond what is stated here).

- Error is the absolute difference, in milliseconds, of each comparable word **start** and
  each comparable word **end** against the baseline. Median error is the median of those
  absolute differences. The 85% figure is the share of those same boundaries that fall
  within 80 ms.
- Report overall figures, plus per-voice and per-phrase breakdowns, as information. Those
  breakdowns have no gate in the plan.
- A word is comparable when WhisperKit and the baseline both produce a span for the same
  phrase token after stripping punctuation and collapsing whitespace. If either side is
  missing, skip that token and count it in a coverage line. Do not invent a richer
  alignment protocol here (that is spec 06).
- The ~80 ms padding is the planned expansion of each Whisper word span on both sides
  (CTO decision 4, also in `docs/thresholds.md`, owned later by spec 07). See Open
  question 3 for whether the gate uses padded or raw times.
- Calibration, as written: the low-confidence bin has more error than the high-confidence
  bin. See Open question 4 for bin edges.
- The original ground truth was "held-out hand-labelled word boundaries". Raph (09:14)
  dropped human labelling. Spec 07's real-speech check was updated to use MFA as a
  baseline; spec 03's row was left as "as before" and never renamed its truth source.
  See Open question 5.
- If the result is under the bar, the report goes to CTO. Nobody lowers a threshold
  quietly. This spec does not change the numbers in `docs/thresholds.md` except to add
  these two timestamp bars (median ≤ 40 ms, ≥ 85% within 80 ms) and to move the misplaced
  "stress-detection bar / 80% / owner spec 03" row to spec 11, where that gate now lives.

### Cancellation (plan §8.2)

- WhisperKit runs inside `withTaskCancellationHandler`, and its early-stop callback
  returns `false`. Confirm that signature on the pinned WhisperKit version. If the pinned
  API differs, document the actual hook and still stop decoding on cancel; do not guess a
  second API.
- A local check (not PR CI): cancel 100 ms into a run, the response returns within about
  300 ms, and the model is not torn down. Full request-coordinator behaviour is spec 12.
- No speculative ASR in v1.

### Reports and replay

- `make eval` runs real WhisperKit on the 159 clips, on the machine, and writes
  `docs/agreement/reports/timestamp-feasibility-<configDigest8>.{json,md}`.
- Every report header carries the plan §6.6 identity:
  - `ConfigIdentity` (`algorithmVersion`, `thresholdsVersion`, `contractVersion`,
    `asrModelID`, `pitchTrackerID`, `voicingID` — use explicit placeholders such as `none`
    for IDs this spec does not yet own);
  - the corpus manifest hash (SHA-256 of the sorted file hashes);
  - the label (baseline) hash;
  - `sourceTreeHash`: SHA-256 of `git ls-tree -r --full-tree <evaluated commit>`, sorted,
    with every entry under `docs/agreement/reports/` removed; also the evaluated commit
    SHA and a clean-tree flag (a dirty tree cannot produce a release report);
  - `configDigest`: SHA-256 of the canonical JSON of `ConfigIdentity` plus the full
    `Thresholds`;
  - the Xcode, Swift and macOS versions (and the runner image when the run is on CI).
- The report also includes: model IDs and weight SHA-256s, baseline identity (MFA version
  and model pin, or whatever Open question 5 resolves to), n comparable boundaries,
  coverage, median error, share within 80 ms, the unpadded figures if the gate used
  padded spans, the calibration table, load time, cold and warm ASR time, the 900 ms
  budget line, and a clear PASS / FAIL / NOT EVALUATED. NOT EVALUATED is never a pass.
- A later release check (spec 02 / 11) recomputes `sourceTreeHash` and `configDigest` and
  requires a match. A report may sit in a descendant commit whose diff from the evaluated
  commit touches only `docs/agreement/reports/`, and must be under 7 days old. This spec
  must compute the two digests the same way, and must not commit a report from a dirty
  tree.
- `make agreement-record` runs real WhisperKit and writes per-clip word-timestamp JSON
  (words, start, end, probability, `asrModelID`) that `FixtureTimestamper` can replay.
  The recorded files and a manifest hash are the input to later CI. They are not a
  substitute for the accuracy report.

### Makefile targets

The stubs today print `not yet: spec 03` and exit 0 for `fetch-models`, `eval` and
`agreement-record`. This spec makes those three commands real:

- `fetch-models` downloads the pinned weights, verifies SHA-256, and fails on mismatch.
- `eval` produces the report above. It fails (non-zero) on FAIL, and also on NOT
  EVALUATED when it was meant to be a release run.
- `agreement-record` writes the replay JSON and manifest.

Agents must not edit the `Makefile` (AGENTS.md). The agent implements the work as scripts
or package commands (for example `scripts/fetch-models.sh`, `scripts/eval-timestamps.sh`,
`scripts/agreement-record.sh`, or a small Swift tool in the package). A hand follow-up,
or Raph applying a listed diff, wires the three Makefile stubs to those commands. Until
that wiring lands, the How to test steps may call the scripts directly.

A nightly workflow that re-runs real WhisperKit is called out in v1 and needs a
`.github/` change. It is out of scope here.

### Package shape

- Live ASR and the fixture replay sit behind a small protocol in `AMAlignment`, which
  already owns word timings. WhisperKit is a new SPM dependency: MIT, pinned version,
  reason written in the PR (on-device word timestamps; this is the plan's chosen ASR).
- The app target stays thin. No AppKit or UIKit in AccentKit. No entitlements, no
  `NSMicrophoneUsageDescription`, no signing changes, no team ID.
- Load-and-warm timings on M1 are measured and reported. iPhone timing is Milestone 2.

## Defaults

- Open questions below are built with the stated default. Do not stop to ask.
- Evaluate official mic1 VCTK utterances, 159 clips, unless a shared 02/15 trim already
  exists.
- If `base.en` misses the 900 ms warm budget, fall back to pinned `tiny.en` and gate that
  model instead, reporting both.

## Guardrails

- On-device only at runtime. Weights stay out of git. A hash mismatch fails the build.
- No secrets, team IDs, or personal paths in the repo.
- `make check` stays green without model weights and without VCTK. No new warnings from
  our code. Swift 6 strict concurrency.
- Risk: high (model weights). A factory implementation PR that touches `Resources/Models/`
  waits for Raph even after a `merge` verdict.
- Never lower the 40 ms / 85% bars quietly.

## Out of scope

- Stress detection, the CMUdict baseline, speechocean762, and all §6.7 scoring gates
  (spec 11).
- The agreement harness, VCTK eval-speaker picker, and cache-warm job (spec 02).
- Syllable segmentation, the 40 ms / 80% syllable-boundary check, and human syllable
  labels (spec 07; MFA is only a word-boundary baseline here if Open question 5's default
  is used).
- The pipeline coordinator, operational errors, and L_stop / L_speech budgets (spec 12).
- Bundling starter audio into the app (spec 15), live capture, entitlements, signing,
  notarization, the iOS target, `.factory/`, `.github/`, and the Makefile itself.

## Open question (built with the default)

1. **WhisperKit and weight pins.** The plan requires a SHA-256 pin and a pinned upstream
   commit, and does not give the hashes. Default: pin a current official Argmax
   WhisperKit release and its official `openai_whisper-base.en` Core ML weights (MIT),
   never `main`. Record the commit and the full SHA-256 in `Resources/Models/`. Do not
   invent a hash in this spec. `tiny.en`, if needed, is pinned the same way.
2. **VCTK 0.92 archive SHA-256.** The plan leaves the pin to spec 02. Default: the first
   fetch records the official archive digest in a fetch manifest and fails on a later
   mismatch. Do not invent the digest here.
3. **Raw vs padded times.** The bar says "with 80 ms padding applied" and does not say
   whether error is measured on raw WhisperKit starts/ends or after the ~80 ms span
   expansion. Default: the gate uses the padded spans, as written; the report also prints
   the unpadded median and the unpadded share within 80 ms.
4. **Calibration bins.** No bin count or edges are given. Default: two bins, split at the
   median word probability over comparable tokens; the low bin's mean absolute error must
   be greater than the high bin's. If a bin is empty, the calibration line is NOT
   EVALUATED (and that is not a pass).
5. **Word-boundary truth source.** Hand labels are no longer allowed. The plan's
   replacement for hand labels is "MFA as a baseline" (explicitly on spec 07; only "as
   before" on spec 03). Default: Montreal Forced Aligner word alignments of the 159
   clips, with the MFA version and acoustic model pinned in the report and in the
   baseline hash. MFA runs only as offline tooling, never in the app. If MFA cannot be
   run, the report is NOT EVALUATED, not a pass.

## How to test (Raph)

1. `make check` is green (generate, unsigned macOS build, package tests, corpus guard, no
   AppKit/UIKit in AccentKit). It does not fetch models, does not run WhisperKit, and
   does not need VCTK.
2. After the Makefile stubs are wired (or via the scripts this spec adds), `make
   fetch-models` fetches the pinned `base.en` weights and verifies SHA-256. A wrong hash
   fails.
3. On a clean tree, on an M1 or later Mac, `make eval` writes
   `docs/agreement/reports/timestamp-feasibility-<configDigest8>.{json,md}` whose header
   carries `sourceTreeHash` and `configDigest`. Recompute both by hand from the recipe
   in §6.6 and confirm they match. The tree must have been clean when the report was
   written.
4. The report's overall median error is ≤ 40 ms, at least 85% of comparable boundaries
   are within 80 ms, and the low-confidence bin has more error than the high-confidence
   bin. Load, cold and warm ASR times are printed against the 900 ms warm budget. If any
   of those bars fail, the report is FAIL and goes to CTO; the numbers are not edited to
   pass.
5. `make agreement-record` writes replay JSON for the clips, and a package test replays
   one of those files without running ASR.
6. Optional: cancel a run 100 ms in and confirm the response returns within about 300 ms
   without tearing down the model.
7. Optional: if SpeechAnalyzer assets are already on the machine, the report includes the
   comparator; if not, it says `comparator not present` and does not try to download them.

## Implementation notes

Built by hand through Claude Code (Opus) on 2026-11-23, on M3 Max, macOS 26.3, Xcode 26.2.

**Result: FAIL, goes to CTO.** On the 155 available clips the padded-span gate gives median 120 ms (bar ≤ 40) and
36.8% within 80 ms (bar ≥ 85%). Raw spans are no better: median 100 ms, 42.3% within 80 ms. Calibration passes
(low bin 145.1 ms > high bin 143.1 ms, a thin margin). Warm ASR median 127.7 ms is well inside the 900 ms budget, so
`base.en` ships and `tiny.en` was not pinned. The report is `docs/agreement/reports/timestamp-feasibility-<digest8>`.
WhisperKit's word boundaries are systematically early against MFA (mean signed error: starts −120 ms, ends −138 ms),
and the 80 ms padding makes starts worse while helping ends. No threshold or number was changed to pass.

What was built:

- `AMAlignment`: `WordTimestamper` protocol; `WhisperKitTimestamper` (actor; `ModelManifest.verify` runs before
  WhisperKit sees a file; `download: false`; local tokenizer folder); `FixtureTimestamper` (replays
  `fixtures/timestamps/<model>/`, checks every file hash and `recordingsSHA256`). WhisperKit 1.1.1 is pinned
  `exact:`. `@preconcurrency import WhisperKit` because its class is not `Sendable` (Swift 5 mode); the actor owns
  the only instance and refuses overlapping calls (`busy`; queueing is spec 12). No `@unchecked Sendable`.
- Cancellation: on the pinned 1.1.1 the hook is `TranscriptionCallback = @Sendable (TranscriptionProgress) -> Bool?`;
  returning `false` sets WhisperKit's early-stop flag. It runs inside `withTaskCancellationHandler`, then
  `Task.checkCancellation()` throws. `scripts/asr-cancel-check.sh`: 5 trials, cancel 100 ms into a 119 s input,
  worst return 3.2 ms, model still loaded, next request correct.
- `AMTimestampEval` (library) and `am-timestamps` (executable): local tooling only, not linked into the app. Token
  rule: whitespace split, punctuation stripped, lower case; each side is paired with the phrase tokens by the
  longest in-order exact match (nothing richer: spec 06). Errors are rounded to the microsecond so an exact 80 ms is
  not pushed outside the tolerance by floating point.
- Identity uses spec 01's `ConfigIdentity`, `CanonicalJSON` and `configDigest` from AMCore (spec 01 landed first, so
  no local copy remains). `pitchTrackerID` and `voicingID` are `none`. `Thresholds.wordTimestamps` holds the bars
  (three keyed rows, because the mirror needs one number per row).
- Scripts (the Makefile stays a stub; see the PR's hand follow-up): `fetch-models.sh` (`--verify` too),
  `fetch-vctk.sh`, `setup-mfa.sh`, `mfa-align.sh`, `agreement-record.sh`, `eval-timestamps.sh` (`--dev` for a
  dirty tree), `asr-cancel-check.sh`. ASR runs under `sandbox-exec` with `(deny network*)`.
- VCTK is streamed once through SHA-256 into `bsdtar`, which keeps only the clips; the 11 GB archive never lands on
  disk. Archive SHA-256 `f96258be9fdc2cbff6559541aae7ea4f59df3fcaf5cf963aae5ca647357e359c`, pinned on first fetch.
- Baseline: MFA 3.4.4 (conda-forge, via micromamba 2.10.0-0, all inside the git-ignored `.cache/mfa`), acoustic
  model and dictionary `english_mfa` v3.1.0, pinned by SHA-256 in `fixtures/vctk/mfa-models.sha256`. Output
  committed as `fixtures/vctk/mfa-word-baseline.json` (the label hash).

Gaps and decisions for review:

1. **Four specified clips are not in VCTK 0.92**: p227_007, p233_010, p241_015, p241_020 (no audio, no transcript).
   155 of 159 were evaluated; no substitutes were chosen. CPO may want to amend the set.
2. **Padding against the bar.** With the gate on padded spans (Open question 3 default), a perfectly timed word
   scores 80 ms on each boundary, which is over the 40 ms median bar by construction. The padded gate can pass only
   if the raw spans are about 80 ms too narrow on each side. CTO should confirm which times the bar means.
3. **Apple SpeechAnalyzer**: `SpeechTranscriber.installedLocales` lists en_US, but `AssetInventory.status` reports
   `supported`, not `installed`. As the spec keys on AssetInventory, the report says `comparator not present`. The
   comparator code exists but has not run on real assets.
4. The fallback is keyed on the median warm ASR time (the spec gives no statistic); p90 and max are reported.
5. Padded spans are not clamped to the clip (the conservative choice).
6. Calibration's two bins split at the median probability: low is below it, high is at or above it.
7. `Thresholds.wordTimestamps` was added without bumping `thresholdsVersion`. No existing value changed and no
   analysis output reads these bars; a bump would need a new golden record with a duplicate digest, which spec 01's
   test forbids. `configDigest` changes anyway, since it covers the full `Thresholds`.
8. The committed replay and baseline JSON hold VCTK transcript words (CC BY 4.0); attribution is in both files'
   `attribution` field. The VCTK section of `THIRD_PARTY_NOTICES.md` belongs to spec 02 and was not edited.
9. AGENTS.md's module map doesn't list the tooling targets `AMTimestampEval` and `am-timestamps`; AGENTS.md is not
   on this spec's edit list.
