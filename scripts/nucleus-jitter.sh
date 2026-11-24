#!/usr/bin/env bash
# Spec 25 §5 / spec 26 §4 acceptance 1: spec 11 §4b's oracle-boundary jitter test, run with `.span` and `.nucleus`
# side by side on the head's thresholds (main's verdict thresholds, spec 26's grid-chosen nucleus values). For spec 26
# §5 it also reruns spec 25's `.nucleus` (spec 25's nucleus values, N_w the context count, no ambiguity check) for the
# flip breakdown, and measures detection on held-out VCTK at the head's values (reported, never used to choose).
# Measures with `am-timestamps spec11-guard --rows jitter`, then `am-eval nucleus-jitter` applies the limits, prints
# the table and writes docs/agreement/reports/nucleus-jitter-<configDigest8>.{json,md}. Local only: reads caches, no
# network.
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
# Spec 25's `.nucleus` for spec 26 §5: the head's thresholds with spec 25's nucleus values and no ambiguity check.
nice -n 10 "$root/scripts/am-eval.sh" thresholds-json --spec25-nucleus --out "$out/spec25-thresholds.json"
runs=(span:span: nucleus:nucleus: spec25:nucleus:--thresholds="$out/spec25-thresholds.json")
for run in "${runs[@]}"; do
  name="${run%%:*}"; rest="${run#*:}"; measurement="${rest%%:*}"; flag="${rest#*:}"
  args=()
  if [[ -n "$flag" ]]; then args=(--thresholds "${flag#--thresholds=}" --context-counts-only); fi
  nice -n 10 "$root/scripts/am-timestamps.sh" spec11-guard --out "$out/$name.json" --label main --seed "$seed" \
    --measurement "$measurement" --rows jitter ${args[@]+"${args[@]}"} \
    --vctk-inputs "$work/inputs.json" --vctk-baseline "$work/mfa-baseline.json" --vctk-replay "$cache/vctk-timings" \
    --set-name vctk-held-out \
    --reference "$reference" --manifest "$root/Resources/Models/openai_whisper-base.en/manifest.json" \
    --model-dir "$models/openai_whisper-base.en"
done
held=()
if [[ -d "$work/mfa-work/aligned" ]]; then
  nice -n 10 "$root/scripts/am-eval.sh" nucleus-count-held-out --inputs "$work/inputs.json" \
    --mfa "$work/mfa-work/aligned" --out "$out/held-out-detection.json"
  held=(--held-out-detection "$out/held-out-detection.json")
fi
nice -n 10 "$root/scripts/am-eval.sh" nucleus-jitter --span "$out/span.json" --nucleus "$out/nucleus.json" \
  --spec25-recomputed "$out/spec25.json" ${held[@]+"${held[@]}"} --write-report ${summary[@]+"${summary[@]}"}
