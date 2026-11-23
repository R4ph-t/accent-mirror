#!/usr/bin/env bash
# Spec 04, Open question 1: pyin-1 against Praat's autocorrelation pitch on three real clips (low, mid and high
# voice), on frames both call voiced. Local only, never part of `make check` or CI.
#
# Pass per clip: gross pitch error (more than 20% off Praat) under 5% of frames both call voiced, and voicing
# agreement at least 90% of frames. A FAIL goes to CTO; thresholds are not changed to pass.
#
# Clips: AM_PITCH_CLIPS="low=<wav> mid=<wav> high=<wav>", else eval-cache/pitch-clips/{low,mid,high}.wav (pick them
# from spec 02's VCTK cache). Praat: $PRAAT, else `praat` on PATH, else /Applications/Praat.app.
# Prints the table and a last line starting "pitch real clips:". Exit 0 PASS, 1 FAIL, 2 NOT EVALUATED (not a pass).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

not_evaluated() {
  echo "pitch real clips: NOT EVALUATED ($1)"
  exit 2
}

praat="${PRAAT:-}"
if [[ -z "$praat" ]]; then
  if command -v praat >/dev/null 2>&1; then praat=$(command -v praat)
  elif [[ -x /Applications/Praat.app/Contents/MacOS/Praat ]]; then praat=/Applications/Praat.app/Contents/MacOS/Praat
  fi
fi
[[ -n "$praat" && -x "$praat" ]] || not_evaluated "Praat not found: set PRAAT or install Praat"
praat_version=$("$praat" --version 2>/dev/null | head -1)
[[ -n "$praat_version" ]] || praat_version="unknown"

clips="${AM_PITCH_CLIPS:-low=eval-cache/pitch-clips/low.wav mid=eval-cache/pitch-clips/mid.wav high=eval-cache/pitch-clips/high.wav}"

work=$(mktemp -d "${TMPDIR:-/tmp}/pitch-real-clips.XXXXXX")
trap 'rm -rf "$work"' EXIT
manifest="$work/manifest.tsv"
: >"$manifest"
for entry in $clips; do
  label="${entry%%=*}"
  wav="${entry#*=}"
  [[ -f "$wav" ]] || not_evaluated "clip '$label' missing: $wav"
  wav_abs="$(cd "$(dirname "$wav")" && pwd)/$(basename "$wav")"
  out="$work/$label.praat.txt"
  wav16k="$work/$label.16k.wav"
  "$praat" --run scripts/pitch-real-clips.praat "$wav_abs" "$wav16k" "$out" >/dev/null 2>"$work/$label.praat.err" \
    || not_evaluated "Praat failed on '$label': $(head -1 "$work/$label.praat.err")"
  printf '%s\t%s\t%s\n' "$label" "$wav16k" "$out" >>"$manifest"
done
[[ $(wc -l <"$manifest") -eq 3 ]] || not_evaluated "need exactly three clips (low, mid, high)"

echo "Praat: $praat_version"
log="$work/swift-test.log"
AM_PITCH_REAL_CLIPS_MANIFEST="$manifest" swift test --package-path Packages/AccentKit \
  --filter RealClipComparison >"$log" 2>&1
grep -E '^(clip|----|low|mid|high|[A-Za-z0-9_-]+ +\|)' "$log" | grep -F '|' || true
verdict=$(grep -E '^pitch real clips: (PASS|FAIL)' "$log" | tail -1)
[[ -n "$verdict" ]] || { tail -20 "$log"; not_evaluated "the comparison did not run"; }
echo "$verdict"
[[ "$verdict" == "pitch real clips: PASS"* ]] && exit 0 || exit 1
