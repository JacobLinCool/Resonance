#!/usr/bin/env bash
# Lint Swift sources with SwiftLint.  Extra args pass through (e.g. --strict).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

have swiftlint || fail "swiftlint not found — install with: brew install swiftlint"

cd "$ROOT_DIR"
info "Linting Sources"
swiftlint lint --strict "$@"
