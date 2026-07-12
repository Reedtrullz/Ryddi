#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ryddi-app-e2e.XXXXXX")"
app_pid=""
keep_scratch="${RYDDI_E2E_KEEP_SCRATCH:-0}"

cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  if [[ "$keep_scratch" == "1" ]]; then
    echo "Ryddi app E2E scratch preserved: $scratch"
  else
    rm -rf "$scratch"
  fi
}
trap cleanup EXIT

available_kib="$(df -Pk /System/Volumes/Data | awk 'NR == 2 { print $4 }')"
minimum_free_gib="${RYDDI_E2E_MIN_FREE_GIB:-30}"
if ! [[ "$minimum_free_gib" =~ ^[0-9]+$ ]] || (( minimum_free_gib < 1 )); then
  echo "RYDDI_E2E_MIN_FREE_GIB must be a positive integer." >&2
  exit 2
fi
minimum_kib=$((minimum_free_gib * 1024 * 1024))
if [[ -z "$available_kib" || "$available_kib" -lt "$minimum_kib" ]]; then
  echo "Ryddi app E2E requires at least $minimum_free_gib GiB free on /System/Volumes/Data." >&2
  exit 1
fi

fixture="$scratch/fixture"
"$root/Scripts/make-app-e2e-fixture.sh" "$fixture" >"$scratch/fixture-root.txt"

if [[ -n "${RYDDI_E2E_APP_PATH:-}" ]]; then
  app="$RYDDI_E2E_APP_PATH"
  if [[ "$app" != /* ]]; then
    app="$root/$app"
  fi
else
  env -u CODESIGN_IDENTITY \
    CONFIGURATION="${RYDDI_E2E_CONFIGURATION:-debug}" \
    RYDDI_RELEASE_SIGNING=optional \
    "$root/Scripts/package-app.sh" >"$scratch/package-app.txt"
  app="$root/dist/Ryddi.app"
fi

app_binary="$app/Contents/MacOS/Ryddi"
cli="$app/Contents/MacOS/reclaimer"
if [[ ! -x "$app_binary" || ! -x "$cli" ]]; then
  echo "Ryddi app E2E requires a packaged app with Ryddi and reclaimer executables: $app" >&2
  exit 1
fi

audit_root="$scratch/audit"
config_root="$scratch/config"
history_root="$scratch/history"
report_root="$scratch/reports"
holding_root="$scratch/holding"
mkdir -p "$audit_root" "$config_root" "$history_root" "$report_root" "$holding_root"

run_cli() {
  env \
    RYDDI_AUDIT_ROOT="$audit_root" \
    RYDDI_CONFIG_ROOT="$config_root" \
    RYDDI_SCAN_HISTORY_ROOT="$history_root" \
    RYDDI_REPORT_ROOT="$report_root" \
    RYDDI_HOLDING_ROOT="$holding_root" \
    "$cli" "$@"
}

browser_marker="$fixture/Library/Application Support/Google/Chrome/Default/Login Data"
codex_marker="$fixture/.codex/sessions/e2e-session.jsonl"
app_info="$fixture/Applications/Ryddi E2E Fixture.app/Contents/Info.plist"
app_executable="$fixture/Applications/Ryddi E2E Fixture.app/Contents/MacOS/RyddiE2EFixture"
symlink_candidate="$fixture/Library/Caches/Codex/symlink-candidate"
browser_before="$(shasum -a 256 "$browser_marker" | awk '{ print $1 }')"
codex_before="$(shasum -a 256 "$codex_marker" | awk '{ print $1 }')"
app_info_before="$(shasum -a 256 "$app_info" | awk '{ print $1 }')"
app_executable_before="$(shasum -a 256 "$app_executable" | awk '{ print $1 }')"
symlink_before="$(readlink "$symlink_candidate")"

env \
  RYDDI_E2E_MODE=1 \
  RYDDI_E2E_SCOPE_ROOT="$fixture" \
  RYDDI_AUDIT_ROOT="$audit_root" \
  RYDDI_CONFIG_ROOT="$config_root" \
  RYDDI_SCAN_HISTORY_ROOT="$history_root" \
  RYDDI_REPORT_ROOT="$report_root" \
  RYDDI_HOLDING_ROOT="$holding_root" \
  "$app_binary" >"$scratch/app.log" 2>&1 &
app_pid=$!

for _ in {1..20}; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    echo "Ryddi app exited during fixture-mode launch." >&2
    cat "$scratch/app.log" >&2
    exit 1
  fi
  sleep 0.25
done

screenshot="$scratch/ryddi-summary.png"
screenshot_captured="false"
mkdir -p "$root/.build/e2e-module-cache"
window_id="$(
  /usr/bin/swift \
    -module-cache-path "$root/.build/e2e-module-cache" \
    -e 'import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for item in windows {
    let owner = (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    let layer = (item[kCGWindowLayer as String] as? NSNumber)?.intValue
    if owner == pid && layer == 0,
       let number = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value {
        print(number)
        break
    }
}' "$app_pid" 2>"$scratch/window-id.err" || true
)"
if [[ "$window_id" =~ ^[0-9]+$ ]] \
  && command -v screencapture >/dev/null 2>&1 \
  && screencapture -x -o -l "$window_id" "$screenshot" 2>"$scratch/screencapture.err"; then
  if [[ -s "$screenshot" ]] && [[ "$(stat -f%z "$screenshot")" -gt 10000 ]]; then
    sips -g pixelWidth -g pixelHeight "$screenshot" >"$scratch/screenshot-metadata.txt"
    screenshot_captured="true"
  fi
fi
if [[ "$screenshot_captured" != "true" ]]; then
  if [[ "${RYDDI_E2E_REQUIRE_SCREENSHOT:-0}" == "1" ]]; then
    echo "Ryddi app E2E could not capture a non-empty screenshot." >&2
    cat "$scratch/screencapture.err" >&2 2>/dev/null || true
    exit 1
  fi
  echo "warning: screenshot unavailable in this session; app launch proof continues" >&2
fi

common_scan_args=(
  --path "$fixture"
  --min-size 1
  --max-depth 8
  --large-threshold 32768
  --no-lsof
  --json
)
run_cli scan "${common_scan_args[@]}" >"$scratch/scan.json"
run_cli plan "${common_scan_args[@]}" >"$scratch/plan.json"
run_cli execute --dry-run --save-audit "${common_scan_args[@]}" >"$scratch/dry-run.json"

grep -q '"displayName" : "cache.bin"' "$scratch/scan.json"
grep -q "Login Data" "$scratch/scan.json"
grep -q "e2e-session.jsonl" "$scratch/scan.json"
grep -q "symlink-candidate" "$scratch/scan.json"
grep -q '"selected" : true' "$scratch/plan.json"
grep -q '"status" : "dry-run"' "$scratch/dry-run.json"

run_cli apps uninstall \
  --dry-run \
  --no-lsof \
  --save-audit \
  --app "$fixture/Applications/Ryddi E2E Fixture.app" \
  --path "$fixture/Applications" \
  --home "$fixture" \
  --min-size 1 \
  --json >"$scratch/app-uninstall-dry-run.json"
grep -q '"status" : "dry-run"' "$scratch/app-uninstall-dry-run.json"

if [[ "$(shasum -a 256 "$browser_marker" | awk '{ print $1 }')" != "$browser_before" ]]; then
  echo "browser profile fixture changed during app E2E" >&2
  exit 1
fi
if [[ "$(shasum -a 256 "$codex_marker" | awk '{ print $1 }')" != "$codex_before" ]]; then
  echo "Codex session fixture changed during app E2E" >&2
  exit 1
fi
if [[ "$(shasum -a 256 "$app_info" | awk '{ print $1 }')" != "$app_info_before" ]]; then
  echo "app fixture metadata changed during app E2E" >&2
  exit 1
fi
if [[ "$(shasum -a 256 "$app_executable" | awk '{ print $1 }')" != "$app_executable_before" ]]; then
  echo "app fixture executable changed during app E2E" >&2
  exit 1
fi
if [[ ! -L "$symlink_candidate" || "$(readlink "$symlink_candidate")" != "$symlink_before" ]]; then
  echo "symlink fixture changed during app E2E" >&2
  exit 1
fi
if ! kill -0 "$app_pid" 2>/dev/null; then
  echo "Ryddi app exited before fixture E2E completed." >&2
  cat "$scratch/app.log" >&2
  exit 1
fi

echo "Ryddi app E2E passed: launch=yes screenshot=$screenshot_captured scan=yes plan=yes dry-run=yes protected-preserved=yes"
