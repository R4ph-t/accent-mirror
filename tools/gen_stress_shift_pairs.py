#!/usr/bin/env python3
"""Generate AMAlignment's stress-shift-pairs.json from the bundled CMUdict (spec 06).

Lists every CMUdict word whose multi-syllable variants differ in primary stress, with each variant's ARPAbet and
0-based primary syllable, joined with the hand-curated POS mapping in tools/stress-shift-pos.tsv (noun, verb,
adjective -> index of the first variant with that primary; null when the word stays expectedAmbiguous).

Pure Python 3, no dependencies, no network. Usage:
  python3 tools/gen_stress_shift_pairs.py          # rewrite the JSON
  python3 tools/gen_stress_shift_pairs.py --check  # regenerate in memory; print a diff and exit 1 if it differs
"""
import difflib
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Packages", "AccentKit", "Sources", "AMAlignment", "Resources")
DICT = os.path.join(RESOURCES, "CMUdict", "cmudict.dict")
MANIFEST = os.path.join(RESOURCES, "CMUdict", "manifest.json")
POS_TABLE = os.path.join(ROOT, "tools", "stress-shift-pos.tsv")
OUTPUT = os.path.join(RESOURCES, "stress-shift-pairs.json")
POS_COLUMNS = ("noun", "verb", "adjective")


def read_dictionary(path):
    words = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            word, *phones = line.split()
            word = re.sub(r"\(\d+\)$", "", word)
            words.setdefault(word, []).append(phones)
    return words


def primary_index(phones):
    """0-based syllable of the first primary stress, or None (fewer than 2 syllables, or no primary)."""
    stresses = [p[-1] for p in phones if p[-1].isdigit()]
    if len(stresses) < 2 or "1" not in stresses:
        return None
    return stresses.index("1")


def read_pos_table(path):
    rows = {}
    with open(path, encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            if line.startswith("#") or not line.strip():
                continue
            cells = line.rstrip("\n").split("\t")
            if len(cells) < 4:
                sys.exit(f"{path}:{number}: expected word, noun, verb, adjective")
            word = cells[0]
            if word in rows:
                sys.exit(f"{path}:{number}: duplicate row for {word!r}")
            values = {}
            for column, cell in zip(POS_COLUMNS, cells[1:4]):
                if cell == "-":
                    values[column] = None
                elif cell.isdigit() and int(cell) >= 1:
                    values[column] = int(cell) - 1
                else:
                    sys.exit(f"{path}:{number}: {column} must be a 1-based syllable or '-', got {cell!r}")
            rows[word] = values
    return rows


def generate():
    words = read_dictionary(DICT)
    pos = read_pos_table(POS_TABLE)
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    with open(DICT, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()

    pairs = {}
    for word in sorted(words):
        variants = [{"arpabet": " ".join(p), "primary": primary_index(p)} for p in words[word]]
        primaries = {v["primary"] for v in variants if v["primary"] is not None}
        if len(primaries) < 2:
            continue
        entry = {"variants": variants}
        mapping = pos.get(word, dict.fromkeys(POS_COLUMNS))
        for column in POS_COLUMNS:
            wanted = mapping[column]
            if wanted is None:
                entry[column] = None
                continue
            match = next((i for i, v in enumerate(variants) if v["primary"] == wanted), None)
            if match is None:
                sys.exit(f"{POS_TABLE}: {word} {column} wants syllable {wanted + 1}, which no variant stresses")
            entry[column] = match
        pairs[word] = entry

    unknown = sorted(set(pos) - set(pairs))
    if unknown:
        sys.exit(f"{POS_TABLE}: not stress-shift words in CMUdict: {', '.join(unknown)}")

    document = {
        "generatedBy": "tools/gen_stress_shift_pairs.py",
        "source": {"commit": manifest["commit"], "sha256": digest},
        "posTable": "tools/stress-shift-pos.tsv",
        "words": pairs,
    }
    return json.dumps(document, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


def main(argv):
    text = generate()
    if "--check" in argv:
        current = open(OUTPUT, encoding="utf-8").read() if os.path.exists(OUTPUT) else ""
        if current == text:
            print("stress-shift-pairs.json is up to date.")
            return 0
        sys.stdout.writelines(difflib.unified_diff(
            current.splitlines(True), text.splitlines(True), "stress-shift-pairs.json (committed)",
            "stress-shift-pairs.json (regenerated)"))
        return 1
    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"wrote {os.path.relpath(OUTPUT, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
