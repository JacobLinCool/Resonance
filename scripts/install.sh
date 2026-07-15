#!/usr/bin/env bash
# Build a signed Release app and install it atomically.
#
# Required:
#   DEVELOPMENT_TEAM  Apple Developer team ID used for automatic signing
#   BUNDLE_ID         matching explicit App ID with MusicKit and ShazamKit enabled
#
# Optional:
#   INSTALL_DIR       destination directory (default: /Applications)
#   LAUNCH            1 to launch after installation, 0 not to (default: 1)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

[ "$#" -eq 0 ] || fail "usage: scripts/install.sh"
[ -n "${DEVELOPMENT_TEAM:-}" ] \
  || fail "make install requires DEVELOPMENT_TEAM and a matching BUNDLE_ID; see README.md"

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
LAUNCH="${LAUNCH:-1}"
case "$INSTALL_DIR" in
  /*) ;;
  *) fail "INSTALL_DIR must be an absolute path" ;;
esac
case "$LAUNCH" in
  0 | 1) ;;
  *) fail "LAUNCH must be 0 or 1" ;;
esac

validate_xcode
mkdir -p "$INSTALL_DIR" || fail "could not create $INSTALL_DIR"
[ -w "$INSTALL_DIR" ] \
  || fail "$INSTALL_DIR is not writable; choose another explicit INSTALL_DIR"

DERIVED="$(mktemp -d)"
STAGE_ROOT="$(mktemp -d "$INSTALL_DIR/.Resonance.install.XXXXXX")"
BACKUP_ROOT=""
DEST="$INSTALL_DIR/$APP_NAME.app"
NEW_DEST_INSTALLED=0

cleanup() {
  local status=$?
  trap - EXIT

  if [ "$status" -ne 0 ]; then
    if [ "$NEW_DEST_INSTALLED" = "1" ] && [ -e "$DEST" ]; then
      rm -rf "$DEST" \
        || warn "could not remove the invalid new app at $DEST"
    fi

    if [ -n "$BACKUP_ROOT" ] \
      && [ -d "$BACKUP_ROOT/$APP_NAME.app" ] \
      && [ ! -e "$DEST" ]; then
      if mv "$BACKUP_ROOT/$APP_NAME.app" "$DEST"; then
        info "Restored the previous $APP_NAME installation"
      else
        warn "restore failed; the previous app remains at $BACKUP_ROOT/$APP_NAME.app"
      fi
    fi
  fi

  rm -rf "$DERIVED" "$STAGE_ROOT" \
    || warn "could not remove temporary build files"
  if [ -n "$BACKUP_ROOT" ]; then
    if [ -d "$BACKUP_ROOT/$APP_NAME.app" ]; then
      warn "preserved the previous app at $BACKUP_ROOT/$APP_NAME.app"
    else
      rm -rf "$BACKUP_ROOT" \
        || warn "could not remove the empty backup directory $BACKUP_ROOT"
    fi
  fi
  exit "$status"
}
trap cleanup EXIT

info "Building signed $APP_NAME (Release)"
build_app Release "$DERIVED"
SRC_APP="$(app_path Release "$DERIVED")"
STAGED_APP="$STAGE_ROOT/$APP_NAME.app"
ditto "$SRC_APP" "$STAGED_APP"
validate_app "$STAGED_APP"

ACTUAL_TEAM="$(codesign -dvv "$STAGED_APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[ "$ACTUAL_TEAM" = "$DEVELOPMENT_TEAM" ] \
  || fail "signed app team mismatch: expected $DEVELOPMENT_TEAM, found ${ACTUAL_TEAM:-none}"

VERSION="$(bundle_value "$STAGED_APP" CFBundleShortVersionString)"
assert_replaceable_app "$DEST"
quit_app "$DEST"

if [ -e "$DEST" ]; then
  BACKUP_ROOT="$(mktemp -d "$INSTALL_DIR/.Resonance.backup.XXXXXX")"
  mv "$DEST" "$BACKUP_ROOT/$APP_NAME.app"
fi

mv "$STAGED_APP" "$DEST"
NEW_DEST_INSTALLED=1
validate_app "$DEST"
if [ -n "$BACKUP_ROOT" ]; then
  rm -rf "$BACKUP_ROOT" \
    || warn "installed successfully, but could not remove $BACKUP_ROOT"
fi
BACKUP_ROOT=""
NEW_DEST_INSTALLED=0

info "Installed $APP_NAME $VERSION to $DEST"
if [ "$LAUNCH" = "1" ]; then
  info "Launching $APP_NAME"
  open "$DEST"
fi

cat <<EOF

$APP_NAME runs only in the menu bar; it does not appear in the Dock.
On first Enable, macOS requests:
  • Microphone — to recognize nearby music
  • Media & Apple Music — to play the matching catalog track
EOF
