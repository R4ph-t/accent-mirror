#!/usr/bin/env bash
# Builds Resources/Starter/ (spec 15): CPO's starter phrases (fixtures/starter/phrases.json), each kept phrase's
# native VCTK 0.92 recordings trimmed by spec 02's rule (same cut for every speaker, 2–6 s), the recorded WhisperKit
# word timings shifted onto the trimmed clips (fixtures/timestamps/), and each recording's L0/L1 analysis built by the
# pipeline's own rebuild path. Regenerates the whole folder; two runs give byte-identical files. No ASR, no network.
#
# Needs the pinned raw clips: AM_EVAL_CACHE/vctk/raw (scripts/fetch-vctk-eval.sh puts them there; every clip is
# checked against fixtures/vctk/eval-speakers.json).
#
#   scripts/build-starter.sh
#   AM_EVAL_CACHE=/elsewhere/eval-cache scripts/build-starter.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"
raw="$cache/vctk/raw"
[[ -d "$raw" ]] || { echo "build-starter: no VCTK clips in $raw: run scripts/fetch-vctk-eval.sh first" >&2; exit 1; }

"$root/scripts/am-eval.sh" starter-build \
  --phrases "$root/fixtures/starter/phrases.json" \
  --eval-speakers "$root/fixtures/vctk/eval-speakers.json" \
  --raw "$raw" \
  --timings "$root/fixtures/timestamps/openai_whisper-base.en" \
  --out "$root/Resources/Starter"
echo "build-starter: $(du -sh "$root/Resources/Starter" | cut -f 1) in Resources/Starter"
