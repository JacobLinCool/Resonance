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
  "$ROOT_DIR/Resources/Resonance.entitlements" \
  >/dev/null

info "Checking GitHub Actions workflows"
actionlint "$ROOT_DIR"/.github/workflows/*.yml

info "Project files passed static validation"
