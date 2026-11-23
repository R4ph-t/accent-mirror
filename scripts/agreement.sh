#!/usr/bin/env bash
# The agreement harness (spec 02). Local and nightly only: PR CI runs the package tests, never this.
# Reads the corpus caches (scripts/fetch-*.sh); makes no network call.
#
#   scripts/agreement.sh                          # every suite
#   scripts/agreement.sh --suite sets             # recount the §6.3 sets (fetched corpus, else the label fixture)
#   scripts/agreement.sh --suite smoke            # smoke set: manifest, size cap, load time, placement goldens (never a rate gate)
#   scripts/agreement.sh --suite positive         # VCTK pair counts (metrics from spec 10)
#   scripts/agreement.sh --suite l2-shared [--write-report] [--release]   # shared-detector mode, reported (gate: spec 11)
#     needs the fetched corpus and its replayed timings: scripts/am-eval.sh record-timings --set l2-shared
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"
suite=all
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite) suite="$2"; shift 2 ;;
    --write-report|--release) extra+=("$1"); shift ;;
    *) echo "agreement.sh: unknown argument $1" >&2; exit 64 ;;
  esac
done

am_eval() { "$root/scripts/am-eval.sh" "$@"; }

run_sets() {
  if [[ -d "$cache/speechocean762/current" ]]; then
    am_eval sets --corpus "$cache/speechocean762/current"
  else
    echo "agreement.sh: no fetched speechocean762 (scripts/fetch-speechocean762.sh); counting from the label fixture"
    am_eval sets
  fi
}

case "$suite" in
  sets) run_sets ;;
  smoke) am_eval suite --suite smoke && am_eval smoke-detector ;;
  positive) am_eval suite --suite positive --vctk "$cache/vctk/current" ;;
  l2-shared) am_eval suite --suite l2-shared ${extra[@]+"${extra[@]}"} ;;
  all)
    status=0
    run_sets || status=1
    am_eval suite --suite smoke || status=1
    am_eval smoke-detector || status=1
    am_eval suite --suite positive --vctk "$cache/vctk/current" || status=1
    am_eval suite --suite l2-shared ${extra[@]+"${extra[@]}"} || status=1
    exit $status
    ;;
  *) echo "agreement.sh: unknown suite $suite (sets, smoke, positive, l2-shared, all)" >&2; exit 64 ;;
esac
