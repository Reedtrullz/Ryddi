#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_basename="${RYDDI_ARTIFACT_BASENAME:-Ryddi-v0.2.0}"
status=0
resolved_identity=""

note() {
  printf '%s\n' "$1"
}

fail() {
  status=1
  printf '%s\n' "$1"
}

identity_lines() {
  security find-identity -v -p codesigning 2>/dev/null || true
}

developer_id_matches() {
  identity_lines | grep "Developer ID Application" || true
}

note "Ryddi release signing doctor"
note "Repository: $root"
note ""

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  identity_line="$(identity_lines | grep -F "$CODESIGN_IDENTITY" || true)"
  if [[ -z "$identity_line" ]]; then
    fail "CODESIGN_IDENTITY was set, but no matching codesigning identity was found."
  elif ! grep -q "Developer ID Application" <<<"$identity_line"; then
    fail "CODESIGN_IDENTITY is not a Developer ID Application certificate."
  else
    resolved_identity="$CODESIGN_IDENTITY"
    note "OK: Developer ID Application identity is available."
  fi
else
  developer_id_text="$(developer_id_matches)"
  developer_id_count="$(printf '%s\n' "$developer_id_text" | awk 'NF { count += 1 } END { print count + 0 }')"
  case "$developer_id_count" in
    0)
      fail "No Developer ID Application identity was found in the login keychain."
      ;;
    1)
      resolved_identity="$(printf '%s\n' "$developer_id_text" | sed -nE 's/.*"([^"]+)".*/\1/p' | head -n 1)"
      note "OK: Found one Developer ID Application identity."
      note "Set CODESIGN_IDENTITY=\"$resolved_identity\" before running the signed gate."
      ;;
    *)
      fail "Multiple Developer ID Application identities were found; set CODESIGN_IDENTITY explicitly."
      ;;
  esac
fi

note ""

notary_ready=false
if [[ "$status" -ne 0 ]]; then
  note "Skipping notary credential check until signing identity is fixed."
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null 2>&1; then
    notary_ready=true
    note "OK: Notary profile '$NOTARY_PROFILE' is usable."
  else
    fail "NOTARY_PROFILE '$NOTARY_PROFILE' could not be used with notarytool history."
    note "Recreate it with:"
    note "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>"
  fi
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  notary_ready=true
  note "OK: Apple ID notarization environment is present."
  note "APPLE_APP_PASSWORD is set; the doctor never prints its value."
else
  fail "Notary credentials are missing."
  note "Use one of these credential paths:"
  note "  xcrun notarytool store-credentials ryddi-notary --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>"
  note "  export NOTARY_PROFILE=ryddi-notary"
  note "or export APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD in this shell."
fi

note ""

if [[ "$status" -eq 0 && "$notary_ready" == "true" ]]; then
  note "Ready for signed release gate:"
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    note "  RYDDI_RELEASE_SIGNING=required RYDDI_ARTIFACT_BASENAME=$artifact_basename Scripts/release-check.sh"
  else
    note "  CODESIGN_IDENTITY=\"$resolved_identity\" RYDDI_RELEASE_SIGNING=required RYDDI_ARTIFACT_BASENAME=$artifact_basename Scripts/release-check.sh"
  fi
else
  note "Not ready for signed release gate yet."
fi

exit "$status"
