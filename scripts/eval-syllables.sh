#!/usr/bin/env bash
# Spec 07, optional and local: writes docs/agreement/reports/syllable-boundaries-<configDigest8>.{json,md}. The
# real-speech lines (speechocean762 recall, VCTK false positives, the MFA syllable-boundary bar) print NOT EVALUATED
# (waiting on spec 23) until spec 23 ships a refiner; NOT EVALUATED is never a pass. Fetches nothing, and runs with
# networking denied by the macOS sandbox. Never run by CI or `make check`.
#
#   scripts/eval-syllables.sh          # report under docs/agreement/reports/
#   scripts/eval-syllables.sh --dev    # report under .cache/reports/
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
package="$root/Packages/AccentKit"
out="$root/docs/agreement/reports"
[[ "${1:-}" == "--dev" ]] && out="$root/.cache/reports"

swift build -c release --package-path "$package" --product am-syllables >&2
bin="$(swift build -c release --package-path "$package" --show-bin-path)/am-syllables"
exec sandbox-exec -p '(version 1)(allow default)(deny network*)' "$bin" report --repo "$root" --out "$out"
