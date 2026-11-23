#!/usr/bin/env python3
"""Picks and builds the fixed smoke set (spec 02, plan §6.3a). Pure Python 3, standard library only.

Content: 20 stress-wrong speechocean762 words (polysyllabic, intelligible, >= 4 of 5 raters agree) and 100 unanimous
stress-correct words (polysyllabic, intelligible), all from train (tuning) speakers only; and 2 VCTK phrases x 3 VCTK
tuning speakers. Utterances are chosen to cover several words each, by a seeded greedy pass:
  1. Shuffle the train utterances with the seed.
  2. Take utterances with stress-wrong candidates, most candidates per second of audio first (shuffle order breaks
     ties), labelling candidates until 20 stress-wrong words are labelled; their correct candidates are labelled too.
  3. Take utterances with the most still-unlabelled correct candidates per second of audio until 100 correct words
     are labelled. (Per second, so the set stays under the 5 MB cap.)
  4. VCTK: 3 tuning speakers by seeded shuffle of those that share at least 2 kept (trimmed) phrases, and the first 2
     shared phrases after a seeded shuffle.
Then it calls `scripts/am-eval.sh smoke-build`, which writes 16 kHz FLAC and fixtures/smoke/manifest.json.

Needs scripts/fetch-speechocean762.sh and scripts/fetch-vctk.sh to have run (reads eval-cache/ only).

  python3 tools/pick_smoke_set.py
"""

import json
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = 20261127
WRONG, CORRECT = 20, 100


def labels():
    speakers, words = {}, []
    with open(os.path.join(ROOT, "fixtures/speechocean762/labels.tsv")) as f:
        for line in f:
            fields = line.rstrip("\n").split("\t")
            if fields[0] == "S":
                speakers[fields[1]] = fields[2]
            elif fields[0] == "W":
                utt, index, speaker, text, ref, wrong, zero = fields[1:]
                syllables = sum(1 for p in ref.split() if p[-1] in "012")
                words.append({"utterance": utt, "index": int(index), "speaker": speaker, "text": text,
                              "syllables": syllables, "wrong": int(wrong), "zero": int(zero)})
    return speakers, words


def main():
    cache = os.environ.get("AM_EVAL_CACHE", os.path.join(ROOT, "eval-cache"))
    corpus = os.path.join(cache, "speechocean762/current")
    vctk = os.path.join(cache, "vctk/current")
    for path in (corpus, vctk):
        if not os.path.exists(path):
            sys.exit("pick_smoke_set: %s missing: run the corpus fetchers first" % path)
    rng = random.Random(SEED)

    speakers, words = labels()
    usable = [w for w in words if speakers[w["speaker"]] == "train" and w["syllables"] >= 2 and w["zero"] < 3]
    wrong = {(w["utterance"], w["index"]): w for w in usable if w["wrong"] >= 4}
    correct = {(w["utterance"], w["index"]): w for w in usable if w["wrong"] == 0}
    utterances = sorted({w["utterance"] for w in usable})
    rng.shuffle(utterances)
    rank = {u: i for i, u in enumerate(utterances)}

    def members(pool, u):
        return [w for (utt, _), w in sorted(pool.items()) if utt == u]

    wav = {}
    with open(os.path.join(corpus, "train/wav.scp")) as f:
        for line in f:
            utt, path = line.split()
            wav[utt] = path
    size = {u: os.path.getsize(os.path.join(corpus, wav[u])) for u in utterances}

    chosen, labelled = [], {}
    def take(u):
        chosen.append(u)
        for w in members(wrong, u):
            if sum(1 for l in labelled.values() if l == "stressWrong") < WRONG:
                labelled[(u, w["index"])] = "stressWrong"
        for w in members(correct, u):
            if sum(1 for l in labelled.values() if l == "stressCorrect") < CORRECT:
                labelled[(u, w["index"])] = "stressCorrect"

    for u in sorted({u for u, _ in wrong}, key=lambda u: (-len(members(wrong, u)) / size[u], rank[u])):
        if sum(1 for l in labelled.values() if l == "stressWrong") >= WRONG:
            break
        take(u)
    while sum(1 for l in labelled.values() if l == "stressCorrect") < CORRECT:
        remaining = [u for u in utterances if u not in chosen and members(correct, u)]
        u = min(remaining, key=lambda u: (-len([w for w in members(correct, u) if (u, w["index"]) not in labelled])
                                          / size[u], rank[u]))
        take(u)

    selection = {"seed": SEED, "speechocean762": [], "vctk": []}
    for u in sorted(chosen):
        ws = [{"id": "%s#%d" % (u, i), "text": next(w["text"] for w in usable if (w["utterance"], w["index"]) == (u, i)),
               "label": label} for (utt, i), label in sorted(labelled.items()) if utt == u]
        speaker = next(w["speaker"] for w in usable if w["utterance"] == u)
        selection["speechocean762"].append({"utterance": u, "speaker": speaker, "wav": wav[u], "words": ws})

    manifest = json.load(open(os.path.join(ROOT, "fixtures/vctk/eval-speakers.json")))
    kept = set(json.load(open(os.path.join(vctk, "trim-report.json")))["kept"])
    tuning = sorted(e["speaker"] for e in manifest["speakers"] if e["split"] == "tuning")
    rng.shuffle(tuning)
    phrases = list(manifest["phrases"])
    rng.shuffle(phrases)
    trio = None
    for a in range(len(tuning)):
        for b in range(a + 1, len(tuning)):
            for c in range(b + 1, len(tuning)):
                group = [tuning[a], tuning[b], tuning[c]]
                shared = [p for p in phrases if all("%s_%s" % (s, p) in kept for s in group)]
                if len(shared) >= 2 and trio is None:
                    trio = (group, shared[:2])
    if trio is None:
        sys.exit("pick_smoke_set: no 3 tuning speakers share 2 kept phrases")
    selection["vctk"] = [{"speaker": s, "phrase": p} for s in sorted(trio[0]) for p in sorted(trio[1])]

    n_wrong = sum(1 for l in labelled.values() if l == "stressWrong")
    n_correct = sum(1 for l in labelled.values() if l == "stressCorrect")
    print("pick_smoke_set: %d utterances (%d stress-wrong, %d stress-correct words); VCTK %s x %s"
          % (len(chosen), n_wrong, n_correct, sorted(trio[0]), sorted(trio[1])))
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, "smoke-selection.json")
    with open(path, "w") as f:
        json.dump(selection, f, indent=2, sort_keys=True)
    out = os.path.join(ROOT, "fixtures/smoke")
    subprocess.run([os.path.join(ROOT, "scripts/am-eval.sh"), "smoke-build", "--selection", path, "--so762", corpus,
                    "--vctk", vctk, "--out", out], check=True)


if __name__ == "__main__":
    main()
