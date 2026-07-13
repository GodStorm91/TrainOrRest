#!/bin/bash
# Renders design/app-icon.svg into the app's icon asset.
# App Store icons must be opaque and free of an alpha channel.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
svg="$root/design/app-icon.svg"
out="$root/TrainOrRest/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

mkdir -p "$(dirname "$out")"
rsvg-convert --width 1024 --height 1024 --background-color '#08080d' "$svg" -o "$out.tmp"
magick "$out.tmp" -alpha remove -alpha off -strip "$out"
rm -f "$out.tmp"

echo "wrote $out"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$out" | tail -3
