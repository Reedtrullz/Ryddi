#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: Scripts/notarize-app.sh dist/Ryddi.app" >&2
  exit 2
fi

app="$1"
zip_path="${app%.app}.zip"

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  : "${APPLE_ID:?Set APPLE_ID or NOTARY_PROFILE}"
  : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID or NOTARY_PROFILE}"
  : "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD or NOTARY_PROFILE}"
fi

ditto -c -k --keepParent "$app" "$zip_path"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$zip_path" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
else
  xcrun notarytool submit "$zip_path" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
codesign --verify --deep --strict --verbose=2 "$app"
