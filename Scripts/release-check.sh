#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist="$root/dist"
app="$dist/Ryddi.app"
artifact_basename="${RYDDI_ARTIFACT_BASENAME:-Ryddi-developer-preview}"
zip_path="$dist/$artifact_basename.zip"
checksum_path="$zip_path.sha256"
manifest_path="$dist/Ryddi-release-manifest.txt"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ryddi-release-check.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

cd "$root"

echo "==> Running Swift tests"
swift test --scratch-path "$root/.build"

echo "==> Building app bundle"
"$root/Scripts/package-app.sh" >"$scratch/package-app-path.txt"

if [[ ! -d "$app" ]]; then
  echo "missing app bundle: $app" >&2
  exit 1
fi

echo "==> Verifying bundle layout"
for executable in Ryddi reclaimer ReclaimerAgent; do
  if [[ ! -x "$app/Contents/MacOS/$executable" ]]; then
    echo "missing executable: $app/Contents/MacOS/$executable" >&2
    exit 1
  fi
done

plist="$app/Contents/Info.plist"
bundle_name="$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist")"
bundle_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")"

if [[ "$bundle_name" != "Ryddi" ]]; then
  echo "unexpected CFBundleName: $bundle_name" >&2
  exit 1
fi

if [[ "$bundle_id" != "com.reidar.ryddi" ]]; then
  echo "unexpected CFBundleIdentifier: $bundle_id" >&2
  exit 1
fi

rules_path="$(find "$app/Contents/Resources" -type f -name rules.json -print -quit)"
if [[ -z "$rules_path" ]]; then
  echo "missing bundled rules.json" >&2
  exit 1
fi

echo "==> Smoke testing bundled CLI"
"$app/Contents/MacOS/reclaimer" status --json >"$scratch/status-smoke.json"
"$app/Contents/MacOS/reclaimer" permissions --json --path "$root/Tests" >"$scratch/permissions-smoke.json"
grep -q '"coverageLevel"' "$scratch/permissions-smoke.json"
"$app/Contents/MacOS/reclaimer" overview --path "$root/Tests" --limit 5 >"$scratch/overview-smoke.txt"
RYDDI_REPORT_ROOT="$scratch/reports" "$app/Contents/MacOS/reclaimer" report --path "$root/Tests" --limit 5 --output "$scratch/evidence-report.md" --ignore-user-policy
grep -q "# Ryddi Evidence Report" "$scratch/evidence-report.md"
grep -q "Explicit Non-Claims" "$scratch/evidence-report.md"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" containers --json --timeout 2 --save-audit >"$scratch/containers-smoke.json"
RYDDI_CONFIG_ROOT="$scratch/config" "$app/Contents/MacOS/reclaimer" policy protect "$root/Tests" --reason "release smoke" >"$scratch/policy-protect-smoke.txt"
RYDDI_CONFIG_ROOT="$scratch/config" "$app/Contents/MacOS/reclaimer" policy list --json >"$scratch/policy-list-smoke.json"

echo "==> Checking code signing state"
signing_state="unsigned developer preview"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --verify --deep --strict --verbose=2 "$app"
  signing_details="$(codesign -dv --verbose=4 "$app" 2>&1 || true)"
  if ! grep -qi "runtime" <<<"$signing_details"; then
    echo "signed app does not report Hardened Runtime in codesign details" >&2
    exit 1
  fi
  signing_state="signed with Hardened Runtime"
elif codesign --verify --deep --strict --verbose=2 "$app" >"$scratch/codesign-verify.txt" 2>&1; then
  signing_state="pre-signed outside this script"
else
  echo "CODESIGN_IDENTITY not set; treating artifact as unsigned developer preview."
fi

echo "==> Creating zip artifact and checksum"
rm -f "$zip_path" "$checksum_path" "$manifest_path"
(
  cd "$dist"
  /usr/bin/zip -qry -X "$zip_path" "Ryddi.app"
)
shasum -a 256 "$zip_path" | tee "$checksum_path"

commit="unknown"
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  commit="$(git -C "$root" rev-parse HEAD)"
fi

cat >"$manifest_path" <<MANIFEST
Ryddi release check
Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Commit: $commit
Bundle: $app
Bundle name: $bundle_name
Bundle id: $bundle_id
Bundle version: $bundle_version
Rules: ${rules_path#$app/}
Signing state: $signing_state
Artifact: $zip_path
Checksum: $(cat "$checksum_path")

Verification performed:
- swift test --scratch-path "$root/.build"
- Scripts/package-app.sh
- bundle executable/resource checks
- bundled reclaimer status --json
- bundled reclaimer permissions --json --path Tests
- bundled reclaimer overview --path Tests --limit 5
- bundled reclaimer report --path Tests --limit 5 --output evidence-report.md
- bundled reclaimer containers --json --timeout 2 --save-audit with temporary audit root
- bundled reclaimer policy protect/list with temporary config root
- codesign verification when CODESIGN_IDENTITY is set
- zip artifact and SHA-256 checksum generation

Non-claims:
- This manifest is not a notarization receipt.
- Unsigned developer preview artifacts may trigger Gatekeeper warnings.
- Packaging does not grant Full Disk Access.
- Packaging does not execute cleanup, install a LaunchAgent, or verify real disk reclaim.
MANIFEST

echo "==> Release check complete"
echo "$zip_path"
echo "$checksum_path"
echo "$manifest_path"
