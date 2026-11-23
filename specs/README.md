# Specs: index

Each spec is a file `<nn>-<slug>.md` in this folder, built on its own branch `factory/<nn>-<slug>` and merged as one
PR. The factory picks only rows whose status is `Ready`, and the table order is the queue order. Raph merging a spec
PR that sets a row to `Ready` is the approval. Estimates are agent time: the agent's run plus Raph's review.

Specs 01–02 and 04–10 (contract, agreement harness, signal and text front end, prominence, time map, scoring) and
22 (synthetic native references, split out of 02 so ElevenLabs stays off the critical path) landed as Draft in spec PRs #5–#7 and are Ready
(Raph waived spec approval on 2026-11-23: "once written go straight to building without asking"). Specs 11–17, 20 and 21 lead to the first build Raph can test (record a starter phrase, see it against the native
recording): the pipeline and coordinator (12), the bundled starter library (15), tuning and the release report (11),
the take store (16), live capture (14), the charts' motion (20), and the wiring (21). Their rows follow 22 in
critical-path order. Spec 13 (sandbox, microphone entitlement and string) is by hand: Raph's, with no agent run, and
21 waits for it. Spec 17 (clip import, no UI) is off the path: its sheets (Designer Addendum r6 E1–E2) are a later UI spec. Spec 11 must not start before the rev 4 evaluation protocol (Raph,
09:56) is in place: it lands in 02 (speaker-isolated folds, the clean 1,400-word FP set, the matched-config fold
runner, the tuning-only selection API) and 22 (TTS voices chosen on the 18 VCTK tuning speakers). Rows 18 and
19 are built (PR #4) and Done after their fix batch (PR #11). Spec 03 does not wait on spec 11; Raph allowed
the timestamp check to proceed after the skeleton.

| # | Spec | Status | Depends on | Agent run | Raph review |
|---|---|---|---|---|---|
| 00 | [Project skeleton (by hand)](00-project-skeleton.md) | Done | – | – | 0.5 h |
| 01 | [Contract v2](01-contract-v2.md) | Done | 00 | 3–4 h | 1 h |
| 02 | [Agreement harness](02-agreement-harness.md) | Done | 01 | 6–8 h | 1.5 h |
| 03 | [Timestamp feasibility](03-timestamp-feasibility.md) | Done | 00 | 3–4 h | 1 h |
| 04 | [Pitch tracker](04-pitch-tracker.md) | Done | 01 | 3–4 h | 1 h |
| 05 | [Take quality and endpointing](05-take-quality-endpointing.md) | Done | 01 (no dependency on 04) | 3–4 h | 1 h |
| 06 | [Pronunciation, alignment, normalisation](06-pronunciation-alignment.md) | Done | 01 | 4–5 h | 1 h |
| 23 | [Word-boundary refinement](23-word-boundary-refinement.md) | Ready | 03, 04, 07 (downstream gate) | 6–8 h | 1.5 h |
| 24 | [VCTK positive-set phrase coverage](24-vctk-positive-phrase-coverage.md) | Done | 02 | 3–4 h | 1 h |
| 07 | [Syllable segmenter and timing confidence](07-syllable-segmenter.md) | Done | 06 (word boundaries injected; its real-speech gates wait on 23) | 3–4 h | 1 h |
| 18 | [UI foundation](18-ui-foundation.md) | Done | 00 | 3–5 h | 1 h |
| 19 | [Fixture-driven UI shell](19-fixture-driven-ui-shell.md) | Done | 18 | 6–8 h | 1.5 h |
| 08 | [Prominence and observed stress](08-prominence-observed-stress.md) | Done | 02, 04, 07 | 4–5 h | 1 h |
| 09 | [Partial time map and native band](09-partial-time-map-band.md) | Done | 02, 04, 07 | 3–4 h | 1 h |
| 10 | [Measures, verdict and diffs](10-measures-verdict-diffs.md) | Done | 02, 08, 09 | 4–5 h | 1.5 h |
| 22 | [Synthetic native references (evaluation only)](22-synthetic-native-references.md) | Ready | 02, 10 | 4–6 h | 1.5 h |
| 12 | [Analysis pipeline and coordinator](12-analysis-coordinator.md) | Ready | 03, 05, 10 | 6–8 h | 1.5 h |
| 15 | [Reference library: bundled starter phrases and native recordings](15-reference-library.md) | Ready | 06, 10, 12 | 4–6 h | 1.5 h |
| 11 | [Stress validation and threshold tuning](11-stress-validation-tuning.md) | Ready | 02, 10, 12, 22 | 6–8 h | 2 h |
| 16 | [Take store](16-take-store.md) | Ready | 01, 12, 15 | 4–5 h | 1 h |
| 14 | [Live microphone capture (macOS)](14-live-capture.md) | Ready | 05 (the hand test needs spec 13) | 3–4 h | 1 h |
| 20 | [Charts: live strip, playhead, earlier takes and voice-switch ease](20-charts-motion.md) | Ready | 19 | 6–8 h | 1.5 h |
| 13 | [Sandbox, microphone entitlement and usage string (by hand)](13-entitlements-mic-string.md) | Ready | 00 | – | 0.5 h |
| 21 | [Coordinator-wired UI: record, compare, play back](21-coordinator-wired-ui.md) | Ready | 11, 12, 13, 14, 15, 16, 20 | 10–12 h | 2 h |
| 17 | [Clip import pipeline (no UI)](17-clip-import.md) | Ready | 03, 06, 12, 15, 16 | 4–5 h | 1 h |
