#!/usr/bin/env bash
# AccentKit stays platform-neutral: no AppKit or UIKit imports in the package.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if grep -rnE '^\s*(@preconcurrency\s+)?import\s+(AppKit|UIKit)\b' Packages/AccentKit/Sources Packages/AccentKit/Tests; then
  echo "check-no-ui-frameworks: AccentKit must not import AppKit or UIKit (see AGENTS.md)." >&2
  exit 1
fi
echo "check-no-ui-frameworks: OK, AccentKit imports neither AppKit nor UIKit."
