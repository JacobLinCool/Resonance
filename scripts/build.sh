#!/usr/bin/env bash
# Build Resonance.  Usage: scripts/build.sh [Debug|Release]   (default: Debug)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

[ "$#" -le 1 ] || fail "usage: scripts/build.sh [Debug|Release]"
CONFIG="${1:-Debug}"

info "Building $APP_NAME ($CONFIG)"
build_app "$CONFIG" "$ROOT_DIR/DerivedData"
APP="$(app_path "$CONFIG" "$ROOT_DIR/DerivedData")"
validate_app "$APP"
info "Built $APP"
