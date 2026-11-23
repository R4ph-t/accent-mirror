#!/usr/bin/env bash
# Fails if a local-only or non-commercial corpus is tracked by git.
# Those corpora (Common Voice, Speech Accent Archive, ...) live only under the
# git-ignored eval-local/ (AGENTS.md, "Data"). Run from anywhere inside the repo.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

pattern='(^|/)eval-local/|(^|/)[^/]*(common[-_ ]?voice|cv-corpus|speech[-_ ]?accent[-_ ]?archive|accent[-_ ]?archive)[^/]*(/|$)'

offending=$(git ls-files | grep -iE "$pattern" || true)

if [[ -n "$offending" ]]; then
  echo "check-local-corpus: these tracked files belong to a local-only corpus; remove them from git:" >&2
  echo "$offending" | sed 's/^/  /' >&2
  exit 1
fi

echo "check-local-corpus: OK, no local-only corpus files tracked."
