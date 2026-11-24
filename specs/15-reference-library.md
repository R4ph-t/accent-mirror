# 15: Reference library: bundled starter phrases and native recordings

Status: Done · Branch: – · Depends on: 06 (pronunciations, starter validator), 10 (verdict path), 12 (L0/L1 stages
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
VCTK"). Spec 06 Open question 4 (this spec defines the phrase JSON shape). Addendum r6 E7 (Notion "Accent Mirror spec v2
(2026-11-23)", end of page): `accent`, `region` and `gender` per recording.

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
  source URL, utterance ID, trim start and end in the source clip, file name and SHA-256, plus `accent`, `region`
  and `gender` copied from that speaker's entry in `fixtures/vctk/eval-speakers.json` (`bundled[]`), for spec 21's
  voice pop-up and subtitle (Addendum r6 E7). `scripts/build-starter.sh` copies them; it never types them by hand.
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

- The sidebar reading this manifest and the voice pop-up and subtitle text (spec 21). User clips and My Phrases (spec 17). Choosing or
  changing phrase content, targets or packs (CPO). Recording the Noun and Verb Pairs gap.

## Open question (built with the default)

1. **Phrases the trim drops** (003 snow peas / blue cheese, 008, 011, 016, 019 raindrops / rainbows, 024). Compound
   Nouns keeps only 2 phrases. Default: bundle only phrases whose headline reference passes the 2–6 s trim, and list
   the dropped ones for CPO, who may ask for clause cuts like spec 24's (a later spec). Never relax the trim.

## How to test (Raph)

1. `make check` is green, including the bundled-identity check and the manifest validation tests.
2. `scripts/build-starter.sh` run twice leaves `git status` clean.
3. `Resources/Starter/manifest.json` lists the four packs in order, Noun and Verb Pairs with zero phrases, and every
   recording with speaker, accent, region, gender, corpus, licence, source URL and SHA-256 (p225 reads English,
   Southern England, F). `du -sh Resources/Starter` is ≤ 30 MB.
4. `swift test --filter AMLibraryTests` covers: a stale identity rebuilds into a temp `Caches/` and never writes the
   bundle; a corrupt cache rebuilds once, then `referenceCacheCorrupt`; zero-phrase packs load.

## Implementation notes

Built 2026-11-24 by hand through Claude Code (branch `factory/15-reference-library`, from main at 52d035d).

**What's built**

- `fixtures/starter/phrases.json`: CPO's table from the Notion page, transcribed once (packs in order, the 20 prompts'
  text, every target's ARPAbet override). The builder reads it and never changes it.
- `scripts/build-starter.sh` → `am-eval starter-build`: checks each raw clip against `fixtures/vctk/eval-speakers.json`,
  applies spec 02's `TrimRule` at the source rate (the same call `vctk-trim` makes), writes mono 16-bit FLAC at 48 kHz,
  shifts the recorded WhisperKit words (`fixtures/timestamps/openai_whisper-base.en`) by the trim start, and builds each
  analysis through `StarterReferences.analyse`, the same code the app's rebuild and the CI check run. Two runs are
  byte-identical.
- Result: **14 phrases kept** (002, 004, 005, 006, 007, 009, 010, 012, 013, 014, 015, 017, 018, 020), **6 dropped**
  (p225 over 6 s: 003 6.44 s, 008 6.87 s, 011 6.07 s, 016 6.00 s, 019 6.90 s, 024 6.38 s), **101 recordings**, 23 MB
  (FLAC stays at 48 kHz). Voices left out: trim over 6 s p226_005, p227_005, p233_005, p345_005, p227_006, p227_015;
  not in VCTK 0.92 p227_007, p233_010, p241_015, p241_020. Packs: Stress Shifts 012, 013, 017, 007, 015, 020, 018,
  014; Noun and Verb Pairs (none); Compound Nouns 006, 005; Weak Forms 002, 004, 009, 010, 014, 018, 005.
- `AMLibrary`: `StarterManifest` (decode, `problems()`, `fileProblems(in:)`, `load(from:)`), `ReferenceLibrary`
  (an actor implementing `ReferenceSet`: current cache file, else bundled record, else rebuild into `Caches/`; never
  writes the bundle), `ReferenceRebuilder` (the closures `AMPipeline` injects), and `ReferenceSet.loadNatives`, the
  rebuild-once policy (a recording that fails after its one rebuild is `referenceCacheCorrupt`).
- `AMPipeline`: `StarterReferences` (each phrase as a `PhraseInput` through spec 06's validator and selector with CPO's
  overrides; the expected L1 key; the rebuild from bundled FLAC + timings) and `ReferenceLibrary.bundled(folder:caches:
  configuration:)` for spec 21. `Analyzer`'s natives loop now calls `loadNatives`; its behaviour is unchanged.
- Tests: `AMLibraryTests` (bundled manifest and files, packs and attribution, validation errors, zero-phrase pack,
  stale identity → `Caches/` with a read-only bundle, corrupt cache → one rebuild, corrupt twice →
  `referenceCacheCorrupt`); `AMPipelineTests/BundledStarterTests` (validator on every phrase; every bundled analysis
  recomputed and compared by key and SHA-256, which is the `make check` guard; one take analysed against the bundled
  library with no rebuild and no cache write).

**Spec gaps (built least-committal)**

1. **Bundled word timings.** The Files list has no timings folder, but the rebuild reads "bundled word timings", so they
   ship as `timings/<phraseID>/<speaker>.json` (spec 03's `RecordedTimestamps`, shifted, clamped into the clip,
   rounded to 1 µs). 404 KB.
2. **Analysis file and key.** `analysis/<phraseID>/<speaker>.json` holds the encoded `NativeAnalysis` bytes (L0 + L1,
   with their keys inside); the record's key is `analysisKey` in the manifest, next to `analysisSHA256`. Cache files
   are `DerivedRecord` JSON.
3. **"Unknown pack" error.** Phrases don't name packs in this format, so it is read as a pack listing a phrase the
   manifest doesn't define (`unknownPhrase(pack:phrase:)`), plus `phraseInNoPack`.
4. **IDs.** Phrase `vctk-<prompt>`, recording `<speaker>_<prompt>` (the harness's IDs). `ReferenceIdentity`:
   transcript revision 0, overrides and targets hashed as canonical JSON, native-set hash as `NativeBand`'s.
5. **Targets = CPO's overrides.** CPO gives an override for every target (spec 06), so `targets` is the overrides'
   indices. On 005, "train station (18–19)" makes both words targets (T R EY1 N, S T EY1 SH AH0 N); CPO's "plus and,
   will, her, at, the" has no indices, so those are not targets. 010 "but" has no ARPAbet on CPO's page and CMUdict has
   one form, so it gets B AH1 T (as CPO did for from, at, would). 024 "or" ER0 (024 is dropped anyway).
6. **005 in Weak Forms** is appended last: CPO says to file it there but gives no position.
7. **Source URL** per recording is the DataShare landing page from `fixtures/corpora/vctk.pin.json`; the DOI is in
   `ATTRIBUTION.md` and `THIRD_PARTY_NOTICES.md`.
8. **16 kHz resampler.** The app can't link `AMEvaluation`, so `StarterReferences.resample` is a copy of
   `AudioFiles.resample` (same filter).
9. **Load-time hashing.** `StarterManifest.load` checks every file's SHA-256 by default (about 23 MB); spec 21 may pass
   `checkFiles: false` at launch if that is too slow in the app.
10. **Rebuild-once loop location.** Moved from `Analyzer` into `AMLibrary` (`loadNatives`) so the policy is tested in
    `AMLibraryTests` as How to test 4 asks.
