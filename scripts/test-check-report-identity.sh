#!/usr/bin/env bash
# Self-test for check-report-identity.sh, in throwaway git repos: a good report passes; a non-report file changed in
# the descendant, a tampered hash, a dirty-tree report, an old report and a non-descendant release each fail.
set -euo pipefail

check="$(cd "$(dirname "$0")" && pwd)/check-report-identity.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

repo() { # name -> path of a repo with one source commit
  local dir="$tmp/$1"
  mkdir -p "$dir/src" "$dir/docs/agreement/reports"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name test
  echo a > "$dir/src/a.swift"
  echo old > "$dir/docs/agreement/reports/old-00000000.json"
  git -C "$dir" add -A && git -C "$dir" commit -qm source
  echo "$dir"
}

report() { # repo, commit, clean(true|false), generatedAt, [hash]
  local hash="${5:-$(cd "$1" && "$check" --tree-hash "$2")}"
  cat > "$1/docs/agreement/reports/l2-shared-12345678.json" <<JSON
{"generatedAt": "$4", "identity": {"evaluatedCommit": "$2", "sourceTreeHash": "$hash", "cleanTree": $3}}
JSON
  git -C "$1" add -A && git -C "$1" commit -qm report
}

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
old="$(date -u -v-8d +%Y-%m-%dT%H:%M:%SZ)"

expect() { # pass|fail, description, repo
  local want="$1" what="$2" dir="$3"
  if (cd "$dir" && "$check" docs/agreement/reports/l2-shared-12345678.json HEAD >/dev/null 2>&1); then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then echo "ok   $what"; else echo "FAIL $what (got $got)"; failures=$((failures + 1)); fi
}

d=$(repo good); report "$d" "$(git -C "$d" rev-parse HEAD)" true "$now"
expect pass "report committed in a descendant that touches only reports" "$d"

d=$(repo same); c=$(git -C "$d" rev-parse HEAD)
cat > "$d/r.json" <<JSON
{"generatedAt": "$now", "identity": {"evaluatedCommit": "$c", "sourceTreeHash": "$(cd "$d" && "$check" --tree-hash "$c")", "cleanTree": true}}
JSON
if (cd "$d" && "$check" r.json "$c" >/dev/null 2>&1); then echo "ok   release is the evaluated commit"; else echo "FAIL release is the evaluated commit"; failures=$((failures + 1)); fi

d=$(repo nonreport); report "$d" "$(git -C "$d" rev-parse HEAD)" true "$now"
echo b > "$d/src/a.swift"; git -C "$d" commit -qam "source change"
expect fail "a non-report file changed in the descendant" "$d"

d=$(repo tampered); report "$d" "$(git -C "$d" rev-parse HEAD)" true "$now" "$(printf '0%.0s' {1..64})"
expect fail "a tampered sourceTreeHash" "$d"

d=$(repo dirty); report "$d" "$(git -C "$d" rev-parse HEAD)" false "$now"
expect fail "a report from a dirty tree" "$d"

d=$(repo stale); report "$d" "$(git -C "$d" rev-parse HEAD)" true "$old"
expect fail "a report older than 7 days" "$d"

d=$(repo branch); base=$(git -C "$d" rev-parse HEAD)
echo c > "$d/src/c.swift"; git -C "$d" add -A; git -C "$d" commit -qm side; side=$(git -C "$d" rev-parse HEAD)
git -C "$d" checkout -q "$base"; git -C "$d" checkout -qb release
report "$d" "$side" true "$now"
expect fail "a release that does not descend from the evaluated commit" "$d"

if [[ $failures -gt 0 ]]; then echo "test-check-report-identity: $failures failure(s)"; exit 1; fi
echo "test-check-report-identity: all passed"
