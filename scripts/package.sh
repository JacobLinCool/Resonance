#!/usr/bin/env bash
# Build and validate a universal .app, .zip, and .dmg in dist/.
#
# Optional distribution credentials:
#   SIGN_IDENTITY   Developer ID Application identity
#   NOTARY_PROFILE  notarytool keychain profile (requires SIGN_IDENTITY)
#   NOTARY_KEYCHAIN file-based keychain containing the profile (CI only)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

[ "$#" -eq 0 ] || fail "usage: scripts/package.sh"
[ -z "${NOTARY_PROFILE:-}" ] || [ -n "${SIGN_IDENTITY:-}" ] \
  || fail "NOTARY_PROFILE requires SIGN_IDENTITY"
[ -z "${NOTARY_KEYCHAIN:-}" ] || [ -n "${NOTARY_PROFILE:-}" ] \
  || fail "NOTARY_KEYCHAIN requires NOTARY_PROFILE"

NOTARY_ARGUMENTS=()
if [ -n "${NOTARY_PROFILE:-}" ]; then
  NOTARY_ARGUMENTS=(--keychain-profile "$NOTARY_PROFILE")
  if [ -n "${NOTARY_KEYCHAIN:-}" ]; then
    [ -e "$NOTARY_KEYCHAIN" ] \
      || fail "notary keychain not found: $NOTARY_KEYCHAIN"
    NOTARY_ARGUMENTS+=(--keychain "$NOTARY_KEYCHAIN")
  fi
fi

CONFIG="Release"
DIST="$ROOT_DIR/dist"
DERIVED="$(mktemp -d)"
OUTPUT="$(mktemp -d "$ROOT_DIR/.dist-build.XXXXXX")"
DMG_STAGE=""
PREVIOUS_DIST=""

cleanup() {
  local status=$?
  local cleanup_failed=0
  trap - EXIT

  if ! rm -rf "$DERIVED"; then
    warn "could not remove temporary build files at $DERIVED"
    cleanup_failed=1
  fi
  if [ -n "$DMG_STAGE" ] && ! rm -rf "$DMG_STAGE"; then
    warn "could not remove temporary DMG files at $DMG_STAGE"
    cleanup_failed=1
  fi
  if [ -n "$OUTPUT" ] && ! rm -rf "$OUTPUT"; then
    warn "could not remove temporary package files at $OUTPUT"
    cleanup_failed=1
  fi

  if [ "$status" -ne 0 ] \
    && [ -n "$PREVIOUS_DIST" ] \
    && [ -d "$PREVIOUS_DIST" ] \
    && [ ! -e "$DIST" ]; then
    mv "$PREVIOUS_DIST" "$DIST" \
      || warn "could not restore the previous dist directory from $PREVIOUS_DIST"
  fi

  if [ "$status" -eq 0 ] && [ "$cleanup_failed" -ne 0 ]; then
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT

info "Building universal $APP_NAME ($CONFIG)"
build_app "$CONFIG" "$DERIVED"
SRC_APP="$(app_path "$CONFIG" "$DERIVED")"
APP="$OUTPUT/$APP_NAME.app"
ditto "$SRC_APP" "$APP"
validate_app "$APP"

EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
ARCH_COUNT="$(wc -w <<<"$ARCHITECTURES" | tr -d ' ')"
[ "$ARCH_COUNT" = "2" ] \
  && [[ " $ARCHITECTURES " = *" arm64 "* ]] \
  && [[ " $ARCHITECTURES " = *" x86_64 "* ]] \
  || fail "Release must contain exactly arm64 and x86_64; found: $ARCHITECTURES"

VERSION="$(bundle_value "$APP" CFBundleShortVersionString)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "invalid CFBundleShortVersionString: $VERSION"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  info "Signing app with hardened runtime"
  ENTITLEMENTS="$ROOT_DIR/Resources/Resonance.entitlements"
  [ -f "$ENTITLEMENTS" ] || fail "entitlements file not found: $ENTITLEMENTS"
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"

  SIGNATURE_DETAILS="$(codesign -dvv "$APP" 2>&1)"
  [[ "$SIGNATURE_DETAILS" = *"(runtime)"* ]] \
    || fail "Developer ID app signature is missing the hardened runtime flag"
  SIGNED_ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
  [[ "$SIGNED_ENTITLEMENTS" != *"com.apple.security.get-task-allow"* ]] \
    || fail "distribution signature must not contain get-task-allow"
  TEAM_ID="$(sed -n 's/^TeamIdentifier=//p' <<<"$SIGNATURE_DETAILS")"
  [ -n "$TEAM_ID" ] || fail "Developer ID signature has no TeamIdentifier"
  if [ -z "${NOTARY_PROFILE:-}" ]; then
    warn "NOTARY_PROFILE is not set; signed artifacts are for validation only and will not be notarized."
  fi
else
  warn "Unsigned distribution credentials: artifacts are for build validation only; recognition and playback will not work."
fi

ZIP="$OUTPUT/$APP_NAME-$VERSION.zip"
create_zip() {
  rm -f "$ZIP"
  (cd "$OUTPUT" && ditto -c -k --keepParent "$APP_NAME.app" "$(basename "$ZIP")")
  unzip -tq "$ZIP" >/dev/null || fail "ZIP integrity check failed"
}

info "Creating $(basename "$ZIP")"
create_zip

if [ -n "${NOTARY_PROFILE:-}" ]; then
  info "Notarizing the ZIP and stapling the app"
  xcrun notarytool submit "${NOTARY_ARGUMENTS[@]}" --wait "$ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  create_zip
fi

DMG="$OUTPUT/$APP_NAME-$VERSION.dmg"
DMG_STAGE="$(mktemp -d)"
ditto "$APP" "$DMG_STAGE/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"

info "Creating $(basename "$DMG")"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG" \
  >/dev/null
hdiutil verify "$DMG" >/dev/null

if [ -n "${SIGN_IDENTITY:-}" ]; then
  info "Signing $(basename "$DMG")"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  info "Notarizing and stapling $(basename "$DMG")"
  xcrun notarytool submit "${NOTARY_ARGUMENTS[@]}" --wait "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  hdiutil verify "$DMG" >/dev/null
fi

if [ -z "${SIGN_IDENTITY:-}" ] || [ -z "${NOTARY_PROFILE:-}" ]; then
  printf '%s\n' \
    "These artifacts are for local validation only." \
    "Do not publish them: they are not both Developer ID-signed and notarized." \
    >"$OUTPUT/VALIDATION_ONLY"
fi

(
  cd "$OUTPUT"
  shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" >SHA256SUMS
)

if [ -e "$DIST" ]; then
  PREVIOUS_PLACEHOLDER="$(mktemp -d "$ROOT_DIR/.dist-previous.XXXXXX")"
  rmdir "$PREVIOUS_PLACEHOLDER"
  PREVIOUS_DIST="$PREVIOUS_PLACEHOLDER"
  mv "$DIST" "$PREVIOUS_DIST"
fi
mv "$OUTPUT" "$DIST"
OUTPUT=""
if [ -n "$PREVIOUS_DIST" ]; then
  rm -rf "$PREVIOUS_DIST" \
    || warn "new package is valid, but the previous dist remains at $PREVIOUS_DIST"
fi
PREVIOUS_DIST=""

info "Packaged $APP_NAME $VERSION ($ARCHITECTURES) into dist/"
ls -1 "$DIST"
