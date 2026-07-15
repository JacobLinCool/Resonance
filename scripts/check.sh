#!/usr/bin/env bash
# Validate non-Swift project files and automation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

[ "$#" -eq 0 ] || fail "usage: scripts/check.sh"
have shellcheck || fail "shellcheck not found — install with: brew install shellcheck"
have actionlint || fail "actionlint not found — install with: brew install actionlint"

info "Checking shell syntax and static analysis"
bash -n "$ROOT_DIR"/scripts/*.sh
shellcheck -x -P "$ROOT_DIR/scripts" "$ROOT_DIR"/scripts/*.sh

info "Checking property lists"
plutil -lint \
  "$ROOT_DIR/Resources/Info.plist" \
  "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" \
  "$ROOT_DIR/Resources/Resonance.entitlements" \
  >/dev/null

[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$ROOT_DIR/Resources/Info.plist")" \
  = "$APP_DISPLAY_NAME" ] \
  || fail "Info.plist must use the App Store display name: $APP_DISPLAY_NAME"
[ "$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$ROOT_DIR/Resources/Info.plist")" \
  = "$APP_CATEGORY" ] \
  || fail "Info.plist must use the App Store category: $APP_CATEGORY"
[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$ROOT_DIR/Resources/Info.plist")" \
  = "false" ] \
  || fail "Info.plist must declare that the app does not use non-exempt encryption"

[ -f "$ROOT_DIR/PRIVACY.md" ] || fail "PRIVACY.md is required for App Store distribution"
[ -f "$ROOT_DIR/docs/APP_STORE.md" ] || fail "docs/APP_STORE.md is required for App Store metadata"

privacy_manifest="$ROOT_DIR/Resources/PrivacyInfo.xcprivacy"
[ "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$privacy_manifest")" = "false" ] \
  || fail "privacy manifest must declare that tracking is disabled"
privacy_manifest_xml="$(plutil -convert xml1 -o - "$privacy_manifest")"
for declaration in \
  NSPrivacyAccessedAPICategorySystemBootTime \
  35F9.1 \
  NSPrivacyAccessedAPICategoryUserDefaults \
  CA92.1; do
  [[ "$privacy_manifest_xml" = *"$declaration"* ]] \
    || fail "privacy manifest is missing required declaration: $declaration"
done

for entitlement in \
  com.apple.security.app-sandbox \
  com.apple.security.device.audio-input \
  com.apple.security.network.client; do
  [ "$(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$ROOT_DIR/Resources/Resonance.entitlements")" \
    = "true" ] \
    || fail "required entitlement is missing or false: $entitlement"
done

info "Checking GitHub Actions workflows"
actionlint "$ROOT_DIR"/.github/workflows/*.yml

info "Project files passed static validation"
