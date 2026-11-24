#!/usr/bin/env bash
# Spec 22: text-to-speech is evaluation tooling only (tools/SynthRef). The app target and AccentKit's sources never
# reference the TTS tool, AVSpeechSynthesizer, ElevenLabs' host, its API-key header or its key variable.
# AccentKit's tests are not scanned: spec 07's TTS marker gate renders a pinned system voice there.
# Usage: check-no-tts-in-app.sh [--root <dir>]   (default: the repository root)
set -euo pipefail
root=""
if [[ "${1:-}" == "--root" ]]; then root="${2:?--root needs a directory}"; fi
if [[ -z "$root" ]]; then root="$(git rev-parse --show-toplevel)"; fi
cd "$root"

paths=()
for p in AccentMirror Packages/AccentKit/Sources Packages/AccentKit/Package.swift project.yml; do
  [[ -e "$p" ]] && paths+=("$p")
done
if [[ ${#paths[@]} -eq 0 ]]; then
  echo "check-no-tts-in-app: nothing to scan under $root" >&2
  exit 2
fi

# AVSpeechSynthesi: AVSpeechSynthesizer, AVSpeechSynthesisVoice, AVSpeechSynthesisMarker.
# elevenlabs.io: ElevenLabs' host. xi-api-key / ELEVENLABS_API_KEY: its key header and variable.
# SynthRef: the TTS tool's package and modules.
pattern='AVSpeechSynthesi|elevenlabs\.io|xi-api-key|ELEVENLABS_API_KEY|SynthRef'
if grep -rnIiE "$pattern" "${paths[@]}"; then
  echo "check-no-tts-in-app: TTS stays in tools/SynthRef; the app and AccentKit must not reference it (spec 22)." >&2
  exit 1
fi
echo "check-no-tts-in-app: OK, no TTS engine, ElevenLabs host or key, or SynthRef reference in the app or AccentKit."
