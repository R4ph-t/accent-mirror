#!/usr/bin/env bash
# Sound judging: fetches facebook/wav2vec2-lv-60-espeak-cv-ft (Apache-2.0) at the commit pinned in
# Resources/Models/wav2vec2-lv-60-espeak-cv-ft/manifest.json, checks every upstream file's SHA-256, converts it to the
# int8 Core ML package with tools/convert_judge_model.py in a pinned Python venv under the git-ignored .cache/
# (coremltools runs only here, never in the app), and checks the package's files and aggregate SHA-256 against the
# manifest. Any mismatch fails and keeps nothing. Weights are never committed and never Git LFS. Local tooling only:
# never run by the app or CI. The "Bundle judge model" build phase runs --verify and compiles the verified package.
#
# The conversion is bit-reproducible with the pinned venv (two conversions compared byte for byte), so packageSHA256
# pins the converted package itself, not a hand-made reference copy.
#
# Once the package verifies, the 1.26 GB PyTorch weights (upstream/pytorch_model.bin) are deleted: the app only
# needs the package. The small upstream files (config, vocabulary, tokenizer) stay and are checked by --verify.
#
#   scripts/fetch-judge-model.sh            # fetch, convert and verify (skips the work when the cache already verifies)
#   scripts/fetch-judge-model.sh --verify   # check an existing fetch without the network
#
# MODELS_CACHE (default .cache/models) is where the model lands; JUDGE_VENV (default .cache/judge-venv) the venv.
set -euo pipefail

verify_only=0
if [[ "${1:-}" == "--verify" ]]; then verify_only=1; fi

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
model="wav2vec2-lv-60-espeak-cv-ft"
manifest="$root/Resources/Models/$model/manifest.json"
dest="${MODELS_CACHE:-$root/.cache/models}/$model"
venv="${JUDGE_VENV:-$root/.cache/judge-venv}"
weights="upstream/pytorch_model.bin"

field() { plutil -extract "$1" raw -o - "$manifest"; }
package="$(field package)"

# Pinned shasum lines for the upstream files (paths relative to $dest) and the package files (relative to the package).
upstream_sums=""
n_upstream=0
while path="$(field "upstream.$n_upstream.path" 2>/dev/null)"; do
  upstream_sums+="$(field "upstream.$n_upstream.sha256")  $path"$'\n'
  n_upstream=$((n_upstream + 1))
done
package_sums=""
n_package=0
while path="$(field "packageFiles.$n_package.path" 2>/dev/null)"; do
  package_sums+="$(field "packageFiles.$n_package.sha256")  $path"$'\n'
  n_package=$((n_package + 1))
done
package_sums="$(printf '%s' "$package_sums" | LC_ALL=C sort -k2)"$'\n'
aggregate="$(printf '%s' "$package_sums" | shasum -a 256 | cut -d' ' -f1)"
if [[ "$aggregate" != "$(field packageSHA256)" ]]; then
  echo "fetch-judge-model: manifest is inconsistent: its package digests hash to $aggregate, not packageSHA256" >&2
  exit 1
fi
if ! grep -q "  $weights\$" <<<"$upstream_sums"; then
  echo "fetch-judge-model: manifest does not list $weights" >&2
  exit 1
fi
kept_sums="$(grep -v "  $weights\$" <<<"$upstream_sums")"$'\n'

check_sums() { (cd "$1" && printf '%s' "$2" | shasum -a 256 --check --quiet --strict -); }
check_package() {
  local dir="$1/$package"
  [[ -d "$dir" ]] || return 1
  # Exactly the pinned files: nothing missing, nothing extra.
  [[ "$(cd "$dir" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)" == "$(printf '%s' "$package_sums" | sed 's/^[0-9a-f]*  //' | sed '/^$/d')" ]] || return 1
  check_sums "$dir" "$package_sums"
}

if [[ -d "$dest" ]] && check_sums "$dest" "$kept_sums" 2>/dev/null && check_package "$dest" 2>/dev/null; then
  echo "fetch-judge-model: OK, $model verified ($n_package package files, packageSHA256 $aggregate)"
  exit 0
fi
if [[ "$verify_only" == 1 ]]; then
  echo "fetch-judge-model: $model is missing or does not match its manifest; run scripts/fetch-judge-model.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "$dest")"
work="$(mktemp -d "$(dirname "$dest")/fetch-judge.XXXXXX")"
trap 'rm -rf "$work"' EXIT
for ((j = 0; j < n_upstream; j++)); do
  path="$(field "upstream.$j.path")"
  mkdir -p "$work/$(dirname "$path")"
  curl -fsSL --retry 5 --retry-all-errors "$(field "upstream.$j.url")" -o "$work/$path"
done
if ! check_sums "$work" "$upstream_sums"; then
  echo "fetch-judge-model: upstream SHA-256 mismatch for $model; nothing was kept" >&2
  exit 1
fi

if [[ ! -x "$venv/bin/python" ]]; then
  if command -v uv >/dev/null; then
    uv venv -q --python "$(field conversion.python)" "$venv"
  else
    "python$(field conversion.python)" -m venv "$venv"
  fi
fi
if command -v uv >/dev/null; then
  VIRTUAL_ENV="$venv" uv pip install -q -r "$root/$(field conversion.requirements)"
else
  "$venv/bin/python" -m pip install -q -r "$root/$(field conversion.requirements)"
fi
"$venv/bin/python" -I "$root/$(field conversion.script)" "$work/upstream" "$work/$package" >"$work/convert.log" 2>&1 || {
  cat "$work/convert.log" >&2
  echo "fetch-judge-model: conversion failed; nothing was kept" >&2
  exit 1
}
rm -f "$work/convert.log"
if ! check_package "$work"; then
  echo "fetch-judge-model: converted package does not match packageSHA256 $aggregate; nothing was kept" >&2
  exit 1
fi
rm -f "$work/$weights"
rm -rf "$dest"
mv "$work" "$dest"
trap - EXIT
echo "fetch-judge-model: OK, $model fetched, converted and verified ($(du -sh "$dest/$package" | cut -f1) package, packageSHA256 $aggregate)"
