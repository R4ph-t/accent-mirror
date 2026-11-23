# 24: VCTK positive-set phrase coverage

Status: Ready · Branch: – · Depends on: 02 (harness, positive set, trim rule, manifests) · Estimate: 3–4 h agent run
+ 1 h Raph review

Source: CTO ruling on spec 02 (#20 at `c097498`, 2026-11-23 14:18 Europe/Paris, relayed by Accent Mirror Lead). Spec
02 merges with the VCTK positive set NOT EVALUATED. 203 headline pairs and 16 held-out speakers meet their
minimums, but only 15 phrases survive the 2–6 s trim, against ≥ 18. This spec closes the phrase gap without lowering
any minimum and without changing the trim.

## Goal

Get the VCTK positive set to **≥ 18 phrases after trimming**, keeping ≥ 150 headline pairs and ≥ 12 held-out
speakers, so the positive-set gates (specs 09 and 10, and 22's placement-FP gate) can be evaluated. Do it first by
splitting the long shared prompts, and bring in a new corpus only if that isn't enough.

## Behaviour

### Step 1: split shared prompts 021 and 023 into sub-phrases

- VCTK shared prompts 021 and 023 run 7–13 s, so the trim rejects every clip. Split each one at **sentence or clause
  boundaries** into sub-phrases that land in 2–6 s for the bundled reference (p225, or p226 where spec 02's table
  says so).
- **Split points come from the text and are the same for every speaker.** A sub-phrase is a contiguous word range of
  the prompt's shared text, ending at a sentence end or a clause boundary (comma, semicolon or colon, or a
  conjunction that starts a clause). It's defined once in a committed table
  (`fixtures/vctk/sub-phrases.json`: prompt, sub-phrase id, word range, text). It's never chosen per speaker or per
  clip.
- **Cut times come from MFA word boundaries**: the same MFA 3.4.4 / `english_mfa` v3.1.0 setup as specs 03 and 23,
  whose own error against TTS markers was about 25 ms median (#27's reference check). Cut each speaker's clip from
  the MFA start of the sub-phrase's first word to the MFA end of its last word, then apply spec 02's trim rule
  unchanged (spec 05's onset rule, 200 ms pre-roll, 300 ms tail, reject outside 2–6 s). A clip whose MFA alignment
  doesn't cover the sub-phrase's words (word sequence mismatch) is rejected and counted. It's never cut by guesswork.
- A clip is listed only if its `txt/` transcript, normalised, contains the sub-phrase text exactly. That's the same
  transcript check spec 02's fix round 2 added.
- A sub-phrase counts as a phrase only if its bundled reference survives the trim.
- Speakers and splits are spec 02's manifest, unchanged: no speaker is added or moved, and held-out speakers stay
  out of references, bands and A(w).

### Counting and reporting

- The positive-set lines report **both**:
  - the **phrase count**: whole prompts plus sub-phrases that survive;
  - the **number of distinct source prompts** behind them.

  Sub-phrases from one prompt share a reader, a recording session and context, so they're correlated.
- The ≥ 18 minimum is checked on the phrase count, as CTO ruled. The distinct-prompt count is reported next to it
  every time.
- In the two-way clustered bootstrap (speaker × phrase), sub-phrases of one prompt are clustered under that **source
  prompt**, so the intervals don't treat them as independent. Worst-phrase figures are still per sub-phrase.
- Also report the headline pairs, the held-out speakers, and per sub-phrase the clips rejected by the trim and by
  MFA mismatch.

### Step 2: only if step 1 is still short, count LibriTTS-R (don't bring it in)

- If the phrase count is still below 18 after step 1, **count**, don't integrate. Using LibriTTS-R's transcripts and
  metadata only (CC BY 4.0, a pinned release, fetched to the git-ignored cache):
  - shared-text phrases: the same normalised text read by several speakers;
  - how many speakers read each one;
  - how many land in 2–6 s;
  - how many distinct source texts they come from.
- Put the counts in the PR and the report as a "LibriTTS-R availability" table, and stop. Bringing LibriTTS-R into
  the positive set is a new CTO decision.

## Defaults

- Sub-phrases get ids `<prompt>-<letter>` (for example `021-a`). The table and the cut list are committed. Audio is
  never committed, beyond the existing smoke set, which doesn't change.
- MFA runs locally through `scripts/mfa-align.sh`. CI never runs MFA: it replays the committed cut list, the same
  pattern as spec 03's baseline.

## Guardrails

- Never lower the minimums (≥ 150 pairs, ≥ 18 phrases, ≥ 12 held-out speakers), and never change the 2–6 s trim.
- Never choose split points by looking at held-out speakers' results. The table is text-defined and checked against
  the bundled reference only.
- NOT EVALUATED never counts as a pass (spec 02's guard). If the set is still short, it stays NOT EVALUATED.
- No new SPM dependency, no runtime network, no Makefile or `.github/` edits.

## Out of scope

- Splitting any other long prompt (003, 008, 011, 016, 019, 024). Do it only if CTO extends this ruling.
- Integrating LibriTTS-R audio.
- Changing speakers or the split.

## Open question (built with the default)

1. **Which clause boundaries.** Default: sentence ends first. Use a comma, semicolon or colon clause boundary only
   when a sentence alone falls outside 2–6 s for the reference. List every chosen cut in the PR with the reference's
   resulting length.
2. **Does a sub-phrase phrase-count satisfy "≥ 18 phrases"?** Default: yes, as CTO ruled ("if that reaches ≥ 18
   phrases, no new corpus is needed"). The distinct-prompt count is always printed next to it so CTO can revisit.

## How to test (Raph)

1. `make check` is green.
2. `swift test --package-path Packages/AccentKit --filter AMEvaluationTests` passes, including:
   - every sub-phrase in `sub-phrases.json` is a contiguous word range ending at a sentence or clause boundary;
   - one cut table applies to every speaker;
   - a clip whose MFA words don't match is rejected and counted;
   - the bootstrap clusters sub-phrases by source prompt;
   - NOT EVALUATED still never reads as a pass.
3. Local: `scripts/agreement.sh --suite positive` prints phrases kept, distinct source prompts, headline pairs and
   held-out speakers, the per-sub-phrase rejections, and PASS / NOT EVALUATED for the minimums. If step 2 ran, it
   also prints the LibriTTS-R availability table.

## Implementation notes

_(filled in by the agent)_
