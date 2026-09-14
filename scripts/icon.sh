#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
iconset="$root/build/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$root/assets/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$root/assets/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 "$root/scripts/artwork_metadata.py" "$iconset"/*.png
iconutil -c icns "$iconset" -o "$root/assets/AppIcon.icns"
python3 "$root/scripts/artwork_metadata.py" "$root/assets/AppIcon.icns"
