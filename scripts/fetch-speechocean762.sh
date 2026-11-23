#!/usr/bin/env bash
# Fetches speechocean762 (CC BY 4.0) into the git-ignored eval-cache/ (spec 02, plan §6.3). An explicit tool step:
# never run by the app or by PR CI.
#
# Audio comes from the OpenSLR 101 tarball. scores.json and scores-detail.json come from the speechocean762 repo at
# the pinned commit: the plan's scores.json digest (31c847b8…a1159f8) is that commit's file, not the tarball's.
# Pins live in fixtures/corpora/speechocean762.pin.json. The plan gives no full archive digest, so the first fetch
# records each missing SHA-256 there (Open question 1) and every later fetch fails on a mismatch. Any failure prints
# "speechocean762: NOT EVALUATED (<reason>)" and exits 1.
#
#   scripts/fetch-speechocean762.sh                       # fetch, verify, extract
#   AM_EVAL_CACHE=/elsewhere scripts/fetch-speechocean762.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pin="$root/fixtures/corpora/speechocean762.pin.json"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"

fail() { echo "speechocean762: NOT EVALUATED ($1)" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
pinned() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$pin" "$1"; }
record() { # key, value
  python3 -I - "$pin" "$1" "$2" <<'PY'
import json, sys
path, key, value = sys.argv[1:]
with open(path) as f:
    data = json.load(f)
data[key] = value
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}
# Verifies $2 against pin $1, recording it on the first fetch.
check_pin() { # key, value, what
  local want; want="$(pinned "$1")"
  if [[ -z "$want" ]]; then
    record "$1" "$2"
    echo "speechocean762: first fetch, recorded $3 SHA-256 $2 in ${pin#"$root"/}"
  elif [[ "$2" != "$want" ]]; then
    fail "$3 SHA-256 $2 does not match the pin ${want}"
  fi
}

url="$(pinned source)"
repo_raw="https://raw.githubusercontent.com/jimbozhang/speechocean762/$(pinned repoCommit)/resource"

mkdir -p "$cache/downloads"
archive="$cache/downloads/speechocean762.tar.gz"
if [[ ! -f "$archive.done" ]]; then
  echo "speechocean762: downloading $url (about 500 MB)"
  curl -fL --retry 3 -C - -o "$archive" "$url" || fail "download failed"
  touch "$archive.done"
fi
archive_sha="$(sha "$archive")"
check_pin archiveSHA256 "$archive_sha" "archive"

dest="$cache/speechocean762/${archive_sha:0:16}"
if [[ ! -f "$dest/.extracted" ]]; then
  rm -rf "$dest.tmp" && mkdir -p "$dest.tmp"
  tar -xzf "$archive" -C "$dest.tmp" || fail "extraction failed"
  rm -rf "$dest" && mv "$dest.tmp" "$dest"
  touch "$dest/.extracted"
fi
corpus="$dest/speechocean762"
[[ -d "$corpus/WAVE" && -f "$corpus/train/utt2spk" ]] || fail "unexpected archive layout"

# Labels from the pinned repo commit, replacing the tarball's resource files.
labels="$dest/repo-resource"
mkdir -p "$labels"
for f in scores.json scores-detail.json; do
  if [[ ! -s "$labels/$f" ]]; then
    curl -fsSL --retry 3 -o "$labels/$f.tmp" "$repo_raw/$f" || fail "download of $f at the pinned commit failed"
    mv "$labels/$f.tmp" "$labels/$f"
  fi
done
scores_sha="$(sha "$labels/scores.json")"
prefix="$(pinned scoresJSONPrefix)"; suffix="$(pinned scoresJSONSuffix)"
[[ "$scores_sha" == "$prefix"* && "$scores_sha" == *"$suffix" ]] \
  || fail "scores.json SHA-256 $scores_sha is not ${prefix}…${suffix}"
check_pin scoresJSONSHA256 "$scores_sha" "scores.json"
check_pin scoresDetailJSONSHA256 "$(sha "$labels/scores-detail.json")" "scores-detail.json"
cp "$labels/scores.json" "$labels/scores-detail.json" "$corpus/resource/"

# Corpus manifest hash: SHA-256 of the sorted SHA-256s of every WAV (what reports carry).
if [[ ! -f "$dest/.corpus-manifest" ]]; then
  (cd "$corpus" && find WAVE -type f -name '*.WAV' -print0 | xargs -0 shasum -a 256) > "$dest/corpus-files.sha256"
  cut -d ' ' -f 1 "$dest/corpus-files.sha256" | LC_ALL=C sort | shasum -a 256 | cut -d ' ' -f 1 > "$dest/.corpus-manifest"
fi
check_pin corpusManifestSHA256 "$(cat "$dest/.corpus-manifest")" "corpus manifest"

ln -sfn "$corpus" "$cache/speechocean762/current"
echo "speechocean762: OK at $cache/speechocean762/current ($(wc -l < "$dest/corpus-files.sha256" | tr -d ' ') WAVs; archive ${archive_sha:0:12}…, scores.json ${scores_sha:0:12}…)"
