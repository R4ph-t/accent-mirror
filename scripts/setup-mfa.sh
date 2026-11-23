#!/usr/bin/env bash
# Installs the Montreal Forced Aligner, the spec 03 word-boundary baseline (Open question 5), into the git-ignored
# cache. Offline tooling only: MFA never runs in the app, in CI or in `make check`.
#
# Pins: micromamba 2.10.0-0 (checked against its published SHA-256), MFA 3.4.4 from conda-forge, and the english_mfa
# v3.1.0 acoustic model and dictionary from their tagged mfa-models releases. The model and dictionary digests are
# recorded in fixtures/vctk/mfa-models.sha256 on first install, and every later install must match them.
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
mfa_home="${MFA_CACHE:-$root/.cache/mfa}"
micromamba_version="2.10.0-0"
mfa_version="3.4.4"
models_tag="v3.1.0"
models_pin="$root/fixtures/vctk/mfa-models.sha256"

mkdir -p "$mfa_home/bin" "$mfa_home/models"
mm="$mfa_home/bin/micromamba"
if [[ ! -x "$mm" ]]; then
  base="https://github.com/mamba-org/micromamba-releases/releases/download/$micromamba_version"
  curl -fsSL --retry 3 "$base/micromamba-osx-arm64" -o "$mm.tmp"
  expected="$(curl -fsSL --retry 3 "$base/micromamba-osx-arm64.sha256" | cut -d' ' -f1)"
  actual="$(shasum -a 256 "$mm.tmp" | cut -d' ' -f1)"
  if [[ "$expected" != "$actual" ]]; then
    rm -f "$mm.tmp"
    echo "setup-mfa: micromamba SHA-256 mismatch: got $actual, expected $expected" >&2
    exit 1
  fi
  chmod +x "$mm.tmp" && mv "$mm.tmp" "$mm"
fi

export MAMBA_ROOT_PREFIX="$mfa_home/mamba"
if [[ ! -x "$mfa_home/env/bin/mfa" ]]; then
  "$mm" create --yes --quiet --prefix "$mfa_home/env" --channel conda-forge --override-channels \
    "montreal-forced-aligner=$mfa_version"
fi

for kind in acoustic dictionary; do
  file="english_mfa.zip"
  [[ "$kind" == dictionary ]] && file="english_mfa.dict"
  if [[ ! -f "$mfa_home/models/$file" ]]; then
    curl -fsSL --retry 3 \
      "https://github.com/MontrealCorpusTools/mfa-models/releases/download/$kind-english_mfa-$models_tag/$file" \
      -o "$mfa_home/models/$file.tmp"
    mv "$mfa_home/models/$file.tmp" "$mfa_home/models/$file"
  fi
done

if [[ -f "$models_pin" ]]; then
  (cd "$mfa_home/models" && shasum -a 256 --check --quiet --strict "$models_pin") || {
    echo "setup-mfa: MFA model files do not match ${models_pin#"$root"/}" >&2
    exit 1
  }
else
  (cd "$mfa_home/models" && shasum -a 256 english_mfa.dict english_mfa.zip) > "$models_pin"
  echo "setup-mfa: first install, recorded model digests in ${models_pin#"$root"/}"
fi

installed="$(MFA_ROOT_DIR="$mfa_home/root" "$mfa_home/env/bin/mfa" version)"
if [[ "$installed" != "$mfa_version" ]]; then
  echo "setup-mfa: expected MFA $mfa_version, found $installed" >&2
  exit 1
fi
echo "setup-mfa: OK, MFA $installed, english_mfa $models_tag in $mfa_home ($(du -sh "$mfa_home" | cut -f1))"
