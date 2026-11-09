#!/bin/zsh
# Landing page screenshots from the real app with made-up data.
# Builds the app (Debug, unsigned so it may write into the output folder),
# runs it with --screenshots, and captures every window the app's tour
# announces with `screencapture -l`. Details: docs/DEMO_MODE.md.
#
#   scripts/screenshots.sh [output-dir]   (default: docs/resources/index)
#   scripts/screenshots.sh --demo         just open the demo, no captures
#
# The terminal running this needs Screen Recording permission. The demo
# doesn't watch the clipboard, register hotkeys or touch the real history,
# so the installed app can keep running.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=build/DemoDD
APP="$DERIVED/Build/Products/Debug/StoneClipboarderTool.app"
BIN="$APP/Contents/MacOS/StoneClipboarderTool"

echo "Building the demo app…"
xcodebuild -project StoneClipboarderTool.xcodeproj -scheme StoneClipboarderTool -configuration Debug \
    -destination "platform=macOS" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build -quiet

# A Debug build writes coverage data (default.profraw) into the working
# directory when it exits; send it nowhere.
export LLVM_PROFILE_FILE=/dev/null

if [[ "${1:-}" == "--demo" ]]; then
    exec "$BIN" --demo
fi

OUT="${1:-docs/resources/index}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# Capture every window the tour announces (<name>.wid holds its number).
(
    set +e  # a request can vanish between the glob and the read
    while true; do
        for request in "$OUT"/*.wid(N); do
            png="${request%.wid}"
            [[ -f "$png" ]] && continue
            window_id=$(cat "$request" 2>/dev/null) || continue
            screencapture -x -o -l "$window_id" "$png" 2>/dev/null || echo "Could not capture $(basename "$png") (Screen Recording?)" >&2
        done
        sleep 0.2
    done
) &
watcher=$!
trap 'kill $watcher 2>/dev/null || true' EXIT

echo "Running the screenshot tour (about a minute; windows will appear)…"
"$BIN" --screenshots "$OUT" >/dev/null 2>&1
echo "Screenshots in $OUT:"
ls -1 "$OUT"/sct-*.png
