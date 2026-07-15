#!/usr/bin/env bash
# Remove the app from the exact install directory and reset its permissions.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

[ "$#" -eq 0 ] || fail "usage: scripts/uninstall.sh"
validate_build_environment

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
case "$INSTALL_DIR" in
  /*) ;;
  *) fail "INSTALL_DIR must be an absolute path" ;;
esac

APP="$INSTALL_DIR/$APP_NAME.app"
if [ -e "$APP" ]; then
  assert_replaceable_app "$APP"
  quit_app "$APP"
  info "Removing $APP"
  rm -rf "$APP" || fail "could not remove $APP; check directory permissions"
else
  warn "$APP is not installed"
fi

info "Resetting privacy permissions for $BUNDLE_ID"
tccutil reset Microphone "$BUNDLE_ID" >/dev/null \
  || warn "could not reset Microphone permission"
tccutil reset MediaLibrary "$BUNDLE_ID" >/dev/null \
  || warn "could not reset Media & Apple Music permission"

info "Uninstalled $APP_NAME"
