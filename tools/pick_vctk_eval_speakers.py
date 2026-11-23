#!/usr/bin/env python3
"""Picks the 30 VCTK eval speakers and splits them 18 tuning / 12 held-out (spec 02, plan §6.1).

Pure Python 3, standard library only. Reads the VCTK 0.92 archive fetched by scripts/fetch-vctk-eval.sh (no network) and
writes fixtures/vctk/eval-speakers.json: speaker, accent, gender, split and the SHA-256 of each of CPO's 20 phrase
files, plus the same hashes for the 8 bundled voices.

Rule:
  1. Candidates: mic1, every shared-text file 001-024 present, not p280 or p315, not one of the bundled 8.
  2. Group candidates by the speaker-info ACCENTS column. Shuffle each group (sorted first) and the group order with
     a fixed seed.
  3. Stratified round-robin: visit the groups in order, taking one speaker from each non-empty group per round, and
     within a group the next speaker of the gender picked less so far (F on a tie), until 30 are picked.
  4. Split by speaker in pick order: of every 5, positions 1, 3 and 5 are tuning and 2 and 4 held-out (18 / 12), so
     both splits get the round-robin's accent and gender spread.

  python3 tools/pick_vctk_eval_speakers.py [--archive eval-cache/downloads/VCTK-Corpus-0.92.zip] [--out ...]
"""

import argparse
import hashlib
import json
import os
import random
import sys
import zipfile

PHRASES = ["002", "003", "004", "005", "006", "007", "008", "009", "010", "011",
           "012", "013", "014", "015", "016", "017", "018", "019", "020", "024"]
SHARED = ["%03d" % i for i in range(1, 25)]
BUNDLED = ["p225", "p226", "p227", "p233", "p241", "p252", "p311", "p345"]
EXCLUDED = ["p280", "p315"]
SEED = 20261123
PICK, TUNING_PATTERN = 30, (True, False, True, False, True)

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


def file_hashes(archive, speaker, names):
    return {t: hashlib.sha256(archive.read(flac(speaker, t))).hexdigest()
            for t in PHRASES if flac(speaker, t) in names}


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

        def entry(speaker, split=None):
            e = {"speaker": speaker, "accent": info[speaker]["accent"], "region": info[speaker]["region"],
                 "gender": info[speaker]["gender"], "files": file_hashes(archive, speaker, names)}
            if split:
                e["split"] = split
            return e

        speakers = [entry(s, "tuning" if TUNING_PATTERN[i % 5] else "heldOut") for i, s in enumerate(picked)]
        manifest = {
            "corpus": "VCTK 0.92 (VCTK-Corpus-0.92.zip), mic1",
            "licence": "CC BY 4.0",
            "seed": args.seed,
            "rule": "tools/pick_vctk_eval_speakers.py: stratified round-robin over speaker-info accent groups, "
                    "gender-balanced, then 3 of every 5 in pick order tuning",
            "excluded": EXCLUDED,
            "candidates": len(candidates),
            "phrases": PHRASES,
            "bundled": [entry(s) for s in BUNDLED],
            "speakers": speakers,
        }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    tuning = sum(1 for s in speakers if s["split"] == "tuning")
    print("pick_vctk_eval_speakers: %d candidates; picked %d (%d tuning, %d held-out) -> %s"
          % (len(candidates), len(speakers), tuning, len(speakers) - tuning, os.path.relpath(args.out, ROOT)))


if __name__ == "__main__":
    main()
