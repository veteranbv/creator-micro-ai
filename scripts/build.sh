#!/bin/bash
set -euo pipefail
root="$(cd "$(/usr/bin/dirname "$0")/.." && pwd)"
universal=false
if [[ $# == 1 && "$1" == --universal ]]; then universal=true
elif [[ $# != 0 ]]; then echo 'Usage: bash scripts/build.sh [--universal]' >&2; exit 1; fi
if [[ "$(/usr/bin/uname -s)" != Darwin ]]; then echo 'Building the helper requires macOS.' >&2; exit 1; fi
build="$root/build"
destination="$build/Creator Micro AI.app"
/bin/mkdir -p "$build/module-cache"
staging=$(/usr/bin/mktemp -d "$build/app.XXXXXX")
app="$staging/Creator Micro AI.app"
/bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
minimum=$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$root/helper/Info.plist")
architectures=("$(/usr/bin/uname -m)")
if [[ "$universal" == true ]]; then architectures=(arm64 x86_64); fi
compiler=$(/usr/bin/xcrun --find swiftc)
sdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
binaries=()
for architecture in "${architectures[@]}"; do
  binary="$staging/CreatorMicroAI-$architecture"
  CLANG_MODULE_CACHE_PATH="$build/module-cache" "$compiler" "$root"/helper/Sources/*.swift \
    -target "${architecture}-apple-macosx${minimum}" \
    -tools-directory "${compiler%/*}" -sdk "$sdk" \
    -module-cache-path "$build/module-cache" -framework Carbon -framework AppKit \
    -framework ApplicationServices -o "$binary"
  actual=$(/usr/bin/otool -l "$binary" | /usr/bin/awk '$1 == "minos" { print $2 }')
  if [[ "$actual" != "$minimum" ]]; then
    echo 'Executable minimum macOS version does not match the app manifest.' >&2
    exit 1
  fi
  binaries+=("$binary")
done
if [[ "$universal" == true ]]; then
  /usr/bin/lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/CreatorMicroAI"
  # Xcode 27's lipo requires a separate verification call for each slice.
  for architecture in "${architectures[@]}"; do
    /usr/bin/lipo "$app/Contents/MacOS/CreatorMicroAI" -verify_arch "$architecture"
  done
else
  /bin/cp "${binaries[0]}" "$app/Contents/MacOS/CreatorMicroAI"
fi
/bin/rm "${binaries[@]}"
/bin/cp "$root/helper/Info.plist" "$app/Contents/Info.plist"
/bin/cp "$root/helper/Resources/worklouder_device_bridge.js" "$app/Contents/Resources/"
/bin/mkdir -p "$app/Contents/Resources/device" "$app/Contents/Resources/helper/Resources" "$app/Contents/Resources/reference/assets"
/bin/cp "$root/device/configure.js" "$root/device/keymap.json" "$app/Contents/Resources/device/"
# The configurator keeps the same reviewed relative import in source and bundles.
/bin/cp "$root/helper/Resources/worklouder_device_bridge.js" "$app/Contents/Resources/helper/Resources/"
/bin/cp "$root/docs/layout.html" "$app/Contents/Resources/reference/"
/bin/cp "$root/docs/assets/keycaps.svg" "$root/docs/assets/creator-micro-device.png" "$app/Contents/Resources/reference/assets/"
/bin/cp "$root/assets/AppIcon.icns" "$app/Contents/Resources/"
/bin/cp "$root/LICENSE" "$root/NOTICE.md" "$app/Contents/Resources/"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"
if [[ -e "$destination" || -L "$destination" ]]; then
  recovery=$(/usr/bin/mktemp -d "$build/previous-app.XXXXXX")
  /bin/mv "$destination" "$recovery/Creator Micro AI.app"
fi
/bin/mv "$app" "$destination"
/bin/rmdir "$staging"
echo "Built and ad-hoc signed: $destination"
echo 'No app was launched and no device or Accessibility settings were changed.'
