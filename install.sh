#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

if [ "$#" -eq 0 ]; then
    exec bash "$SCRIPT_DIR/xrayctl.sh" menu
fi

exec bash "$SCRIPT_DIR/xrayctl.sh" "$@"
