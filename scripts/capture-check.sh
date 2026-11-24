#!/usr/bin/env bash
# Spec 14 hand check, on the Mac only (never CI): records one take from the default microphone (or --device <id>; see
# --list) and prints the start latency (budget 100 ms), t_onset, the stop reason and the take's TakeAnalysis. Saves
# nothing. With microphone access denied in System Settings it prints micDenied. Exits 2 when start took over 100 ms.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$root/Packages/AccentKit" -c release --product am-capture >/dev/null \
  || { echo "am-capture: build failed (swift build --package-path Packages/AccentKit --product am-capture)" >&2; exit 1; }
exec "$root/Packages/AccentKit/.build/release/am-capture" "$@"
