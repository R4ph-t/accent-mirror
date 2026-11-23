#!/usr/bin/env bash
# Spec 23: refines spec 03's Whisper words (its committed WhisperKit base.en replay) with each aligner on the VCTK
# clips, judges them against the MFA baseline on spec 03's unpadded bar, and writes
# docs/agreement/reports/word-boundaries-<configDigest8>.{json,md}. Exits non-zero on FAIL.
#
#   scripts/eval-word-boundaries.sh            # release run: clean tree, report under docs/agreement/reports/
#   scripts/eval-word-boundaries.sh --dev      # any tree, report under .cache/reports/
#   scripts/eval-word-boundaries.sh --record   # any tree: also rewrites the refined replays under fixtures/timestamps/
#
# Needs scripts/fetch-vctk.sh (the clips) and, for b2 (built because b1 failed), scripts/fetch-ctc.sh (the pinned,
# converted wav2vec2-base-960h). No ASR runs: the tool runs with networking denied. scripts/reference-check.sh runs
# first and puts MFA's own error in the report as a labelled line (not a gate); it skips cleanly without MFA or voice.
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
mode=(--release)
out="$root/docs/agreement/reports"
case "${1:-}" in
  --dev) mode=(); out="$root/.cache/reports" ;;
  --record) mode=(--record "$root/fixtures/timestamps"); out="$root/.cache/reports" ;;
  "") ;;
  *) echo "usage: $0 [--dev | --record]" >&2; exit 64 ;;
esac

"$root/scripts/fetch-vctk.sh"
"$root/scripts/fetch-ctc.sh"
"$root/scripts/reference-check.sh"
"$root/scripts/am-timestamps.sh" boundaries ${mode[@]+"${mode[@]}"} \
  --repo "$root" \
  --clips "$root/fixtures/vctk/starter-clips.txt" \
  --corpus "${VCTK_CACHE:-$root/.cache/vctk}/VCTK-Corpus-0.92" \
  --files-pin "$root/fixtures/vctk/vctk-0.92-clips.sha256" \
  --archive-pin "$root/fixtures/vctk/vctk-0.92-archive.sha256" \
  --baseline "$root/fixtures/vctk/mfa-word-baseline.json" \
  --replay "$root/fixtures/timestamps/openai_whisper-base.en" \
  --ctc-manifest "$root/fixtures/models/wav2vec2-base-960h/manifest.json" \
  --ctc-dir "${MODELS_CACHE:-$root/.cache/models}/wav2vec2-base-960h" \
  --reference "$root/.cache/reference/reference-check.json" \
  --out "$out"
