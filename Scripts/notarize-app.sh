#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: Scripts/notarize-app.sh dist/Ryddi.app" >&2
  exit 2
fi

app="$1"
zip_path="${app%.app}.zip"

: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD}"

ditto -c -k --keepParent "$app" "$zip_path"
xcrun notarytool submit "$zip_path" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"
