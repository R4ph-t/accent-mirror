#!/usr/bin/env bash
# Spec 25 §5 acceptance 1: spec 11 §4b's oracle-boundary jitter test, run with `.span` and `.nucleus` side by side on
# the head's thresholds (main's, nucleus parameters at their initial values). Measures with
# `am-timestamps spec11-guard --rows jitter`, then `am-eval nucleus-jitter` applies the limits, prints the table and
# writes docs/agreement/reports/nucleus-jitter-<configDigest8>.{json,md}. Local only: reads caches, no network.
#
#   scripts/nucleus-jitter.sh [--summary <file>]
#
# Env: AM_EVAL_CACHE (needs guard/held-out/{inputs,mfa-baseline}.json from scripts/spec11-guard.sh and vctk-timings/),
# REFERENCE_DIR (the synthetic set: markers.json, mfa-alignment.json, corpus/tts/), MODELS_CACHE (Whisper base.en,
# used live on the synthetic set only for word probabilities and matching, as spec 11's harness does).
# Never runs MFA: a missing input stops the script. The seed is the VCTK split manifest's fold seed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"
models="${MODELS_CACHE:-$root/.cache/models}"
reference="${REFERENCE_DIR:-$root/.cache/reference}"
work="$cache/guard/held-out"
out="$cache/nucleus-jitter"
summary=()
[[ "${1:-}" == "--summary" ]] && summary=(--summary "${2:?--summary needs a file}")

for f in "$work/inputs.json" "$work/mfa-baseline.json" "$reference/markers.json" "$reference/mfa-alignment.json"; do
  [[ -f "$f" ]] || { echo "nucleus-jitter: missing $f (no MFA run here: produce it with scripts/spec11-guard.sh)" >&2; exit 1; }
done
[[ -d "$cache/vctk-timings" ]] || { echo "nucleus-jitter: missing $cache/vctk-timings" >&2; exit 1; }
seed="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["foldSeed"])' "$root/fixtures/splits/vctk.json")"

mkdir -p "$out"
for measurement in span nucleus; do
  nice -n 10 "$root/scripts/am-timestamps.sh" spec11-guard --out "$out/$measurement.json" --label main --seed "$seed" \
    --measurement "$measurement" --rows jitter \
    --vctk-inputs "$work/inputs.json" --vctk-baseline "$work/mfa-baseline.json" --vctk-replay "$cache/vctk-timings" \
    --set-name vctk-held-out \
    --reference "$reference" --manifest "$root/Resources/Models/openai_whisper-base.en/manifest.json" \
    --model-dir "$models/openai_whisper-base.en"
done
nice -n 10 "$root/scripts/am-eval.sh" nucleus-jitter --span "$out/span.json" --nucleus "$out/nucleus.json" \
  --write-report ${summary[@]+"${summary[@]}"}
