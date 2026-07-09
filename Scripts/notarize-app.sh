#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: Scripts/notarize-app.sh dist/Ryddi.app" >&2
  exit 2
fi

app="$1"
dist="$(cd "$(dirname "$app")" && pwd)"
zip_path="${app%.app}.zip"
submit_json="$dist/Ryddi-notary-submit.json"
status_json="$dist/Ryddi-notary-status.json"
log_json="$dist/Ryddi-notary-log.json"
submission_path="$dist/Ryddi-notary-submission.txt"
wait_timeout="${RYDDI_NOTARY_WAIT_TIMEOUT:-30m}"

if [[ ! -d "$app" ]]; then
  echo "missing app bundle: $app" >&2
  exit 1
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  : "${APPLE_ID:?Set APPLE_ID or NOTARY_PROFILE}"
  : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID or NOTARY_PROFILE}"
  : "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD or NOTARY_PROFILE}"
fi

notary_args=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  notary_args+=(--keychain-profile "$NOTARY_PROFILE")
else
  notary_args+=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
fi

json_value() {
  local key="$1"
  local file="$2"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  /usr/bin/tr '\n' ' ' <"$file" | /usr/bin/sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\\1/p" | /usr/bin/head -n 1
}

fetch_notary_log() {
  local submission_id="$1"
  xcrun notarytool log "$submission_id" "${notary_args[@]}" --output-format json >"$log_json" 2>/dev/null || true
}

if [[ -n "${RYDDI_NOTARY_SUBMISSION_ID:-}" ]]; then
  submission_id="$RYDDI_NOTARY_SUBMISSION_ID"
  echo "$submission_id" >"$submission_path"
  echo "==> Resuming notarization submission: $submission_id"
else
  echo "==> Zipping app for notarization"
  rm -f "$zip_path" "$submit_json" "$status_json" "$log_json" "$submission_path"
  ditto -c -k --keepParent "$app" "$zip_path"

  echo "==> Submitting app to Apple notarization"
  xcrun notarytool submit "$zip_path" "${notary_args[@]}" --output-format json >"$submit_json"
  submission_id="$(json_value id "$submit_json")"
  if [[ -z "$submission_id" ]]; then
    echo "notarytool submit did not return a submission id. See $submit_json" >&2
    exit 1
  fi
  echo "$submission_id" >"$submission_path"
fi

echo "==> Waiting for notarization: $submission_id (timeout: $wait_timeout)"
set +e
xcrun notarytool wait "$submission_id" "${notary_args[@]}" --timeout "$wait_timeout" --output-format json >"$status_json"
wait_status=$?
set -e

status="$(json_value status "$status_json")"
if [[ -z "$status" ]]; then
  status="Unknown"
fi

case "$status" in
  Accepted)
    echo "==> Notarization accepted; stapling and validating"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose "$app"
    codesign --verify --deep --strict --verbose=2 "$app"
    ;;
  Invalid|Rejected)
    fetch_notary_log "$submission_id"
    echo "notarization status is $status. See $status_json and $log_json" >&2
    exit 1
    ;;
  "In Progress"|Unknown|*)
    if [[ "$wait_status" -eq 0 && "$status" != "In Progress" && "$status" != "Unknown" ]]; then
      fetch_notary_log "$submission_id"
      echo "notarization returned unexpected status '$status'. See $status_json" >&2
      exit 1
    fi
    echo "notarization is still $status after waiting." >&2
    echo "Resume with:" >&2
    echo "  RYDDI_NOTARY_SUBMISSION_ID=$submission_id RYDDI_NOTARY_WAIT_TIMEOUT=$wait_timeout Scripts/notarize-app.sh \"$app\"" >&2
    exit 75
    ;;
esac
