#!/bin/bash
# Renders design/app-icon.svg into the app's icon asset.
# App Store icons must be opaque and free of an alpha channel.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source="$root/design/app-icon-source.jpg"
out="$root/TrainOrRest/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

mkdir -p "$(dirname "$out")"
magick "$source" \
  -resize 1024x1024^ \
  -gravity center \
  -extent 1024x1024 \
  -alpha remove \
  -alpha off \
  -strip \
  "$out"

echo "wrote $out"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$out" | tail -3
