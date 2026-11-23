#!/usr/bin/env bash
# The tuning runner (spec 02, plan §2): the fixed grid and the selection rule, on cached L1 features. Local only,
# never in PR CI. The objective needs spec 08's detector, so until then this prints the grid and exits 2 (NOT RUN).
# Re-tunes are logged in docs/agreement/tuning-log.md.
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/am-eval.sh" tune "$@"
