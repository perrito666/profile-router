#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${APP_OUTPUT_DIRECTORY:-dist}/Profile Router.app"
DMG="${1:-dist/ProfileRouter.dmg}"
test -d "$APP"
DMG_WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/profile-router-dmg.XXXXXX")"
trap 'rm -rf "$DMG_WORK_DIRECTORY"' EXIT
ditto "$APP" "$DMG_WORK_DIRECTORY/Profile Router.app"
ln -s /Applications "$DMG_WORK_DIRECTORY/Applications"
cp LICENSE "$DMG_WORK_DIRECTORY/LICENSE"
mkdir -p "$(dirname "$DMG")"
hdiutil create -volname "Profile Router" -srcfolder "$DMG_WORK_DIRECTORY" -ov -format UDZO "$DMG"
