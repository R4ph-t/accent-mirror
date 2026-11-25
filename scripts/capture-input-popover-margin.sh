#!/usr/bin/env bash
# On-screen light+dark captures of the Input popover (real NSPopover, system arrow):
#   (1) 1200 wide, mid-screen — arrow on Input, body may overhang the window edge
#   (2) 1068 wide, inspector open — same
#   (3) 1200 wide, window against the screen’s right edge — system clamp keeps the popover on screen
# Writes PNGs (no '@' in names) and measures.txt (arrow tip x vs Input centre, popover vs window and screen).
#
# Uses a *copy* of the test host with a distinct bundle id, so it does not launch, quit, or replace
# the installed Accent Mirror app. This takes over the screen for a few seconds. For Raph to run, not an agent.
#
#   scripts/capture-input-popover-margin.sh
# Optional: OUTPUT_DIR=/path/to/folder scripts/capture-input-popover-margin.sh
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  cd "$(git rev-parse --show-toplevel)"
else
  cd "$(dirname "$0")/.."
fi

command -v xcodegen >/dev/null || { echo "xcodegen is missing: brew install xcodegen" >&2; exit 1; }
xcodegen generate

DERIVED="${DERIVED:-.build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-${TMPDIR:-/tmp}am-input-popover-nspopover}"
CACHE="${CACHE_DIR:-$HOME/dev/accent-mirror-wt/_cache-input-popover}"
HOST_COPY="$CACHE/AccentMirror-popovercapture.app"
RUN="$CACHE/popovercapture.xctestrun"
BUNDLE_ID="com.raphaelterrier.accentmirror.popovercapture"
INSTALLED_APP="${AM_INSTALLED_APP:-$HOME/Applications/Accent Mirror.app}"

mkdir -p "$DERIVED" "$CACHE" "$OUTPUT_DIR"

xcodebuild -project AccentMirror.xcodeproj -scheme AccentMirrorScreenshots \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build-for-testing

SRC="$DERIVED/Build/Products/Debug/AccentMirror.app"
XCTRUN="$(ls -1 "$DERIVED"/Build/Products/*AccentMirrorScreenshots*.xctestrun | head -n 1)"
if [[ ! -d "$SRC" || ! -f "$XCTRUN" ]]; then
  echo "build-for-testing did not produce a test host and xctestrun" >&2
  exit 1
fi

rm -rf "$HOST_COPY"
ditto "$SRC" "$HOST_COPY"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$HOST_COPY/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName AccentMirror-popovercapture" "$HOST_COPY/Contents/Info.plist" 2>/dev/null || true

python3 - "$XCTRUN" "$RUN" "$HOST_COPY" "$BUNDLE_ID" << 'PY'
import plistlib, sys
from pathlib import Path
src, dest, host, bundle = sys.argv[1:5]
data = plistlib.loads(Path(src).read_bytes())
def walk(obj):
    if isinstance(obj, dict):
        if "TestHostPath" in obj:
            obj["TestHostPath"] = host
        if "TestHostBundleIdentifier" in obj:
            obj["TestHostBundleIdentifier"] = bundle
        for v in obj.values():
            walk(v)
    elif isinstance(obj, list):
        for v in obj:
            walk(v)
walk(data)
Path(dest).write_bytes(plistlib.dumps(data))
PY

# If build-for-testing registered the DerivedData app under the product bundle id, point Launch
# Services back at the installed app without launching it.
if [[ -d "$INSTALLED_APP" ]]; then
  /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$INSTALLED_APP"
fi

AML_ONSCREEN_CAPTURE=1 AML_RENDER_DIR="$OUTPUT_DIR" \
  xcodebuild test-without-building -xctestrun "$RUN" -destination 'platform=macOS' \
  -only-testing:AccentMirrorScreenshots/InputPopoverMarginCaptureTests

echo "Captures written to $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
