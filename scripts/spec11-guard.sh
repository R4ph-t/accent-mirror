#!/usr/bin/env bash
# Spec 11 §4c: measures the anti-inconclusive guard with `am-timestamps spec11-guard` (spec 23's harness, verdicts
# only; the limits are applied by am-eval). Local only: reads caches, makes no network call.
#
#   scripts/spec11-guard.sh tuning   <out.json>   # b2 vs MFA and jitter on the VCTK tuning speakers (used by tune.sh)
#   scripts/spec11-guard.sh held-out <out.json>   # synthetic set (control, b2, jitter) and the held-out VCTK speakers
#
# Env: AM_EVAL_CACHE, MODELS_CACHE, MFA_CACHE, REFERENCE_DIR (the synthetic set: markers, MFA on TTS; default
# .cache/reference from scripts/reference-check.sh), GUARD_THRESHOLDS (a Thresholds JSON; default Thresholds.current),
# GUARD_LABEL (default "shipped"). The jitter seed is the VCTK split manifest's fold seed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scope="${1:?usage: spec11-guard.sh tuning|held-out <out.json>}"
out="${2:?usage: spec11-guard.sh tuning|held-out <out.json>}"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"
models="${MODELS_CACHE:-$root/.cache/models}"
reference="${REFERENCE_DIR:-$root/.cache/reference}"
work="$cache/guard/$scope"
seed="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["foldSeed"])' "$root/fixtures/splits/vctk.json")"

mkdir -p "$work"
"$root/scripts/am-eval.sh" guard-inputs --scope "$scope" --out "$work"
if [[ ! -f "$work/mfa-baseline.json" || "$work/clips.txt" -nt "$work/mfa-baseline.json" ]]; then
  MFA_INPUT_CORPUS="$work/corpus" MFA_WORK="$work/mfa-work" BASELINE_OUT="$work/mfa-baseline.json" \
    "$root/scripts/mfa-align.sh" "$work/clips.txt"
fi
case "$scope" in
  tuning) replay="$cache/vctk-tuning-timings"; synthetic=() ;;
  held-out)
    replay="$cache/vctk-timings"
    synthetic=()
    if [[ -f "$reference/markers.json" && -f "$reference/mfa-alignment.json" ]]; then
      synthetic=(--reference "$reference" --manifest "$root/Resources/Models/openai_whisper-base.en/manifest.json"
                 --model-dir "$models/openai_whisper-base.en")
    else
      echo "spec11-guard: no synthetic set in $reference (scripts/reference-check.sh): synthetic rows NOT EVALUATED"
    fi
    ;;
  *) echo "spec11-guard: unknown scope $scope" >&2; exit 64 ;;
esac
thresholds=()
[[ -n "${GUARD_THRESHOLDS:-}" ]] && thresholds=(--thresholds "$GUARD_THRESHOLDS")
"$root/scripts/am-timestamps.sh" spec11-guard --out "$out" --label "${GUARD_LABEL:-shipped}" --seed "$seed" \
  --ctc-manifest "$root/fixtures/models/wav2vec2-base-960h/manifest.json" --ctc-dir "$models/wav2vec2-base-960h" \
  --vctk-inputs "$work/inputs.json" --vctk-baseline "$work/mfa-baseline.json" --vctk-replay "$replay" \
  --set-name "vctk-$scope" ${thresholds[@]+"${thresholds[@]}"} ${synthetic[@]+"${synthetic[@]}"}
