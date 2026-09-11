#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if pgrep -x CreatorMicroAI >/dev/null || pgrep -x WorkLouderFocusHelper >/dev/null; then
  echo 'Quit the running helper before reading or writing the device.' >&2; exit 1
fi
exec env ELECTRON_RUN_AS_NODE=1 /Applications/input.app/Contents/MacOS/input "$root/device/configure.js" "$@"
