# 17: Clip import pipeline (no UI)

Status: Ready · Branch: – · Depends on: 03 (WhisperKit), 06 (persisted pronunciation), 12 (coordinator), 15
(reference format), 16 (take store, unalignable takes) · Estimate: 4–5 h agent run + 1 h Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §7 row 17 ("as before, plus persisted pronunciation"), §8.3 (transcript edit: old takes recomputed,
unrealignable ones marked `unalignable` and kept). First v2 §11 (importer trim input and races) and row 17. Plan v1
`ClipImporter` (formats, first 15 s of speech, on-device transcription, `reanalyze(phraseID:transcript:)`). Designer
spec v1 §8 (15 s limit, the two error sentences, one native take so the band is ±1.5 st, out-of-dictionary words
measured from the recording) and spec v2 §6 (subtitle "My Phrases · From {file name}"), §12, Addendum A5 (A(w) for
imports: the POS-chosen variant saved at import plus the clip's own observed primary). Spec 06 (the persisted value
type for import pronunciations).

## Goal

Turn an audio or video file into a My Phrases entry with its own native reference, entirely on device, and re-run
it when the transcript changes. This spec has no UI; the sheet waits on Designer (see Out of scope).

## Behaviour

### Propose and commit (first v2 §11)

- `propose(url) async -> ClipProposal`: decodes m4a, mp3, wav, aiff, caf, mov and mp4 through AVFoundation (audio
  track only), finds speech regions with spec 05's detector, and returns the duration, the speech regions, a waveform
  overview and a default selection starting at the first speech onset minus 0.2 s and lasting at most 15 s.
- `commit(selection:transcript:)` requires 0.5 s ≤ length ≤ 15 s, entirely inside the file, snapped to 10 ms;
  otherwise it returns a validation error. It needs a transcript with at least one word.
- Errors map to Designer v1 §8.2's two cases: no speech in the selection, and an unreadable file
  (`OperationalError.audioUnreadable` for the second).

### On-device transcription and races

- After the selection settles, the selection is transcribed with the bundled WhisperKit model (spec 12's model host).
  Each selection change bumps `selectionRevision`; a result for an older revision is dropped.
- Once the user has typed (`userEdited = true`), a late ASR result never overwrites the text.
- Closing the importer or changing the selection invalidates the in-flight request through the coordinator.

### The new phrase

- Stored under `Application Support/Accent Mirror/my-phrases/<phraseID>/`: `phrase.json` (text, transcript revision,
  source file name, created-at, the selection), `clip.caf` (the trimmed audio, 16 kHz mono) and the clip's reference
  analysis (spec 12's `DerivedRecord`s), written with the same staging-then-rename rule as spec 16.
- Pronunciation: per word, spec 06's selector picks the context variant (POS) and the choice is **persisted** in
  `phrase.json`; a persisted value is used only if its folded text still matches the word. Words not in CMUdict get
  measured stress from the clip (Designer v1 §8.3).
- Reference: one native take, so the band falls back to ±1.5 st. A(w) = the persisted context primary ∪ the clip's own
  observed primary at high confidence (Addendum A5). Targets: every content word with two or more syllables (plan
  §4.2: "Imports default to every content word with ≥ 2 syllables").
- My Phrases is listed newest first from these folders. The library exposes it next to the starter packs.

### Transcript re-run

- `reanalyze(phraseID:transcript:)` bumps the transcript revision, recomputes the clip's L1 and reference, then
  recomputes every stored take of that phrase through spec 16. A take that can't be realigned is marked
  `unalignable` with the reason ("recorded for the old wording") and kept; it still counts toward the 10.
- A commit cancels any in-flight request for that phrase.

## Defaults

- The file's own audio is never modified or kept beyond the trimmed copy.

## Guardrails

- No network: transcription uses only the bundled model (a test runs `propose` and `commit` with networking denied).
- ASR never runs in CI: tests use `FixtureTimestamper` on committed fixture clips (a CC BY m4a and mp4 made from the
  smoke set).
- `AMLibrary` stays `AMCore`-only; the importer that needs ASR and detection lives in `AMPipeline`.

## Out of scope

- The New Phrase from Clip sheet, its entry points (⌘N, File menu, + button, drop) and post-import transcript editing.
  Designer spec v2 has no design for the sheet and doesn't say where a clip's transcript is edited after import; both
  go to Designer and a later UI spec. Rename and Delete Phrase.

## Open question (built with the default)

1. **Video files with several audio tracks.** Neither the plan nor the design says which track. Default: the first
   audio track only.

## How to test (Raph)

1. `make check` is green.
2. `swift test --filter "AMPipelineTests|AMLibraryTests"` covers: the m4a and mp4 fixtures become a phrase with a
   transcript, offline; an unreadable file and a silent selection give the two errors; selection bounds (0.4 s and
   15.1 s rejected, snapping to 10 ms); a stale transcription is dropped; typed text beats a late ASR result;
   `reanalyze` replaces the reference in place and marks a take that no longer aligns as `unalignable`; the
   persisted pronunciation survives a relaunch.

## Implementation notes

_(filled in by the agent)_
