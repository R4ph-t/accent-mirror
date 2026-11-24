# 22: Synthetic native references (evaluation only)

Status: Ready · Branch: – · Depends on: 02 (harness), 10 (verdict path) · Estimate: 4–6 h agent run + 1.5 h Raph
review · Risk: high

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §6.4 (synthetic references, voice verification, terms, cost, synthetic negative set, TTS traps),
§6.3 end-to-end check (ii), §6.7, Raph review 4 (09:56) items "TTS voices chosen on held-out speakers" and
"ElevenLabs on the critical path", Raph 10:01 verbatim: "Make ElevenLabs the default, Mac voices as fallback". The
plan lists these items under row 02; they are split out here because voice verification needs the detector (08, 10)
and Raph asked to keep ElevenLabs off the critical path. Risk is high: a third-party service, a secret, and terms of
use.

## Goal

Offline tooling that generates synthetic native references for the speechocean762 end-to-end check (ii), verifies
each voice's stress control, and builds the synthetic edited-native negative set. ElevenLabs is the default; Mac
`AVSpeechSynthesizer` Premium voices are the labelled fallback. Nothing here is in the app, and nothing here feeds a
main gate or tuning.

## Behaviour

### Where it lives

- A separate Swift package under `tools/SynthRef/` (an executable), never linked by the app or by `AccentKit`'s
  library products. A new guard, `scripts/check-no-tts-in-app.sh`, fails if the app target or any `AccentKit` source
  references the TTS tool, `AVSpeechSynthesizer`, or ElevenLabs' host. It runs in `make check`'s scripts once Raph
  wires it (listed in the PR), and as a package test until then.

### Engines

- **Default: ElevenLabs**, `eleven_flash_v2` with SSML `<phoneme alphabet="cmu-arpabet">` (works on Flash v2 and
  Turbo v2, English only). Alternative: v4 inline IPA in slashes. The API key is read only from the
  `ELEVENLABS_API_KEY` environment variable, never logged, never written to disk or a report.
- **Fallback: Mac `AVSpeechSynthesizer` Premium voices** with SSML `<phoneme>`, used when there is no key, when
  offline, and for fork PRs. The tool never downloads voices; if no Premium voice is installed, the fallback is NOT
  EVALUATED.
- Every report header carries `syntheticReference: elevenlabs | mac-premium-fallback (<reason>)` and every metric
  from a fallback run is labelled as such.

### Audio handling

- Generated audio is **never committed**, whichever engine made it. It is cached by digest = SHA-256 of (text,
  engine, voice ID, model ID, settings) in git-ignored `eval-cache/tts/` locally and in the private Actions cache in
  CI, never as a public artifact. Only the digest manifest is committed. A cache hit never calls the API.
- ElevenLabs output is never in the tuning pool and never in the smoke set.

### Voice verification (§6.4), per voice and model

- Generate every target word in CPO's set plus a stress-trap list, once with correct stress and once with stress
  moved to another syllable.
- Keep a voice only if all three hold: ≥ 90% of moved items have their observed primary on the marked syllable at ≥
  medium confidence; ≥ 95% of correct items match the expected stress; used as the reference for the **18 VCTK
  tuning speakers only**, it passes the positive-set placement-FP gate (≤ 2%).
- **That placement-FP gate is no longer blocked on spec 24.** It consumes spec 02's positive-set result through spec
  02's `PositiveSetGates.line`. It was blocked on spec 24 (CTO ruling, 2026-11-23 14:18). Spec 24 merged in #35
  (6f69934), and the set is now EVALUABLE (20 phrases, 17 distinct source prompts, 274 headline pairs), so the gate
  evaluates. A NOT EVALUATED line is still never a pass and never a waiver, and no voice passes verification on one. "18 VCTK
  tuning speakers" is a floor (≥ 18; the manifest records the actual 24).
- **Selection uses only VCTK tuning speakers and the verification items**, through spec 02's tuning-only API. Held-
  out VCTK speakers and speechocean762 words are never used to pick voices (Raph 09:56).
- Passing ElevenLabs voices are the default reference; passing Mac Premium voices are the fallback. If no voice of
  either kind passes, check (ii) is NOT EVALUATED and the release is blocked until CTO decides.
- A TTS SSML check proves the phoneme tags are honoured (moved-stress items differ from correct items).

### End-to-end check (ii) path

- The utterance text with a verified synthetic reference as the model take, through the real comparison path
  (warp, comparable set, A(w) including the TTS voice's observed primary, verdict) from spec 10.
- It plugs into spec 02's fold runner as the end-to-end path, so in each of the 5 outer folds it runs with **the
  same fold-trained config** as the shared-detector path. FP for (ii) uses the shipped config on the clean 1,400
  words. Gating is spec 11; this spec makes it runnable locally and reports it.

### Synthetic edited-native negative set (secondary)

- Built from VCTK **tuning** speakers only.
- Null-processing and correct-boost controls; calibrated magnitudes (native P50, P90 and 1.5 × P90), re-measured.
- Two DSPs: our own Swift TD-PSOLA, and the Rubber Band CLI (GPL-2.0-or-later, run as an external offline tool, never
  linked); results must agree within 5 pp.
- Measures which-syllable accuracy (the syllable is known by construction). TTS stress traps are reported for
  sensitivity, not gated.

### CI and cost

- The agent does not edit `.github/`. The PR lists the workflow Raph would add: a scheduled or manually dispatched
  eval workflow on the default branch that receives `ELEVENLABS_API_KEY`, never on `pull_request` from forks;
  everything else uses the fallback.
- Cost estimate from the plan: about 250k characters per full generation, ≈ $10 on Flash pay-as-you-go, or a
  Creator plan; normally a one-off thanks to the cache.

## Defaults

- Until Raph adds the `ELEVENLABS_API_KEY` secret (an open Decision queue row), every run is the labelled Mac
  fallback. Nothing in specs 01–10 waits on this spec.
- The stress-trap list is the stress-shift words from spec 06's `stress-shift-pairs.json` that appear in CPO's set,
  plus "photography", "photograph", "photographic".

## Guardrails

- The app stays fully on device with no network. No TTS code, key or host string in the app or `AccentKit`.
- No generated audio in git, in a public artifact, or in a dataset used to train or improve a model (ElevenLabs
  Prohibited Use Policy).
- No secret in any file, log or report.
- Synthetic audio never enters tuning or a main gate.

## Out of scope

- Running the release gates (spec 11). Any in-app TTS or "practise your own text" mode (not in v1). Choosing or
  buying an ElevenLabs plan (Raph).

## Open question (built with the default)

1. **Split from row 02.** This spec moves the plan's TTS items out of 02. Default: as written; spec 11 depends on 02,
   10 and 22. If Raph prefers the plan's grouping, these sections move back into 02 and 02 waits on 10.
2. **Fallback quality.** Raph doubts the Mac voices ("mac built in voices are shit no?"). Default: they face the
   same verification; if none pass, the fallback is NOT EVALUATED rather than lowered.

## How to test (Raph)

1. `make check` is green and never calls a TTS engine.
2. `rg -n "elevenlabs|AVSpeechSynthesizer" AccentMirror Packages/AccentKit/Sources` prints nothing.
3. Without a key: `tools/SynthRef` run on the verification items writes a report whose header says
   `syntheticReference: mac-premium-fallback (no key)`, or NOT EVALUATED if no Premium voice is installed.
4. With a key in the environment (optional, costs credits): the same run says `elevenlabs`, and a second run is a
   full cache hit with no API call.
5. `git status` after a run shows no audio files.

## Implementation notes

Built 2026-11-24 by hand (Claude Code, Opus) on `factory/22-synthetic-native-references`.

- **Where it lives.** `tools/SynthRef/` is its own Swift package (library `SynthRefKit`, executable `synthref`,
  tests `SynthRefKitTests`) depending only on AccentKit by local path; no new third-party dependency. The app and
  AccentKit's library products never link it. `scripts/check-no-tts-in-app.sh` scans `AccentMirror/`,
  `Packages/AccentKit/Sources`, AccentKit's `Package.swift` and `project.yml` for `AVSpeechSynthesi…`,
  `elevenlabs.io`, `xi-api-key`, `ELEVENLABS_API_KEY` and `SynthRef`; it runs as the package test
  `NoTTSInAppGuardTests` until `make check` calls it. AccentKit's *tests* are not scanned: spec 07's TTS marker gate
  renders a pinned system voice there.
- **Engines.** `EngineChoice.choose` reads `ELEVENLABS_API_KEY` from the process environment only; no key gives
  `syntheticReference: mac-premium-fallback (no key)`, `--offline` gives `(offline)`. `APIKey` redacts itself in
  descriptions, mirrors and dumps. `ElevenLabsEngine` posts to `/v1/text-to-speech/<voice>/with-timestamps` with
  `eleven_flash_v2`, `output_format=pcm_16000`, inline `<phoneme alphabet="cmu-arpabet">`, the key only in
  `xi-api-key`; every request goes through `HTTPTransport`, and tests use a stub. Word spans come from the
  character alignment (unverified until the first keyed run; a mismatch throws). `MacPremiumEngine` renders with
  `AVSpeechSynthesizer.write` to buffers (never played), SSML `<phoneme alphabet="ipa">` with stress marks and a
  bookmark per word; only installed Premium English voices qualify.
- **Cache and manifest.** Digest = SHA-256 of the canonical JSON of (engine text incl. SSML, engine, voice ID, model
  ID, settings). Renders go to git-ignored `eval-cache/tts/renders/`; a hit never calls the engine. Only
  `fixtures/tts/digests.json` is committed (digests, voice/model IDs, character counts, item IDs; no audio, key or
  host).
- **Verification items.** CPO's set = every word of CPO's 20 prompts (`VCTK.starterPhrases`, texts from the
  corpus transcripts) with two or more syllables in CMUdict: 62 words. Traps = stress-shift words among them
  (`into`) plus photography, photograph, photographic. Correct = CMUdict's first variant; moved = primary on the
  next syllable (previous when last). 130 items, 9,378 characters of ElevenLabs SSML per voice.
- **Bars.** `agreement.voiceMovedStressMin` 0.90, `.voiceCorrectStressMin` 0.95 and
  `.syntheticDSPAgreementMaxPoints` 0.05 added (thresholdsVersion 7, untuned). The placement-FP bar for a voice
  goes only through `PositiveSetGates.line` with spec 02's spec 22 dependent (`agreement.placementDiffPairsMax`),
  scored on `TuningPairOutcome`s that can hold only a `TuningSpeaker`. A voice is kept only if moved, correct and
  the FP line all read PASS and the SSML check passes; NOT EVALUATED drops it. `VoiceSelection.tuningSpeakers`
  refuses held-out, bundled and speechocean762 ids. Reference = kept ElevenLabs voice first, then Mac.
- **End-to-end (ii).** `EndToEndPath` is an `EvaluationPath`, so `FoldRunner` runs it with each fold's trained
  config next to the shared-detector path (tested). `PipelineEndToEndScorer` renders the utterance, runs spec 08's
  detector on both takes and spec 10's `PairScoring.score`, which gained an additive `natives:` parameter (default
  empty, spec 10 goldens unchanged) so A(w) includes the voice's high-confidence observed primary. FP uses the
  shipped config on the clean 1,400 and is reported, not gated.
- **Negative set.** Our TD-PSOLA (`TDPSOLA.modify`) and the Rubber Band CLI (only if on PATH; never linked). Edits
  push the next syllable of clear tuning-speaker words at native P50, P90 and 1.5 × P90 (F0, duration, level),
  re-measure the achieved F0 shift, and run null-processing and correct-boost controls.
- **Run on this Mac (no key):** no Premium or Enhanced English voice installed (26 standard voices), so the Mac
  fallback is NOT EVALUATED; Rubber Band is not installed; no replayed word timings exist for VCTK tuning speakers,
  so the placement-FP pairs and the negative set have no takes. Check (ii) is NOT EVALUATED (no verified voice).
