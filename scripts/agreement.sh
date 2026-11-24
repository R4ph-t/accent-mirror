#!/usr/bin/env bash
# The agreement harness (spec 02). Local and nightly only: PR CI runs the package tests, never this.
# Reads the corpus caches (scripts/fetch-*.sh); makes no network call.
#
#   scripts/agreement.sh                          # every suite
#   scripts/agreement.sh --suite sets             # recount the §6.3 sets (fetched corpus, else the label fixture)
#   scripts/agreement.sh --suite smoke            # smoke set: manifest, size cap, load time, placement goldens (never a rate gate)
#   scripts/agreement.sh --suite positive [--write-report]   # VCTK pairs through the pipeline (spec 12), every spec 09/10 gate
#     needs the trimmed VCTK cache and its replayed timings: scripts/am-eval.sh record-timings --set positive
#   scripts/agreement.sh --suite l2-shared [--write-report] [--release]   # shared-detector mode, reported (gate: spec 11)
#   scripts/agreement.sh --suite release          # spec 11: the release suite on the shipped config; writes
#     docs/agreement/reports/release-<configDigest8>.{json,md} (clean tree). Needs scripts/tune.sh first; measures
#     the guard on held-out data with scripts/spec11-guard.sh. Runs under nice.
#     needs the fetched corpus and its replayed timings: scripts/am-eval.sh record-timings --set l2-shared
#   scripts/agreement.sh --suite nucleus-jitter [--summary <file>]   # spec 25 acceptance 1 (.span beside .nucleus);
#     writes docs/agreement/reports/nucleus-jitter-<configDigest8>.{json,md}. Runs under nice (scripts/nucleus-jitter.sh)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"
suite=all
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite) suite="$2"; shift 2 ;;
    --write-report|--release) extra+=("$1"); shift ;;
    --summary) extra+=("$1" "$2"); shift 2 ;;
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
  positive) am_eval suite --suite positive --vctk "$cache/vctk/current" ${extra[@]+"${extra[@]}"} ;;
  l2-shared) am_eval suite --suite l2-shared ${extra[@]+"${extra[@]}"} ;;
  nucleus-jitter) "$root/scripts/nucleus-jitter.sh" ${extra[@]+"${extra[@]}"} ;;
  release)
    mkdir -p "$cache/guard"
    GUARD_LABEL=shipped nice -n 10 "$root/scripts/spec11-guard.sh" held-out "$cache/guard/held-out-shipped.json"
    nice -n 10 "$root/scripts/am-eval.sh" suite --suite release --write-report \
      --guard "$cache/guard/held-out-shipped.json" ${extra[@]+"${extra[@]}"}
    ;;
  all)
    status=0
    run_sets || status=1
    am_eval suite --suite smoke || status=1
    am_eval smoke-detector || status=1
    am_eval suite --suite positive --vctk "$cache/vctk/current" || status=1
    am_eval suite --suite l2-shared ${extra[@]+"${extra[@]}"} || status=1
    exit $status
    ;;
  *) echo "agreement.sh: unknown suite $suite (sets, smoke, positive, l2-shared, release, nucleus-jitter, all)" >&2; exit 64 ;;
esac
