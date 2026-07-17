#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${RYDDI_E2E_APP_PATH:-$root/dist/Ryddi.app}"
output="${RYDDI_E2E_OUTPUT:-$root/dist/e2e-proof}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ryddi-packaged-e2e.XXXXXX")"
scratch="$(cd "$scratch" && pwd -P)"
open_pid=""
keep_scratch="${RYDDI_E2E_KEEP_SCRATCH:-0}"
keep_trash="${RYDDI_E2E_KEEP_TRASH:-0}"
RYDDI_E2E_SCAN_DELAY_MILLISECONDS="750"

cleanup() {
  /usr/bin/osascript -e 'tell application id "com.reidar.ryddi" to quit' >/dev/null 2>&1 || true
  if [[ -n "$open_pid" ]] && kill -0 "$open_pid" 2>/dev/null; then
    kill "$open_pid" 2>/dev/null || true
    wait "$open_pid" 2>/dev/null || true
  fi
  if [[ "$keep_scratch" == "1" ]]; then
    echo "Packaged-app E2E scratch preserved: $scratch" >&2
  else
    rm -rf "$scratch"
  fi
}
trap cleanup EXIT

if [[ ! -d "$app" || ! -f "$app/Contents/Info.plist" ]]; then
  echo "Packaged Ryddi.app is required: $app" >&2
  exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" != "com.reidar.ryddi" ]]; then
  echo "Unexpected packaged app bundle identifier." >&2
  exit 1
fi

fixture="$scratch/fixture"
"$root/Scripts/make-app-e2e-fixture.sh" "$fixture" >/dev/null
candidate="$fixture/Library/Caches/Codex/cache.bin"
browser_marker="$fixture/Library/Application Support/Google/Chrome/Default/Login Data"
codex_marker="$fixture/.codex/sessions/e2e-session.jsonl"
app_marker="$fixture/Applications/Ryddi E2E Fixture.app/Contents/MacOS/RyddiE2EFixture"
browser_before="$(shasum -a 256 "$browser_marker" | awk '{print $1}')"
codex_before="$(shasum -a 256 "$codex_marker" | awk '{print $1}')"
app_before="$(shasum -a 256 "$app_marker" | awk '{print $1}')"

rm -rf "$output"
mkdir -p "$output" "$scratch/audit" "$scratch/config" "$scratch/history" "$scratch/reports" "$scratch/holding" "$scratch/guided-map" "$root/.build/e2e-module-cache"

/usr/bin/osascript -e 'tell application id "com.reidar.ryddi" to quit' >/dev/null 2>&1 || true
sleep 1

/usr/bin/open -W -n -F \
  --env "RYDDI_E2E_MODE=1" \
  --env "RYDDI_E2E_SCOPE_ROOT=$fixture" \
  --env "RYDDI_E2E_SCAN_DELAY_MILLISECONDS=$RYDDI_E2E_SCAN_DELAY_MILLISECONDS" \
  --env "RYDDI_AUDIT_ROOT=$scratch/audit" \
  --env "RYDDI_CONFIG_ROOT=$scratch/config" \
  --env "RYDDI_SCAN_HISTORY_ROOT=$scratch/history" \
  --env "RYDDI_REPORT_ROOT=$scratch/reports" \
  --env "RYDDI_HOLDING_ROOT=$scratch/holding" \
  --env "RYDDI_GUIDED_MAP_ROOT=$scratch/guided-map" \
  "$app" >"$scratch/open.log" 2>&1 &
open_pid=$!

/usr/bin/swiftc \
  -parse-as-library \
  -module-cache-path "$root/.build/e2e-module-cache" \
  "$root/Tests/AppE2E/RyddiAXHarness.swift" \
  -o "$scratch/RyddiAXHarness"
"$scratch/RyddiAXHarness" \
  --bundle-id com.reidar.ryddi \
  --app "$app" \
  --candidate "$candidate" \
  --output "$output"

for proof in "$output/e2e-result.json" "$output/ryddi-minimum.png" "$output/ryddi-regular.png" "$output/ryddi-wide.png"; do
  test -s "$proof" || { echo "Missing packaged-app E2E proof: $proof" >&2; exit 1; }
done
jq -e '
  .scanProgressVisible == true
  and .cancelledScanBecameIdle == true
  and .cancelledScanHadNoLateCommit == true
  and .normalScanCompleted == true
  and .originalCandidateMissing == true
  and .executionResultVisible == true
  and .verificationActionVisible == true
  and .candidateRowRemoved == true
  and .reclaimActionHidden == true
  and .reclaimActionHiddenAfterVerificationScan == true
' "$output/e2e-result.json" >/dev/null

test "$(shasum -a 256 "$browser_marker" | awk '{print $1}')" = "$browser_before"
test "$(shasum -a 256 "$codex_marker" | awk '{print $1}')" = "$codex_before"
test "$(shasum -a 256 "$app_marker" | awk '{print $1}')" = "$app_before"
printf '%s  %s\n' "$browser_before" "browser-profile" >"$output/protected-fixture.sha256"
printf '%s  %s\n' "$codex_before" "codex-session" >>"$output/protected-fixture.sha256"
printf '%s  %s\n' "$app_before" "app-bundle" >>"$output/protected-fixture.sha256"

perform_receipt="$(find "$scratch/audit" -name 'receipt-*.json' -type f -print0 | xargs -0 jq -r 'select(.mode == "perform") | input_filename' | head -n 1)"
if [[ -z "$perform_receipt" || ! -f "$perform_receipt" ]]; then
  echo "Packaged-app E2E did not save a perform receipt." >&2
  exit 1
fi
source_path="$(jq -r '.actions[] | select(.status == "done" and .action == "trash") | .path' "$perform_receipt" | head -n 1)"
trash_path="$(jq -r '.actions[] | select(.status == "done" and .action == "trash") | .resultingPath' "$perform_receipt" | head -n 1)"
receipt_fixture="$fixture"
if [[ "$receipt_fixture" == /private/var/* ]]; then
  receipt_fixture="${receipt_fixture#/private}"
fi
if [[ "$source_path" != "$receipt_fixture/"* || "$trash_path" != "$HOME/.Trash/"* || ! -e "$trash_path" ]]; then
  echo "Refusing to clean an E2E Trash artifact without bounded receipt evidence." >&2
  exit 1
fi
if [[ "$keep_trash" != "1" ]]; then
  rm -rf -- "$trash_path"
fi
result_tmp="$scratch/e2e-result.json"
jq --argjson cleaned "$([[ "$keep_trash" == "1" ]] && echo false || echo true)" \
  '. + {protectedFixtureIntact: true, trashArtifactCleaned: $cleaned}' "$output/e2e-result.json" >"$result_tmp"
mv "$result_tmp" "$output/e2e-result.json"

echo "Packaged-app AX E2E passed: $output"
