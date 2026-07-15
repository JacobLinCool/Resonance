#!/usr/bin/env bash
# Create or upload a Mac App Store archive.
#
# Required for both modes:
#   DEVELOPMENT_TEAM  Apple team that owns the explicit App ID
#   APP_VERSION       X.Y.Z marketing version
#   BUILD_NUMBER      Positive, previously unused App Store build number
#
# Upload mode also requires an App Store Connect API key:
#   APP_STORE_API_KEY_PATH
#   APP_STORE_API_KEY_ID
#   APP_STORE_API_ISSUER_ID
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

[ "$#" -eq 1 ] || fail "usage: scripts/app-store.sh <archive|upload>"
MODE="$1"
case "$MODE" in
  archive | upload) ;;
  *) fail "unknown mode '$MODE' (use archive or upload)" ;;
esac

[ -n "${DEVELOPMENT_TEAM:-}" ] \
  || fail "DEVELOPMENT_TEAM is required for Mac App Store signing"
[ -n "${APP_VERSION:-}" ] \
  || fail "APP_VERSION is required for Mac App Store archives"
[ -n "${BUILD_NUMBER:-}" ] \
  || fail "BUILD_NUMBER is required for Mac App Store archives"
validate_build_environment

AUTHENTICATION_ARGUMENTS=()
configure_authentication() {
  local key_path="${APP_STORE_API_KEY_PATH:-}"
  local key_id="${APP_STORE_API_KEY_ID:-}"
  local issuer_id="${APP_STORE_API_ISSUER_ID:-}"

  if [ -z "$key_path$key_id$issuer_id" ]; then
    [ "$MODE" = "archive" ] \
      || fail "upload requires APP_STORE_API_KEY_PATH, APP_STORE_API_KEY_ID, and APP_STORE_API_ISSUER_ID"
    return
  fi

  [ -n "$key_path" ] && [ -n "$key_id" ] && [ -n "$issuer_id" ] \
    || fail "set all App Store Connect API key variables, or none of them"
  [ -f "$key_path" ] && [ -r "$key_path" ] \
    || fail "App Store Connect API key is not a readable file: $key_path"
  [[ "$key_id" =~ ^[A-Z0-9]{10}$ ]] \
    || fail "APP_STORE_API_KEY_ID must be a 10-character key ID"
  [[ "$issuer_id" =~ ^[0-9a-fA-F-]{36}$ ]] \
    || fail "APP_STORE_API_ISSUER_ID must be a UUID"

  AUTHENTICATION_ARGUMENTS=(
    -authenticationKeyPath "$key_path"
    -authenticationKeyID "$key_id"
    -authenticationKeyIssuerID "$issuer_id"
  )
}
configure_authentication

OUTPUT_DIR="$ROOT_DIR/dist/app-store"
FINAL_ARCHIVE="$OUTPUT_DIR/$APP_NAME-$APP_VERSION-$BUILD_NUMBER.xcarchive"
[ ! -e "$FINAL_ARCHIVE" ] \
  || fail "archive already exists: $FINAL_ARCHIVE (use a new build number or run make clean)"

TEMP_ROOT="$(mktemp -d "$ROOT_DIR/.app-store-build.XXXXXX")"
DERIVED_DATA="$TEMP_ROOT/DerivedData"
TEMP_ARCHIVE="$TEMP_ROOT/$APP_NAME.xcarchive"
EXPORT_PATH="$TEMP_ROOT/export"
EXPORT_OPTIONS="$TEMP_ROOT/ExportOptions.plist"

cleanup() {
  local status=$?
  trap - EXIT
  rm -rf "$TEMP_ROOT" \
    || warn "could not remove temporary App Store files at $TEMP_ROOT"
  exit "$status"
}
trap cleanup EXIT

info "Archiving $APP_DISPLAY_NAME $APP_VERSION ($BUILD_NUMBER) for the Mac App Store"
run_xcodebuild \
  AppStore \
  "$DERIVED_DATA" \
  -destination 'generic/platform=macOS' \
  -archivePath "$TEMP_ARCHIVE" \
  "ONLY_ACTIVE_ARCH=NO" \
  "ARCHS=arm64 x86_64" \
  "${AUTHENTICATION_ARGUMENTS[@]}" \
  -quiet \
  archive

ARCHIVED_APP="$TEMP_ARCHIVE/Products/Applications/$APP_NAME.app"
validate_app "$ARCHIVED_APP"

EXECUTABLE="$ARCHIVED_APP/Contents/MacOS/$APP_NAME"
ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
ARCH_COUNT="$(wc -w <<<"$ARCHITECTURES" | tr -d ' ')"
[ "$ARCH_COUNT" = "2" ] \
  && [[ " $ARCHITECTURES " = *" arm64 "* ]] \
  && [[ " $ARCHITECTURES " = *" x86_64 "* ]] \
  || fail "App Store archive must contain arm64 and x86_64; found: $ARCHITECTURES"

LINKED_FRAMEWORKS="$(otool -L "$EXECUTABLE")"
[[ "$LINKED_FRAMEWORKS" = *"/MusicKit.framework/"* ]] \
  || fail "App Store executable does not link MusicKit directly"
[[ "$LINKED_FRAMEWORKS" = *"/ShazamKit.framework/"* ]] \
  || fail "App Store executable does not link ShazamKit directly"

if [ "$MODE" = "upload" ]; then
  plutil -create xml1 "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :method string app-store-connect" "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :destination string upload" "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :signingStyle string automatic" "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :teamID string $DEVELOPMENT_TEAM" "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :distributionBundleIdentifier string $BUNDLE_ID" "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :manageAppVersionAndBuildNumber bool false" "$EXPORT_OPTIONS"
  /usr/libexec/PlistBuddy -c "Add :uploadSymbols bool true" "$EXPORT_OPTIONS"
  mkdir -p "$EXPORT_PATH"

  info "Cloud-signing and uploading $APP_DISPLAY_NAME to App Store Connect"
  (
    cd "$ROOT_DIR" || exit 1
    xcodebuild \
      -exportArchive \
      -archivePath "$TEMP_ARCHIVE" \
      -exportPath "$EXPORT_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS" \
      -allowProvisioningUpdates \
      "${AUTHENTICATION_ARGUMENTS[@]}"
  )
fi

mkdir -p "$OUTPUT_DIR"
mv "$TEMP_ARCHIVE" "$FINAL_ARCHIVE"

if [ "$MODE" = "upload" ]; then
  info "Uploaded $APP_DISPLAY_NAME $APP_VERSION ($BUILD_NUMBER) to App Store Connect"
else
  info "Created Mac App Store archive"
fi
info "Archive: $FINAL_ARCHIVE"
