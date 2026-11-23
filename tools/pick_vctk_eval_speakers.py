#!/usr/bin/env python3
"""Picks the 40 VCTK eval speakers and splits them 24 tuning / 16 held-out (spec 02, plan §6.1, CTO ruling).

Pure Python 3, standard library only. Reads the VCTK 0.92 archive fetched by scripts/fetch-vctk-eval.sh (no network) and
writes fixtures/vctk/eval-speakers.json: speaker, accent, gender, split and the SHA-256 of each phrase file, plus the
same hashes for the 8 bundled voices.

Phrases: CPO's 20, plus the shared-text prompts they left out (001, 021, 022, 023; CTO ruling on the positive-set
shortfall). An added prompt's file is listed for a speaker only if its transcript (txt/, lower-cased, apostrophes and
hyphens dropped, letters and spaces only) is the prompt's text in PHRASE_TEXT, so every listed clip of a phrase reads
the same words. Speakers without a matching transcript are left out of that phrase and printed. CPO's 20 are listed
as before.

Rule:
  1. Candidates: mic1, every shared-text file 001-024 present, not p280 or p315, not one of the bundled 8.
  2. Group candidates by the speaker-info ACCENTS column. Shuffle each group (sorted first) and the group order with
     a fixed seed.
  3. Stratified round-robin: visit the groups in order, taking one speaker from each non-empty group per round, and
     within a group the next speaker of the gender picked less so far (F on a tie), until 40 are picked.
  4. Split by speaker in pick order: of every 5, positions 1, 3 and 5 are tuning and 2 and 4 held-out (24 / 16), so
     both splits get the round-robin's accent and gender spread.

The pick is prefix-stable: picking 40 makes the same first 30 picks, in the same order, as the original 30, so no
speaker already in the manifest changes split (AMEvaluationTests checks the first 30 against the original list).
40 is the smallest count above 30 that adds whole blocks of 5 and keeps the 6 VCTK CV folds equal (24 tuning = 6 x 4).

  python3 tools/pick_vctk_eval_speakers.py [--archive eval-cache/downloads/VCTK-Corpus-0.92.zip] [--out ...]
"""

import argparse
import hashlib
import json
import os
import random
import re
import sys
import zipfile

CPO_PHRASES = ["002", "003", "004", "005", "006", "007", "008", "009", "010", "011",
               "012", "013", "014", "015", "016", "017", "018", "019", "020", "024"]
# The shared-text prompts CPO's 20 left out, with the text every listed clip must read (normalised).
PHRASE_TEXT = {
    "001": "please call stella",
    "021": "the difference in the rainbow depends considerably upon the size of the drops and the width of the "
           "colored band increases as the size of the drops increases",
    "022": "the actual primary rainbow observed is said to be the effect of superimposition of a number of bows",
    "023": "if the red of the second bow falls upon the green of the first the result is to give a bow with an "
           "abnormally wide yellow band since red and green light when mixed form yellow",
}
PHRASES = sorted(CPO_PHRASES + list(PHRASE_TEXT))
SHARED = ["%03d" % i for i in range(1, 25)]
BUNDLED = ["p225", "p226", "p227", "p233", "p241", "p252", "p311", "p345"]
EXCLUDED = ["p280", "p315"]
SEED = 20261123
PICK, TUNING_PATTERN = 40, (True, False, True, False, True)
# Floors, not exact counts (spec 02, CTO ruling 2026-11-23 14:18): >= 18 tuning, >= 12 held-out. The actual counts
# are written to the manifest as tuningCount / heldOutCount.
MIN_TUNING, MIN_HELD_OUT = 18, 12

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def flac(speaker, text_id):
    return "wav48_silence_trimmed/%s/%s_%s_mic1.flac" % (speaker, speaker, text_id)


def speaker_info(archive):
    info = {}
    lines = archive.read("speaker-info.txt").decode("utf-8").splitlines()
    for line in lines[1:]:
        fields = line.split()
        if len(fields) >= 4:
            info[fields[0]] = {"gender": fields[2], "accent": fields[3], "region": " ".join(fields[4:])}
    return info


def pick(info, names, seed):
    candidates = [s for s in sorted(info)
                  if s not in BUNDLED and s not in EXCLUDED and all(flac(s, t) in names for t in SHARED)]
    rng = random.Random(seed)
    groups = {}
    for speaker in candidates:
        groups.setdefault(info[speaker]["accent"], []).append(speaker)
    order = sorted(groups)
    for accent in order:
        rng.shuffle(groups[accent])
    rng.shuffle(order)
    picked, genders = [], {"F": 0, "M": 0}
    while len(picked) < PICK and any(groups[a] for a in order):
        for accent in order:
            if not groups[accent] or len(picked) == PICK:
                continue
            want = "F" if genders["F"] <= genders["M"] else "M"
            members = groups[accent]
            choice = next((s for s in members if info[s]["gender"] == want), members[0])
            members.remove(choice)
            picked.append(choice)
            genders[info[choice]["gender"]] = genders.get(info[choice]["gender"], 0) + 1
    if len(picked) < PICK:
        sys.exit("pick_vctk_eval_speakers: only %d candidates" % len(picked))
    return candidates, picked


def normalised(text):
    return " ".join(re.sub(r"[^a-z ]", " ", text.lower().replace("'", "").replace("-", "")).split())


def text_matches(archive, names, speaker, text_id):
    if text_id not in PHRASE_TEXT:
        return True
    path = "txt/%s/%s_%s.txt" % (speaker, speaker, text_id)
    return path in names and normalised(archive.read(path).decode("utf-8", "replace")) == PHRASE_TEXT[text_id]


def file_hashes(archive, speaker, names, dropped):
    out = {}
    for t in PHRASES:
        if flac(speaker, t) not in names:
            continue
        if not text_matches(archive, names, speaker, t):
            dropped.append("%s_%s" % (speaker, t))
            continue
        out[t] = hashlib.sha256(archive.read(flac(speaker, t))).hexdigest()
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--archive", default=os.path.join(ROOT, "eval-cache/downloads/VCTK-Corpus-0.92.zip"))
    parser.add_argument("--out", default=os.path.join(ROOT, "fixtures/vctk/eval-speakers.json"))
    parser.add_argument("--seed", type=int, default=SEED)
    args = parser.parse_args()
    if not os.path.exists(args.archive):
        sys.exit("pick_vctk_eval_speakers: %s missing: run scripts/fetch-vctk-eval.sh first" % args.archive)

    with zipfile.ZipFile(args.archive) as archive:
        names = set(archive.namelist())
        info = speaker_info(archive)
        candidates, picked = pick(info, names, args.seed)
        dropped = []

        def entry(speaker, split=None):
            e = {"speaker": speaker, "accent": info[speaker]["accent"], "region": info[speaker]["region"],
                 "gender": info[speaker]["gender"], "files": file_hashes(archive, speaker, names, dropped)}
            if split:
                e["split"] = split
            return e

        speakers = [entry(s, "tuning" if TUNING_PATTERN[i % 5] else "heldOut") for i, s in enumerate(picked)]
        tuning_count = sum(1 for s in speakers if s["split"] == "tuning")
        held_out_count = len(speakers) - tuning_count
        if tuning_count < MIN_TUNING or held_out_count < MIN_HELD_OUT:
            sys.exit("pick_vctk_eval_speakers: %d tuning / %d held-out is below the floors (>= %d / >= %d)"
                     % (tuning_count, held_out_count, MIN_TUNING, MIN_HELD_OUT))
        manifest = {
            "corpus": "VCTK 0.92 (VCTK-Corpus-0.92.zip), mic1",
            "licence": "CC BY 4.0",
            "seed": args.seed,
            "rule": "tools/pick_vctk_eval_speakers.py: stratified round-robin over speaker-info accent groups, "
                    "gender-balanced, then 3 of every 5 in pick order tuning; added prompts listed only where the "
                    "transcript matches phraseText",
            "excluded": EXCLUDED,
            "candidates": len(candidates),
            "phrases": PHRASES,
            "phraseText": PHRASE_TEXT,
            "bundled": [entry(s) for s in BUNDLED],
            "speakers": speakers,
            "tuningCount": tuning_count,
            "heldOutCount": held_out_count,
        }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    for clip in dropped:
        print("pick_vctk_eval_speakers: left out %s (transcript is not the shared text)" % clip)
    print("pick_vctk_eval_speakers: %d candidates; picked %d (%d tuning, %d held-out) -> %s"
          % (len(candidates), len(speakers), tuning_count, held_out_count, os.path.relpath(args.out, ROOT)))


if __name__ == "__main__":
    main()
