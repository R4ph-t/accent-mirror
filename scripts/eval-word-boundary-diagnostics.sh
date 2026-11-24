#!/usr/bin/env bash
# CTO diagnostic round on spec 23's downstream gate (decision on #27, 2026-11-23). Same harness, verdict function,
# thresholds, sets and comparability rules as the gate in docs/agreement/reports/word-boundaries-cfd62cd8.md; measures
# only. Writes docs/agreement/reports/word-boundaries-diagnostics-2026-11-23.{json,md}.
#
#   scripts/eval-word-boundary-diagnostics.sh         # release run: clean tree, report under docs/agreement/reports/
#   scripts/eval-word-boundary-diagnostics.sh --dev   # any tree, report under .cache/reports/
#
# Reads the synthetic set from .cache/reference/ as scripts/reference-check.sh left it (TTS audio, markers, MFA on
# TTS); it does not regenerate it. No ASR on VCTK (spec 03's replay); Whisper runs live on the TTS audio only, from
# the pinned local model, with networking denied. Exits 4 when b2's diff does not reproduce the gate report.
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
mode=(--release)
out="$root/docs/agreement/reports"
case "${1:-}" in
  --dev) mode=(); out="$root/.cache/reports" ;;
  "") ;;
  *) echo "usage: $0 [--dev]" >&2; exit 64 ;;
esac

reference="$root/.cache/reference"
[[ -f "$reference/markers.json" && -f "$reference/mfa-alignment.json" ]] \
  || { echo "no synthetic set in .cache/reference: run scripts/reference-check.sh first" >&2; exit 2; }
"$root/scripts/fetch-vctk.sh"
"$root/scripts/fetch-ctc.sh"
"$root/scripts/fetch-models.sh" --verify openai_whisper-base.en
"$root/scripts/am-timestamps.sh" diagnostics ${mode[@]+"${mode[@]}"} \
  --repo "$root" \
  --clips "$root/fixtures/vctk/starter-clips.txt" \
  --corpus "${VCTK_CACHE:-$root/.cache/vctk}/VCTK-Corpus-0.92" \
  --files-pin "$root/fixtures/vctk/vctk-0.92-clips.sha256" \
  --baseline "$root/fixtures/vctk/mfa-word-baseline.json" \
  --replay "$root/fixtures/timestamps/openai_whisper-base.en" \
  --ctc-manifest "$root/fixtures/models/wav2vec2-base-960h/manifest.json" \
  --ctc-dir "${MODELS_CACHE:-$root/.cache/models}/wav2vec2-base-960h" \
  --reference "$reference" \
  --manifest "$root/Resources/Models/openai_whisper-base.en/manifest.json" \
  --model-dir "${MODELS_CACHE:-$root/.cache/models}/openai_whisper-base.en" \
  --gate-report "$root/docs/agreement/reports/word-boundaries-cfd62cd8.json" \
  --name word-boundaries-diagnostics-2026-11-23 \
  --out "$out"
