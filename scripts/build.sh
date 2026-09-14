#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then echo 'Building the helper requires macOS.' >&2; exit 1; fi
build="$root/build"
destination="$build/Creator Micro AI.app"
mkdir -p "$build/module-cache"
staging=$(mktemp -d "$build/app.XXXXXX")
app="$staging/Creator Micro AI.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
minimum=$(plutil -extract LSMinimumSystemVersion raw -o - "$root/helper/Info.plist")
CLANG_MODULE_CACHE_PATH="$build/module-cache" swiftc "$root"/helper/Sources/*.swift \
  -target "$(uname -m)-apple-macosx${minimum}" \
  -module-cache-path "$build/module-cache" -framework Carbon -framework AppKit \
  -framework ApplicationServices -o "$app/Contents/MacOS/CreatorMicroAI"
actual=$(otool -l "$app/Contents/MacOS/CreatorMicroAI" | awk '$1 == "minos" { print $2 }')
if [[ "$actual" != "$minimum" ]]; then
  echo 'Executable minimum macOS version does not match the app manifest.' >&2
  exit 1
fi
cp "$root/helper/Info.plist" "$app/Contents/Info.plist"
cp "$root/helper/Resources/worklouder_device_bridge.js" "$app/Contents/Resources/"
cp "$root/assets/AppIcon.icns" "$app/Contents/Resources/"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
if [[ -e "$destination" || -L "$destination" ]]; then
  recovery=$(mktemp -d "$build/previous-app.XXXXXX")
  mv "$destination" "$recovery/Creator Micro AI.app"
fi
mv "$app" "$destination"
rmdir "$staging"
echo "Built and ad-hoc signed: $destination"
echo 'No app was launched and no device or Accessibility settings were changed.'
