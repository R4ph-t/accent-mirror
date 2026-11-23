#!/usr/bin/env bash
# Fetches the spec 03 evaluation clips (fixtures/vctk/starter-clips.txt) from the official VCTK 0.92 archive into the
# git-ignored cache. Local tooling only: never run by the app, CI or `make check`.
#
# The archive (~11 GB) is streamed once: every byte goes through SHA-256 while bsdtar extracts only the 159 mic1 clips
# and their transcripts, so the full archive never lands on disk.
#
# Pins (spec 03, Open question 2): the first fetch records the archive digest in
# fixtures/vctk/vctk-0.92-archive.sha256 and the extracted files' digests in fixtures/vctk/vctk-0.92-clips.sha256.
# Every later fetch must match both, or it fails and keeps nothing. Clips the archive does not contain are listed
# and left out of the pins; the evaluation reports them as absent.
#
# VCTK 0.92 is CC BY 4.0 (Yamagishi, Veaux, MacDonald, University of Edinburgh CSTR). Audio is never committed.
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
url="${VCTK_URL:-https://datashare.ed.ac.uk/bitstream/handle/10283/3443/VCTK-Corpus-0.92.zip}"
cache="${VCTK_CACHE:-$root/.cache/vctk}"
dest="$cache/VCTK-Corpus-0.92"
clips="$root/fixtures/vctk/starter-clips.txt"
archive_pin="$root/fixtures/vctk/vctk-0.92-archive.sha256"
files_pin="$root/fixtures/vctk/vctk-0.92-clips.sha256"

if [[ -d "$dest" && -f "$files_pin" ]] && (cd "$dest" && shasum -a 256 --check --quiet --strict "$files_pin"); then
  echo "fetch-vctk: OK, $(wc -l < "$files_pin" | tr -d ' ') pinned files already in $dest"
  exit 0
fi

patterns=()
while IFS= read -r clip; do
  [[ -z "$clip" || "$clip" == \#* ]] && continue
  speaker="${clip%%_*}"
  patterns+=("wav48_silence_trimmed/$speaker/${clip}_mic1.flac" "txt/$speaker/$clip.txt")
done < "$clips"

mkdir -p "$cache"
work="$(mktemp -d "$cache/fetch.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/out"
mkfifo "$work/stream"
shasum -a 256 < "$work/stream" | cut -d' ' -f1 > "$work/archive.sha256" &
hasher=$!

echo "fetch-vctk: streaming $url (about 11 GB), extracting up to ${#patterns[@]} files"
# bsdtar reads the whole stream and exits 1 if a requested member is absent; absent clips are reported below,
# so only the download and the digest must succeed.
set +e
curl -fsSL --retry 3 "$url" | tee "$work/stream" | bsdtar -xf - -C "$work/out" "${patterns[@]}" 2> "$work/bsdtar.log"
status=("${PIPESTATUS[@]}")
set -e
wait "$hasher"
if [[ "${status[0]}" != 0 || "${status[1]}" != 0 ]]; then
  echo "fetch-vctk: download failed (curl ${status[0]}, tee ${status[1]})" >&2
  exit 1
fi
if grep -v "Not found in archive" "$work/bsdtar.log" | grep -v "Error exit delayed" | grep -q .; then
  cat "$work/bsdtar.log" >&2
  exit 1
fi
digest="$(cat "$work/archive.sha256")"
echo "fetch-vctk: archive SHA-256 $digest"

present=()
for pattern in "${patterns[@]}"; do
  if [[ -f "$work/out/$pattern" ]]; then present+=("$pattern"); else echo "fetch-vctk: not in VCTK 0.92: $pattern"; fi
done

if [[ -f "$archive_pin" ]]; then
  pinned="$(cut -d' ' -f1 "$archive_pin")"
  if [[ "$digest" != "$pinned" ]]; then
    echo "fetch-vctk: archive SHA-256 mismatch: got $digest, pinned $pinned" >&2
    exit 1
  fi
else
  echo "$digest  VCTK-Corpus-0.92.zip" > "$archive_pin"
  echo "fetch-vctk: first fetch, recorded the archive digest in ${archive_pin#"$root"/}"
fi

if [[ -f "$files_pin" ]]; then
  (cd "$work/out" && shasum -a 256 --check --quiet --strict "$files_pin") || {
    echo "fetch-vctk: extracted files do not match ${files_pin#"$root"/}" >&2
    exit 1
  }
else
  (cd "$work/out" && printf '%s\n' "${present[@]}" | LC_ALL=C sort | xargs shasum -a 256) > "$files_pin"
  echo "fetch-vctk: first fetch, recorded ${#present[@]} file digests in ${files_pin#"$root"/}"
fi

rm -rf "$dest"
mv "$work/out" "$dest"
echo "fetch-vctk: OK, ${#present[@]} of ${#patterns[@]} files in $dest ($(du -sh "$dest" | cut -f1))"
