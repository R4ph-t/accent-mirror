#!/usr/bin/env bash
# Spec 23, CTO review: the reference sanity check. Synthesises each eval phrase once with a pinned on-device voice and
# SSML <mark> bookmarks around every word, aligns the audio with the baseline's own aligner (MFA 3.4.4, english_mfa
# v3.1.0, through scripts/mfa-align.sh), and writes MFA's own error per side to .cache/reference/reference-check.json.
# A labelled line in the word-boundary report, never a gate. Local tooling: it fetches nothing, writes no audio into
# git, and skips cleanly (exit 0, writing reference-check.json.skipped) when the voice or MFA is missing.
#
#   scripts/reference-check.sh
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
voice="${REFERENCE_VOICE:-com.apple.voice.compact.en-US.Samantha}"
out="$root/.cache/reference"
mfa_home="${MFA_CACHE:-$root/.cache/mfa}"
result="$out/reference-check.json"

skip() {
  mkdir -p "$out"
  rm -f "$result"
  printf '%s\n' "$1" > "$result.skipped"
  echo "reference-check: SKIPPED, $1"
  exit 0
}

[[ -x "$mfa_home/env/bin/mfa" && -f "$mfa_home/models/english_mfa.zip" && -f "$mfa_home/models/english_mfa.dict" ]] \
  || skip "MFA is not installed in ${mfa_home#"$root"/} (scripts/setup-mfa.sh)"

status=0
"$root/scripts/am-timestamps.sh" tts-reference \
  --clips "$root/fixtures/vctk/starter-clips.txt" \
  --corpus "${VCTK_CACHE:-$root/.cache/vctk}/VCTK-Corpus-0.92" \
  --files-pin "$root/fixtures/vctk/vctk-0.92-clips.sha256" \
  --voice "$voice" --out "$out" || status=$?
[[ "$status" == 3 ]] && skip "voice $voice is not installed on this Mac"
[[ "$status" == 0 ]] || exit "$status"

MFA_INPUT_CORPUS="$out/corpus" MFA_WORK="$out/mfa-work" BASELINE_OUT="$out/mfa-alignment.json" \
  "$root/scripts/mfa-align.sh" "$out/clips.txt"
"$root/scripts/am-timestamps.sh" reference-compare \
  --markers "$out/markers.json" --baseline "$out/mfa-alignment.json" --out "$result"
rm -f "$result.skipped"
