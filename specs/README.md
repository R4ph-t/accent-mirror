# Specs: index

Each spec is a file `<nn>-<slug>.md` in this folder, built on its own branch `factory/<nn>-<slug>` and merged as one
PR. The factory picks only rows whose status is `Ready`, and the table order is the queue order. Raph merging a spec
PR that sets a row to `Ready` is the approval. Estimates are agent time: the agent's run plus Raph's review.

Specs 01–02 and 04–10 (contract, agreement harness, signal and text front end, prominence, time map, scoring) and
22 (synthetic native references, split out of 02 so ElevenLabs stays off the critical path) landed as Draft in spec PRs #5–#7 and are Ready
(Raph waived spec approval on 2026-11-23: "once written go straight to building without asking"). Specs 11–17, 20 and 21 lead to the first build Raph can test (record a starter phrase, see it against the native
recording): the pipeline and coordinator (12), the bundled starter library (15), tuning and the release report (11),
the take store (16), live capture (14), the charts' motion (20), and the wiring (21). Their rows follow 22, with
the analysis specs (12, 11) first (see "Analysis first" below). Spec 13 (sandbox, microphone entitlement and string) is by hand: Raph's, with no agent run, and
21 waits for it. Spec 17 (clip import, no UI) is off the path: its sheets (Designer Addendum r6 E1–E2) are a later UI spec. Spec 11 must not start before the rev 4 evaluation protocol (Raph,
09:56) is in place: it lands in 02 (speaker-isolated folds, the clean 1,400-word FP set, the matched-config fold
runner, the tuning-only selection API) and 22 (TTS voices chosen on the 18 VCTK tuning speakers). Rows 18 and
19 are built (PR #4) and Done after their fix batch (PR #11). Spec 03 does not wait on spec 11; Raph allowed
the timestamp check to proceed after the skeleton.

**Analysis first (Raph, 2026-11-24 09:08 and 09:09 Europe/Paris).** "Validate principles and core workings of the
audio analysis before spending more cycles on UI", and the validation runs through the factory with no hand runs.
So:

- **v1 is show-don't-judge (Raph, 2026-11-24 18:42 Europe/Paris, relayed by CPO: "Yes, ship v1 as show-don't-judge,
  and merge #68").** Spike 27 came back NO-GO (CTO accepted; report `docs/agreement/reports/spike27-69675122.md`,
  docs PR #69). v1 overlays your pitch and timing on the native reference with no stress or phrase verdicts;
  scoring stays off until a model clears spec 27's gates (Milestone 2). Spec 28 gates the verdict paths out of the
  shipped app; spec 29 draws Designer spec v3's result screen (which wins over v2 and addenda r2–r6:
  https://app.notion.com/p/4220d0d4459281d39d67d6fdc5d50dfc); 20 and 21 now depend on 28 and 29. The verdict gates of 11, 23, 25 and 26 are superseded: 11, 25 and 26
  read `Replaced by 28`, and their branches (`factory/11-…`, `factory/25-…`, `factory/26-…`) stay unmerged as
  history and data. Plan: Notion "Accent Mirror v1 show-don't-judge integration plan (2026-11-24)",
  https://app.notion.com/p/4220d0d4459281399adef9364a99bb69 (CTO approved). The bullets below are history.
- **Repointed 2026-11-24 (Manufacture Lead's ask, CTO OK; CTO decision record
  https://app.notion.com/p/4220d0d445928128b258faf2852259c1): 20 and 21 now depend on 27, not 11.** Spec 27's
  offline spike (GO or NO-GO) replaces the reference-diff verdict gates of 11, 23, 25 and 26. Its row reaches Done
  only after CTO rules on the spike report. The bullets below describe the original spec 11 mechanism and are kept as
  history.
- **20 and 21 are blocked until spec 11's release report shows every positive-set gate PASS**, with every
  negative-set (L2) gate PASS and `Spec 11 guard: MET`. NOT EVALUATED is never a pass. The block is the index:
  both rows list 11 in Depends on, and the picker takes them only once 11's row is Done on main.
- **Spec 11 can only become Done when that is true.** Its build runs the release suite itself and commits the
  report, and spec 11 adds `AnalysisGateTests` to AccentKit's tests (`make test`, so CI's `build & test` check runs
  it). The test fails unless the committed report for the current `configDigest` shows the gates above (spec 11
  §7). Red CI means the PR can't merge, so the row never reaches Done and 20 and 21 stay blocked. A FAIL goes to
  CTO with the numbers; no gate is lowered to get past it. Nobody flips 20 or 21 by hand.
- Spec 12's build likewise records the held-out word timings and commits the positive-suite report itself (spec
  12, "Held-out pairs through the pipeline").
- The queue puts the analysis specs first: 22, 12, 11, then the rest.

| # | Spec | Status | Depends on | Agent run | Raph review |
|---|---|---|---|---|---|
| 00 | [Project skeleton (by hand)](00-project-skeleton.md) | Done | – | – | 0.5 h |
| 01 | [Contract v2](01-contract-v2.md) | Done | 00 | 3–4 h | 1 h |
| 02 | [Agreement harness](02-agreement-harness.md) | Done | 01 | 6–8 h | 1.5 h |
| 03 | [Timestamp feasibility](03-timestamp-feasibility.md) | Done | 00 | 3–4 h | 1 h |
| 04 | [Pitch tracker](04-pitch-tracker.md) | Done | 01 | 3–4 h | 1 h |
| 05 | [Take quality and endpointing](05-take-quality-endpointing.md) | Done | 01 (no dependency on 04) | 3–4 h | 1 h |
| 06 | [Pronunciation, alignment, normalisation](06-pronunciation-alignment.md) | Done | 01 | 4–5 h | 1 h |
| 23 | [Word-boundary refinement (measurement-only; b2 not shipped; downstream verdict gate superseded)](23-word-boundary-refinement.md) | Done | 03, 04, 07 (downstream gate) | 6–8 h | 1.5 h |
| 24 | [VCTK positive-set phrase coverage](24-vctk-positive-phrase-coverage.md) | Done | 02 | 3–4 h | 1 h |
| 07 | [Syllable segmenter and timing confidence](07-syllable-segmenter.md) | Done | 06 (word boundaries injected; its real-speech gates wait on 23) | 3–4 h | 1 h |
| 18 | [UI foundation](18-ui-foundation.md) | Done | 00 | 3–5 h | 1 h |
| 19 | [Fixture-driven UI shell](19-fixture-driven-ui-shell.md) | Done | 18 | 6–8 h | 1.5 h |
| 08 | [Prominence and observed stress](08-prominence-observed-stress.md) | Done | 02, 04, 07 | 4–5 h | 1 h |
| 09 | [Partial time map and native band](09-partial-time-map-band.md) | Done | 02, 04, 07 | 3–4 h | 1 h |
| 10 | [Measures, verdict and diffs](10-measures-verdict-diffs.md) | Done | 02, 08, 09 | 4–5 h | 1.5 h |
| 22 | [Synthetic native references (evaluation only)](22-synthetic-native-references.md) | Done | 02, 10 | 4–6 h | 1.5 h |
| 12 | [Analysis pipeline and coordinator](12-analysis-coordinator.md) | Done | 03, 05, 10 | 6–8 h | 1.5 h |
| 11 | [Stress validation and threshold tuning (verdict gates superseded: spike 27 NO-GO, v1 show-don't-judge)](11-stress-validation-tuning.md) | Replaced by 28 | 02, 10, 12, 22, 23 (b2 harness for the guard; #27 merges as measurement-only) | 9–12 h | 2.5 h |
| 25 | [Nucleus-anchored syllable measurement (spec 11's FALLBACK; hand build; verdict gate superseded, branch kept as data)](25-nucleus-anchored-syllables.md) | Replaced by 28 | 07, 08, 12, 23 (spec 11's harness and FALLBACK report) | 6–8 h | 1.5 h |
| 26 | [Nucleus count and edge-robust assignment (stacks on 25; hand build; verdict gate superseded, branch kept as data)](26-nucleus-count-assignment.md) | Replaced by 28 | 07, 08, 12, 23, 25 (stacked on branch factory/25-nucleus-anchored) | 6–8 h | 1.5 h |
| 27 | [Word-stress classifier and native envelope: offline feasibility spike, GO/NO-GO (CTO decision 2026-11-24 + lit review; hand build; NO-GO, CTO accepted; report in docs PR #69, row goes Done once that merges)](27-stress-classifier-feasibility-spike.md) | Ready | 02, 06, 10, 22, 24, 25 (front end, branch factory/25-nucleus-anchored), 26 (detection grid, branch factory/26-nucleus-count-assignment) | 10 h (time box) | 1.5 h |
| 15 | [Reference library: bundled starter phrases and native recordings](15-reference-library.md) | Done | 06, 10, 12 | 4–6 h | 1.5 h |
| 16 | [Take store](16-take-store.md) | Done | 01, 12, 15 | 4–5 h | 1 h |
| 28 | [Scoring off: show-don't-judge v1 (verdict paths gated out of the shipped app; Raph 2026-11-24 18:42)](28-scoring-off.md) | Ready | 10, 12, 15, 16, 19 (spike 27 NO-GO; report in docs PR #69) | 6–8 h | 2 h |
| 14 | [Live microphone capture (macOS)](14-live-capture.md) | Done | 05 (the hand test needs spec 13) | 3–4 h | 1 h |
| 20 | [Charts: live strip, playhead, earlier takes and voice-switch ease](20-charts-motion.md) | Ready | 19, 29, 28 (v3 result screen and scoring off; was 27, repointed 2026-11-24 after spike 27's NO-GO and Raph's v1 show-don't-judge decision) | 6–8 h | 1.5 h |
| 13 | [Sandbox, microphone entitlement and usage string (by hand)](13-entitlements-mic-string.md) | Ready | 00 | – | 0.5 h |
| 21 | [Coordinator-wired UI: record, compare, play back](21-coordinator-wired-ui.md) | Ready | 29, 28 (v3 result screen and scoring off; was 27, repointed 2026-11-24 after spike 27's NO-GO and Raph's v1 show-don't-judge decision), 12, 13, 14, 15, 16, 20 | 10–12 h | 2 h |
| 17 | [Clip import pipeline (no UI)](17-clip-import.md) | Done | 03, 06, 12, 15, 16 | 4–5 h | 1 h |
| 29 | [v3/v3.1 show-don't-judge UI: YOUR TAKE, Play Both, strip, inspector, earlier takes (Designer spec v3 + v3.1 addendum; fixture-driven)](29-v3-show-dont-judge-ui.md) | Ready | 28, 19 (needs PR #29, specs 18–19 fixes round 5, merged first) | 8–10 h | 2 h |
