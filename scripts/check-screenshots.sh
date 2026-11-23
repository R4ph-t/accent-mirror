#!/usr/bin/env bash
# Blank-frame and size check for the UI-shell screenshots (spec 19). Local only; not part of `make check` or CI.
set -euo pipefail
# Run from the repo root when inside a work tree. The test VM's synced copy has no usable git metadata, so there
# it runs from the script's parent folder instead of printing "fatal: not a git repository".
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  cd "$(git rev-parse --show-toplevel)"
else
  cd "$(dirname "$0")/.."
fi
swift scripts/check-screenshots.swift "${1:-screenshots/ui-shell}"
