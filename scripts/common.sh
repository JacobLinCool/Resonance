#!/usr/bin/env bash
# Shared configuration and helpers. Source from a Bash script in this directory.

APP_NAME="Resonance"
SCHEME="Resonance"
PROJECT="Resonance.xcodeproj"
DEFAULT_BUNDLE_ID="dev.jacoblincool.Resonance"
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$1" >&2; }
fail() {
  printf '\033[1;31merror:\033[0m %s\n' "$1" >&2
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

validate_xcode() {
  have xcodebuild || fail "xcodebuild not found — install Xcode 26 or later"

  local version_output version_line major
  version_output="$(xcodebuild -version 2>/dev/null)" \
    || fail "full Xcode is not selected — install Xcode 26+, then select it with xcode-select"
  version_line="${version_output%%$'\n'*}"
  [[ "$version_line" =~ ^Xcode[[:space:]]+([0-9]+)(\.[0-9]+)*$ ]] \
    || fail "could not determine the selected Xcode version"
  major="${BASH_REMATCH[1]}"
  [ "$major" -ge 26 ] \
    || fail "Xcode 26 or later is required; selected: $version_line"
}

validate_build_environment() {
  [[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] \
    || fail "invalid BUNDLE_ID '$BUNDLE_ID'"

  if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    [[ "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]] \
      || fail "DEVELOPMENT_TEAM must be a 10-character Apple team ID"
  fi
  if [ -n "${APP_VERSION:-}" ]; then
    [[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || fail "APP_VERSION must use X.Y.Z format"
  fi
  if [ -n "${BUILD_NUMBER:-}" ]; then
    [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] \
      || fail "BUILD_NUMBER must be a positive integer"
  fi
}

ensure_project() {
  have xcodegen || fail "xcodegen not found — run make setup"
  (cd "$ROOT_DIR" && xcodegen generate --quiet)
}

# run_xcodebuild <configuration> <derived-data-path> <extra xcodebuild arguments...>
run_xcodebuild() {
  local configuration="$1"
  local derived_data="$2"
  shift 2

  validate_xcode
  validate_build_environment
  ensure_project

  local -a settings=(
    "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID"
  )

  if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    settings+=(
      -allowProvisioningUpdates
      "CODE_SIGN_STYLE=Automatic"
      "CODE_SIGN_IDENTITY=Apple Development"
      "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
      "ENABLE_HARDENED_RUNTIME=YES"
    )
  else
    settings+=(
      "CODE_SIGN_STYLE=Manual"
      "CODE_SIGN_IDENTITY=-"
      "DEVELOPMENT_TEAM="
      "ENABLE_HARDENED_RUNTIME=NO"
    )
  fi

  [ -z "${APP_VERSION:-}" ] || settings+=("MARKETING_VERSION=$APP_VERSION")
  [ -z "${BUILD_NUMBER:-}" ] || settings+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

  (
    cd "$ROOT_DIR" || exit 1
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$configuration" \
      -derivedDataPath "$derived_data" \
      "${settings[@]}" \
      "$@"
  )
}

# build_app <Debug|Release> <derived-data-path>
build_app() {
  local configuration="$1"
  local derived_data="$2"
  case "$configuration" in
    Debug)
      run_xcodebuild \
        "$configuration" \
        "$derived_data" \
        -destination "platform=macOS,arch=$(uname -m)" \
        -quiet \
        build
      ;;
    Release)
      run_xcodebuild \
        "$configuration" \
        "$derived_data" \
        -destination 'generic/platform=macOS' \
        "ONLY_ACTIVE_ARCH=NO" \
        "ARCHS=arm64 x86_64" \
        -quiet \
        build
      ;;
    *)
      fail "unknown configuration '$configuration' (use Debug or Release)"
      ;;
  esac
}

test_app() {
  run_xcodebuild \
    Debug \
    "$ROOT_DIR/DerivedData/Tests" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -enableCodeCoverage YES \
    -quiet \
    test
}

app_path() {
  printf '%s/Build/Products/%s/%s.app\n' "$2" "$1" "$APP_NAME"
}

bundle_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

validate_app() {
  local app="$1"
  [ -d "$app" ] || fail "app bundle not found: $app"
  [ -f "$app/Contents/Info.plist" ] || fail "app has no Info.plist: $app"
  [ -x "$app/Contents/MacOS/$APP_NAME" ] || fail "app has no executable: $app"

  local actual_bundle_id
  actual_bundle_id="$(bundle_value "$app" CFBundleIdentifier)" \
    || fail "could not read bundle ID from $app"
  [ "$actual_bundle_id" = "$BUNDLE_ID" ] \
    || fail "bundle ID mismatch at $app: expected $BUNDLE_ID, found $actual_bundle_id"

  local version
  version="$(bundle_value "$app" CFBundleShortVersionString)" \
    || fail "could not read app version from $app"
  [ -n "$version" ] || fail "app version is empty: $app"
  codesign --verify --deep --strict "$app" \
    || fail "code signature validation failed: $app"
}

assert_replaceable_app() {
  local app="$1"
  [ -e "$app" ] || return 0
  [ -d "$app" ] || fail "refusing to replace non-app path: $app"

  local actual_bundle_id
  actual_bundle_id="$(bundle_value "$app" CFBundleIdentifier 2>/dev/null)" \
    || fail "refusing to replace an unreadable app bundle: $app"
  [ "$actual_bundle_id" = "$BUNDLE_ID" ] \
    || fail "refusing to replace $app (bundle ID is $actual_bundle_id, expected $BUNDLE_ID)"
}

# Quit only the executable inside the exact app bundle being replaced.
quit_app() {
  local app="$1"
  local executable="$app/Contents/MacOS/$APP_NAME"
  [ -x "$executable" ] || return 0

  local pid command_path found=0
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    command_path="$(ps -p "$pid" -o command= | sed -E 's/^[[:space:]]+//')"
    [ "$command_path" = "$executable" ] || continue
    found=1
    info "Quitting $app"
    kill -TERM "$pid" || fail "could not stop $app (PID $pid)"

    local attempt=0
    while [ "$attempt" -lt 50 ]; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
      attempt=$((attempt + 1))
    done
    kill -0 "$pid" 2>/dev/null \
      && fail "$app did not quit within 5 seconds"
  done < <(pgrep -x "$APP_NAME" || true)

  [ "$found" -eq 0 ] || info "$APP_NAME stopped"
}
