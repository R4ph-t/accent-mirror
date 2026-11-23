#!/usr/bin/env bash
# Builds and runs the spec 03 tool (`am-timestamps`, release build) with networking denied by the macOS sandbox, so
# ASR provably runs from local files only. Local tooling: never run by the app, CI or `make check`.
#
#   scripts/am-timestamps.sh <command> [options]   # see `am-timestamps` for commands
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
package="$root/Packages/AccentKit"
swift build -c release --package-path "$package" --product am-timestamps >&2
bin="$(swift build -c release --package-path "$package" --show-bin-path)/am-timestamps"
exec sandbox-exec -p '(version 1)(allow default)(deny network*)' "$bin" "$@"
