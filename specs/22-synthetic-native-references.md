# 22: Synthetic native references (evaluation only)

Status: Draft · Branch: – · Depends on: 02 (harness), 10 (verdict path) · Estimate: 4–6 h agent run + 1.5 h Raph
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

_(filled in by the agent)_
