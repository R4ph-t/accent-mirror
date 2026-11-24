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
# first (MFA on synthesised, SSML-marked phrases; skips cleanly without MFA or voice). The report's ship gate is
# downstream (spec 07's verdicts under oracle vs b2 boundaries, synthetic and VCTK); 40 ms / 85% is a reported target.
# Exits 1 on a downstream FAIL and, on a release run, 3 on NOT EVALUATED.
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
# The synthetic set needs Whisper's words on the TTS audio (b2's seed, as in the pipeline); checked offline only.
whisper=()
if "$root/scripts/fetch-models.sh" --verify openai_whisper-base.en; then
  whisper=(--manifest "$root/Resources/Models/openai_whisper-base.en/manifest.json"
           --model-dir "${MODELS_CACHE:-$root/.cache/models}/openai_whisper-base.en")
fi
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
  --reference "$root/.cache/reference" ${whisper[@]+"${whisper[@]}"} \
  --out "$out"
