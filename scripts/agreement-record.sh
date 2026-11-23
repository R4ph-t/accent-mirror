#!/usr/bin/env bash
# Spec 03 `make agreement-record`: runs the pinned WhisperKit model on the 159 VCTK starter clips and writes one
# replay JSON per clip (words, start, end, probability, asrModelID) plus manifest.json (with recordingsSHA256) to
# fixtures/timestamps/<model>/. FixtureTimestamper replays them in CI, which never runs ASR.
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
model="openai_whisper-base.en"

"$root/scripts/fetch-models.sh" --verify "$model"
"$root/scripts/fetch-vctk.sh"
"$root/scripts/am-timestamps.sh" record \
  --clips "$root/fixtures/vctk/starter-clips.txt" \
  --corpus "${VCTK_CACHE:-$root/.cache/vctk}/VCTK-Corpus-0.92" \
  --manifest "$root/Resources/Models/$model/manifest.json" \
  --model-dir "${MODELS_CACHE:-$root/.cache/models}/$model" \
  --out "$root/fixtures/timestamps/$model"
