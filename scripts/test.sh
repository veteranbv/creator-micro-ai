#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
node --test tests/*.test.js
python3 -m unittest discover -s .github/scripts -p 'test_*.py'
python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/privacy_check.py
python3 scripts/publication_check.py --all-history
if [[ "$(uname -s)" == Darwin ]]; then
  mkdir -p build/tests build/module-cache
  swiftc helper/Sources/ControllerActions.swift tests/controller-targets.swift \
    -module-cache-path build/module-cache -framework Carbon -framework AppKit -o build/tests/controller-targets
  build/tests/controller-targets
  swiftc helper/Sources/WorkspaceShortcut.swift tests/shortcut-events.swift \
    -module-cache-path build/module-cache -o build/tests/shortcut-events
  build/tests/shortcut-events
  swiftc helper/Sources/LayerSelection.swift tests/layer-selection.swift \
    -module-cache-path build/module-cache -o build/tests/layer-selection
  build/tests/layer-selection
  bash scripts/build.sh
else
  echo 'Swift/AppKit tests require macOS. CI runs them in the macOS job.'
fi
