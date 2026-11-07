#!/bin/bash
# Local builds for testing. Not used by CI (.github/workflows/release.yml).
#
#   scripts/local-build.sh release   Release build, Xcode signing, into the
#                                    default DerivedData Build/Products/Release
#   scripts/local-build.sh run       release, quit the running copy, open it
#   scripts/local-build.sh install   CI-style build (unsigned, then ad-hoc
#                                    signed), replace /Applications/<app>, open
#   scripts/local-build.sh path      print the DerivedData Release .app path
#
# The two builds keep separate data (see AGENTS.md "Sandbox differs"):
#   release/run  signed with entitlements → sandboxed, history in
#                ~/Library/Containers/d3f0ld.StoneClipboarderTool/
#   install      ad-hoc, no entitlements → not sandboxed, the same history as
#                the app installed from a GitHub release. Every ad-hoc build
#                has a new signature, so macOS asks for Accessibility again.
#
# Env: INSTALL_DIR (default /Applications), NO_OPEN=1 to skip launching.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT=StoneClipboarderTool.xcodeproj
SCHEME=StoneClipboarderTool
APP_NAME=StoneClipboarderTool.app
PROCESS_NAME=StoneClipboarderTool
BUNDLE_ID=d3f0ld.StoneClipboarderTool
INSTALL_DIR=${INSTALL_DIR:-/Applications}
LOCAL_DERIVED_DATA=build/DerivedData

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

release_products_dir() {
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -showBuildSettings 2>/dev/null |
        awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = /{ print $2; exit }'
}

release_app_path() {
    local dir
    dir=$(release_products_dir)
    [[ -n "$dir" ]] || fail "couldn't read BUILT_PRODUCTS_DIR from xcodebuild"
    echo "$dir/$APP_NAME"
}

build_release() {
    log "Building Release (Xcode signing) …"
    xcodebuild build -quiet \
        -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -destination "platform=macOS"
    local app
    app=$(release_app_path)
    [[ -d "$app" ]] || fail "build finished but $app is missing"
    log "Built $app"
}

# Quits every running copy (installed or built) and waits for it to exit.
quit_running() {
    pgrep -x "$PROCESS_NAME" >/dev/null || return 0
    log "Quitting the running $PROCESS_NAME …"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 50); do
        pgrep -x "$PROCESS_NAME" >/dev/null || return 0
        sleep 0.1
    done
    log "Still running after 5 s, sending SIGTERM"
    pkill -x "$PROCESS_NAME" || true
    sleep 0.5
}

launch() {
    [[ "${NO_OPEN:-0}" == 1 ]] && return 0
    log "Opening $1"
    # -n: LaunchServices would otherwise just activate a copy with the same
    # bundle id that is still shutting down.
    open -n "$1"
}

cmd_install() {
    log "Building Release like CI (unsigned) …"
    xcodebuild build -quiet \
        -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -derivedDataPath "$LOCAL_DERIVED_DATA" -destination "platform=macOS" \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
    local built="$LOCAL_DERIVED_DATA/Build/Products/Release/$APP_NAME"
    [[ -d "$built" ]] || fail "build finished but $built is missing"

    log "Ad-hoc signing …"
    codesign --force --deep --sign - "$built"

    local target="$INSTALL_DIR/$APP_NAME"
    quit_running
    log "Installing to $target"
    rm -rf "$target"
    ditto "$built" "$target"
    launch "$target"
}

case "${1:-}" in
    release) build_release ;;
    run)
        build_release
        quit_running
        launch "$(release_app_path)"
        ;;
    install) cmd_install ;;
    path) release_app_path ;;
    *)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
