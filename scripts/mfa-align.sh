#!/usr/bin/env bash
# Builds the spec 03 word-boundary baseline: Montreal Forced Aligner word alignments of the evaluation clips
# (Open question 5 default), written to fixtures/vctk/mfa-word-baseline.json. Its SHA-256 is the report's label hash.
# Needs scripts/fetch-vctk.sh and scripts/setup-mfa.sh first. Offline tooling only: never in the app or CI.
#
#   scripts/mfa-align.sh [clips-file]   # default: fixtures/vctk/starter-clips.txt
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
clips="${1:-$root/fixtures/vctk/starter-clips.txt}"
corpus="${VCTK_CACHE:-$root/.cache/vctk}/VCTK-Corpus-0.92"
mfa_home="${MFA_CACHE:-$root/.cache/mfa}"
out="${BASELINE_OUT:-$root/fixtures/vctk/mfa-word-baseline.json}"
mfa="$mfa_home/env/bin/mfa"
export MFA_ROOT_DIR="$mfa_home/root"
export PATH="$mfa_home/env/bin:$PATH"   # MFA calls the OpenFst and Kaldi binaries of its environment

[[ -x "$mfa" ]] || { echo "mfa-align: MFA is not installed; run scripts/setup-mfa.sh" >&2; exit 1; }
"$root/scripts/setup-mfa.sh" > /dev/null   # re-checks the pinned versions and model digests

# MFA's input: one folder per speaker, each clip's official audio next to its official transcript (.lab).
work="$mfa_home/work"
rm -rf "$work"
mkdir -p "$work/corpus" "$work/aligned"
while IFS= read -r clip; do
  [[ -z "$clip" || "$clip" == \#* ]] && continue
  speaker="${clip%%_*}"
  mkdir -p "$work/corpus/$speaker"
  ln -s "$corpus/wav48_silence_trimmed/$speaker/${clip}_mic1.flac" "$work/corpus/$speaker/$clip.flac"
  cp "$corpus/txt/$speaker/$clip.txt" "$work/corpus/$speaker/$clip.lab"
done < "$clips"

command=(mfa align --clean --overwrite --output_format json --num_jobs 4
         CORPUS english_mfa.dict english_mfa.zip OUTPUT)
"$mfa" align --clean --overwrite --output_format json --num_jobs 4 \
  "$work/corpus" "$mfa_home/models/english_mfa.dict" "$mfa_home/models/english_mfa.zip" "$work/aligned"

"$root/scripts/am-timestamps.sh" baseline \
  --clips "$clips" --mfa-output "$work/aligned" --out "$out" \
  --mfa-version "$("$mfa" version)" \
  --acoustic-model "$mfa_home/models/english_mfa.zip" --dictionary "$mfa_home/models/english_mfa.dict" \
  --command "${command[*]}"
