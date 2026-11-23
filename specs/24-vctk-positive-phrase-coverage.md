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

Built 2026-11-23 (hand build, Claude Code on Opus). Step 1 alone closes the gap, so step 2 (LibriTTS-R) did not run.

**Result** (`scripts/agreement.sh --suite positive`, local VCTK cache):

| Count | Spec 02 | Spec 24 | Minimum |
|---|---|---|---|
| Phrases kept (whole prompts + sub-phrases) | 15 | **20** | ≥ 18: PASS |
| Distinct source prompts | 15 | **17** | reported, not gated |
| Headline pairs | 203 | **275** | ≥ 150: PASS |
| Held-out speakers | 16 | **16** | ≥ 12: PASS |

The positive set now reads EVALUABLE. Every dependent gate (specs 09, 10, 22) still reads NOT EVALUATED, because none
has been measured yet. It goes through `PositiveSetGates.line` unchanged.

**Cuts** (`fixtures/vctk/sub-phrases.json`, Open question 1 default). 021 and 023 are each one sentence, and p225's
clips of them are 8.1 s and 9.3 s of words, so sentence ends can't help and both are cut at commas. I used the fewest
cuts that put every piece of p225's clip in 2–6 s. 021 has one comma. For 023, a cut at either comma alone leaves a
piece whose p225 word span is over 6 s (6.10 s and 6.33 s), so it is cut at both. Lengths are p225's after the trim:

| Sub-phrase | Words | Text | Ends at | p225 |
|---|---|---|---|---|
| 021-a | 0–12 | the difference in the rainbow depends considerably upon the size of the drops | comma | 4.00 s |
| 021-b | 13–27 | and the width of the colored band increases as the size of the drops increases | sentence | 3.83 s |
| 023-a | 0–13 | if the red of the second bow falls upon the green of the first | comma | 2.96 s |
| 023-b | 14–26 | the result is to give a bow with an abnormally wide yellow band | comma | 3.09 s |
| 023-c | 27–35 | since red and green light when mixed form yellow | sentence | 2.63 s |

Per-sub-phrase rejections: 0 MFA mismatches anywhere. Trim: 021-a 0, 021-b 0, 023-a 0, 023-b 0, 023-c 1 (p239,
held-out, 1.88 s).

**How it works**

- `AMEvaluation/SubPhrases.swift` holds the table (`VCTKSubPhraseTable`, with `problems(phraseText:)`: contiguous range,
  text equal to its words, starts and ends at a sentence or clause boundary), the cutter (`VCTKSubPhraseCut.make`:
  the sub-phrase's words must appear exactly once, contiguously, in the MFA words, otherwise `mfaMismatch`) and the
  committed cut list (`fixtures/vctk/sub-phrase-cuts.json`). The cut list is tied to the table by SHA-256.
- `scripts/vctk-sub-phrase-cuts.sh` extracts the listed 021/023 clips from the pinned archive (checked against
  eval-speakers.json), aligns them through `scripts/mfa-align.sh` (MFA 3.4.4, english_mfa v3.1.0), then runs
  `am-eval vctk-sub-phrase-cuts`. It's local only: CI and `scripts/fetch-vctk-eval.sh` replay the committed list.
- `am-eval vctk-trim` cuts each clip at its committed MFA times, then applies `TrimRule` unchanged. The trimmed cache
  key now covers the table and the cut list too.
- The split prompts leave the positive set and their sub-phrases replace them (`evaluationPhrases`). Whole 021/023
  are still trimmed and their rejections still reported.
- Clustering: `ScoredUnit` and `BootstrapUnit` gain a `phraseCluster` field, which defaults to the phrase.
  `VCTKPair.scoredUnit(hit:)` sets it to the source prompt, so the two-way bootstrap draws 021-a and 021-b together.
  Worst-phrase figures stay per sub-phrase. The two-way label now reads "speakers × source prompts".
- `VCTKPairs` takes its phrase list explicitly and reports `phraseCount`, `sourcePromptCount` and `minimums()`: each
  minimum prints PASS when met and NOT EVALUATED otherwise, never FAIL. A shortfall line always carries the
  distinct-prompt count, for example `phrases 16 < 18 (14 distinct source prompts)`.
- No threshold changed and no version bump. The 18-phrase floor is still `VCTKPairs.minimumPhrases`, and the 2–6 s
  trim, speakers and splits are untouched.

**Spec gaps (least-committal choice built)**

1. *Pre-roll and tail at a cut.* The clip is cut at the MFA word edges and the trim is then applied unchanged, so its
   200 ms pre-roll and 300 ms tail are clamped at the cut. A sub-phrase clip carries no silence from the neighbouring
   words, and never any of their speech. For every p225 sub-phrase, the trim kept the whole word span.
2. *Four clips are outside spec 02's manifest but contain a sub-phrase exactly.* Spec 02 lists a clip only when its
   whole transcript is the shared text. p252_021 ("bands", bundled), p269_021 ("drop"), p313_021 ("sizes") and
   p336_023 ("forms", all three held-out) differ only outside 021-a / 023-a and 023-b. Adding them would change spec
   02's eval-speakers.json and its hash, so they are left out. They would add at most 4 headline pairs and no phrase.
3. *MFA isn't bit-reproducible between runs* (`--num_jobs 4`): a few word edges move by 10 ms. The committed cut list
   is the frozen record, and the SHA-256 of the alignments it came from is recorded in it.
4. `PositiveSetGates.blockingSpec` still says "spec 24". If the set ever falls short again, the line names this spec
   as the blocker. Spec 02's code is left as it is.
