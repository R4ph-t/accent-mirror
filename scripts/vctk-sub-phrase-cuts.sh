#!/usr/bin/env bash
# Builds fixtures/vctk/sub-phrase-cuts.json (spec 24): where every listed clip of a split VCTK prompt (021, 023) is cut
# into the sub-phrases of fixtures/vctk/sub-phrases.json. Offline tooling only: never in the app or CI (CI and
# scripts/fetch-vctk-eval.sh replay the committed cut list).
#
# 1. Extracts the clips fixtures/vctk/eval-speakers.json lists for the split prompts, and their transcripts, from the
#    pinned VCTK 0.92 archive (scripts/fetch-vctk-eval.sh first) into the git-ignored eval-cache/vctk-sub/.
# 2. Aligns them with the same MFA 3.4.4 / english_mfa v3.1.0 setup as spec 03, through scripts/mfa-align.sh
#    (scripts/setup-mfa.sh first).
# 3. Cuts each clip at the MFA span of a sub-phrase's words, extended outward into the neighbouring silence by up to
#    the trim's 200 ms pre-roll and 300 ms tail, each stopping at the midpoint of the gap to the neighbouring word (the
#    clip edge if there's none); a clip whose MFA words don't contain the sub-phrase exactly once is rejected and
#    counted, never cut by guesswork.
#
#   scripts/vctk-sub-phrase-cuts.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"
archive="$cache/downloads/$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["archiveName"])' "$root/fixtures/corpora/vctk.pin.json")"
[[ -f "$archive.done" ]] || { echo "vctk-sub-phrase-cuts: no verified VCTK archive: run scripts/fetch-vctk-eval.sh" >&2; exit 1; }

work="$cache/vctk-sub"
corpus="$work/VCTK-Corpus-0.92"
rm -rf "$corpus"
python3 -I - "$archive" "$root/fixtures/vctk/eval-speakers.json" "$root/fixtures/vctk/sub-phrases.json" "$corpus" \
  "$work/clips.txt" <<'PY'
import hashlib, json, os, sys, zipfile
archive, manifest, table, corpus, clips = sys.argv[1:]
m = json.load(open(manifest))
prompts = sorted({s["prompt"] for s in json.load(open(table))["subPhrases"]})
listed = []
with zipfile.ZipFile(archive) as z:
    for e in m["bundled"] + m["speakers"]:
        s = e["speaker"]
        for t in prompts:
            if t not in e["files"]:
                continue
            audio = z.read("wav48_silence_trimmed/%s/%s_%s_mic1.flac" % (s, s, t))
            if hashlib.sha256(audio).hexdigest() != e["files"][t]:
                sys.exit("vctk-sub-phrase-cuts: %s_%s: SHA-256 does not match eval-speakers.json" % (s, t))
            for sub, name, data in (("wav48_silence_trimmed", "%s_%s_mic1.flac" % (s, t), audio),
                                    ("txt", "%s_%s.txt" % (s, t), z.read("txt/%s/%s_%s.txt" % (s, s, t)))):
                os.makedirs(os.path.join(corpus, sub, s), exist_ok=True)
                with open(os.path.join(corpus, sub, s, name), "wb") as f:
                    f.write(data)
            listed.append("%s_%s" % (s, t))
with open(clips, "w") as f:
    f.write("".join(c + "\n" for c in sorted(listed)))
print("vctk-sub-phrase-cuts: %d clips of prompts %s" % (len(listed), ", ".join(prompts)))
PY

VCTK_CACHE="$work" BASELINE_OUT="$work/mfa-alignments.json" "$root/scripts/mfa-align.sh" "$work/clips.txt"
"$root/scripts/am-eval.sh" vctk-sub-phrase-cuts --alignments "$work/mfa-alignments.json" --transcripts "$corpus/txt"
