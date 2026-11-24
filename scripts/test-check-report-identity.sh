#!/usr/bin/env bash
# Self-test for check-report-identity.sh, in throwaway git repos: a good report passes; a non-report file changed in
# the descendant, a tampered hash, a dirty-tree report, an old report and a non-descendant release each fail. Then
# check-positive-set-guard.sh on doctored fixtures: a dependent PASS, `Release gate: MET` or a waiver while the
# positive set is NOT EVALUATED each fail.
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

# The positive-set guard (check-positive-set-guard.sh), on doctored report fixtures.
guard="$(cd "$(dirname "$0")" && pwd)/check-positive-set-guard.sh"
blocked='{"blocked": {"on": "spec 24", "reason": "phrases 15 < 18"}}'
not_evaluated='{"notEvaluated": {"shortfalls": ["phrases 15 < 18"], "blockedOn": "spec 24"}}'
fixture() { # file, positiveSet, dependent line's status, release line, [note], [positive-set line]
  cat > "$1" <<JSON
{"generatedAt": "$now", "positiveSet": $2,
 "metrics": [{"name": "Any-diff pairs (spec 10)", "dependsOnPositiveSet": true, "status": $3},
             {"name": "L2 recall", "status": {"pass": {}}}],
 "summary": {"positiveSet": $2, "gated": []},
 "summaryLines": ["Negative set: NOT EVALUATED", "${6:-Positive set: NOT EVALUATED (blocked on spec 24: phrases 15 < 18)}", "$4"],
 "notes": ["${5:-positive set: NOT EVALUATED}"]}
JSON
}
expect_guard() { # pass|fail, description, file
  if "$guard" "$3" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$1" ]]; then echo "ok   $2"; else echo "FAIL $2 (got $got)"; failures=$((failures + 1)); fi
}
fixture "$tmp/g-ok.json" "$not_evaluated" "$blocked" "Release gate: NOT MET"
expect_guard pass "guard: positive set NOT EVALUATED, every dependent line NOT EVALUATED" "$tmp/g-ok.json"
fixture "$tmp/g-pass.json" "$not_evaluated" '{"pass": {}}' "Release gate: NOT MET"
expect_guard fail "guard: doctored dependent line says PASS while the positive set is NOT EVALUATED" "$tmp/g-pass.json"
fixture "$tmp/g-met.json" "$not_evaluated" "$blocked" "Release gate: MET"
expect_guard fail "guard: doctored Release gate: MET while the positive set is NOT EVALUATED" "$tmp/g-met.json"
fixture "$tmp/g-line.json" "$not_evaluated" "$blocked" "Release gate: NOT MET" "" "Positive set: PASS"
expect_guard fail "guard: doctored Positive set: PASS line" "$tmp/g-line.json"
fixture "$tmp/g-missing.json" "null" '{"pass": {}}' "Release gate: NOT MET"
expect_guard fail "guard: no positiveSet recorded and a dependent PASS (fail closed)" "$tmp/g-missing.json"
fixture "$tmp/g-waiver.json" "$not_evaluated" "$blocked" "Release gate: NOT MET" "positive set waived until spec 24"
expect_guard fail "guard: a waiver line" "$tmp/g-waiver.json"
fixture "$tmp/g-evaluable.json" '{"evaluable": {}}' '{"pass": {}}' "Release gate: NOT MET" "" "Positive set: EVALUABLE"
expect_guard pass "guard: positive set evaluable, a dependent PASS is allowed" "$tmp/g-evaluable.json"

d=$(repo guarded); c=$(git -C "$d" rev-parse HEAD)
fixture "$tmp/g-identity.json" "$not_evaluated" '{"pass": {}}' "Release gate: NOT MET"
python3 -I -c '
import json, sys
src, dst, commit, tree = sys.argv[1:]
r = json.load(open(src))
r["identity"] = {"evaluatedCommit": commit, "sourceTreeHash": tree, "cleanTree": True}
json.dump(r, open(dst, "w"))
' "$tmp/g-identity.json" "$d/docs/agreement/reports/l2-shared-12345678.json" "$c" "$(cd "$d" && "$check" --tree-hash "$c")"
git -C "$d" add -A && git -C "$d" commit -qm report
expect fail "check-report-identity fails a doctored report whose dependent line says PASS" "$d"

if [[ $failures -gt 0 ]]; then echo "test-check-report-identity: $failures failure(s)"; exit 1; fi
echo "test-check-report-identity: all passed"
