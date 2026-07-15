#!/usr/bin/env bash
# Format all Swift code, or verify formatting with --lint.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

if have swift-format; then
  FMT=(swift-format)
elif swift format --version >/dev/null 2>&1; then
  FMT=(swift format)
else
  fail "swift-format not found — install Xcode 26+ or: brew install swift-format"
fi

case "${1:-}" in
  "")
    [ "$#" -eq 0 ] || fail "usage: scripts/format.sh [--lint]"
    info "Formatting Swift code"
    (cd "$ROOT_DIR" && "${FMT[@]}" format --in-place --recursive Sources Tests scripts/GenerateAppIcon.swift)
    ;;
  --lint)
    [ "$#" -eq 1 ] || fail "usage: scripts/format.sh [--lint]"
    info "Checking Swift formatting"
    (cd "$ROOT_DIR" && "${FMT[@]}" lint --recursive --strict Sources Tests scripts/GenerateAppIcon.swift)
    ;;
  *)
    fail "usage: scripts/format.sh [--lint]"
    ;;
esac
