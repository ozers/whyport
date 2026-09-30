#!/usr/bin/env bash
# Renders Resources/AppIcon.icns and Resources/dmg-background.tiff from Sources/WhyPort/Artwork.swift.
# Run it after changing the artwork and commit the results; release builds only copy them.
set -euo pipefail

cd "$(dirname "$0")"
./build-app.sh >/dev/null
BIN=".build/WhyPort.app/Contents/MacOS/WhyPort"
WORK=".build/artwork"
rm -rf "$WORK"
mkdir -p "$WORK/AppIcon.iconset" Resources

"$BIN" --snapshot "$WORK/icon.png" --page icon
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$WORK/icon.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns

"$BIN" --snapshot "$WORK/background@2x.png" --page dmg-background
sips -z 800 1320 "$WORK/background@2x.png" --out "$WORK/background@2x.png" >/dev/null
sips -z 400 660 "$WORK/background@2x.png" --out "$WORK/background.png" >/dev/null
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out Resources/dmg-background.tiff 2>/dev/null

echo "Wrote Resources/AppIcon.icns and Resources/dmg-background.tiff"
