#!/usr/bin/env bash
# Spec 12's latency bench: L_stop, L_speech and the L2 recompute for 3, 15 and 20 s takes (10 runs each, median and
# max, the limiting stage), PASS or FAIL against each budget. Local only: it runs the real WhisperKit model warm
# (fetched by scripts/fetch-models.sh; MODELS_CACHE overrides .cache/models). Never CI. No network.
#
#   scripts/bench.sh [--runs <n>] [--model-dir <dir>]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
exec "$root/scripts/am-eval.sh" bench "$@"
