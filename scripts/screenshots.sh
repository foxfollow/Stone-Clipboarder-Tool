#!/bin/zsh
# Renders the landing page screenshots (docs/resources/index/sct-*.png) from
# the app's real views with made-up data (StoneClipboarderToolTests/
# LandingScreenshots.swift). The test shows each view in a window behind the
# others; this script captures that window with `screencapture -l`, so the
# terminal running it needs Screen Recording permission. Without it the test
# draws the layer tree instead (small artifacts on rounded outlines).
#
#   scripts/screenshots.sh [output-dir]   (default: docs/resources/index)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-docs/resources/index}"
OUT="$(cd "$OUT" && pwd)"

# Capture every window the test announces until it finishes.
(
    set +e  # a request can vanish between the glob and the read
    while true; do
        for request in "$OUT"/*.wid(N); do
            png="${request%.wid}"
            [[ -f "$png" ]] && continue
            window_id=$(cat "$request" 2>/dev/null) || continue
            screencapture -x -o -l "$window_id" "$png" 2>/dev/null
        done
        sleep 0.2
    done
) &
watcher=$!
trap 'kill $watcher 2>/dev/null || true' EXIT

TEST_RUNNER_STONE_SCREENSHOTS_DIR="$OUT" TEST_RUNNER_STONE_SCREENSHOTS_EXTERNAL=1 \
    xcodebuild test -project StoneClipboarderTool.xcodeproj -scheme StoneClipboarderTool \
    -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO -derivedDataPath build/ScreenshotsDD \
    -only-testing:StoneClipboarderToolTests/LandingScreenshots -quiet
echo "Screenshots in $OUT"
