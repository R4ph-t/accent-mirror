#!/usr/bin/env bash
# Spec 23 b2: fetches facebook/wav2vec2-base-960h (Apache-2.0) at the commit pinned in
# fixtures/models/wav2vec2-base-960h/manifest.json, checks every upstream file's SHA-256, converts it to Core ML with
# tools/convert_ctc.py in a pinned Python venv under the git-ignored .cache/ (coremltools runs only here, never in the
# app), and checks the converted package's files and aggregate SHA-256 against the manifest. Any mismatch fails and
# keeps nothing. Weights are never committed and never Git LFS. Local tooling only: never run by the app or CI.
#
#   scripts/fetch-ctc.sh            # fetch, convert and verify (skips the work when the cache already verifies)
#   scripts/fetch-ctc.sh --verify   # check an existing fetch without the network
set -euo pipefail

verify_only=0
if [[ "${1:-}" == "--verify" ]]; then verify_only=1; fi

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
model="wav2vec2-base-960h"
manifest="$root/fixtures/models/$model/manifest.json"
dest="${MODELS_CACHE:-$root/.cache/models}/$model"
venv="${CTC_VENV:-$root/.cache/ctc-venv}"

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
  echo "fetch-ctc: manifest is inconsistent: its package digests hash to $aggregate, not packageSHA256" >&2
  exit 1
fi

check_upstream() { (cd "$1" && printf '%s' "$upstream_sums" | shasum -a 256 --check --quiet --strict -); }
check_package() {
  local dir="$1/$package"
  [[ -d "$dir" ]] || return 1
  # Exactly the pinned files: nothing missing, nothing extra.
  [[ "$(cd "$dir" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)" == "$(printf '%s' "$package_sums" | sed 's/^[0-9a-f]*  //' | sed '/^$/d')" ]] || return 1
  (cd "$dir" && printf '%s' "$package_sums" | shasum -a 256 --check --quiet --strict -)
}

if [[ -d "$dest" ]] && check_upstream "$dest" 2>/dev/null && check_package "$dest" 2>/dev/null; then
  echo "fetch-ctc: OK, $model verified ($n_upstream upstream files, $n_package package files, packageSHA256 $aggregate)"
  exit 0
fi
if [[ "$verify_only" == 1 ]]; then
  echo "fetch-ctc: $model is missing or does not match its manifest; run scripts/fetch-ctc.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "$dest")"
work="$(mktemp -d "$(dirname "$dest")/fetch-ctc.XXXXXX")"
trap 'rm -rf "$work"' EXIT
for ((j = 0; j < n_upstream; j++)); do
  path="$(field "upstream.$j.path")"
  mkdir -p "$work/$(dirname "$path")"
  curl -fsSL --retry 5 --retry-all-errors "$(field "upstream.$j.url")" -o "$work/$path"
done
if ! check_upstream "$work"; then
  echo "fetch-ctc: upstream SHA-256 mismatch for $model; nothing was kept" >&2
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
  echo "fetch-ctc: conversion failed; nothing was kept" >&2
  exit 1
}
rm -f "$work/convert.log"
if ! check_package "$work"; then
  echo "fetch-ctc: converted package does not match packageSHA256 $aggregate; nothing was kept" >&2
  exit 1
fi
rm -rf "$dest"
mv "$work" "$dest"
trap - EXIT
echo "fetch-ctc: OK, $model fetched, converted and verified ($(du -sh "$dest/$package" | cut -f1) package, packageSHA256 $aggregate)"
