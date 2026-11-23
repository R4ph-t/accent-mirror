#!/usr/bin/env bash
# Checks an agreement report can stand for a release (spec 02, plan §6.6).
#
#   scripts/check-report-identity.sh <report.json> <release-commit>
#   scripts/check-report-identity.sh --tree-hash <commit>     # print sourceTreeHash (used by the self-test)
#
# Passes only if:
#   - the report came from a clean tree;
#   - sourceTreeHash recomputed at the evaluated commit, and at the release commit, both equal the report's
#     (sourceTreeHash: SHA-256 of `git ls-tree -r --full-tree <commit>`, lines under docs/agreement/reports/ removed,
#     the rest sorted by byte value, each followed by a newline; the same definition as AMEvaluation.ReportHashes);
#   - the release commit is the evaluated commit or a descendant whose `git diff --name-only <evaluated>..<release>`
#     touches only docs/agreement/reports/;
#   - the report is under 7 days old.
# Self-test: scripts/test-check-report-identity.sh.
set -euo pipefail

reports_prefix="docs/agreement/reports/"

tree_hash() { # commit
  git ls-tree -r --full-tree "$1" \
    | awk -F '\t' -v prefix="$reports_prefix" 'index($2, prefix) != 1' \
    | LC_ALL=C sort \
    | shasum -a 256 | cut -d ' ' -f 1
}

if [[ "${1:-}" == "--tree-hash" ]]; then
  tree_hash "$2"
  exit 0
fi

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/check-report-identity.sh <report.json> <release-commit>" >&2
  exit 64
fi
report="$1"
release="$(git rev-parse --verify "$2^{commit}")"

fail() { echo "check-report-identity: FAIL: $1" >&2; exit 1; }

fields="$(python3 -I - "$report" <<'PY'
import datetime, json, sys
r = json.load(open(sys.argv[1]))
i = r["identity"]
generated = datetime.datetime.strptime(r["generatedAt"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
age = (datetime.datetime.now(datetime.timezone.utc) - generated).total_seconds()
print(i["evaluatedCommit"], i["sourceTreeHash"], "clean" if i["cleanTree"] else "dirty", int(age))
PY
)" || fail "cannot read $report"
read -r evaluated recorded clean age <<<"$fields"

[[ "$clean" == clean ]] || fail "the report was written from a dirty tree"
git cat-file -e "$evaluated^{commit}" 2>/dev/null || fail "evaluated commit $evaluated is not in this repository"
[[ "$(tree_hash "$evaluated")" == "$recorded" ]] || fail "sourceTreeHash does not match the evaluated commit $evaluated"
[[ "$(tree_hash "$release")" == "$recorded" ]] || fail "sourceTreeHash does not match the release commit $release"
git merge-base --is-ancestor "$evaluated" "$release" || fail "release $release does not descend from $evaluated"
changed="$(git diff --name-only "$evaluated..$release" | grep -v "^$reports_prefix" || true)"
[[ -z "$changed" ]] || fail "the release changes files outside $reports_prefix since $evaluated: $(echo $changed)"
(( age >= 0 && age < 7 * 24 * 3600 )) || fail "the report is $((age / 86400)) days old (limit 7)"

echo "check-report-identity: OK ($report valid for $release)"
