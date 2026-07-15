#!/usr/bin/env bash
# Remove the generated project and all build artifacts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

cd "$ROOT_DIR"
shopt -s nullglob
paths=("$PROJECT" DerivedData .build dist .dist-build.* .dist-previous.*)
for path in "${paths[@]}"; do
  if [ -e "$path" ]; then
    info "Removing $path"
    rm -rf "$path"
  fi
done
info "Clean."
