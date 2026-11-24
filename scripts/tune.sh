#!/usr/bin/env bash
# The tuning runner (spec 02's grid and selection rule; spec 11 §2 and §4c): measures the guard on the VCTK tuning
# speakers, then fits the fixed grid on cached L1 features, runs the nested CV (§1) and the VCTK CV, and writes
# eval-cache/tuning/tuning-<configDigest8>.json for the release suite. Local only, never in PR CI. Re-tunes are logged
# in docs/agreement/tuning-log.md. Runs under nice with 3 jobs by default (AM_EVAL_JOBS).
#
#   scripts/tune.sh [am-eval tune options]
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)/.."
cache="${AM_EVAL_CACHE:-$root/eval-cache}"
mkdir -p "$cache/tuning"
GUARD_LABEL=initial nice -n 10 "$root/scripts/spec11-guard.sh" tuning "$cache/tuning/guard-tuning.json"
exec nice -n 10 "$root/scripts/am-eval.sh" tune --jobs "${AM_EVAL_JOBS:-3}" --guard "$cache/tuning/guard-tuning.json" "$@"
