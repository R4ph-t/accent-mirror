# 16: Take store

Status: Ready · Branch: – · Depends on: 01 (contract, `PersistenceStatus`), 12 (cache identity, `TakePersisting`),
15 (phrase and reference IDs) · Estimate: 4–5 h agent run + 1 h Raph review

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §8.3 (persistence status, the take transaction, prune, launch recovery, transcript edits, display),
§9.2 (cache levels; L2 kept for at most 3 voices per take; paths, atomic writes, identity in derived JSON), §7 row 16.
First v2 row 16 (a changed identity triggers a lazy recompute from audio, ghosts included). Plan v1 `TakeStore` (last
10 clean takes per phrase, survives a relaunch). Designer spec v1 §7 (take numbering and time) and spec v2 §7, §12
("10 kept, 3 shown on hover"), §13 item 2 (saveFailed, savedPruneFailed) and item 6 (unalignable takes still count
toward the 10), Addenda A7 and B8 (unsaved attempts are never in the store).

## Goal

Keep the last 10 clean takes per phrase on disk, crash-safe, with their derived analyses, and give the app what it
needs for the take menu and the earlier-take ghosts. Implements spec 12's `TakePersisting`.

## Behaviour

### Layout

`Application Support/Accent Mirror/phrases/<phraseID>/takes/<takeID>/` containing `audio.caf` (16 kHz mono Float32),
`features.json` (L0 and L1), `comparison-<voice>.json` (L2, one per voice, at most 3, least recently used dropped
first) and `manifest.json` (SHA-256 of each file, the `AnalysisIdentity`, take number, recorded-at time, and
`unalignable` with its reason when set). URLs come from `FileManager.url(for:in:appropriateFor:create:)`; the root is
injectable so tests use a temp directory.

### Save (only `analysed` takes; §8.3)

1. Write `audio.caf`, `features.json` and `comparison-<voice>.json` into `phrases/<phraseID>/takes/.staging/<takeID>/`,
   then fsync.
2. Write `manifest.json` last, then fsync.
3. **Commit** = one atomic directory rename to `takes/<takeID>/` on the same volume.
- Status updates go through spec 12: `pending`, then `saved(takeID)`, `saveFailed(error)` or
  `savedPruneFailed(takeID, error)`. The result is displayed whatever the save does.
- `takeProblem`, `failed`, `cancelled` and unsaved attempts (too quiet, clipped, too short, words don't match; A7 and
  B8) are never written.

### Prune

Runs only after a commit. Takes beyond 10 for that phrase (oldest first) are renamed into `takes/.trash/` and then
deleted. A failure gives `savedPruneFailed` and is retried at the next launch. Nothing is pruned before a save
succeeds. Unalignable takes count toward the 10.

### Launch recovery

- Delete everything in `.staging/` and `.trash/`.
- A take directory with no manifest, or whose audio hash doesn't match, moves to `takes/.quarantine/`, is logged, and
  is left out of the list.
- Derived JSON missing or with a mismatched identity: keep the take and recompute lazily (through spec 12) when it's
  next shown or needed as a ghost.

### Reading

- `takes(for:)` lists a phrase's takes newest first with number ("Take 1" … "Take n", numbers never reused within a
  phrase), recorded-at time, and status (comparable / unalignable with reason).
- `result(take:voice:)` returns the stored L2 record if its identity matches, else calls the recompute closure
  injected by `AMPipeline` (spec 12) on the stored audio, stores the new record and returns it. Derived files are
  spec 12's `DerivedRecord`s; `AMLibrary` never imports `AMPipeline`.
- `ghosts(before:)` returns up to the 3 takes recorded before the given one, never unalignable ones (Designer §13
  item 6), each with its pitch on the model timeline for the current voice.
- `markUnalignable(take:reason:)` for spec 17's transcript re-run.

## Defaults

- A take's L2 for a new voice is computed on demand (voice switch) and stored, evicting the least recently used of 3.
- Deleting a take by hand isn't in this spec's UI scope; the store exposes `delete(take:)` (atomic rename to `.trash/`
  then delete) for later use and tests.

## Guardrails

- Every write is atomic; no partially written take is ever listed (tests kill the save between each step).
- The store writes only under its root, never in the bundle or `Caches/`.
- No network. No audio leaves the container.

## Out of scope

- The take menu and ghosts UI (specs 20 and 21). Clip phrases' storage (spec 17). iOS backup flags (Milestone 2:
  derived data excluded from backup, audio backed up).

## Open question (built with the default)

1. **Take numbering after pruning.** Default: numbers keep counting up per phrase (Take 11 after Take 1 is pruned),
   so a number never points at two different takes.

## How to test (Raph)

1. `make check` is green.
2. `swift test --filter AMLibraryTests` covers: save then relaunch lists the take; the 11th take prunes the oldest;
   a crash after each save step leaves no listed partial take and recovery cleans `.staging/`; an audio hash mismatch
   quarantines; a thresholdsVersion change recomputes L2 lazily and keeps the take; L2 is kept for at most 3 voices;
   failed and unsaved takes are never written; `ghosts(before:)` skips unalignable takes; a prune failure gives
   `savedPruneFailed` and succeeds at the next launch.

## Implementation notes

_(filled in by the agent)_
