# 06: Pronunciation, alignment, normalisation

Status: Draft · Branch: – · Depends on: 01 (contract v2) · Estimate: 4–5 h agent run + 1 h Raph review · Risk: high

Source: Plan v2 revision 4.1 (Notion "Accent Mirror v1 groundwork plan v2 (2026-11-23)", approved 2026-11-23 09:56
Europe/Paris): §3.1 (pronunciation selection), §3.3 (context-compatible pronunciation), §4.1–§4.3 (normalisation,
content words, targets, match %, alignment). Function-word list and alignment scoring are from the first v2 §4.
Risk is high because it bundles a third-party dictionary (CMUdict) and edits `THIRD_PARTY_NOTICES.md`.

## Goal

Everything that turns phrase text and heard words into an expected pronunciation per word and a `WordAlignment`:
a bundled CMUdict, the syllabifier, pronunciation selection (override, NLTagger, CMUdict, unknown), the
normalisation equivalence table, content words and targets, and Needleman–Wunsch word alignment. All in
`AMAlignment`, all on device.

## Behaviour

### CMUdict and the syllabifier

- Bundle CMUdict (cmudict 0.7b lineage, the ARPAbet source CPO's overrides use) as an `AMAlignment` package
  resource, pinned to an upstream commit with its SHA-256 recorded in a manifest; its licence text sits next to it
  and in `THIRD_PARTY_NOTICES.md`. It is a BSD-style licence, GPL-3.0-compatible.
- `Syllabifier`: ARPAbet → syllables by maximum onset (with the legal English onset list), each syllable carrying
  dictionary stress 1 / 2 / 0.
- Out-of-vocabulary words: vowel-group syllabification, and the word is `expectedAmbiguous` for placement.

### Pronunciation selection (§3.1), per word, first match wins

1. The phrase JSON's `pronunciations` override (starter phrases have one for every target, from CPO's phrase page).
   For imports, the chosen pronunciation is **persisted** into `phrase.json` at import time, so re-analysis never
   re-tags: the selector takes a persisted value when present and never calls the tagger then.
2. Imports only: `NLTagger` with `.lexicalClass` and the language set explicitly to `.english`, mapped through
   `stress-shift-pairs.json`. If the phrase has fewer than 3 tokens, or the tag isn't noun, verb or adjective, the
   word is `expectedAmbiguous`: no placement diff, excluded from S and U.
3. The first CMUdict variant, if the word has only one primary-stress pattern.
4. Unknown (OOV): vowel-group syllabification, `expectedAmbiguous`.

The result carries its source (`override`, `persistedImport`, `tagger`, `dictionary`, `unknown`) so spec 08 can build
the context-compatible accepted pattern (§3.3): the override, or the POS-selected and persisted variant. Other
CMUdict variants are **not** accepted patterns.

- `stress-shift-pairs.json` is **generated** from CMUdict by `tools/gen_stress_shift_pairs.py` (pure Python, no
  dependencies): words whose variants differ in primary stress. Its POS mapping (which variant goes with noun, verb,
  adjective) is a hand-curated table in the repo (Open question 1).
- A ~50-sentence NLTagger regression fixture covers the stress-shift words in noun and verb contexts ("a new record" /
  "record it", "the present" / "present the case", object, project, permit, increase, conduct, contract, desert,
  produce, …).
- Starter-phrase check: a validator fails when a phrase has a target word with CMUdict stress variants and no
  override. This spec ships the validator and tests it on a fixture phrase file; spec 15 runs it on the bundled
  phrases in CI.

### Normalisation (§4.1): the only allowed equivalences

Case and punctuation folded; fillers dropped (um, uh, er, erm); immediate repeats collapsed; contraction ↔
expansion (a list); number ↔ spoken form; hyphen ↔ space ↔ joined for compounds on a list ("train station" /
"train-station"); US ↔ UK spelling (a list). Anything else is a substitution. Each equivalence is a row in one
table, tested in both directions.

### Content words, targets, match % (§4.2)

- Content words: every word not on the closed `function-words.txt` list (about 150 determiners, pronouns,
  prepositions, conjunctions, auxiliaries and particles). No tagger involved.
- Targets: from the phrase JSON. Imports default to every content word with ≥ 2 syllables.
- Match % = matched content words ÷ content words; with 0 content words, matched words ÷ all words. A substitution is
  never matched.

### Alignment (§4.3)

- Needleman–Wunsch of normalised heard words against phrase words: match +2, substitution −1, insertion or omission
  −1. Fillers are removed before alignment.
- Output: `WordAlignment` of `AlignedWordPair`s (spec 01): `present(phrase:you:)`, `substituted(phrase:heard:you:)`,
  `missing(phrase:)`, `inserted(heard:you:afterPhrase:)`, in your-time order with phrase order preserved.
- Summary for the decision procedure: match %, non-filler insertion count, missing or substituted targets,
  missing or substituted non-targets, insertion words. Match % < 80% or more than 2 non-filler insertions →
  `wordsDontMatch` (decided in spec 01's procedure; this spec supplies the numbers).

## Defaults

- Numbers: cardinals 0–9999, years read as pairs ("1990" ↔ "nineteen ninety"), ordinals 1st–31st. Anything else is
  compared literally.
- Lists (`contractions.txt`, `us-uk.txt`, `compounds.txt`, `function-words.txt`) are plain text in `AMAlignment`
  resources, one entry per line, with a header comment naming the source. Compounds start with the compounds in
  CPO's phrase set.

## Guardrails

- On device only; the dictionary is bundled, never fetched at runtime. `NaturalLanguage` is allowed; no network.
- No AppKit or UIKit. Swift 6 strict concurrency.
- Dictionary licence in `THIRD_PARTY_NOTICES.md` (a risky path, so the implementation PR waits for Raph).

## Out of scope

- Syllable timing and confidence (spec 07). Prominence and A(w) (spec 08). Bundled phrase JSON (spec 15). The import
  flow and `phrase.json` storage (specs 16–17): this spec only defines the persisted value type.

## Open question (built with the default)

1. **POS mapping for stress-shift pairs.** The plan says the mapping is "hand-curated" and doesn't say by whom.
   Default: the agent drafts it from the usual English pattern (two-syllable noun/adjective → first-syllable
   stress, verb → second) and only for words the generator lists; every row is reviewable in the PR, and words where
   the pattern doesn't hold (for example "desert" as a place noun) stay `expectedAmbiguous`. CPO can review the list;
   it doesn't block the build.
2. **Which CMUdict.** Default: the current `cmusphinx/cmudict` repository at a pinned commit, which continues
   0.7b. If CPO's overrides were taken from a different snapshot, the overrides still win (rule 1), so it only
   affects imports.

## How to test (Raph)

1. `make check` is green.
2. `swift test --package-path Packages/AccentKit --filter AMAlignmentTests` passes:
   - "photography" → pho·TOG·ra·phy; "record" noun vs verb choose different variants via the tagger fixture; an
     override beats the tagger; a persisted import pronunciation is used without calling the tagger;
   - a two-token import with "record" is `expectedAmbiguous`;
   - the equivalence table passes both ways (fillers, repeats, contractions, numbers, compounds, US/UK);
   - alignment tables cover insertions, omissions, substitutions, a missing target, the 80% rule, more than 2
     insertions, and a phrase with 0 content words;
   - the starter-phrase validator rejects a target with variants and no override.
3. `python3 tools/gen_stress_shift_pairs.py --check` regenerates `stress-shift-pairs.json` and prints no diff.

## Implementation notes

_(filled in by the agent)_
