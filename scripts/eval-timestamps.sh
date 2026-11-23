#!/usr/bin/env bash
# Spec 03 `make eval`: runs the pinned WhisperKit model on the 159 VCTK starter clips, compares its word boundaries
# with the MFA baseline, and writes docs/agreement/reports/timestamp-feasibility-<configDigest8>.{json,md}.
# A release run (the default) refuses a dirty tree, and exits non-zero on FAIL and on NOT EVALUATED.
#
#   scripts/eval-timestamps.sh          # release run: clean tree, report under docs/agreement/reports/
#   scripts/eval-timestamps.sh --dev    # any tree, report under .cache/reports/, NOT EVALUATED exits 0
#
# Needs scripts/fetch-models.sh, scripts/fetch-vctk.sh and, for the baseline, scripts/setup-mfa.sh then
# scripts/mfa-align.sh (its output, fixtures/vctk/mfa-word-baseline.json, is committed).
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
model="openai_whisper-base.en"
release=(--release)
out="$root/docs/agreement/reports"
if [[ "${1:-}" == "--dev" ]]; then
  release=()
  out="$root/.cache/reports"
fi

"$root/scripts/fetch-models.sh" --verify "$model"
"$root/scripts/fetch-vctk.sh"
"$root/scripts/am-timestamps.sh" eval "${release[@]}" \
  --repo "$root" \
  --clips "$root/fixtures/vctk/starter-clips.txt" \
  --corpus "${VCTK_CACHE:-$root/.cache/vctk}/VCTK-Corpus-0.92" \
  --archive-pin "$root/fixtures/vctk/vctk-0.92-archive.sha256" \
  --baseline "$root/fixtures/vctk/mfa-word-baseline.json" \
  --manifest "$root/Resources/Models/$model/manifest.json" \
  --model-dir "${MODELS_CACHE:-$root/.cache/models}/$model" \
  --out "$out"
