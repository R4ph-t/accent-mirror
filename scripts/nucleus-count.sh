#!/usr/bin/env bash
# Spec 26 §1: the nucleus count grid on the VCTK tuning speakers only (detection truth: MFA words and phones, N_w; no
# verdict, flip or held-out number). Prints the grid table (count-match, vowel-inside, IoU, feasible) and the chosen
# point, writes docs/agreement/reports/nucleus-count-<configDigest8>.{json,md} and the tuning-log entry's text.
#
#   scripts/nucleus-count.sh [--tuning-log <entry.md>] [--lag real|offset-fixed]
#
# Env: AM_EVAL_CACHE (needs guard/tuning/{inputs.json,mfa-work/aligned/} from spec 11's guard). Never runs MFA: a
# missing input stops the script. §1a found a real pYIN lag, so the default grid is voicedWithinMs ∈ {0, 30, 60}.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${AM_EVAL_CACHE:-$root/eval-cache}"
work="$cache/guard/tuning"
for f in "$work/inputs.json" "$work/mfa-work/aligned"; do
  [[ -e "$f" ]] || { echo "nucleus-count: missing $f (no MFA run here: the tuning-speaker MFA outputs come from spec 11's guard)" >&2; exit 1; }
done
nice -n 10 "$root/scripts/am-eval.sh" nucleus-count --inputs "$work/inputs.json" --mfa "$work/mfa-work/aligned" \
  --write-report "$@"
