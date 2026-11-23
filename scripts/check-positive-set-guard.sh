#!/usr/bin/env bash
# Fails an agreement report that reads a NOT EVALUATED positive set as a pass (spec 02, CTO ruling 2026-11-23 14:18).
#
#   scripts/check-positive-set-guard.sh <report.json>
#
# The positive set counts as evaluable only if the report's `positiveSet` and `summary.positiveSet` both say
# `evaluable`; a missing value is NOT EVALUATED (fail closed). While it is NOT EVALUATED, the report fails if:
#   - a metric line with `dependsOnPositiveSet: true` has status `pass`;
#   - a summary line says `Release gate: MET`, or a `Positive set:` line says anything but NOT EVALUATED.
# Any report fails if any string in it mentions a waiver: NOT EVALUATED is never waived.
# check-report-identity.sh runs this too. Self-test: scripts/test-check-report-identity.sh. AMEvaluationTests runs it
# on a generated report and a doctored copy, so PR CI covers it.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/check-positive-set-guard.sh <report.json>" >&2
  exit 64
fi

python3 -I - "$1" <<'PY'
import json, sys

path = sys.argv[1]
try:
    with open(path) as f:
        report = json.load(f)
except Exception as error:
    print("check-positive-set-guard: FAIL: cannot read %s (%s)" % (path, error), file=sys.stderr)
    sys.exit(1)


def evaluable(value):
    return isinstance(value, dict) and set(value) == {"evaluable"}


summary = report.get("summary") or {}
positive_ok = evaluable(report.get("positiveSet")) and (
    "positiveSet" not in summary or evaluable(summary.get("positiveSet")))


def status_of(metric):
    status = metric.get("status")
    return next(iter(status)) if isinstance(status, dict) and status else str(status)


problems = []
if not positive_ok:
    for metric in list(report.get("metrics") or []) + list(summary.get("gated") or []):
        if metric.get("dependsOnPositiveSet") is True and status_of(metric) == "pass":
            problems.append("'%s' says PASS while the positive set is NOT EVALUATED" % metric.get("name", "?"))
    for line in report.get("summaryLines") or []:
        if line.strip() == "Release gate: MET":
            problems.append("'Release gate: MET' while the positive set is NOT EVALUATED")
        if line.startswith("Positive set:") and not line.startswith("Positive set: NOT EVALUATED"):
            problems.append("'%s' while the positive set is NOT EVALUATED" % line)


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)


for text in strings(report):
    if "waive" in text.lower():
        problems.append("waiver text: '%s'" % text[:80])

if problems:
    for problem in problems:
        print("check-positive-set-guard: FAIL: " + problem, file=sys.stderr)
    sys.exit(1)
print("check-positive-set-guard: OK (%s; positive set %s)"
      % (path, "evaluable" if positive_ok else "NOT EVALUATED, no line reads as a pass"))
PY
