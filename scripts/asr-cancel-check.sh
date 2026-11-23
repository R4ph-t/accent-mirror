#!/usr/bin/env bash
# Spec 03 local cancellation check (plan §8.2; not PR CI): cancels a WhisperKit transcription 100 ms in, five times,
# and checks each returns within about 300 ms, that the model is still loaded, and that the next request works.
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
model="openai_whisper-base.en"

"$root/scripts/fetch-models.sh" --verify "$model"
"$root/scripts/fetch-vctk.sh"
"$root/scripts/am-timestamps.sh" cancel-check \
  --clips "$root/fixtures/vctk/starter-clips.txt" \
  --corpus "${VCTK_CACHE:-$root/.cache/vctk}/VCTK-Corpus-0.92" \
  --manifest "$root/Resources/Models/$model/manifest.json" \
  --model-dir "${MODELS_CACHE:-$root/.cache/models}/$model"
