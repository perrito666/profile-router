#!/bin/bash
set -euo pipefail
umask 077
NOTARY_INPUT="${1:?Pass the ZIP or DMG to notarize}"
NOTARY_RESULT="${RUNNER_TEMP:?RUNNER_TEMP is required}/profile-router-notary-result.json"
if [[ -n "${API_KEY_P8:-}" ]]; then
  printf '%s' "$API_KEY_P8" > "$RUNNER_TEMP/profile-router-AuthKey.p8"
  chmod 600 "$RUNNER_TEMP/profile-router-AuthKey.p8"
  xcrun notarytool submit "$NOTARY_INPUT" --key "$RUNNER_TEMP/profile-router-AuthKey.p8" \
    --key-id "${API_KEY_ID:?Set APPLE_API_KEY_ID}" --issuer "${API_ISSUER_ID:?Set APPLE_API_ISSUER_ID}" \
    --wait --output-format json > "$NOTARY_RESULT"
else
  xcrun notarytool submit "$NOTARY_INPUT" --apple-id "${APPLE_ID:?Set APPLE_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD}" \
    --team-id "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}" --wait --output-format json > "$NOTARY_RESULT"
fi
python3 - "$NOTARY_RESULT" <<'PY'
import json
import sys
with open(sys.argv[1]) as result:
    status = json.load(result).get("status")
if status != "Accepted":
    raise SystemExit(f"Apple notarization was not accepted: {status}")
print("Apple notarization accepted.")
PY
