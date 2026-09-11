#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then echo 'Building the helper requires macOS.' >&2; exit 1; fi
build="$root/build"
app="$build/Creator Micro AI.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$build/module-cache"
CLANG_MODULE_CACHE_PATH="$build/module-cache" swiftc "$root"/helper/Sources/*.swift \
  -module-cache-path "$build/module-cache" -framework Carbon -framework AppKit \
  -framework ApplicationServices -o "$app/Contents/MacOS/CreatorMicroAI"
cp "$root/helper/Info.plist" "$app/Contents/Info.plist"
cp "$root/helper/Resources/worklouder_device_bridge.js" "$app/Contents/Resources/"
cp "$root/assets/AppIcon.icns" "$app/Contents/Resources/"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built and ad-hoc signed: $app"
echo 'No app was launched and no device or Accessibility settings were changed.'
