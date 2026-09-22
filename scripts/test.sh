#!/bin/bash
set -euo pipefail
root="$(cd "$(/usr/bin/dirname "$0")/.." && pwd)"
cd "$root"
if [[ $# != 0 && $# != 2 && $# != 3 ]]; then echo 'Usage: bash scripts/test.sh [ABSOLUTE_NODE ABSOLUTE_PYTHON [ABSOLUTE_JQ]]' >&2; exit 1; fi
node="${1:-node}"
python="${2:-python3}"
if [[ $# -ge 2 && ( "$node" != /* || "$python" != /* ) ]]; then
  echo 'Explicit test interpreters must use absolute paths.' >&2; exit 1
fi
if [[ $# == 3 && "$3" != /* ]]; then echo 'Explicit JSON test tool must use an absolute path.' >&2; exit 1; fi
"$node" --test tests/*.test.js
CREATOR_TEST_JQ="${3:-jq}" "$python" -m unittest discover -s .github/scripts -p 'test_*.py'
"$python" -m unittest discover -s tests -p 'test_*.py'
"$python" scripts/privacy_check.py
"$python" scripts/publication_check.py --all-history
if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
  /bin/mkdir -p build/tests build/module-cache
  compiler=$(/usr/bin/xcrun --find swiftc)
  sdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
  "$compiler" -tools-directory "${compiler%/*}" -sdk "$sdk" helper/Sources/HelperHealth.swift tests/helper-health.swift \
    -module-cache-path build/module-cache -o build/tests/helper-health
  build/tests/helper-health
  "$compiler" -tools-directory "${compiler%/*}" -sdk "$sdk" helper/Sources/BridgePipe.swift tests/bridge-pipe.swift \
    -module-cache-path build/module-cache -o build/tests/bridge-pipe
  build/tests/bridge-pipe
  "$compiler" -tools-directory "${compiler%/*}" -sdk "$sdk" helper/Sources/DeviceBridge.swift \
    helper/Sources/BridgePipe.swift helper/Sources/HelperHealth.swift helper/Sources/SetupWindow.swift \
    helper/Sources/SetupState.swift helper/Sources/SetupDeviceOperation.swift tests/device-bridge.swift \
    -module-cache-path build/module-cache -framework AppKit -o build/tests/device-bridge
  build/tests/device-bridge
  "$compiler" -tools-directory "${compiler%/*}" -sdk "$sdk" helper/Sources/ControllerActions.swift helper/Sources/HelperHealth.swift tests/controller-targets.swift \
    -module-cache-path build/module-cache -framework Carbon -framework AppKit -o build/tests/controller-targets
  build/tests/controller-targets
  "$compiler" -tools-directory "${compiler%/*}" -sdk "$sdk" helper/Sources/WorkspaceShortcut.swift tests/shortcut-events.swift \
    -module-cache-path build/module-cache -o build/tests/shortcut-events
  build/tests/shortcut-events
  "$compiler" -tools-directory "${compiler%/*}" -sdk "$sdk" helper/Sources/LayerSelection.swift tests/layer-selection.swift \
    -module-cache-path build/module-cache -o build/tests/layer-selection
  build/tests/layer-selection
  "$compiler" -tools-directory "${compiler%/*}" -sdk "$sdk" helper/Sources/WorkspaceSelection.swift tests/workspace-selection.swift \
    -module-cache-path build/module-cache -o build/tests/workspace-selection
  build/tests/workspace-selection
  "$compiler" -tools-directory "${compiler%/*}" -sdk "$sdk" helper/Sources/SetupState.swift helper/Sources/SetupDeviceOperation.swift tests/setup-state.swift \
    -module-cache-path build/module-cache -framework AppKit -o build/tests/setup-state
  build/tests/setup-state
  "$compiler" -tools-directory "${compiler%/*}" -sdk "$sdk" helper/Sources/SetupWindow.swift helper/Sources/SetupState.swift \
    helper/Sources/SetupDeviceOperation.swift helper/Sources/HelperHealth.swift tests/setup-window.swift \
    -module-cache-path build/module-cache -framework AppKit -o build/tests/setup-window
  build/tests/setup-window --render
  build/tests/setup-window --lifecycle
  /bin/bash scripts/build.sh --universal
else
  echo 'Swift/AppKit tests require macOS. CI runs them in the macOS job.'
fi
