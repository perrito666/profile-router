#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${CONFIGURATION:-release}"
if [[ "$CONFIGURATION" != release && "$CONFIGURATION" != debug ]]; then
  echo "CONFIGURATION must be release or debug" >&2
  exit 1
fi
swift build --configuration "$CONFIGURATION" "$@"
BINARY_DIRECTORY="$(swift build --configuration "$CONFIGURATION" --show-bin-path "$@")"
APP="${APP_OUTPUT_DIRECTORY:-dist}/Profile Router.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY_DIRECTORY/ProfileRouter" "$APP/Contents/MacOS/ProfileRouter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
# Finder metadata on cloud-backed folders can otherwise prevent code signing.
xattr -cr "$APP"
# Ad-hoc signing supports local use; this is not Developer ID signing or notarization.
codesign --force --sign "${SIGNING_IDENTITY:--}" --options runtime --entitlements Resources/ProfileRouter.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
