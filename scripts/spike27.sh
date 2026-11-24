#!/usr/bin/env bash
# Spec 27: the word-stress classifier and native envelope spike (offline, GO / NO-GO). Prepares every population
# through spec 25's nucleus front end at spec 26's frozen values, builds the TD-PSOLA identity takes and negatives,
# trains on the tuning side only (τ, variant, family, arm, envelopes on speaker-grouped CV), then evaluates every gate
# for each arm × boundary source and ends `Spike 27: GO`, `Spike 27: NO-GO` or `Spike 27: NO-GO (oracle-only)`.
#
#   scripts/spike27.sh [--write-report] [--stage prepare|negatives|train|evaluate|all]
#
# Env: AM_EVAL_CACHE (guard/{tuning,held-out}, vctk-*-timings, speechocean762{,-timings}), REFERENCE_DIR (the TTS
# references). Work files go to $AM_EVAL_CACHE/../spike27 and the 20 spot-check negatives to $AM_EVAL_CACHE/../listen,
# both outside the worktree. Never runs ASR or MFA, makes no network call. Runs under nice with 3 jobs.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"
for f in "$cache/guard/tuning/inputs.json" "$cache/guard/held-out/inputs.json" "$cache/vctk-tuning-timings" \
         "$cache/vctk-timings" "$cache/speechocean762/current" "$cache/speechocean762-timings"; do
  [[ -e "$f" ]] || { echo "spike27: missing $f" >&2; exit 1; }
done
stage=all
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage) stage="$2"; shift 2 ;;
    *) extra+=("$1"); shift ;;
  esac
done
nice -n 10 swift build -j 3 --package-path "$root/Packages/AccentKit" -c release --product am-eval >/dev/null
nice -n 10 "$root/scripts/am-eval.sh" spike27 --stage "$stage" --jobs 3 ${extra[@]+"${extra[@]}"}
