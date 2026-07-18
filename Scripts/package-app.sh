#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
app_name="Ryddi"
bundle_id="com.reidar.ryddi"
bundle_version="${RYDDI_VERSION:-0.4.0}"
bundle_build="${RYDDI_BUILD_NUMBER:-5}"
source_commit="${RYDDI_SOURCE_COMMIT:-$(git -C "$root" rev-parse HEAD)}"
source_dirty="${RYDDI_SOURCE_DIRTY:-$([[ -n "$(git -C "$root" status --porcelain --untracked-files=normal)" ]] && echo true || echo false)}"
build_date="${RYDDI_BUILD_DATE:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
signing_required="${RYDDI_RELEASE_SIGNING:-optional}"
dist="$root/dist"
app="$dist/$app_name.app"
icon="$root/Assets/Ryddi.icns"
sparkle_public_key="4YdSipywmXBBwUau2EfbDEcHTuvbJKxTkJATpH0gnnU="

if [[ ! -s "$icon" ]]; then
  echo "missing packaged app icon: $icon" >&2
  exit 1
fi

if [[ "$signing_required" == "required" && -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "RYDDI_RELEASE_SIGNING=required but CODESIGN_IDENTITY is not set." >&2
  exit 1
fi

if [[ "$signing_required" == "required" && -n "${CODESIGN_IDENTITY:-}" ]]; then
  identity_line="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$CODESIGN_IDENTITY" || true)"
  if ! grep -q "Developer ID Application" <<<"$identity_line"; then
    echo "RYDDI_RELEASE_SIGNING=required requires a Developer ID Application identity." >&2
    echo "Current CODESIGN_IDENTITY did not resolve to a Developer ID Application certificate." >&2
    exit 1
  fi
fi

swift build --scratch-path "$root/.build" -c "$configuration" --product RyddiApp
swift build --scratch-path "$root/.build" -c "$configuration" --product reclaimer
bin_dir="$(swift build --scratch-path "$root/.build" -c "$configuration" --show-bin-path)"
binary="$bin_dir/RyddiApp"
cli_binary="$bin_dir/reclaimer"
resource_bundle="$bin_dir/Ryddi_ReclaimerCore.bundle"
legacy_resource_bundle="$bin_dir/MacDiskReclaimer_ReclaimerCore.bundle"
selected_resource_bundle=""
sparkle_framework="$bin_dir/Sparkle.framework"

if [[ ! -d "$sparkle_framework" ]]; then
  echo "missing built Sparkle.framework: $sparkle_framework" >&2
  exit 1
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$icon" "$app/Contents/Resources/Ryddi.icns"
cp "$binary" "$app/Contents/MacOS/$app_name"
cp "$cli_binary" "$app/Contents/MacOS/reclaimer"
/usr/bin/ditto "$sparkle_framework" "$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$resource_bundle" ]]; then
  selected_resource_bundle="$resource_bundle"
elif [[ -d "$legacy_resource_bundle" ]]; then
  selected_resource_bundle="$legacy_resource_bundle"
fi
if [[ -n "$selected_resource_bundle" ]]; then
  conventional_resource_bundle="$app/Contents/Resources/$(basename "$selected_resource_bundle")"
  cp -R "$selected_resource_bundle" "$conventional_resource_bundle"
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
  <key>CFBundleIconFile</key>
  <string>Ryddi</string>
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
  <key>SUFeedURL</key>
  <string>https://raw.githubusercontent.com/Reedtrullz/Ryddi/main/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>$sparkle_public_key</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUAllowsAutomaticUpdates</key>
  <false/>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
  <key>SURequireSignedFeed</key>
  <true/>
</dict>
</plist>
PLIST

build_metadata="$app/Contents/Resources/Ryddi-build.json"
build_metadata_plist="$app/Contents/Resources/.Ryddi-build.plist"
/usr/bin/plutil -create xml1 "$build_metadata_plist"
/usr/bin/plutil -insert version -string "$bundle_version" "$build_metadata_plist"
/usr/bin/plutil -insert build -string "$bundle_build" "$build_metadata_plist"
/usr/bin/plutil -insert sourceCommit -string "$source_commit" "$build_metadata_plist"
/usr/bin/plutil -insert sourceDirty -string "$source_dirty" "$build_metadata_plist"
/usr/bin/plutil -insert buildDate -string "$build_date" "$build_metadata_plist"
/usr/bin/plutil -convert json -o "$build_metadata" "$build_metadata_plist"
rm "$build_metadata_plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$sparkle/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$CODESIGN_IDENTITY" "$sparkle/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$sparkle/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$sparkle/Updater.app"
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app/Contents/MacOS/reclaimer"
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app"
  codesign --verify --deep --strict --verbose=2 "$app/Contents/Frameworks/Sparkle.framework"
  codesign --verify --strict --verbose=2 "$app/Contents/MacOS/reclaimer"
  codesign --verify --deep --strict --verbose=2 "$app"
else
  echo "CODESIGN_IDENTITY not set; app bundle left unsigned."
fi

echo "$app"
