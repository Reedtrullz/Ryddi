#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
app_name="Ryddi"
bundle_id="com.reidar.ryddi"
bundle_version="${RYDDI_VERSION:-0.2.0}"
bundle_build="${RYDDI_BUILD_NUMBER:-2}"
signing_required="${RYDDI_RELEASE_SIGNING:-optional}"
dist="$root/dist"
app="$dist/$app_name.app"

if [[ "$signing_required" == "required" && -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "RYDDI_RELEASE_SIGNING=required but CODESIGN_IDENTITY is not set." >&2
  exit 1
fi

swift build --scratch-path "$root/.build" -c "$configuration" --product RyddiApp
swift build --scratch-path "$root/.build" -c "$configuration" --product reclaimer
swift build --scratch-path "$root/.build" -c "$configuration" --product ReclaimerAgent
bin_dir="$(swift build --scratch-path "$root/.build" -c "$configuration" --show-bin-path)"
binary="$bin_dir/RyddiApp"
cli_binary="$bin_dir/reclaimer"
agent_binary="$bin_dir/ReclaimerAgent"
resource_bundle="$bin_dir/Ryddi_ReclaimerCore.bundle"
legacy_resource_bundle="$bin_dir/MacDiskReclaimer_ReclaimerCore.bundle"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/$app_name"
cp "$cli_binary" "$app/Contents/MacOS/reclaimer"
cp "$agent_binary" "$app/Contents/MacOS/ReclaimerAgent"
if [[ -d "$resource_bundle" ]]; then
  cp -R "$resource_bundle" "$app/Contents/Resources/"
elif [[ -d "$legacy_resource_bundle" ]]; then
  cp -R "$legacy_resource_bundle" "$app/Contents/Resources/"
fi

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$app_name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleName</key>
  <string>$app_name</string>
  <key>CFBundleDisplayName</key>
  <string>$app_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$bundle_version</string>
  <key>CFBundleVersion</key>
  <string>$bundle_build</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Reidar</string>
</dict>
</plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app"
else
  echo "CODESIGN_IDENTITY not set; app bundle left unsigned."
fi

echo "$app"
