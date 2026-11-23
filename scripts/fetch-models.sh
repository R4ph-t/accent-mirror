#!/usr/bin/env bash
# Fetches the pinned speech-model files listed in Resources/Models/<model>/manifest.json into the git-ignored cache,
# and verifies every file's SHA-256 and the manifest's aggregate digest. Any mismatch fails and keeps nothing.
# Weights are never committed and never Git LFS (AGENTS.md). Local tooling only: never run by the app or CI.
#
#   scripts/fetch-models.sh [model]           # default: openai_whisper-base.en
#   scripts/fetch-models.sh --verify [model]  # check an existing fetch without the network
set -euo pipefail

verify_only=0
if [[ "${1:-}" == "--verify" ]]; then verify_only=1; shift; fi
model="${1:-openai_whisper-base.en}"

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
manifest="$root/Resources/Models/$model/manifest.json"
dest="${MODELS_CACHE:-$root/.cache/models}/$model"
[[ -f "$manifest" ]] || { echo "fetch-models: no manifest at ${manifest#"$root"/}" >&2; exit 1; }

field() { plutil -extract "$1" raw -o - "$manifest"; }

# The pinned list, as shasum lines ("<sha256>  <path>"), sorted by path (the aggregate digest is over these lines).
sums=""
i=0
while path="$(field "files.$i.path" 2>/dev/null)"; do
  sums+="$(field "files.$i.sha256")  $path"$'\n'
  i=$((i + 1))
done
sums="$(printf '%s' "$sums" | LC_ALL=C sort -k2)"$'\n'
aggregate="$(printf '%s' "$sums" | shasum -a 256 | cut -d' ' -f1)"
if [[ "$aggregate" != "$(field modelSHA256)" ]]; then
  echo "fetch-models: manifest is inconsistent: its file digests hash to $aggregate, not modelSHA256" >&2
  exit 1
fi

check() { (cd "$1" && printf '%s' "$sums" | shasum -a 256 --check --quiet --strict -); }

if [[ -d "$dest" ]] && check "$dest"; then
  echo "fetch-models: OK, $model already fetched and verified ($i files, $(field asrModelID))"
  exit 0
fi
if [[ "$verify_only" == 1 ]]; then
  echo "fetch-models: $model is missing or does not match its manifest; run scripts/fetch-models.sh $model" >&2
  exit 1
fi

mkdir -p "$(dirname "$dest")"
work="$(mktemp -d "$(dirname "$dest")/fetch.XXXXXX")"
trap 'rm -rf "$work"' EXIT
for ((j = 0; j < i; j++)); do
  path="$(field "files.$j.path")"
  mkdir -p "$work/$(dirname "$path")"
  curl -fsSL --retry 3 "$(field "files.$j.url")" -o "$work/$path"
done
if ! check "$work"; then
  echo "fetch-models: SHA-256 mismatch for $model; nothing was kept" >&2
  exit 1
fi
rm -rf "$dest"
mv "$work" "$dest"
trap - EXIT
echo "fetch-models: OK, $model fetched and verified ($i files, $(du -sh "$dest" | cut -f1), $(field asrModelID))"
