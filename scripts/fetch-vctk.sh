#!/usr/bin/env bash
# Fetches VCTK 0.92 (CC BY 4.0, about 11 GB) into the git-ignored eval-cache/ (spec 02, plan §6.1, §6.2). An explicit
# tool step: never run by the app or by PR CI.
#
# 1. Downloads the archive (resumable) and verifies it: the size and the official MD5 DataShare publishes, then the
#    SHA-256 pinned in fixtures/corpora/vctk.pin.json (recorded by the first fetch, Open question 1).
# 2. If fixtures/vctk/eval-speakers.json exists, extracts only CPO's 20 phrases (mic1) for the 8 bundled voices and
#    the 30 eval speakers, checks each file against the manifest's SHA-256, and trims them (2–6 s, the same rule for
#    every speaker; spec 02 Open question 2) to 16 kHz FLAC, cached under eval-cache/vctk/trimmed/<manifest hash>/.
#    Without the manifest it stops after step 1: run tools/pick_vctk_eval_speakers.py, then this again.
#
#   scripts/fetch-vctk.sh
#   AM_EVAL_CACHE=/elsewhere scripts/fetch-vctk.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pin="$root/fixtures/corpora/vctk.pin.json"
manifest="$root/fixtures/vctk/eval-speakers.json"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"

fail() { echo "vctk: NOT EVALUATED ($1)" >&2; exit 1; }
pinned() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$pin" "$1"; }

mkdir -p "$cache/downloads"
archive="$cache/downloads/$(pinned archiveName)"
if [[ ! -f "$archive.done" ]]; then
  # DataShare ignores range requests, so no resume: download to .part unless a complete archive is already there.
  if [[ ! -f "$archive" || "$(stat -f %z "$archive")" != "$(pinned archiveBytes)" ]]; then
    echo "vctk: downloading $(pinned archiveName) (about 11 GB) from DataShare"
    curl -fL --retry 5 -o "$archive.part" "$(pinned source)" || fail "download failed"
    mv "$archive.part" "$archive"
  fi
  size="$(stat -f %z "$archive")"
  [[ "$size" == "$(pinned archiveBytes)" ]] || fail "archive is $size bytes, expected $(pinned archiveBytes)"
  md5="$(md5 -q "$archive")"
  [[ "$md5" == "$(pinned archiveMD5Official)" ]] || fail "archive MD5 $md5 is not the official $(pinned archiveMD5Official)"
  touch "$archive.done"
fi

if [[ ! -f "$archive.sha256" ]]; then shasum -a 256 "$archive" | cut -d ' ' -f 1 > "$archive.sha256"; fi
got="$(cat "$archive.sha256")"
want="$(pinned archiveSHA256)"
if [[ -z "$want" ]]; then
  python3 -I - "$pin" "$got" <<'PY'
import json, sys
path, value = sys.argv[1:]
with open(path) as f:
    data = json.load(f)
data["archiveSHA256"] = value
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  echo "vctk: first fetch, recorded archive SHA-256 $got in ${pin#"$root"/}"
elif [[ "$got" != "$want" ]]; then
  fail "archive SHA-256 $got does not match the pin $want"
fi
echo "vctk: archive OK (${got:0:12}…)"

if [[ ! -f "$manifest" ]]; then
  echo "vctk: ${manifest#"$root"/} missing: run python3 tools/pick_vctk_eval_speakers.py, then scripts/fetch-vctk.sh again"
  exit 0
fi

key="$(shasum -a 256 "$manifest" | cut -d ' ' -f 1)"
raw="$cache/vctk/raw"
trimmed="$cache/vctk/trimmed/${key:0:16}"
if [[ ! -f "$trimmed/.done" ]]; then
  python3 -I - "$archive" "$manifest" "$raw" <<'PY'
import json, os, sys, zipfile
archive, manifest, raw = sys.argv[1:]
m = json.load(open(manifest))
with zipfile.ZipFile(archive) as z:
    for e in m["bundled"] + m["speakers"]:
        s = e["speaker"]
        os.makedirs(os.path.join(raw, s), exist_ok=True)
        for t in e["files"]:
            name = "%s_%s_mic1.flac" % (s, t)
            with open(os.path.join(raw, s, name), "wb") as f:
                f.write(z.read("wav48_silence_trimmed/%s/%s" % (s, name)))
PY
  rm -rf "$trimmed"
  "$root/scripts/am-eval.sh" vctk-trim --eval-speakers "$manifest" --raw "$raw" --out "$trimmed"
  touch "$trimmed/.done"
fi
ln -sfn "$trimmed" "$cache/vctk/current"
echo "vctk: OK, trimmed clips at $cache/vctk/current ($(du -sh "$trimmed" | cut -f 1))"
