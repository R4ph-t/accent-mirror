#!/usr/bin/env bash
# Builds (release, quietly) and runs am-eval, the agreement harness's runner. Used by the other harness scripts.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$root/Packages/AccentKit" -c release --product am-eval >/dev/null \
  || { echo "am-eval: build failed (swift build --package-path Packages/AccentKit --product am-eval)" >&2; exit 1; }
cd "$root"
exec "$root/Packages/AccentKit/.build/release/am-eval" "$@"
