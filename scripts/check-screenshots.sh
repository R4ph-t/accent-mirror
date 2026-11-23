#!/usr/bin/env bash
# Blank-frame and size check for the UI-shell screenshots (spec 19). Local only; not part of `make check` or CI.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
swift scripts/check-screenshots.swift "${1:-screenshots/ui-shell}"
