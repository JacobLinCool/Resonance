#!/usr/bin/env bash
# Run the hosted unit-test target with repository-local build artifacts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

[ "$#" -eq 0 ] || fail "usage: scripts/test.sh"

info "Running tests"
test_app
info "Tests passed"
