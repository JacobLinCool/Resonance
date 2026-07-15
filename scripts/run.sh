#!/usr/bin/env bash
# Build and launch the app for development.
# Usage: scripts/run.sh [Debug|Release]   (default: Debug)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

[ "$#" -le 1 ] || fail "usage: scripts/run.sh [Debug|Release]"
CONFIG="${1:-Debug}"

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  warn "This ad-hoc build is for UI validation only; ShazamKit and MusicKit require DEVELOPMENT_TEAM and BUNDLE_ID."
fi

info "Building $APP_NAME ($CONFIG)"
build_app "$CONFIG" "$ROOT_DIR/DerivedData"

APP="$(app_path "$CONFIG" "$ROOT_DIR/DerivedData")"
[ -d "$APP" ] || fail "build did not produce $APP"

quit_app "$APP"
info "Launching $APP"
open "$APP"
