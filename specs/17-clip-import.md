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
type for import pronunciations). Designer spec v2 Addendum r6 E1 and E2 (Notion, end of the v2 page) for the
later UI only.

## Goal

Turn an audio or video file into a My Phrases entry with its own native reference, entirely on device, and re-run
it when the transcript changes. This spec has no UI; the sheets (Addendum r6 E1 and E2) are a later UI spec (see Out of scope).

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

- **The import UI**, which a later UI spec builds on top of this one, from Designer's Addendum r6: E1 (the New
  Phrase from Clip sheet, its states and copy, and its entry points ⌘N, File ▸ New Phrase from Clip…, "+ NEW PHRASE"
  and drop on the window) and E2 (the Edit Transcript sheet, opened from the inspector's PHRASE section, the sidebar
  row's context menu and File ▸ Edit Transcript…). E2 replaces v2 §12's "Return or leaving the field" commit: the
  re-run happens only on Save, so the later UI calls `reanalyze(phraseID:transcript:)` once per Save and this spec
  never re-runs on a keystroke or focus change. E1 already matches this spec's API: the sheet's selection limits
  (0.5–15 s), its two error lines and "typed text is never overwritten by a late result" are the rules here.
- Rename and Delete Phrase.

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

Built by hand through Claude Code on 2026-11-24 (not a factory run).

**Shape.** Decoding and speech regions are in `AMCapture`. The store and phrase.json live in `AMLibrary`, which
depends on AMCore only. The importer, which needs ASR and the analyzer, is in `AMPipeline`.

- `AMCapture/ClipDecoder.swift`: AVFoundation `AVAssetReader` on the **first audio track** (Open question 1), giving
  16 kHz mono Float32. Any failure, whether a missing file, no audio track or a format AVFoundation refuses, is one
  `ClipDecodeError` (`.audioUnreadable`). `TakeAnalysis.speechRegions` (new, additive) exposes spec 05's kept speech
  segments.
- `AMLibrary/MyPhraseStore.swift`: `<root>/my-phrases/<phraseID>/` holds `phrase.json` (`MyPhrase`: text,
  `transcriptRevision`, `sourceFileName`, `createdAt`, `selection`, `clipSHA256`, per-word `StoredPronunciation`),
  `clip.caf` (16 kHz mono Float32) and `reference.json` (the clip's L0/L1 `DerivedRecord`). Creation is staged in
  `my-phrases/.staging/<id>/`, with phrase.json written last, then committed by one `renameExclusive`, as in spec 16.
  A re-run replaces reference.json and then phrase.json, each with spec 16's atomic replace. The store is the phrase's
  `ReferenceSet` (one native, `RecordingID("clip")`, voice `clip`) and rebuilds a reference keyed for other code
  from clip.caf through an injected `MyPhraseRebuilder`, as `ReferenceLibrary` does. `listing`, `phrases()`, is newest
  first. `MyPhrase.subtitle` is "My Phrases · From {file name}".
- `AMLibrary/PhraseLibrary.swift`: one `ReferenceSet` over the starter `ReferenceLibrary` and My Phrases, with
  `packs` and `myPhraseList()` side by side.
- `AMPipeline/ImportedPhrases.swift`: the phrase as the analyzer reads it. Spec 06's selector runs with
  `.imported(persisted:)`, so a persisted value is used only while its folded text matches. Targets are every
  content word with ≥ 2 syllables, and A(w) is seeded with the context primary. The clip, as the only native reading,
  adds its own high-confidence observed primary through the analyzer's existing native-readings path. With one
  native, `NativeBand` has no other voices and falls back to ±1.5 st.
- `AMPipeline/ClipImporter.swift`: `propose(url)`, `session(_:)` (a `ClipImportSession` with `selectionRevision`,
  `userEdited` and stale drop), `commit(_:selection:transcript:)` and `reanalyze(phraseID:transcript:)`.

**Out-of-dictionary words (Designer v1 §8.3).** A content word of two or more spelling syllables that isn't in CMUdict
is measured from the clip. The clip is analysed once with every syllable of that word accepted. Its observed primary,
at high confidence, becomes the word's stress (`AH1` on that syllable, `AH0` elsewhere), which is persisted with
`chosenBy: unknown`. The clip is then analysed again with the final words. A word that can't be measured is persisted
with no pronunciation and stays `expectedAmbiguous` (no placement row), and the next re-run measures it again.

**Transcript re-run.** `reanalyze` invalidates the coordinator's request if it is for this phrase
(`transcriptEditCommitted`), bumps the revision, recomputes the reference in place and writes it. It then asks the
take store for each stored take's comparison with the clip, which recomputes because the L1 key moved. A take whose
recompute fails, or whose comparison isn't `analysed` (for example `wordsDontMatch`), is marked unalignable with
"recorded for the old wording" and kept. A take that realigns is marked comparable again (new
`TakeStore.markComparable`). A later call for the same phrase supersedes an earlier one, which then throws `cancelled`
before writing.

**Races.** Each `select` validates and snaps the selection, bumps `selectionRevision`, cancels the transcription in
flight, calls `coordinator.invalidate(.importerSelectionChanged)` and transcribes the new selection. A result is
applied only for the current revision of an open session, and never once `userEdited` is set. `close()` cancels,
calls `invalidate(.importerClosed)` and drops anything that arrives after.

**Fix to spec 16 (found here).** `TakeFiles.readAudio` did one `AVAudioFile.read(into:)`, which stops at a 4096-frame
boundary. Every stored take or clip longer than 0.256 s came back short (76 160 → 75 776 samples), so a recompute ran
on audio that didn't match its recorded SHA-256. It now reads until the whole file is in and throws if the count is
still short. A regression test (`longClipRoundTrips`) covers it.

**Tests** (Swift Testing, temp folders, `FixtureTimestamper`). The m4a and mp4 are encoded in the test
(`Tests/AMPipelineTests/ClipEncoding.swift`, AAC, with the mp4's H.264 track first) from the committed CC BY 4.0 smoke
set's VCTK p288 reading of prompt 018. No audio is committed. The replayed words are the smoke set's recorded timings,
shifted to the selection and keyed by the selection audio's SHA-256.
`MyPhraseStoreTests` (8) and `ClipImporterTests` (7, the first parameterised over m4a and mp4) cover:

- import offline with every URL request failing
- the two errors
- selection bounds and snapping
- a stale transcription dropped
- typed text beating a late result
- `reanalyze` replacing the reference in place and marking the take unalignable, then comparable again
- the persisted pronunciation surviving a relaunch without a tagger call

**Spec gaps (built with the least-committal default).**

1. *Where the importer's in-flight request lives.* The coordinator has one request slot, used by takes, and no
   transcription request. The session owns its transcription task, and every selection change or close also calls
   `coordinator.invalidate(...)` with the existing `importerSelectionChanged` and `importerClosed` reasons.
2. *"After the selection settles."* Debouncing a dragged selection belongs to the later UI. `select(_:)` is the
   settled selection and transcribes at once.
3. *"No speech in the selection"* is decided by spec 05's detector run over the whole file: no kept speech region
   overlaps the selection. A selection with no speech gets `transcriptionError = .noSpeech` in the session, and
   `commit` throws `.noSpeech`.
4. *Snapping.* The selection is checked against the file, then start and end are rounded to 10 ms, and the length
   limits are checked on the snapped values. An end that rounds past the file is snapped down instead. The 0.5 s,
   15 s and 0.2 s figures are Designer's product limits, not tuned values, so they are constants on `ClipImporter`
   and not in `Thresholds.swift`, which spec 11 owns.
5. *An unmeasurable out-of-dictionary word* stays ambiguous (see above). The high-confidence bar is the same as
   A(w)'s for native readings.
6. *Which failures make a take unalignable.* Only a recompute that fails, or a comparison that isn't `analysed`, does
   so. A storage failure leaves the take as it was and reports it in `ReanalysisReport.failed`. The model was
   loaded moments earlier for the clip, so a model failure can't reach the take loop.
7. *ASR runs twice on a new clip*: once for the proposed transcript, and again inside the reference analysis. This
   keeps the reference path identical to `analyseNative`. Reusing the first result is an optimisation for later.
