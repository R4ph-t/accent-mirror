# 26: Nucleus count and edge-robust assignment (stacks on spec 25)

Status: Ready · Branch: factory/26-nucleus-count-assignment (hand build, from cd1855b) · Depends on: 07, 08, 12, 23, 25 (stacked on the unmerged branch
`factory/25-nucleus-anchored` at cd1855b and its report `nucleus-jitter-acb3910a`; see CTO decision 6) · Estimate:
6–8 h agent run + 1.5 h Raph review · Risk: high

Risk: high. It changes `Packages/AccentKit/Sources/AMCore/Thresholds.swift` (nucleus keys chosen on the pre-declared
grid), adds an `UnavailableReason` to the contract, and bumps `thresholdsVersion` and `algorithmVersion`. CTO approved this spec on 2026-11-24 at 16:02 Europe/Paris with
two markups (folded in: §1a and §4) and accepted defaults 2, 3, 5, 6 and 7. The implementation goes to CTO for an engine and threshold review
together with spec 25, before either merges.

Source: CTO's ruling of 2026-11-24 15:56 Europe/Paris (relayed by Accent Mirror Lead), after spec 25's acceptance 1
FAIL (report `docs/agreement/reports/nucleus-jitter-acb3910a.md` on `factory/25-nucleus-anchored`). CTO withdraws the
2–3-syllable cut; no scope cut goes to Raph yet. Spec 25's numbers at ±40 ms, `.span` → `.nucleus`: synthetic pooled
8.1% → 6.5% (2-syllable 17.6% → 11.8%, n 51), VCTK held-out pooled 11.6% → 4.5% (2-syllable 12.2% → 3.3%,
3-syllable 17.8% → 3.3%). Inconclusive under jitter is 28.3% (synthetic) and 60.6% (VCTK), against the 10% budget.
Near-edge on VCTK: words with a nucleus peak within 40 ms of an oracle edge flip 10.1% (126 / 1,249), the rest 1.8%
(48 / 2,641); synthetic doesn't separate (6.5% both ways). Spec 25's build found the main cause of nucleus-short
words: the peak frame must be pYIN-voiced, and pYIN's voicing starts about 60 ms after ACF's at vowel onsets, past
the envelope peak (p238_001 "stella": peak 1.53–1.57 s, pYIN voiced from 1.58 s, ACF from 1.52 s). Raph asked for
prior art (2026-11-24, via Accent Mirror Lead); it is in the next section.

**Build order (CTO, 16:02):**
1. the timestamp check (§1a);
2. any tracker fix, as its own commit;
3. the grid on tuning speakers (§1);
4. the frozen choice, committed;
5. acceptance 1 (§4);
6. on a pass, acceptances 2–4 and a PR stacked on 25 (not merged). On a FAIL, the build stops and writes §6.

## Prior art (algorithms only; no code is copied)

Each source was checked on 2026-11-24. Licences are noted wherever code exists, and nothing here is reused as code.

- **de Jong & Wempe (2009),** "Praat script to detect syllable nuclei and measure speech rate automatically",
  *Behavior Research Methods* 41(2), 385–390, doi:10.3758/BRM.41.2.385. Nuclei are intensity peaks above a threshold
  with a preceding dip of at least **2 dB (unfiltered) or 4 dB (filtered speech)**, and unvoiced peaks are discarded
  using a pitch track with a 100 ms window and 20 ms steps. Later versions of the script (v2/v3) suggest a 2–4 dB
  minimum dip, with 4 dB for clean, filtered speech. The v3 script is GPL-3.0-or-later, so it is compatible, but we
  only describe the method. Used for: the `minProminenceDB` range, and evidence that a coarse voicing check (100 ms
  window) is standard, which supports the voicing tolerance.
- **Mermelstein (1975),** "Automatic segmentation of speech into syllabic units", *JASA* 58(4), 880–883,
  doi:10.1121/1.380738. Finds syllable boundaries at loudness minima, scored by the gap between the loudness
  function's convex hull and the function, with recursive subdivision. It missed 6.9% of syllables and added 2.6% on
  about 400 syllables. Its abstract suggests "alternative fluent-form syllabifications for multisyllabic words and
  ... phonological rules for predicting syllabic contractions" to improve count agreement. Used for: N_w as a set
  with reduced forms (§2). The convex-hull dip test, which suits merged vowels with shallow dips, is noted as an
  alternative and not built here (CTO decision 7).
- **Mertens, Prosogram** (Mertens 2004, Speech Prosody, "The Prosogram: semi-automatic transcription of prosody based
  on a tonal perception model"; tool at sites.google.com/site/prosogram). Pitch is measured on syllabic nuclei: the
  voiced part around the local intensity peak, bounded at **−3 dB (left) and −9 dB (right)** from the peak, and
  intervals are adjusted to the voiced regions. The scripts are **Creative Commons, non-commercial**, so they're not
  GPL-compatible. Nothing is reused; only the published nucleus definition is cited. Used for: the `regionDropDB`
  range (3–9 dB) and the nucleus-based f0 window.
- **Tepperman & Narayanan (2005),** "Automatic syllable stress detection using prosodic features for pronunciation
  evaluation of language learners", ICASSP 2005, I-937–940, doi:10.1109/ICASSP.2005.1415269. Primary stress in CAPT
  is detected from **nucleus** f0, energy and duration (nucleus boundaries from forced alignment), each normalised
  within the word, at about 80% accuracy on ISLE learners. This supports nucleus-anchored stress features and
  within-word comparison (spec 08's approach).
- **Corpora:** speechocean762 (Zhang et al., Interspeech 2021; **CC BY 4.0**; word-level stress labels 10 = correct
  or monosyllable, 5 = wrong) is the L2 set already in use. L2-ARCTIC (Zhao et al., Interspeech 2018) is **CC BY-NC
  4.0**, so it is never committed (AGENTS.md: `eval-local/` only) and is not used here.

## Goal

Make the nucleus count right and the word assignment robust to edge error. Detection settings are chosen against
detection truth only, never against verdicts. Then re-run spec 25's acceptance 1 unchanged. Either it passes, or the
build writes the final scope proposal (§6). This is the last fallback.

## Behaviour

### 1a. Timestamp check first (CTO markup 1)

Before any grid run, the build checks `PYINTracker`'s frame timestamp convention. A steady lag of about 60 ms looks
like frames stamped at their **start** rather than their **centre**: half of a 2048-sample frame at 16 kHz is 64 ms.

- **Checks:**
  - On spec 25's pulse train (known vowel onsets), compare the first pYIN-voiced frame time with the true onset.
  - On about 20 MFA vowel onsets per tuning speaker, from at least 5 tuning speakers, compare pYIN and ACF voicing
    onsets with the MFA vowel start.
  - Report the median and 90th-percentile signed offsets.
  - Read the tracker's code for where each frame's time comes from.
- **If it's an offset bug,** the build fixes it in the tracker as **its own commit**, before the grid:
  - `algorithmVersion` goes to the next one in this stack (3);
  - spec 04's goldens are regenerated;
  - a new test asserts that pYIN's voicing onset lands within 10 ms of the true onset on the pulse train;
  - the Implementation notes say that pitch consumers (the live strip and spec 09's metrics) shift by the corrected
    offset.
  - The grid then uses `voicedWithinMs` ∈ {0, 30}.
- **If it's real pYIN behaviour** (a lag that varies with onset type, or that remains with centre stamping), the
  tracker is left alone and the grid uses `voicedWithinMs` ∈ {0, 30, 60}.
- Either way, the grid stays detection-only on tuning speakers. The finding, with its numbers, goes into the
  `nucleus-count` report and the tuning log.

### 1. Count fix, tuned against detection only

- **Pre-declared fixed grid**, written here before any run. No value outside it is ever used.
  - `nucleus.minProminenceDB` ∈ {1.5, 2.0, 2.5, 3.0, 4.0}. This spans de Jong & Wempe's 2 dB (unfiltered) and 4 dB
    (filtered) dips, plus one step below for shallow vowel–vowel dips, around spec 25's 3 dB.
  - `nucleus.minSeparationMs` ∈ {50, 60, 70, 90}. Spec 25 used 70. 50 allows short unstressed syllables in fast
    speech; 90 is the most conservative merge.
  - `nucleus.regionDropDB` ∈ {3, 6, 9}. This spans Prosogram's −3 dB and −9 dB bounds and spec 25's 6.
  - `nucleus.voicedWithinMs` (CTO-approved fourth dimension, markup 1): {0, 30} if §1a finds an offset bug and the
    tracker is fixed, otherwise {0, 30, 60}. A candidate peak counts as voiced when any pYIN-voiced frame lies within
    ±W ms of it; 0 is spec 25's rule. This matches de Jong & Wempe's coarse voicing check. The nucleus region still
    uses voiced frames only.
  - That's 120 points (with {0, 30}) or 180 (with {0, 30, 60}). Every other nucleus parameter stays at spec 25's value:
    `minPeakDBFS` −45, `skipCostMs` 60, `windowMs` 30.
- **Data:** the VCTK **tuning** speakers only (the split manifest, 24 speakers), with their MFA word and phone
  alignments from spec 07's pinned MFA. Phone tiers are re-derived from the existing tuning-speaker MFA runs if they're
  missing. No held-out speaker, synthetic audio or L2 audio enters the choice, and neither does any verdict, flip or
  gate number.
- **Objective:** maximise the **count-match rate**, the share of comparable words (MFA word boundaries, `present`
  words with ≥ 1 syllable) whose assigned nucleus count P is in the word's **allowed set N_w** (§2).
- **Floor (proposed: 0.90):** at least 90% of assigned nucleus peaks must lie inside an MFA vowel interval widened by
  10 ms on each side. A point under the floor is infeasible.
- **Tie-breaks, in order:**
  1. the higher vowel-inside share;
  2. the higher median overlap (IoU) between nucleus regions and their MFA vowel intervals (the only criterion that
     `regionDropDB` affects; CTO decision 2);
  3. the point closest to spec 25's initial values.
- **Output:**
  - The chosen point goes into `Thresholds.swift` and `docs/thresholds.md`.
  - A `docs/agreement/tuning-log.md` entry records the grid, every point's count-match rate, vowel-inside share and
    IoU, the feasible count, the choice, and the hash of the reduced-forms file.
  - If no point is feasible, nothing changes, and the build reports the closest points and goes straight to §6.

### 2. Allowed counts N_w

- N_w becomes a **set**: the syllable counts of every CMUdict pronunciation of the word (spec 06's bundled
  dictionary), plus the counts from a committed list of **reduced forms**. This follows Mermelstein's suggestion of
  alternative fluent-form syllabifications.
- **Where the list lives:** `Packages/AccentKit/Sources/AMAlignment/Resources/ReducedForms/reduced-forms.json`.
  - It's committed before any run and **frozen once the grid starts** (CTO, 16:02); it's never edited on results.
  - Each entry is `{word, fullCount, reducedCount, droppedSyllable (index in the context pronunciation), stress,
    source}`.
  - Entries only add counts; they never remove CMUdict's.
  - When the file is built, any count CMUdict already lists is dropped.
- **Initial list.** It comes from general English phonology (schwa or syncope elision before a liquid or nasal, and
  smoothing), not from the corpora:
  - **3 → 2 syllables:** family, every, camera, different, chocolate, favorite, several, general, natural, probably,
    restaurant, evening, memory, history, factory, mystery, boundary, library, separate (adjective), average,
    beverage, opera, centuries, various, business, Wednesday, everyone.
  - **4 → 3 syllables:** temperature, comfortable, vegetable, interesting, actually, usually, basically, everything,
    everybody.
  - **5 → 4 syllables:** especially.
  - **Smoothing pairs, one count added each way:** fire, hour, our (1 ↔ 2), poem (2 ↔ 1), real (1 ↔ 2).
- **Index mapping:** when the DP picks a reduced count, the take's syllable k maps to the context pronunciation's
  syllable through `droppedSyllable`. That keeps A(w), `placementDecision` and S/U working on context indices. A
  CMUdict alternate with a different count uses its own stress pattern, mapped the same way through spec 06's
  syllabifier.
- **The DP** (spec 25 §2) accepts any count in N_w, and ties go to the context pronunciation's count. Split confidence
  stays spec 07's 0.9 − 0.3·|P − N|, where N is the allowed count closest to P.

### 3. Assignment stability (no blanket inconclusive)

- A word is **edge-exposed** when an assigned or candidate nucleus peak lies within 40 ms of either of its edges.
- For each edge-exposed word, the build computes its verdict under **both candidate assignments** of each such peak:
  the DP's choice, and the peak moved to the neighbouring word (or skipped, when the neighbour can't take it under
  N_w). Every word the move touches is re-verdicted.
- If the verdicts agree, the word keeps its verdict. If they don't, each word whose verdict differs gets
  `.unavailable(.assignmentAmbiguous)`, a new `UnavailableReason` in AMCore (a contract addition; CTO decision 3).
  Near-edge words aren't made inconclusive wholesale; only disagreement does that.
- The report prints an `assignmentAmbiguous` line per set and group, on both the unjittered and ±40 ms runs: the count, the rate, its Wilson interval, and its
  share of the inconclusive rate.

### 4. Acceptance tests, in order (stop at the first failure)

1. **Acceptance 1, unchanged from spec 25 §5.1.**
   - Setup: the oracle-boundary jitter test (TTS markers on synthetic, MFA on held-out VCTK), at ±20, ±40 and ±80 ms,
     with the split manifest's fixed seed. Flips count anything↔inconclusive.
   - Pass conditions:
     - **≤ 2% flips at ±40 ms on each set**, pooled and in every multi-syllable group (2, 3, 4+) with n ≥ 30;
     - a per-group inconclusive rise of ≤ 2 points (groups 2 and 3, n ≥ 30);
     - the **10% inconclusive budget**, which must hold on **both** populations (CTO markup 4): the compared words'
       inconclusive share on the **unjittered** oracle run, and their inconclusive share on the **±40 ms jittered**
       runs. The per-group rise is still jittered against unjittered.
   - Groups with n < 30, and the ±20 and ±80 ms runs, are reported only.
   - It runs on the grid-chosen nucleus parameters and main's verdict thresholds. The `.span` results and spec 25's
     `.nucleus` results (acb3910a) are printed as before columns.
2. **Control** (spec 11 §4), as in spec 25 §5.2.
3. **Aligner comparison** (spec 23's `DownstreamHarness`), as in spec 25 §5.3.
4. **The full spec 11 gate rows**, as in spec 25 §5.4.
- **CI:** `NucleusJitterGateTests` (spec 25) reads the new report for the head's `configDigest`. Red CI means no
  merge.

### 5. Diagnostics (reported, required)

- **Why synthetic doesn't separate on near-edge words** (spec 25: 6.5% both ways; 2-syllable 11.8%). For the
  synthetic set at ±40 ms, under both spec 25's `.nucleus` and this spec's, break every flip down by:
  - **transition type:** feedback↔close, feedback↔feedback on another syllable, and anything↔inconclusive (by reason:
    nucleus-short, `assignmentAmbiguous`, low confidence);
  - **whether the k-th nucleus moved:** a different set of nuclei assigned to the word under jitter, against the same
    nuclei with a changed measurement (exposure flipped through the word-timing gap, clamping, or a change in the
    comparable set);
  - **exposure:** flips where the word's lengthening exposure changed under jitter. Spec 25's structural rule reads the
    word-timing gap, which jitter moves.
- **TTS-marker check.**
  - For each synthetic word, compare its TTS-marker edges with MFA on the same audio: median and 90th-percentile |Δ|,
    and the share over 40 ms, per edge side.
  - Note the markers' 512-sample resolution (about 23 ms).
  - Report the flip rate for words whose marker and MFA edges agree within 20 ms, against the rest.
  - If the cause is the synthetic oracle, the report says so with these numbers. **The synthetic set is never dropped**,
    and its gate stays as written.
- **Also reported:**
  - the count-match rate and vowel-inside share on held-out VCTK (never used to choose);
  - the nucleus-short rate per group;
  - the share of chosen counts that are reduced forms or CMUdict alternates.

### 6. Stop rule: no more fallbacks

If acceptance 1 fails, there is no further fallback. The build stops: no acceptances 2–4, and no parameter change
outside the grid. It writes a **scope proposal** into the report with at least two cut shapes, each with numbers, for
CTO to route to Raph via CPO.

- **(a) Confident subset.** Per-word stress verdicts only on count-matched, unambiguous words: P ∈ N_w, not
  `assignmentAmbiguous`, not nucleus-short. Give:
  - the subset's size: its share of comparable words per set and group, its share of the starter phrases'
    placement-applicable words, and the phrases affected;
  - its ±40 ms flip rate, pooled and per group;
  - recall on the 134 L2 stress-wrong words (count and Wilson interval);
  - the clean-1,400 false-flag rate;
  - the positive-set placement and any-diff rows.
- **(b) v1 without per-word stress verdicts.** Keep the phrase-level rhythm and intonation rows (nPVI, weak length,
  band coverage, pitch range, final direction) and drop the placement and contrast verdicts. Give the positive-set rows
  that remain, with their n, and the starter targets that lose their stress feedback.

Nothing is cut in code here.

## Defaults

- The grid run happens locally on the Mac, by the build itself (spec 11 §7's rule: no hand runs). Parameters outside
  the grid don't change.
- `thresholdsVersion` and `algorithmVersion` follow on from spec 25's branch (9 and 2): **10 and 3**, with a new
  golden-digest record (CTO decision 6).
- Reports: `docs/agreement/reports/nucleus-count-<configDigest8>.{json,md}` for the grid, and
  `nucleus-jitter-<configDigest8>.{json,md}` for acceptance 1 and §6, each with spec 02's identity header.

## Guardrails

- Never loosen ≤ 2%, the 2-point rise, the 10% budget, n ≥ 30, the 150-pair minimum or any spec 11 gate. NOT
  EVALUATED is never a pass.
- No verdict, flip, gate or held-out number enters the grid choice. A test asserts that the grid runner reads only
  tuning-speaker detection data.
- The reduced-forms list is committed before the grid run, and a test checks that its hash in the tuning log matches.
- No code from Praat scripts, Prosogram or any other tool is copied; only the published methods are used. No new
  dependency, no network, and no AppKit or UIKit in AccentKit.

## Out of scope

- Any scope cut (§6 only proposes one).
- A new pitch tracker or voicing source. Spec 04's tracker stays; the voicing tolerance is a window on its output.
- Retuning verdict thresholds or margins.
- Phone-level CTC from b2.
- Mermelstein's convex-hull boundary test (CTO decision 7).
- UI copy for the new reason (an open copy item for Designer).

## Risks

- **The voicing lag isn't among CTO's three parameters.** Without the proposed `voicedWithinMs`, the grid may not fix
  the nucleus-short rate, which was about half of VCTK words in spec 25.
- **Reduced forms widen N_w,** so a wrong count can "match". The vowel-inside floor guards against this.
- **Ambiguity marking can eat the budget.** If many words are ambiguous, the 10% budget fails and §6 applies.
- **The synthetic set is small** (51 two-syllable and 15 three-syllable words), so its intervals are wide.
- **The contract addition** touches every `switch` over `UnavailableReason`.

## Decided (CTO, 2026-11-24 16:02)

1. **Voicing tolerance:** approved after the timestamp check (§1a). The grid uses {0, 30} if the tracker offset is
   fixed, or {0, 30, 60} if the lag is real pYIN behaviour.
2. **`regionDropDB`:** chosen on region–vowel overlap (accepted).
3. **`assignmentAmbiguous`:** shown like low confidence. The implementation PR logs it as an open copy item for
   Designer. No UI work.
4. **The 10% budget** must hold on both the unjittered oracle run and the ±40 ms jittered runs (markup 4).
5. **Vowel-inside floor:** 0.90 with 10 ms tolerance (accepted).
6. **Stacking:** the branch `factory/26-nucleus-count-assignment` comes from cd1855b, versions are 10 and 3, and it is
   reviewed jointly with spec 25 (accepted). If §1a fixes the tracker, that commit is the one that takes
   `algorithmVersion` 3, and the nucleus changes share it.
7. **Mermelstein's convex-hull dip** is out of scope (accepted).

## How to test (Raph)

Every step is run by the build agent and repeated by the reviewer. None needs Raph's hands.

1. `make check` is green, apart from the gate tests while a gate is NOT MET.
2. `swift test --package-path Packages/AccentKit --filter "NucleusTests|NucleusCountTests|AssignmentStabilityTests|PitchTrackerTests"`
   checks that:
   - if §1a fixed the tracker, pYIN's voicing onset is within 10 ms of the true onset on the pulse train, and spec 04's
     goldens match;
   - the grid runner refuses a held-out or synthetic input and reads no verdict;
   - a reduced form ("family" with 2 nuclei) matches, maps syllable indices through `droppedSyllable`, and keeps
     A(w) on context indices;
   - a peak 30 ms inside a word edge gives two candidate assignments; agreeing verdicts are kept, and differing ones
     give `.assignmentAmbiguous` on exactly the words that differ;
   - a word with no peak near an edge is never marked ambiguous;
   - spec 25's tests still pass.
3. `scripts/agreement.sh --suite nucleus-count` prints the grid table (count-match, vowel-inside, IoU, feasible) and
   the chosen point, from tuning speakers only, and writes the tuning-log entry.
4. `scripts/agreement.sh --suite nucleus-jitter` prints acceptance 1 as in spec 25, plus `assignmentAmbiguous`, the §5
   diagnostics and the TTS-marker check. It ends with `Nucleus jitter: MET` or `NOT MET (stop; scope proposal
   written)`, and two runs give identical numbers.
5. On FAIL, the report's §6 section has cut shapes (a) and (b), with the numbers listed there.
6. The committed reports' `sourceTreeHash` and `configDigest` match the head (`scripts/check-report-identity.sh`).

## Implementation notes

_(filled in by the agent)_
