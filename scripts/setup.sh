#!/usr/bin/env bash
# First-time setup: ensure the toolchain is present and generate the project.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

info "Checking Xcode command-line tools"
validate_xcode

if ! have xcodegen; then
  info "xcodegen not found — installing with Homebrew"
  have brew || fail "Homebrew not found — install it from https://brew.sh, then re-run this script."
  brew install xcodegen
fi

info "Generating $PROJECT"
( cd "$ROOT_DIR" && xcodegen generate )

info "Setup complete. Run make test, or follow README.md to configure a signed development build."
