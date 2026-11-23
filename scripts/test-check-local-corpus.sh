#!/usr/bin/env bash
# Self-test for check-local-corpus.sh: it must fail on each offending path
# and pass on a clean repo. Uses throwaway git repos in a temp dir.
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/check-local-corpus.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

new_repo() {
  local dir="$tmp/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  echo "$dir"
}

track() { # repo, path
  mkdir -p "$1/$(dirname "$2")"
  echo x > "$1/$2"
  git -C "$1" add -f "$2"
}

failures=0

# Clean repo: must pass.
clean=$(new_repo clean)
track "$clean" README.md
track "$clean" Packages/AccentKit/Sources/AMCore/AMCore.swift
track "$clean" docs/voice-notes.md
if (cd "$clean" && "$guard" >/dev/null 2>&1); then
  echo "ok   clean tree passes"
else
  echo "FAIL clean tree was rejected"; failures=$((failures + 1))
fi

# Each offending path: must fail and name the path.
i=0
for path in \
  eval-local/clip.wav \
  data/Common-Voice/en/clip.mp3 \
  data/commonvoice/clip.mp3 \
  cv-corpus-17.0/en/clip.mp3 \
  corpora/Speech_Accent_Archive/english1.mp3 \
  corpora/accent-archive.zip
do
  i=$((i + 1))
  repo=$(new_repo "bad$i")
  track "$repo" README.md
  track "$repo" "$path"
  if out=$(cd "$repo" && "$guard" 2>&1); then
    echo "FAIL guard passed with $path tracked"; failures=$((failures + 1))
  elif grep -qF "$path" <<<"$out"; then
    echo "ok   rejects $path"
  else
    echo "FAIL guard failed but did not name $path"; failures=$((failures + 1))
  fi
done

if [[ $failures -gt 0 ]]; then
  echo "test-check-local-corpus: $failures failure(s)"; exit 1
fi
echo "test-check-local-corpus: all passed"
