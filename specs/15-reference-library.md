# 15: Reference library: bundled starter phrases and native recordings

Status: Ready · Branch: – · Depends on: 06 (pronunciations, starter validator), 10 (verdict path), 12 (L0/L1 stages
and cache identity) · Estimate: 4–6 h agent run + 1.5 h Raph review · Risk: high

Risk: high. This spec adds `Resources/Starter/` (bundled third-party audio), edits `THIRD_PARTY_NOTICES.md` and adds a
resource entry to `project.yml`, all risky paths. The PR waits for Raph's Merge OK. VCTK 0.92 is CC BY 4.0, already
cleared for committing (AGENTS.md: committed audio is CC BY or CC0 only, with attribution).

Source: CPO's starter phrase set (Notion "Accent Mirror starter phrase set (2026-11-23)"): packs, phrases, target
words, expected stress, overrides, the 8 voices (p225, p226, p227, p233, p241, p252, p311, p345, mic1; never p315; no
p225 for 015), "Lead owns extraction, trimming to the 2–6 s window, the JSON format … bundling". Plan v2 §6.1 ("our
job (specs 02 and 15): extraction, the 2–6 s trim with the same cut for every speaker, phrase JSON and bundling"),
§9.2 (bundle read-only, rebuilds in `Caches/`), §7 row 15 and the first v2 row 15 (a stale bundled identity fails CI;
a corrupt cache rebuilds once, then `referenceCacheCorrupt`). Designer spec v2 §5.1 and §12 (packs, order and the
coming-soon state come from the manifest, nothing hard-coded) and §6 (subtitle "{pack} · Native speaker {voice},
VCTK"). Spec 06 Open question 4 (this spec defines the phrase JSON shape).

## Goal

Ship the starter phrases inside the app as data: each phrase's text, pack, targets and pronunciation overrides, its
native recordings with full attribution, and each recording's precomputed analysis, so a take can be compared at once
with no ASR on the reference and no network.

## Behaviour

### Content

- **Phrases:** CPO's 20 VCTK 0.92 shared-text utterances, filtered by spec 02's trim rule (unchanged: spec 05's onset
  rule, 200 ms pre-roll, 300 ms tail, reject outside 2–6 s) applied to the **headline reference** (p225; p226 for
  015). On main's numbers that keeps 14 phrases and drops 003, 008, 011, 016, 019 and 024 (p225 over 6 s). The build
  prints the kept and dropped lists; the PR lists them for CPO.
- **Voices:** the 8 CPO voices per phrase, mic1, each trimmed with the same rule. A voice whose clip is missing (4 in
  the archive: p227_007, p233_010, p241_015, p241_020) or rejected by the trim is left out of that phrase and listed.
- **Packs and order** from CPO's tables: Stress Shifts, Noun and Verb Pairs, Compound Nouns, Weak Forms. A phrase CPO
  lists in two packs appears in both. **Noun and Verb Pairs has zero phrases** and is still in the manifest, so the
  sidebar shows it as coming soon (Designer §5.1) with no code change.
- **Targets and overrides** exactly as CPO wrote them (0-based word indices after spec 06's tokenisation; ARPAbet
  overrides, e.g. weak `can` K AH0 N on 005). Every phrase passes spec 06's `StarterPhraseValidator`. A phrase with no
  target fails the build (CPO: a phrase with no target is inconclusive).

### Files (`Resources/Starter/`)

- `manifest.json` (`formatVersion`, packs in order with phrase IDs, and per phrase: ID, text, targets,
  pronunciations, headline voice, recordings). Per recording: speaker ID, corpus "VCTK 0.92", licence "CC BY 4.0",
  source URL, utterance ID, trim start and end in the source clip, file name and SHA-256.
- `audio/<phraseID>/<speaker>.flac`: the trimmed clip, mono, source sample rate.
- `analysis/<phraseID>/<speaker>.json`: the L0 and L1 analysis (spec 12's `DerivedRecord`s) with its identity, built from the
  trimmed audio and the recorded WhisperKit word timings in `fixtures/timestamps/` shifted by the trim start.
- `ATTRIBUTION.md` (CSTR VCTK 0.92, CC BY 4.0, DOI 10.7488/ds/2645, per-speaker list) and a VCTK entry in
  `THIRD_PARTY_NOTICES.md`.
- `project.yml` adds `Resources/Starter` to the app as a folder resource (read-only in the bundle).

### Library API (`AMLibrary`)

- `StarterManifest` decodes and validates `manifest.json` (unknown pack, missing file, SHA mismatch and zero targets
  are errors with the item named).
- `ReferenceLibrary` implements spec 12's `ReferenceSet` (declared in `AMLibrary`) for a phrase: each recording's L0/L1 analysis and
  `ReferenceIdentity` (recording SHA, native-set hash). The native band and A(w) come from all of the phrase's voices,
  exactly as the agreement harness uses them.
- **Identity and rebuilds (§9.2):** the bundle is read-only. If a bundled analysis's identity doesn't match the
  running code (for example a `featureVersion` or `algorithmVersion` bump), the library rebuilds it from the bundled
  audio and bundled word timings into `Caches/`, through a rebuild closure injected by `AMPipeline` (`AMLibrary`
  never imports it), and uses that. A corrupt cache file is rebuilt once; a second
  failure is `referenceCacheCorrupt(recording)`.
- Builder: `scripts/build-starter.sh` (VCTK from the existing pinned fetch, the existing trim, the recorded timings)
  regenerates the whole folder; running it twice gives byte-identical files.

## Defaults

- Audio stays FLAC at the source rate. If `Resources/Starter/` would exceed 30 MB, re-encode at 24 kHz FLAC and say so
  in the PR.
- The headline voice is the default selected voice in the app; the others follow CPO's order.
- Sub-phrases of prompts 021 and 023 (spec 24) stay evaluation-only. They aren't CPO content.

## Guardrails

- CI check: recompute every bundled analysis from the committed audio and timings; any identity or digest difference
  fails `make check`. CI never runs ASR.
- No Common Voice or local-only corpus (the existing guard). No network at runtime. Never hard-code a pack or phrase
  in Swift.
- Never write into the bundle; rebuilds go to `Caches/`, never to `Application Support/`.

## Out of scope

- The sidebar reading this manifest and the voice pop-up (spec 21). User clips and My Phrases (spec 17). Choosing or
  changing phrase content, targets or packs (CPO). Recording the Noun and Verb Pairs gap.

## Open question (built with the default)

1. **Phrases the trim drops** (003 snow peas / blue cheese, 008, 011, 016, 019 raindrops / rainbows, 024). Compound
   Nouns keeps only 2 phrases. Default: bundle only phrases whose headline reference passes the 2–6 s trim, and list
   the dropped ones for CPO, who may ask for clause cuts like spec 24's (a later spec). Never relax the trim.

## How to test (Raph)

1. `make check` is green, including the bundled-identity check and the manifest validation tests.
2. `scripts/build-starter.sh` run twice leaves `git status` clean.
3. `Resources/Starter/manifest.json` lists the four packs in order, Noun and Verb Pairs with zero phrases, and every
   recording with speaker, corpus, licence, source URL and SHA-256. `du -sh Resources/Starter` is ≤ 30 MB.
4. `swift test --filter AMLibraryTests` covers: a stale identity rebuilds into a temp `Caches/` and never writes the
   bundle; a corrupt cache rebuilds once, then `referenceCacheCorrupt`; zero-phrase packs load.

## Implementation notes

_(filled in by the agent)_
