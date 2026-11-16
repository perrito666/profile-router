#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/profile-router-icon.XXXXXX")"
trap 'rm -rf "$ICON_WORK_DIRECTORY"' EXIT
swift scripts/make-icon.swift Resources/AppIcon.png
mkdir -p "$ICON_WORK_DIRECTORY/AppIcon.iconset"
for ICON_SIZE in 16 32 128 256 512; do
  sips -z "$ICON_SIZE" "$ICON_SIZE" Resources/AppIcon.png --out "$ICON_WORK_DIRECTORY/AppIcon.iconset/icon_${ICON_SIZE}x${ICON_SIZE}.png" >/dev/null
  RETINA_SIZE=$((ICON_SIZE * 2))
  sips -z "$RETINA_SIZE" "$RETINA_SIZE" Resources/AppIcon.png --out "$ICON_WORK_DIRECTORY/AppIcon.iconset/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" >/dev/null
done
python3 scripts/pack-icon.py "$ICON_WORK_DIRECTORY/AppIcon.iconset" Resources/AppIcon.icns
