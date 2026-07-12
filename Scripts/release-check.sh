#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist="$root/dist"
app="$dist/Ryddi.app"
signing_required="${RYDDI_RELEASE_SIGNING:-optional}"
release_version="${RYDDI_VERSION:-0.3.0}"
release_build="${RYDDI_BUILD_NUMBER:-3}"
if [[ -n "${RYDDI_ARTIFACT_BASENAME:-}" ]]; then
  artifact_basename="$RYDDI_ARTIFACT_BASENAME"
elif [[ "$signing_required" == "required" ]]; then
  artifact_basename="Ryddi-v$release_version"
else
  artifact_basename="Ryddi-developer-preview"
fi
zip_path="$dist/$artifact_basename.zip"
checksum_path="$zip_path.sha256"
manifest_path="$dist/Ryddi-release-manifest.txt"
stage_dir="$dist/$artifact_basename"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ryddi-release-check.XXXXXX")"
hidden_build_dir=""
packaged_ax_e2e_status="not-required"

cleanup() {
  if [[ -n "$hidden_build_dir" && -d "$hidden_build_dir" ]]; then
    if [[ ! -e "$root/.build" ]]; then
      mv "$hidden_build_dir" "$root/.build"
    else
      echo "warning: leaving hidden build dir in place because $root/.build was recreated: $hidden_build_dir" >&2
    fi
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT

hide_build_dir_for_packaged_smokes() {
  if [[ -d "$root/.build" ]]; then
    hidden_build_dir="$root/.build.release-check-hidden.$$"
    rm -rf "$hidden_build_dir"
    mv "$root/.build" "$hidden_build_dir"
  fi
}

assert_public_manifest_has_no_local_paths() {
  local manifest="$1"
  if [[ -n "${HOME:-}" ]] && grep -F "$HOME" "$manifest" >/dev/null 2>&1; then
    echo "release manifest leaks HOME path: $HOME" >&2
    exit 1
  fi
  if [[ -n "$root" ]] && grep -F "$root" "$manifest" >/dev/null 2>&1; then
    echo "release manifest leaks repository path: $root" >&2
    exit 1
  fi
  if grep -Eq '/Users/[^[:space:]]+' "$manifest"; then
    echo "release manifest leaks a /Users absolute path" >&2
    exit 1
  fi
}

archive_staged_release() {
  local staged_manifest="$stage_dir/Ryddi-release-manifest.txt"
  local staged_checksums="$stage_dir/Ryddi-checksums.sha256"
  if [[ ! -d "$stage_dir/Ryddi.app" || ! -f "$staged_manifest" || ! -f "$staged_checksums" ]]; then
    echo "staged release is incomplete: $stage_dir" >&2
    return 1
  fi
  rm -f "$zip_path" "$checksum_path"
  /usr/bin/ditto -c -k --keepParent "$stage_dir" "$zip_path"
  shasum -a 256 "$zip_path" >"$checksum_path"
  cp "$staged_manifest" "$manifest_path"
}

stage_release_artifact() {
  if [[ "$signing_required" == "required" ]]; then
    if [[ "$artifact_basename" != Ryddi-v* ]]; then
      echo "signed releases require a versioned Ryddi-v* artifact name" >&2
      return 1
    fi
    release_kind="signed-notarized-release"
  else
    if [[ "$artifact_basename" == Ryddi-v* ]]; then
      echo "unsigned previews cannot use a versioned release artifact name" >&2
      return 1
    fi
    release_kind="unsigned-preview"
    signing_identity="unsigned"
  fi

  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"
  /usr/bin/ditto "$app" "$stage_dir/Ryddi.app"
  if [[ "$packaged_ax_e2e_status" == "passed" ]]; then
    /usr/bin/ditto "$dist/e2e-proof" "$stage_dir/Packaged-App-E2E"
  fi

  local payload_probe="$dist/.Ryddi-app-payload.zip"
  rm -f "$payload_probe"
  /usr/bin/ditto -c -k --keepParent "$app" "$payload_probe"
  app_payload_sha="$(shasum -a 256 "$payload_probe" | awk '{print $1}')"
  rm -f "$payload_probe"

  cat >"$stage_dir/Ryddi-release-manifest.txt" <<MANIFEST
manifest_schema=ryddi.release-trust.v1
release_kind=$release_kind
version=$bundle_version
build=$bundle_build
source_commit=$commit
signing_identity=$signing_identity
codesign_verified=$codesign_verified
hardened_runtime=$hardened_runtime
notarization_submission_id=$notary_submission
notarization_status=$notarization_status
stapler_validated=$stapler_validated
stapled=$stapler_validated
gatekeeper=$gatekeeper_status
packaged_ax_e2e=$packaged_ax_e2e_status
packaged_ax_e2e_proof=$([[ "$packaged_ax_e2e_status" == "passed" ]] && echo included || echo not-included)
sha256=$app_payload_sha

Ryddi release evidence
Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Artifact directory: $artifact_basename
App payload SHA-256: $app_payload_sha

Non-claims:
- The app payload hash is distinct from the external archive checksum.
- Gatekeeper acceptance does not by itself prove that a notarization ticket is stapled.
- Packaging does not grant Full Disk Access or execute cleanup.
MANIFEST
  printf '%s  %s\n' "$app_payload_sha" "Ryddi.app" >"$stage_dir/Ryddi-checksums.sha256"
  assert_public_manifest_has_no_local_paths "$stage_dir/Ryddi-release-manifest.txt"
  archive_staged_release
}

if [[ "${RYDDI_RELEASE_CHECK_LIBRARY_ONLY:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

cd "$root"
rm -f "$zip_path" "$checksum_path" "$manifest_path"

if [[ "$signing_required" == "required" ]]; then
  if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
    echo "RYDDI_RELEASE_SIGNING=required but CODESIGN_IDENTITY is not set." >&2
    exit 1
  fi
  identity_line="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$CODESIGN_IDENTITY" || true)"
  if ! grep -q "Developer ID Application" <<<"$identity_line"; then
    echo "RYDDI_RELEASE_SIGNING=required requires a Developer ID Application identity." >&2
    echo "Current CODESIGN_IDENTITY did not resolve to a Developer ID Application certificate." >&2
    exit 1
  fi
  if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
      echo "RYDDI_RELEASE_SIGNING=required requires NOTARY_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD." >&2
      exit 1
    fi
  fi
fi

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
bundle_build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")"

if [[ "$bundle_name" != "Ryddi" ]]; then
  echo "unexpected CFBundleName: $bundle_name" >&2
  exit 1
fi

if [[ "$bundle_id" != "com.reidar.ryddi" ]]; then
  echo "unexpected CFBundleIdentifier: $bundle_id" >&2
  exit 1
fi

if [[ "$signing_required" == "required" && "$bundle_version" != "$release_version" ]]; then
  echo "unexpected release CFBundleShortVersionString: $bundle_version" >&2
  exit 1
fi

if [[ "$signing_required" == "required" && "$bundle_build" != "$release_build" ]]; then
  echo "unexpected release CFBundleVersion: $bundle_build" >&2
  exit 1
fi

rules_path="$(find "$app/Contents/Resources" -type f -name rules.json -print -quit)"
if [[ -z "$rules_path" ]]; then
  echo "missing bundled rules.json" >&2
  exit 1
fi

echo "==> Running fixture-backed app E2E"
RYDDI_E2E_APP_PATH="$app" \
  RYDDI_E2E_REQUIRE_SCREENSHOT="${RYDDI_E2E_REQUIRE_SCREENSHOT:-0}" \
  "$root/Scripts/app-e2e-smoke.sh"

if [[ "${RYDDI_REQUIRE_PACKAGED_AX_E2E:-0}" == "1" ]]; then
  echo "==> Running packaged-app Accessibility E2E"
  RYDDI_E2E_APP_PATH="$app" \
    RYDDI_E2E_OUTPUT="$dist/e2e-proof" \
    "$root/Scripts/run-packaged-app-e2e.sh"
  jq -e '.executionResultVisible == true and .originalCandidateMissing == true and .trashArtifactCleaned == true' \
    "$dist/e2e-proof/e2e-result.json" >/dev/null
  packaged_ax_e2e_status="passed"
else
  rm -rf "$dist/e2e-proof"
fi

echo "==> Smoke testing bundled CLI"
hide_build_dir_for_packaged_smokes
receipt_fixture="$scratch/receipt-fixture/Library/Caches/Codex"
mkdir -p "$receipt_fixture"
printf 'fixture cache\n' >"$receipt_fixture/cache.bin"
native_fixture="$scratch/native-fixture/Library/Caches/Homebrew/downloads"
mkdir -p "$native_fixture"
printf 'homebrew cache\n' >"$native_fixture/bottle.tar.gz"
trash_fixture="$scratch/trash-fixture/.Trash"
mkdir -p "$trash_fixture"
printf 'old download\n' >"$trash_fixture/old-download.dmg"
printf 'hidden trash\n' >"$trash_fixture/.hidden-trash"
downloads_fixture="$scratch/downloads-fixture/Downloads"
mkdir -p "$downloads_fixture"
printf 'installer image\n' >"$downloads_fixture/FixtureInstaller.dmg"
printf 'package installer\n' >"$downloads_fixture/FixturePackage.pkg"
printf 'download archive\n' >"$downloads_fixture/FixtureArchive.zip"
printf 'old loose note\n' >"$downloads_fixture/old-note.txt"
touch -t 202401010101 "$downloads_fixture/FixtureInstaller.dmg" "$downloads_fixture/FixtureArchive.zip" "$downloads_fixture/old-note.txt"
browser_fixture="$scratch/browser-fixture"
browser_cache="$browser_fixture/Library/Caches/Google/Chrome/Default"
browser_profile="$browser_fixture/Library/Application Support/Google/Chrome/Default"
mkdir -p \
  "$browser_cache/Cache/Cache_Data" \
  "$browser_cache/Code Cache/js" \
  "$browser_cache/GPUCache" \
  "$browser_profile"
printf 'browser disk cache\n' >"$browser_cache/Cache/Cache_Data/data_0"
printf 'browser code cache\n' >"$browser_cache/Code Cache/js/script.bin"
printf 'browser gpu cache\n' >"$browser_cache/GPUCache/gpu.bin"
printf 'profile should remain protected\n' >"$browser_profile/Login Data"
package_fixture="$scratch/package-fixture"
package_homebrew="$package_fixture/Library/Caches/Homebrew"
package_npm="$package_fixture/.npm/_cacache"
package_gradle="$package_fixture/.gradle/caches"
mkdir -p \
  "$package_homebrew/downloads" \
  "$package_npm/content-v2/sha512/aa" \
  "$package_gradle/modules-2/files-2.1/example" \
  "$package_fixture/.m2"
printf 'homebrew bottle\n' >"$package_homebrew/downloads/bottle.tar.gz"
printf 'npm package cache\n' >"$package_npm/content-v2/sha512/aa/cache.bin"
printf 'gradle artifact\n' >"$package_gradle/modules-2/files-2.1/example/artifact.jar"
printf '//registry.npmjs.org/:_authToken=fixture\n' >"$package_fixture/.npmrc"
printf '<settings>fixture</settings>\n' >"$package_fixture/.m2/settings.xml"
project_fixture="$scratch/project-fixture"
project_root="$project_fixture/Projects"
project_web="$project_root/WebApp"
project_python="$project_root/PyApp"
project_swift="$project_root/SwiftApp"
project_rust="$project_root/RustApp"
project_ios="$project_root/iOSApp"
project_flutter="$project_root/FlutterApp"
project_android="$project_root/AndroidApp"
project_skipped="$project_root/SkippedWeb"
project_mono="$project_root/MonoRepo"
project_mono_web="$project_mono/apps/web"
mkdir -p \
  "$project_web/src" \
  "$project_web/node_modules/react" \
  "$project_web/.next/cache" \
  "$project_web/dist" \
  "$project_python/.venv/lib/python/site-packages" \
  "$project_swift/.build/debug" \
  "$project_rust/target/debug" \
  "$project_ios/Pods/Alamofire" \
  "$project_flutter/.dart_tool" \
  "$project_flutter/build" \
  "$project_android/app/src/main" \
  "$project_android/app/build/intermediates" \
  "$project_skipped/node_modules/react" \
  "$project_mono_web/node_modules/react" \
  "$project_mono_web/dist"
printf '{"name":"fixture-web","packageManager":"npm@10.8.0","scripts":{"build":"vite build","clean":"rimraf dist .next","deploy":"vercel --prod --token=abc123","postinstall":"node scripts/postinstall.js","test:coverage":"vitest --coverage","bad script":"echo unsafe"}}\n' >"$project_web/package.json"
printf '{"lockfileVersion":3}\n' >"$project_web/package-lock.json"
printf 'source should remain protected\n' >"$project_web/src/index.ts"
printf 'SECRET=fixture\n' >"$project_web/.env"
printf 'node_modules/\n.next/\ndist/\n' >"$project_web/.gitignore"
printf 'react package\n' >"$project_web/node_modules/react/index.js"
printf 'next cache\n' >"$project_web/.next/cache/chunk.bin"
printf 'web build\n' >"$project_web/dist/app.js"
git -C "$project_web" init -q
git -C "$project_web" config user.name "Ryddi Release Check"
git -C "$project_web" config user.email "ryddi-release-check@example.invalid"
git -C "$project_web" config commit.gpgsign false
git -C "$project_web" add .gitignore package.json package-lock.json src/index.ts
git -C "$project_web" -c commit.gpgsign=false commit -qm "fixture"
printf 'source should remain protected after dirty change\n' >"$project_web/src/index.ts"
printf 'local untracked evidence\n' >"$project_web/local-note.md"
printf '[project]\nname = "fixture"\n' >"$project_python/pyproject.toml"
printf 'home = /usr/bin\n' >"$project_python/.venv/pyvenv.cfg"
printf 'python package\n' >"$project_python/.venv/lib/python/site-packages/pkg.py"
printf 'let package = Package(name: "Fixture")\n' >"$project_swift/Package.swift"
printf 'swift object\n' >"$project_swift/.build/debug/App.o"
printf '[package]\nname = "fixture"\n' >"$project_rust/Cargo.toml"
printf 'rust binary\n' >"$project_rust/target/debug/app"
printf "platform :ios, '17.0'\n" >"$project_ios/Podfile"
printf 'pod source\n' >"$project_ios/Pods/Alamofire/file.swift"
printf 'name: fixture\n' >"$project_flutter/pubspec.yaml"
printf '{"configVersion":2}\n' >"$project_flutter/.dart_tool/package_config.json"
printf 'flutter build\n' >"$project_flutter/build/app.dill"
printf 'pluginManagement {}\n' >"$project_android/settings.gradle"
printf 'plugins { id "com.android.application" }\n' >"$project_android/app/build.gradle"
printf '<manifest />\n' >"$project_android/app/src/main/AndroidManifest.xml"
printf 'android classes\n' >"$project_android/app/build/intermediates/classes.bin"
printf '{"scripts":{"build":"vite build"}}\n' >"$project_skipped/package.json"
printf '{"lockfileVersion":3}\n' >"$project_skipped/package-lock.json"
printf 'skipped project dependency\n' >"$project_skipped/node_modules/react/index.js"
printf '{"name":"fixture-monorepo","packageManager":"pnpm@9.2.0","workspaces":["apps/*","packages/*"]}\n' >"$project_mono/package.json"
printf 'packages:\n  - "apps/*"\n  - "packages/*"\n' >"$project_mono/pnpm-workspace.yaml"
printf 'lockfile\n' >"$project_mono/pnpm-lock.yaml"
printf '{"name":"@fixtures/web","scripts":{"build":"vite build","clean":"rimraf dist"}}\n' >"$project_mono_web/package.json"
printf 'monorepo dependency\n' >"$project_mono_web/node_modules/react/index.js"
printf 'monorepo dist\n' >"$project_mono_web/dist/app.js"
device_fixture="$scratch/device-fixture"
device_backup_root="$device_fixture/Library/Application Support/MobileSync/Backup"
device_backup_a="$device_backup_root/1111222233334444555566667777888899990000"
device_backup_b="$device_backup_root/aaaabbbbccccdddd"
mkdir -p "$device_backup_a/00" "$device_backup_b/01"
printf 'ios backup data\n' >"$device_backup_a/00/backup-data.bin"
printf 'metadata missing backup data\n' >"$device_backup_b/01/backup-data.bin"
cat >"$device_backup_a/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Display Name</key>
  <string>Release Smoke iPhone</string>
  <key>Device Name</key>
  <string>Release Smoke Device</string>
  <key>Product Name</key>
  <string>iPhone</string>
  <key>Product Type</key>
  <string>iPhone16,1</string>
  <key>Last Backup Date</key>
  <date>2024-01-01T01:01:01Z</date>
  <key>Is Encrypted</key>
  <true/>
</dict>
</plist>
PLIST
xcode_fixture="$scratch/xcode-fixture"
xcode_derived="$xcode_fixture/Library/Developer/Xcode/DerivedData/ReleaseSmoke-abc/Build/Products"
xcode_module="$xcode_fixture/Library/Developer/Xcode/ModuleCache.noindex/Swift"
xcode_docs="$xcode_fixture/Library/Developer/Xcode/DocumentationCache"
xcode_archive="$xcode_fixture/Library/Developer/Xcode/Archives/2026-01-01/ReleaseSmoke.xcarchive"
xcode_device_support="$xcode_fixture/Library/Developer/Xcode/iOS DeviceSupport/17.2/Symbols"
xcode_simulator="$xcode_fixture/Library/Developer/CoreSimulator/Devices/SIM-1"
xcode_runtime="$xcode_fixture/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 17.simruntime/Contents"
xcode_logs="$xcode_fixture/Library/Logs/CoreSimulator"
xcode_user_data="$xcode_fixture/Library/Developer/Xcode/UserData/CodeSnippets"
xcode_profiles="$xcode_fixture/Library/MobileDevice/Provisioning Profiles"
mkdir -p \
  "$xcode_derived" \
  "$xcode_module" \
  "$xcode_docs" \
  "$xcode_archive/dSYMs/ReleaseSmoke.app.dSYM/Contents/Resources/DWARF" \
  "$xcode_device_support" \
  "$xcode_simulator/data/Containers/Data/Application" \
  "$xcode_runtime" \
  "$xcode_logs" \
  "$xcode_user_data" \
  "$xcode_profiles"
printf 'object file\n' >"$xcode_derived/app.o"
printf 'module cache\n' >"$xcode_module/Swift.pcm"
printf 'documentation cache\n' >"$xcode_docs/doc.db"
printf 'archive symbols\n' >"$xcode_archive/dSYMs/ReleaseSmoke.app.dSYM/Contents/Resources/DWARF/ReleaseSmoke"
printf 'device symbols\n' >"$xcode_device_support/symbol.bin"
printf 'simulator app data\n' >"$xcode_simulator/data/Containers/Data/Application/app.db"
printf 'simulator runtime\n' >"$xcode_runtime/runtime.bin"
printf 'simulator log\n' >"$xcode_logs/sim.log"
printf 'snippet should stay protected\n' >"$xcode_user_data/snippet.codesnippet"
printf 'profile should stay protected\n' >"$xcode_profiles/profile.mobileprovision"
cat >"$xcode_archive/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>ApplicationProperties</key>
  <dict>
    <key>ApplicationName</key>
    <string>ReleaseSmoke</string>
  </dict>
</dict>
</plist>
PLIST
cat >"$xcode_simulator/device.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>name</key>
  <string>Release Smoke iPhone</string>
</dict>
</plist>
PLIST
agent_fixture="$scratch/agent-fixture"
mkdir -p \
  "$agent_fixture/.codex/cache" \
  "$agent_fixture/.codex/sessions/2026/07" \
  "$agent_fixture/.claude/projects" \
  "$agent_fixture/.ollama/models/blobs" \
  "$agent_fixture/Library/Application Support/Cursor/Cache"
printf 'agent cache\n' >"$agent_fixture/.codex/cache/blob.bin"
printf '{"token":"fixture"}\n' >"$agent_fixture/.codex/auth.json"
printf 'session fixture\n' >"$agent_fixture/.codex/sessions/2026/07/session.jsonl"
printf 'claude project fixture\n' >"$agent_fixture/.claude/projects/project.jsonl"
printf 'ollama model fixture\n' >"$agent_fixture/.ollama/models/blobs/model.bin"
printf 'cursor cache fixture\n' >"$agent_fixture/Library/Application Support/Cursor/Cache/cache.bin"
touch -t 202401010101 \
  "$agent_fixture/.codex/cache" \
  "$agent_fixture/.codex/cache/blob.bin" \
  "$agent_fixture/.codex/sessions" \
  "$agent_fixture/.codex/sessions/2026" \
  "$agent_fixture/.codex/sessions/2026/07" \
  "$agent_fixture/.codex/sessions/2026/07/session.jsonl" \
  "$agent_fixture/.codex/auth.json" \
  "$agent_fixture/.claude/projects" \
  "$agent_fixture/.claude/projects/project.jsonl" \
  "$agent_fixture/Library/Application Support/Cursor/Cache" \
  "$agent_fixture/Library/Application Support/Cursor/Cache/cache.bin"
drill_fixture="$scratch/drill-fixture"
mkdir -p \
  "$drill_fixture/Library/Caches/Codex" \
  "$drill_fixture/Library/Logs/com.openai.codex" \
  "$drill_fixture/Downloads/Installers"
printf 'drill cache\n' >"$drill_fixture/Library/Caches/Codex/cache.bin"
printf 'drill log\n' >"$drill_fixture/Library/Logs/com.openai.codex/old.log"
printf 'drill download\n' >"$drill_fixture/Downloads/Installers/app.dmg"
large_fixture="$scratch/large-fixture"
mkdir -p "$large_fixture/Downloads" "$large_fixture/Library/Caches/Codex"
dd if=/dev/zero of="$large_fixture/Downloads/old-large.mov" bs=24000 count=1 2>/dev/null
dd if=/dev/zero of="$large_fixture/Downloads/large-only.dmg" bs=28000 count=1 2>/dev/null
printf 'old note\n' >"$large_fixture/Downloads/old-only.txt"
dd if=/dev/zero of="$large_fixture/Library/Caches/Codex/cache.bin" bs=32000 count=1 2>/dev/null
touch -t 202401010101 "$large_fixture/Downloads/old-large.mov" "$large_fixture/Downloads/old-only.txt"
app_fixture="$scratch/app-fixture"
app_root="$app_fixture/Applications"
app_home="$app_fixture/Home"
app_bundle="$app_root/Fixture.app"
mkdir -p \
  "$app_bundle/Contents/MacOS" \
  "$app_home/Library/Caches/com.example.fixture" \
  "$app_home/Library/Preferences"
cat >"$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.fixture</string>
  <key>CFBundleDisplayName</key>
  <string>Fixture</string>
  <key>CFBundleName</key>
  <string>Fixture</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleExecutable</key>
  <string>Fixture</string>
</dict>
</plist>
PLIST
printf 'fixture executable\n' >"$app_bundle/Contents/MacOS/Fixture"
printf 'fixture cache\n' >"$app_home/Library/Caches/com.example.fixture/cache.bin"
printf 'fixture preferences\n' >"$app_home/Library/Preferences/com.example.fixture.plist"
"$app/Contents/MacOS/reclaimer" status --json >"$scratch/status-smoke.json"
"$app/Contents/MacOS/reclaimer" scopes --preset general >"$scratch/scopes-general-smoke.txt"
grep -q "Mode: General Mac" "$scratch/scopes-general-smoke.txt"
grep -q "Downloads review" "$scratch/scopes-general-smoke.txt"
grep -q "Scanning personal folders is review-oriented" "$scratch/scopes-general-smoke.txt"
"$app/Contents/MacOS/reclaimer" scopes --json --preset all >"$scratch/scopes-all-smoke.json"
grep -q '"label" : "All"' "$scratch/scopes-all-smoke.json"
grep -q '"preset" : "all"' "$scratch/scopes-all-smoke.json"
"$app/Contents/MacOS/reclaimer" scopes templates list --include-missing-scopes >"$scratch/scope-templates-list.txt"
grep -q "Ryddi scope templates" "$scratch/scope-templates-list.txt"
grep -q "Weekly General Review" "$scratch/scope-templates-list.txt"
grep -q "Package Manager Caches" "$scratch/scope-templates-list.txt"
grep -q "Project Dependencies" "$scratch/scope-templates-list.txt"
grep -q "Xcode Review" "$scratch/scope-templates-list.txt"
grep -q "Device Backups Review" "$scratch/scope-templates-list.txt"
"$app/Contents/MacOS/reclaimer" scopes templates show weekly-general --json >"$scratch/scope-template-show.json"
grep -q '"id" : "weekly-general"' "$scratch/scope-template-show.json"
grep -q '"recommendedUse"' "$scratch/scope-template-show.json"
"$app/Contents/MacOS/reclaimer" scopes --template weekly-general --json >"$scratch/scope-template-plan.json"
grep -q '"label" : "Weekly General Review"' "$scratch/scope-template-plan.json"
grep -q "Scope templates are suggested scan roots only" "$scratch/scope-template-plan.json"
RYDDI_CONFIG_ROOT="$scratch/template-config" "$app/Contents/MacOS/reclaimer" scopes templates save weekly-general \
  --name "Weekly Template Copy" \
  --json >"$scratch/scope-template-save.json"
grep -q '"name" : "Weekly Template Copy"' "$scratch/scope-template-save.json"
RYDDI_CONFIG_ROOT="$scratch/template-config" "$app/Contents/MacOS/reclaimer" scopes saved show "Weekly Template Copy" >"$scratch/scope-template-saved-show.txt"
grep -q "Saved scope set: Weekly Template Copy" "$scratch/scope-template-saved-show.txt"
scope_fixture="$scratch/scope-fixture"
mkdir -p "$scope_fixture/Downloads" "$scope_fixture/Library/Caches/Codex"
printf 'scope download\n' >"$scope_fixture/Downloads/app.dmg"
printf 'scope cache\n' >"$scope_fixture/Library/Caches/Codex/cache.bin"
RYDDI_CONFIG_ROOT="$scratch/scope-config" "$app/Contents/MacOS/reclaimer" scopes saved add "General Fixture" \
  --path "$scope_fixture/Downloads" \
  --path "$scope_fixture/Library/Caches" \
  --summary "Release smoke saved scope set." \
  --json >"$scratch/scope-set-add.json"
grep -q '"name" : "General Fixture"' "$scratch/scope-set-add.json"
grep -q '"Release smoke saved scope set."' "$scratch/scope-set-add.json"
RYDDI_CONFIG_ROOT="$scratch/scope-config" "$app/Contents/MacOS/reclaimer" scopes saved list >"$scratch/scope-set-list.txt"
grep -q "General Fixture" "$scratch/scope-set-list.txt"
RYDDI_CONFIG_ROOT="$scratch/scope-config" "$app/Contents/MacOS/reclaimer" scopes saved show "General Fixture" >"$scratch/scope-set-show.txt"
grep -q "Saved scope set: General Fixture" "$scratch/scope-set-show.txt"
RYDDI_CONFIG_ROOT="$scratch/scope-config" "$app/Contents/MacOS/reclaimer" scopes --scope-set "General Fixture" --json >"$scratch/scope-set-plan.json"
grep -q '"label" : "General Fixture"' "$scratch/scope-set-plan.json"
grep -q "Saved scope sets store scan roots only" "$scratch/scope-set-plan.json"
RYDDI_CONFIG_ROOT="$scratch/scope-config" "$app/Contents/MacOS/reclaimer" scan --json --scope-set "General Fixture" --min-size 1 --max-depth 2 >"$scratch/scope-set-scan.json"
grep -q '"scopeName" : "Downloads"' "$scratch/scope-set-scan.json"
grep -q '"scopeName" : "Caches"' "$scratch/scope-set-scan.json"
RYDDI_CONFIG_ROOT="$scratch/scope-config" "$app/Contents/MacOS/reclaimer" scopes saved export --output "$scratch/scope-set-export.json"
grep -q '"sets"' "$scratch/scope-set-export.json"
RYDDI_CONFIG_ROOT="$scratch/scope-import-config" "$app/Contents/MacOS/reclaimer" scopes saved import "$scratch/scope-set-export.json" --replace --json >"$scratch/scope-set-import.json"
grep -q '"mode" : "replace"' "$scratch/scope-set-import.json"
grep -q '"finalSetCount" : 1' "$scratch/scope-set-import.json"
RYDDI_CONFIG_ROOT="$scratch/scope-config" "$app/Contents/MacOS/reclaimer" schedule preview \
  --kind evidence \
  --preset general \
  --hour 7 \
  --minute 15 \
  --limit 25 \
  --cli-path "$app/Contents/MacOS/reclaimer" >"$scratch/schedule-general-preview.plist"
grep -q "Ryddi scheduled report preview" "$scratch/schedule-general-preview.plist"
grep -q "<string>report</string>" "$scratch/schedule-general-preview.plist"
grep -q "<string>--save-report</string>" "$scratch/schedule-general-preview.plist"
grep -q "<string>general</string>" "$scratch/schedule-general-preview.plist"
grep -q "<integer>7</integer>" "$scratch/schedule-general-preview.plist"
if grep -q "<string>execute</string>" "$scratch/schedule-general-preview.plist"; then
  echo "schedule preview unexpectedly includes execute" >&2
  exit 1
fi
RYDDI_CONFIG_ROOT="$scratch/scope-config" "$app/Contents/MacOS/reclaimer" schedule preview \
  --json \
  --scope-set "General Fixture" \
  --hour 8 \
  --minute 45 \
  --cli-path "$app/Contents/MacOS/reclaimer" >"$scratch/schedule-scope-set-preview.json"
grep -q '"kind" : "savedScopeSet"' "$scratch/schedule-scope-set-preview.json"
grep -q '"value" : "General Fixture"' "$scratch/schedule-scope-set-preview.json"
grep -q '"--scope-set"' "$scratch/schedule-scope-set-preview.json"
"$app/Contents/MacOS/reclaimer" schedule preview \
  --json \
  --kind evidence \
  --template weekly-general \
  --cli-path "$app/Contents/MacOS/reclaimer" >"$scratch/schedule-template-preview.json"
grep -q '"kind" : "template"' "$scratch/schedule-template-preview.json"
grep -q '"value" : "weekly-general"' "$scratch/schedule-template-preview.json"
grep -q '"--template"' "$scratch/schedule-template-preview.json"
if "$app/Contents/MacOS/reclaimer" schedule uninstall --unload >"$scratch/schedule-uninstall-manual.log" 2>&1; then
  echo "bundled CLI unexpectedly unloaded or removed a LaunchAgent schedule" >&2
  exit 1
fi
grep -q "will not unload or remove LaunchAgent files automatically" "$scratch/schedule-uninstall-manual.log"
"$app/Contents/MacOS/reclaimer" rules >"$scratch/rules-smoke.txt"
grep -q "Ryddi rule catalog" "$scratch/rules-smoke.txt"
grep -q "Never Touch" "$scratch/rules-smoke.txt"
"$app/Contents/MacOS/reclaimer" rules --json >"$scratch/rules-smoke.json"
grep -q '"ruleVersion"' "$scratch/rules-smoke.json"
grep -q '"codex.credentials.never"' "$scratch/rules-smoke.json"
user_rule_fixture="$scratch/user-rule-fixture/UserReviewTarget"
mkdir -p "$user_rule_fixture"
printf 'custom review data\n' >"$user_rule_fixture/blob.bin"
cat >"$scratch/user-rules.json" <<JSON
{
  "schemaVersion" : 1,
  "id" : "release-smoke-user-rules",
  "exportedAt" : "2026-01-01T00:00:00Z",
  "rules" : [
    {
      "id" : "user.release-smoke.review-target",
      "title" : "Release smoke review target",
      "category" : "Release Smoke",
      "priority" : 5000,
      "safetyClass" : "preserveByDefault",
      "actionKind" : "reportOnly",
      "match" : {
        "containsAny" : ["/UserReviewTarget/"],
        "suffixAny" : [],
        "basenameAny" : [],
        "pathExtensionAny" : []
      },
      "evidence" : ["Custom release-smoke rule marks this fixture for manual review."],
      "conditions" : ["Review before cleanup."],
      "recovery" : "Remove or replace the local user rule pack to stop this custom classification."
    }
  ],
  "nonClaims" : [
    "Release smoke rule pack is local review data only."
  ]
}
JSON
RYDDI_CONFIG_ROOT="$scratch/user-rule-config" "$app/Contents/MacOS/reclaimer" rules user preview "$scratch/user-rules.json" --json >"$scratch/user-rules-preview.json"
grep -q '"isImportable" : true' "$scratch/user-rules-preview.json"
grep -q '"acceptedRuleCount" : 1' "$scratch/user-rules-preview.json"
RYDDI_CONFIG_ROOT="$scratch/user-rule-config" "$app/Contents/MacOS/reclaimer" rules user import "$scratch/user-rules.json" --json >"$scratch/user-rules-import.json"
grep -q '"includedByDefault" : false' "$scratch/user-rules-import.json"
grep -q '"finalRuleCount" : 1' "$scratch/user-rules-import.json"
RYDDI_CONFIG_ROOT="$scratch/user-rule-config" "$app/Contents/MacOS/reclaimer" rules --include-user-rules --json >"$scratch/rules-with-user-smoke.json"
grep -q '"userRuleCount" : 1' "$scratch/rules-with-user-smoke.json"
grep -q '"source" : "User"' "$scratch/rules-with-user-smoke.json"
RYDDI_CONFIG_ROOT="$scratch/user-rule-config" "$app/Contents/MacOS/reclaimer" scan --json --path "$user_rule_fixture" --min-size 1 --max-depth 1 >"$scratch/scan-without-user-rules.json"
if grep -q '"user.release-smoke.review-target"' "$scratch/scan-without-user-rules.json"; then
  echo "user rule applied without --include-user-rules" >&2
  exit 1
fi
RYDDI_CONFIG_ROOT="$scratch/user-rule-config" "$app/Contents/MacOS/reclaimer" scan --json --path "$user_rule_fixture" --min-size 1 --max-depth 1 --include-user-rules >"$scratch/scan-with-user-rules.json"
grep -q '"user.release-smoke.review-target"' "$scratch/scan-with-user-rules.json"
grep -q '"safetyClass" : "preserveByDefault"' "$scratch/scan-with-user-rules.json"
"$app/Contents/MacOS/reclaimer" agents --json \
  --path "$agent_fixture/.codex" \
  --path "$agent_fixture/.claude" \
  --path "$agent_fixture/.ollama" \
  --path "$agent_fixture/Library/Application Support/Cursor" \
  --min-size 1 \
  --max-depth 4 \
  --limit 50 >"$scratch/agents-smoke.json"
grep -q '"owner" : "Codex"' "$scratch/agents-smoke.json"
grep -q '"owner" : "Claude"' "$scratch/agents-smoke.json"
grep -q '"owner" : "Cursor"' "$scratch/agents-smoke.json"
grep -q '"owner" : "Ollama"' "$scratch/agents-smoke.json"
grep -q '"bucket" : "reclaimableCache"' "$scratch/agents-smoke.json"
grep -q '"bucket" : "valuableHistory"' "$scratch/agents-smoke.json"
grep -q '"bucket" : "protectedState"' "$scratch/agents-smoke.json"
grep -q '"bucket" : "quitFirst"' "$scratch/agents-smoke.json"
grep -q "does not delete agent sessions" "$scratch/agents-smoke.json"
"$app/Contents/MacOS/reclaimer" agents retention --json \
  --path "$agent_fixture/.codex" \
  --path "$agent_fixture/.claude" \
  --path "$agent_fixture/.ollama" \
  --path "$agent_fixture/Library/Application Support/Cursor" \
  --profile balanced \
  --min-size 1 \
  --max-depth 4 \
  --limit 50 >"$scratch/agents-retention-smoke.json"
grep -q '"profile" : "balanced"' "$scratch/agents-retention-smoke.json"
grep -q '"recommendation" : "cleanupPlan"' "$scratch/agents-retention-smoke.json"
grep -q '"recommendation" : "compressAfterReview"' "$scratch/agents-retention-smoke.json"
grep -q '"recommendation" : "protect"' "$scratch/agents-retention-smoke.json"
grep -q "does not delete, compress, move, or modify agent files" "$scratch/agents-retention-smoke.json"
"$app/Contents/MacOS/reclaimer" native --json \
  --path "$scratch/native-fixture/Library/Caches/Homebrew" \
  --min-size 1 \
  --max-depth 3 \
  --limit 20 >"$scratch/native-smoke.json"
grep -q '"command" : "brew cleanup -n"' "$scratch/native-smoke.json"
grep -q '"command" : "brew cleanup"' "$scratch/native-smoke.json"
grep -q "No native cleanup command was executed" "$scratch/native-smoke.json"
fake_brew_bin="$scratch/fake-brew-bin"
mkdir -p "$fake_brew_bin"
cat >"$fake_brew_bin/brew" <<'BREW'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "cleanup" && ( "${2:-}" == "--dry-run" || "${2:-}" == "-n" ) && $# -eq 2 ]]; then
  printf 'Would remove Homebrew cache fixture\n'
  exit 0
fi
if [[ "${1:-}" == "cleanup" && $# -eq 1 ]]; then
  printf 'Removed Homebrew cache fixture\n'
  exit 0
fi
printf 'unsupported fake brew command: %s\n' "$*" >&2
exit 64
BREW
chmod +x "$fake_brew_bin/brew"
PATH="$fake_brew_bin:$PATH" RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" native run --dry-run --json \
  --path "$scratch/native-fixture/Library/Caches/Homebrew" \
  --command-id brew.preview \
  --min-size 1 \
  --max-depth 3 \
  --save-audit >"$scratch/native-run-dry-run.json"
grep -q '"status" : "dry-run"' "$scratch/native-run-dry-run.json"
grep -q '"command" : "brew cleanup -n"' "$scratch/native-run-dry-run.json"
grep -q "Would remove Homebrew cache fixture" "$scratch/native-run-dry-run.json"
grep -q "only one explicitly selected native-tool command" "$scratch/native-run-dry-run.json"
find "$scratch/audit" -name 'native-tool-execution-*.json' -print -quit | grep -q 'native-tool-execution-'
PATH="$fake_brew_bin:$PATH" RYDDI_AUDIT_ROOT="$scratch/audit-homebrew-fresh" "$app/Contents/MacOS/reclaimer" native homebrew cleanup --yes --save-audit --json \
  --finding-path "$scratch/native-fixture/Library/Caches/Homebrew" \
  --timeout 5 >"$scratch/native-homebrew-fresh-perform.json"
grep -q '"mode" : "perform"' "$scratch/native-homebrew-fresh-perform.json"
grep -q "Removed Homebrew cache fixture" "$scratch/native-homebrew-fresh-perform.json"
RYDDI_AUDIT_ROOT="$scratch/audit-homebrew-fresh" "$app/Contents/MacOS/reclaimer" native receipts list --json >"$scratch/native-homebrew-fresh-receipts.json"
grep -q '"id" : "brew.preview"' "$scratch/native-homebrew-fresh-receipts.json"
grep -q '"status" : "dry-run"' "$scratch/native-homebrew-fresh-receipts.json"
grep -q '"id" : "brew.cleanup"' "$scratch/native-homebrew-fresh-receipts.json"
grep -q '"status" : "done"' "$scratch/native-homebrew-fresh-receipts.json"
test "$(find "$scratch/audit-homebrew-fresh" -name 'native-tool-execution-*.json' -type f | wc -l | tr -d '[:space:]')" = "2"
PATH="$fake_brew_bin:$PATH" RYDDI_AUDIT_ROOT="$scratch/audit-homebrew" "$app/Contents/MacOS/reclaimer" native homebrew cleanup --dry-run --save-audit --json \
  --finding-path "$scratch/native-fixture/Library/Caches/Homebrew" \
  --timeout 5 >"$scratch/native-homebrew-dry-run.json"
grep -q '"mode" : "dryRun"' "$scratch/native-homebrew-dry-run.json"
grep -q "Would remove Homebrew cache fixture" "$scratch/native-homebrew-dry-run.json"
find "$scratch/audit-homebrew" -name 'native-tool-execution-*.json' -print -quit | grep -q 'native-tool-execution-'
RYDDI_AUDIT_ROOT="$scratch/audit-homebrew" "$app/Contents/MacOS/reclaimer" native receipts list --json >"$scratch/native-receipts-list.json"
grep -q '"id" : "brew.preview"' "$scratch/native-receipts-list.json"
RYDDI_AUDIT_ROOT="$scratch/audit-homebrew" "$app/Contents/MacOS/reclaimer" native receipts export \
  --path-style redacted \
  --output "$scratch/native-receipt-report.md" >"$scratch/native-receipt-export.txt"
grep -q "Ryddi Native Command Receipt Report" "$scratch/native-receipt-report.md"
grep -q "Homebrew dry run completed" "$scratch/native-receipt-report.md"
PATH="$fake_brew_bin:$PATH" RYDDI_AUDIT_ROOT="$scratch/audit-homebrew" "$app/Contents/MacOS/reclaimer" native homebrew cleanup --yes --save-audit --json \
  --finding-path "$scratch/native-fixture/Library/Caches/Homebrew" \
  --timeout 5 >"$scratch/native-homebrew-perform.json"
grep -q '"mode" : "perform"' "$scratch/native-homebrew-perform.json"
grep -q "Removed Homebrew cache fixture" "$scratch/native-homebrew-perform.json"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" trash --json \
  --path "$trash_fixture" \
  --limit 20 \
  --max-depth 4 \
  --save-audit >"$scratch/trash-smoke.json"
grep -q '"permissionState" : "readable"' "$scratch/trash-smoke.json"
grep -q '"displayName" : "old-download.dmg"' "$scratch/trash-smoke.json"
grep -q '"displayName" : ".hidden-trash"' "$scratch/trash-smoke.json"
grep -q "Trash Review is report-only" "$scratch/trash-smoke.json"
find "$scratch/audit" -name 'trash-review-*.json' -print -quit | grep -q 'trash-review-'
test -f "$trash_fixture/old-download.dmg"
test -f "$trash_fixture/.hidden-trash"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" downloads --json \
  --path "$downloads_fixture" \
  --limit 20 \
  --old-days 30 \
  --max-depth 4 \
  --save-audit >"$scratch/downloads-smoke.json"
grep -q '"permissionState" : "readable"' "$scratch/downloads-smoke.json"
grep -q '"displayName" : "FixtureInstaller.dmg"' "$scratch/downloads-smoke.json"
grep -q '"kind" : "diskImage"' "$scratch/downloads-smoke.json"
grep -q '"displayName" : "FixturePackage.pkg"' "$scratch/downloads-smoke.json"
grep -q '"kind" : "packageInstaller"' "$scratch/downloads-smoke.json"
grep -q '"displayName" : "FixtureArchive.zip"' "$scratch/downloads-smoke.json"
grep -q '"kind" : "archive"' "$scratch/downloads-smoke.json"
grep -q '"workflow" : "trashReview"' "$scratch/downloads-smoke.json"
grep -q '"workflow" : "archiveReview"' "$scratch/downloads-smoke.json"
grep -q '"workflow" : "manualReview"' "$scratch/downloads-smoke.json"
grep -q '"workflowSummaries"' "$scratch/downloads-smoke.json"
grep -q '"workflowSteps"' "$scratch/downloads-smoke.json"
grep -q "Downloads Review is report-only" "$scratch/downloads-smoke.json"
grep -q "workflow labels" "$scratch/downloads-smoke.json"
find "$scratch/audit" -name 'downloads-review-*.json' -print -quit | grep -q 'downloads-review-'
test -f "$downloads_fixture/FixtureInstaller.dmg"
test -f "$downloads_fixture/FixturePackage.pkg"
test -f "$downloads_fixture/FixtureArchive.zip"
test -f "$downloads_fixture/old-note.txt"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" browsers --json \
  --home "$browser_fixture" \
  --path "$browser_cache" \
  --limit 20 \
  --max-depth 5 \
  --save-audit >"$scratch/browsers-smoke.json"
grep -q '"browser" : "chrome"' "$scratch/browsers-smoke.json"
grep -q '"kind" : "diskCache"' "$scratch/browsers-smoke.json"
grep -q '"kind" : "codeCache"' "$scratch/browsers-smoke.json"
grep -q '"kind" : "gpuCache"' "$scratch/browsers-smoke.json"
grep -q '"runtimeSummaries"' "$scratch/browsers-smoke.json"
grep -q "Runtime status is based on local process-name matching" "$scratch/browsers-smoke.json"
grep -q "Browser process detection is advisory" "$scratch/browsers-smoke.json"
grep -q "Browser Cache Review is report-only" "$scratch/browsers-smoke.json"
grep -q "bookmarks, cookies" "$scratch/browsers-smoke.json"
find "$scratch/audit" -name 'browser-cache-review-*.json' -print -quit | grep -q 'browser-cache-review-'
test -f "$browser_cache/Cache/Cache_Data/data_0"
test -f "$browser_cache/Code Cache/js/script.bin"
test -f "$browser_cache/GPUCache/gpu.bin"
test -f "$browser_profile/Login Data"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" packages --json \
  --home "$package_fixture" \
  --limit 20 \
  --max-depth 6 \
  --include-missing-scopes \
  --save-audit >"$scratch/packages-smoke.json"
grep -q '"manager" : "homebrew"' "$scratch/packages-smoke.json"
grep -q '"manager" : "npm"' "$scratch/packages-smoke.json"
grep -q '"manager" : "gradle"' "$scratch/packages-smoke.json"
grep -q '"kind" : "downloadCache"' "$scratch/packages-smoke.json"
grep -q '"kind" : "packageStore"' "$scratch/packages-smoke.json"
grep -q "Package Cache Review is report-only" "$scratch/packages-smoke.json"
grep -q "protected package-manager" "$scratch/packages-smoke.json"
find "$scratch/audit" -name 'package-cache-review-*.json' -print -quit | grep -q 'package-cache-review-'
test -f "$package_homebrew/downloads/bottle.tar.gz"
test -f "$package_npm/content-v2/sha512/aa/cache.bin"
test -f "$package_gradle/modules-2/files-2.1/example/artifact.jar"
test -f "$package_fixture/.npmrc"
test -f "$package_fixture/.m2/settings.xml"
RYDDI_CONFIG_ROOT="$scratch/project-policy-config" "$app/Contents/MacOS/reclaimer" projects policy skip-review "$project_skipped" \
  --reason "release smoke skip" >"$scratch/project-policy-skip.txt"
RYDDI_CONFIG_ROOT="$scratch/project-policy-config" "$app/Contents/MacOS/reclaimer" projects policy export --output "$scratch/project-policy-export.json"
grep -q '"schemaVersion" : 1' "$scratch/project-policy-export.json"
RYDDI_CONFIG_ROOT="$scratch/project-policy-import-config" "$app/Contents/MacOS/reclaimer" projects policy import "$scratch/project-policy-export.json" --json >"$scratch/project-policy-import.json"
grep -q '"finalProjectCount" : 1' "$scratch/project-policy-import.json"
RYDDI_CONFIG_ROOT="$scratch/project-policy-config" RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" projects --json \
  --path "$project_root" \
  --limit 40 \
  --old-days 30 \
  --search-depth 6 \
  --max-depth 8 \
  --include-vcs-status \
  --save-audit >"$scratch/projects-smoke.json"
grep -q '"ecosystem" : "javascript"' "$scratch/projects-smoke.json"
grep -q '"ecosystem" : "python"' "$scratch/projects-smoke.json"
grep -q '"ecosystem" : "swift"' "$scratch/projects-smoke.json"
grep -q '"ecosystem" : "rust"' "$scratch/projects-smoke.json"
grep -q '"ecosystem" : "cocoaPods"' "$scratch/projects-smoke.json"
grep -q '"ecosystem" : "dartFlutter"' "$scratch/projects-smoke.json"
grep -q '"ecosystem" : "android"' "$scratch/projects-smoke.json"
grep -q '"kind" : "nodeModules"' "$scratch/projects-smoke.json"
grep -q '"kind" : "pythonVirtualEnvironment"' "$scratch/projects-smoke.json"
grep -q '"kind" : "swiftBuild"' "$scratch/projects-smoke.json"
grep -q '"kind" : "rustTarget"' "$scratch/projects-smoke.json"
grep -q '"kind" : "cocoaPodsPods"' "$scratch/projects-smoke.json"
grep -q '"kind" : "dartTool"' "$scratch/projects-smoke.json"
grep -q '"kind" : "androidBuild"' "$scratch/projects-smoke.json"
grep -q '"state" : "dirty"' "$scratch/projects-smoke.json"
grep -q '"command" : "npm ci"' "$scratch/projects-smoke.json"
grep -q '"toolName" : "npm"' "$scratch/projects-smoke.json"
grep -q '"toolVersion" : "10.8.0"' "$scratch/projects-smoke.json"
grep -q '"toolSummaries"' "$scratch/projects-smoke.json"
grep -q '"scriptSummaries"' "$scratch/projects-smoke.json"
grep -q '"scriptRiskSummaries"' "$scratch/projects-smoke.json"
grep -q '"workspaceSummaries"' "$scratch/projects-smoke.json"
grep -q '"workspaceRootCount" : 1' "$scratch/projects-smoke.json"
grep -q '"workspaceInfo"' "$scratch/projects-smoke.json"
grep -q '"kind" : "pnpm"' "$scratch/projects-smoke.json"
grep -q '"rootName" : "MonoRepo"' "$scratch/projects-smoke.json"
grep -q '"workspace-detected"' "$scratch/projects-smoke.json"
grep -q '"command" : "pnpm install --frozen-lockfile"' "$scratch/projects-smoke.json"
grep -Fq '"command" : "pnpm --filter @fixtures\/web run build"' "$scratch/projects-smoke.json"
grep -Fq '"command" : "pnpm --filter @fixtures\/web run clean"' "$scratch/projects-smoke.json"
grep -Fq '"packageName" : "@fixtures\/web"' "$scratch/projects-smoke.json"
grep -q '"workingDirectory"' "$scratch/projects-smoke.json"
grep -q '"context"' "$scratch/projects-smoke.json"
grep -q '"workspace-command-context"' "$scratch/projects-smoke.json"
grep -q '"packageScripts"' "$scratch/projects-smoke.json"
grep -q '"scriptReviews"' "$scratch/projects-smoke.json"
grep -q '"commandPreview" : "rimraf dist .next"' "$scratch/projects-smoke.json"
grep -Fq '"commandPreview" : "vercel --prod --token=[redacted]"' "$scratch/projects-smoke.json"
grep -q '"risk" : "cleanup"' "$scratch/projects-smoke.json"
grep -q '"risk" : "networkOrPublishReview"' "$scratch/projects-smoke.json"
grep -q '"risk" : "lifecycle"' "$scratch/projects-smoke.json"
grep -q '"isCommandHintEligible" : false' "$scratch/projects-smoke.json"
grep -q '"script-risk-network-or-publish-review"' "$scratch/projects-smoke.json"
grep -q '"script-manual-review"' "$scratch/projects-smoke.json"
grep -q '"build"' "$scratch/projects-smoke.json"
grep -q '"clean"' "$scratch/projects-smoke.json"
grep -q '"command" : "npm run build"' "$scratch/projects-smoke.json"
grep -q '"command" : "npm run clean"' "$scratch/projects-smoke.json"
! grep -q '"bad script"' "$scratch/projects-smoke.json"
grep -q '"projectsWithDirtyVCSCount" : 1' "$scratch/projects-smoke.json"
grep -q '"decision" : "skipReview"' "$scratch/projects-smoke.json"
grep -q '"projectName" : "SkippedWeb"' "$scratch/projects-smoke.json"
grep -q "Project Dependency Review is report-only" "$scratch/projects-smoke.json"
grep -q "Protected project files" "$scratch/projects-smoke.json"
RYDDI_CONFIG_ROOT="$scratch/project-policy-config" "$app/Contents/MacOS/reclaimer" projects --json \
  --path "$project_root" \
  --limit 40 \
  --search-depth 6 \
  --max-depth 8 \
  --include-policy-skipped >"$scratch/projects-policy-override.json"
grep -q '"projectPolicyDecision" : "skipReview"' "$scratch/projects-policy-override.json"
find "$scratch/audit" -name 'project-dependency-review-*.json' -print -quit | grep -q 'project-dependency-review-'
test -f "$project_web/src/index.ts"
test -f "$project_skipped/node_modules/react/index.js"
test -f "$project_web/.env"
test -f "$project_web/node_modules/react/index.js"
test -f "$project_mono_web/node_modules/react/index.js"
test -f "$project_mono_web/dist/app.js"
test -f "$project_python/.venv/pyvenv.cfg"
test -f "$project_swift/.build/debug/App.o"
test -f "$project_rust/target/debug/app"
test -f "$project_ios/Pods/Alamofire/file.swift"
test -f "$project_flutter/.dart_tool/package_config.json"
test -f "$project_android/app/build/intermediates/classes.bin"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" device-backups --json \
  --home "$device_fixture" \
  --limit 20 \
  --old-days 30 \
  --max-depth 8 \
  --save-audit >"$scratch/device-backups-smoke.json"
grep -q '"permissionState" : "readable"' "$scratch/device-backups-smoke.json"
grep -q '"displayName" : "Release Smoke iPhone"' "$scratch/device-backups-smoke.json"
grep -q '"encryptionState" : "encrypted"' "$scratch/device-backups-smoke.json"
grep -q '"metadataState" : "missing"' "$scratch/device-backups-smoke.json"
grep -q "Device Backups Review is report-only" "$scratch/device-backups-smoke.json"
grep -q "Apple MobileSync" "$scratch/device-backups-smoke.json"
find "$scratch/audit" -name 'device-backup-review-*.json' -print -quit | grep -q 'device-backup-review-'
test -f "$device_backup_a/00/backup-data.bin"
test -f "$device_backup_a/Info.plist"
test -f "$device_backup_b/01/backup-data.bin"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" xcode --json \
  --home "$xcode_fixture" \
  --limit 30 \
  --old-days 30 \
  --max-depth 8 \
  --include-missing-scopes \
  --save-audit >"$scratch/xcode-smoke.json"
grep -q '"kind" : "derivedData"' "$scratch/xcode-smoke.json"
grep -q '"kind" : "moduleCache"' "$scratch/xcode-smoke.json"
grep -q '"kind" : "documentationCache"' "$scratch/xcode-smoke.json"
grep -q '"kind" : "archives"' "$scratch/xcode-smoke.json"
grep -q '"kind" : "deviceSupport"' "$scratch/xcode-smoke.json"
grep -q '"kind" : "simulatorDevices"' "$scratch/xcode-smoke.json"
grep -q '"kind" : "simulatorRuntimes"' "$scratch/xcode-smoke.json"
grep -q '"kind" : "simulatorLogs"' "$scratch/xcode-smoke.json"
grep -q "Xcode Review is report-only" "$scratch/xcode-smoke.json"
grep -q "Protected Xcode developer state" "$scratch/xcode-smoke.json"
find "$scratch/audit" -name 'xcode-review-*.json' -print -quit | grep -q 'xcode-review-'
test -f "$xcode_derived/app.o"
test -f "$xcode_module/Swift.pcm"
test -f "$xcode_archive/Info.plist"
test -f "$xcode_device_support/symbol.bin"
test -f "$xcode_simulator/data/Containers/Data/Application/app.db"
test -f "$xcode_runtime/runtime.bin"
test -f "$xcode_logs/sim.log"
test -f "$xcode_user_data/snippet.codesnippet"
test -f "$xcode_profiles/profile.mobileprovision"
"$app/Contents/MacOS/reclaimer" permissions --json --path "$root/Tests" >"$scratch/permissions-smoke.json"
grep -q '"coverageLevel"' "$scratch/permissions-smoke.json"
"$app/Contents/MacOS/reclaimer" permissions guide --path "$root/Tests" --output "$scratch/permissions-guide.md"
grep -q "# Ryddi Permission Walkthrough" "$scratch/permissions-guide.md"
grep -q "Full Disk Access" "$scratch/permissions-guide.md"
grep -q "does not grant macOS permissions" "$scratch/permissions-guide.md"
existing_permission_guide="$scratch/permissions-guide-existing.md"
printf 'keep existing output\n' >"$existing_permission_guide"
if "$app/Contents/MacOS/reclaimer" permissions guide --path "$root/Tests" --output "$existing_permission_guide" >"$scratch/permissions-guide-existing.log" 2>&1; then
  echo "bundled CLI unexpectedly replaced existing permission guide output" >&2
  exit 1
fi
grep -q "Output file already exists" "$scratch/permissions-guide-existing.log"
grep -q '^keep existing output$' "$existing_permission_guide"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" active --json --path "$root/Tests" --min-size 1 --max-depth 1 --limit 5 --save-audit >"$scratch/active-smoke.json"
grep -q '"candidateCount"' "$scratch/active-smoke.json"
"$app/Contents/MacOS/reclaimer" overview --path "$root/Tests" --limit 5 --sort reclaim --group safety >"$scratch/overview-smoke.txt"
grep -q "By owner" "$scratch/overview-smoke.txt"
grep -q "Estimated immediate reclaim" "$scratch/overview-smoke.txt"
grep -q "Top-offender non-claims" "$scratch/overview-smoke.txt"
"$app/Contents/MacOS/reclaimer" overview --json --path "$root/Tests" --limit 5 --sort reclaim --group safety >"$scratch/overview-smoke.json"
grep -q '"ownerSummaries"' "$scratch/overview-smoke.json"
grep -q '"topOffenderTable"' "$scratch/overview-smoke.json"
grep -q '"estimatedImmediateReclaim"' "$scratch/overview-smoke.json"
grep -q '"group" : "safety"' "$scratch/overview-smoke.json"
cat >"$scratch/release-trust-fixture.txt" <<'TRUST'
manifest_schema=ryddi.release-trust.v1
version=0.3.0
build=3
artifact=Ryddi-v0.3.0.zip
sha256=fixture-sha
source_commit=fixture-commit
codesign_verified=true
hardened_runtime=true
notarization_status=Accepted
stapled=true
gatekeeper=accepted
TRUST
"$app/Contents/MacOS/reclaimer" release-trust --json --manifest "$scratch/release-trust-fixture.txt" >"$scratch/release-trust-smoke.json"
grep -q '"state" : "stapledAndAccepted"' "$scratch/release-trust-smoke.json"
"$app/Contents/MacOS/reclaimer" trust --json --path "$root/Tests" --limit 5 >"$scratch/trust-smoke.json"
grep -q '"recommendedActions"' "$scratch/trust-smoke.json"
grep -q '"nonClaims"' "$scratch/trust-smoke.json"
"$app/Contents/MacOS/reclaimer" dogfood --path "$root/Tests" --path-style redacted --output "$scratch/dogfood-smoke.md"
grep -q "No cleanup was executed" "$scratch/dogfood-smoke.md"
grep -q "does not grant macOS permissions" "$scratch/dogfood-smoke.md"
grep -q "cannot promise exact free-space gains" "$scratch/dogfood-smoke.md"
"$app/Contents/MacOS/reclaimer" explain "$receipt_fixture" --min-size 1 --max-depth 2 --no-lsof >"$scratch/explain-smoke.txt"
grep -q "Ryddi finding explanation" "$scratch/explain-smoke.txt"
grep -q "What this is" "$scratch/explain-smoke.txt"
grep -q "Why matched" "$scratch/explain-smoke.txt"
grep -q "Risk and exact action" "$scratch/explain-smoke.txt"
grep -q "Explanation non-claims" "$scratch/explain-smoke.txt"
"$app/Contents/MacOS/reclaimer" explain "$receipt_fixture" --json --min-size 1 --max-depth 2 --no-lsof >"$scratch/explain-smoke.json"
grep -q '"cleanupPermission"' "$scratch/explain-smoke.json"
grep -q '"exactAction"' "$scratch/explain-smoke.json"
grep -q '"whatThisIs"' "$scratch/explain-smoke.json"
grep -q '"whyMatched"' "$scratch/explain-smoke.json"
"$app/Contents/MacOS/reclaimer" queues --path "$root/Tests" --limit 5 >"$scratch/queues-smoke.txt"
grep -q "Ryddi review queues" "$scratch/queues-smoke.txt"
grep -q "Personal/App Assets" "$scratch/queues-smoke.txt"
grep -q "Queue non-claims" "$scratch/queues-smoke.txt"
"$app/Contents/MacOS/reclaimer" queues --json --path "$root/Tests" --limit 5 >"$scratch/queues-smoke.json"
grep -q '"queues"' "$scratch/queues-smoke.json"
grep -q '"queueID" : "safeMaintenance"' "$scratch/queues-smoke.json"
grep -q '"estimatedImmediateReclaim"' "$scratch/queues-smoke.json"
"$app/Contents/MacOS/reclaimer" queues --path "$root/Tests" --queue unknown --limit 5 >"$scratch/queue-detail-smoke.txt"
grep -q "Ryddi review queue: Unknown" "$scratch/queue-detail-smoke.txt"
grep -q "Queue ID: unknown" "$scratch/queue-detail-smoke.txt"
grep -q "Queue non-claims" "$scratch/queue-detail-smoke.txt"
"$app/Contents/MacOS/reclaimer" queues --json --path "$root/Tests" --queue unknown --limit 5 >"$scratch/queue-detail-smoke.json"
grep -q '"queueID" : "unknown"' "$scratch/queue-detail-smoke.json"
grep -q '"rowCount"' "$scratch/queue-detail-smoke.json"
grep -q '"rows"' "$scratch/queue-detail-smoke.json"
"$app/Contents/MacOS/reclaimer" large \
  --path "$large_fixture" \
  --min-size 1 \
  --max-depth 4 \
  --large-threshold 16000 \
  --old-days 30 \
  --limit 10 >"$scratch/large-smoke.txt"
grep -q "Ryddi large & old file review" "$scratch/large-smoke.txt"
grep -q "Large and old" "$scratch/large-smoke.txt"
grep -q "Large & old non-claims" "$scratch/large-smoke.txt"
grep -q "Estimated immediate reclaim" "$scratch/large-smoke.txt"
"$app/Contents/MacOS/reclaimer" large \
  --json \
  --path "$large_fixture" \
  --min-size 1 \
  --max-depth 4 \
  --large-threshold 16000 \
  --old-days 30 \
  --review old \
  --sort age \
  --limit 10 >"$scratch/large-smoke.json"
grep -q '"mode" : "old"' "$scratch/large-smoke.json"
grep -q '"largeAndOldCount"' "$scratch/large-smoke.json"
grep -q '"reviewReason"' "$scratch/large-smoke.json"
grep -q "do not grant cleanup permission" "$scratch/large-smoke.json"
"$app/Contents/MacOS/reclaimer" archive \
  --path "$large_fixture" \
  --min-size 1 \
  --max-depth 4 \
  --large-threshold 16000 \
  --old-days 30 \
  --limit 10 >"$scratch/archive-smoke.txt"
grep -q "Ryddi archive candidate review" "$scratch/archive-smoke.txt"
grep -q "Recommendations" "$scratch/archive-smoke.txt"
grep -q "Review for Trash" "$scratch/archive-smoke.txt"
grep -q "Archive review non-claims" "$scratch/archive-smoke.txt"
"$app/Contents/MacOS/reclaimer" archive \
  --json \
  --path "$large_fixture" \
  --min-size 1 \
  --max-depth 4 \
  --large-threshold 16000 \
  --old-days 30 \
  --limit 10 >"$scratch/archive-smoke.json"
grep -q '"recommendation" : "trashReview"' "$scratch/archive-smoke.json"
grep -q '"recommendationSummaries"' "$scratch/archive-smoke.json"
grep -q '"archiveCandidateBytes"' "$scratch/archive-smoke.json"
grep -q "does not compress, move, Trash, or delete files" "$scratch/archive-smoke.json"
"$app/Contents/MacOS/reclaimer" archive \
  --path "$large_fixture" \
  --min-size 1 \
  --max-depth 4 \
  --large-threshold 16000 \
  --old-days 30 \
  --output "$scratch/archive-review.md" \
  --path-style redacted
grep -q "# Ryddi Archive Candidate Review" "$scratch/archive-review.md"
grep -q "Candidate Checklist" "$scratch/archive-review.md"
grep -q "<path redacted>" "$scratch/archive-review.md"
grep -q "This report does not compress, move, Trash, or delete files" "$scratch/archive-review.md"
"$app/Contents/MacOS/reclaimer" drilldown --json --path "$drill_fixture" --min-size 1 --max-depth 4 --tree-depth 4 --limit 1 >"$scratch/drilldown-smoke.json"
grep -q '"rootNodes"' "$scratch/drilldown-smoke.json"
grep -q '"children"' "$scratch/drilldown-smoke.json"
grep -q '"omittedChildCount" : 1' "$scratch/drilldown-smoke.json"
grep -q "Parent rows include measured descendant bytes" "$scratch/drilldown-smoke.json"
"$app/Contents/MacOS/reclaimer" apps uninstall-preview \
  --app "$app_bundle" \
  --path "$app_root" \
  --home "$app_home" \
  --min-size 1 \
  --output "$scratch/app-uninstall-preview.md" \
  --path-style redacted
grep -q "# Ryddi App Uninstall Preview" "$scratch/app-uninstall-preview.md"
grep -q "Only the selected app bundle" "$scratch/app-uninstall-preview.md"
grep -q "<path redacted>" "$scratch/app-uninstall-preview.md"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" apps uninstall-preview \
  --json \
  --app "$app_bundle" \
  --path "$app_root" \
  --home "$app_home" \
  --min-size 1 \
  --save-audit >"$scratch/app-uninstall-preview.json"
grep -q '"disposition" : "trashPreview"' "$scratch/app-uninstall-preview.json"
grep -q '"relatedItems"' "$scratch/app-uninstall-preview.json"
find "$scratch/audit" -name 'app-uninstall-preview-*.json' -print -quit | grep -q .
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" apps uninstall \
  --json \
  --dry-run \
  --no-lsof \
  --app "$app_bundle" \
  --path "$app_root" \
  --home "$app_home" \
  --min-size 1 \
  --save-audit >"$scratch/app-uninstall-dry-run.json"
grep -q '"status" : "dry-run"' "$scratch/app-uninstall-dry-run.json"
grep -q "Related support files would remain untouched" "$scratch/app-uninstall-dry-run.json"
find "$scratch/audit" -name 'app-uninstall-receipt-*.json' -print -quit | grep -q .
history_fixture="$scratch/history-fixture"
history_cache="$history_fixture/Library/Caches/Codex"
mkdir -p "$history_cache"
printf 'old cache\n' >"$history_cache/old.bin"
RYDDI_SCAN_HISTORY_ROOT="$scratch/history" "$app/Contents/MacOS/reclaimer" history record --path "$history_fixture" --min-size 1 --max-depth 3 >"$scratch/history-record-1.txt"
printf 'new cache growth\n' >"$history_cache/new.bin"
RYDDI_SCAN_HISTORY_ROOT="$scratch/history" "$app/Contents/MacOS/reclaimer" history record --path "$history_fixture" --min-size 1 --max-depth 3 >"$scratch/history-record-2.txt"
RYDDI_SCAN_HISTORY_ROOT="$scratch/history" "$app/Contents/MacOS/reclaimer" history report --output "$scratch/growth-report.md" --path-style redacted
grep -q "# Ryddi Growth Report" "$scratch/growth-report.md"
grep -q "Largest Category Deltas" "$scratch/growth-report.md"
grep -q "does not prove exact current disk state" "$scratch/growth-report.md"
grep -q "<path redacted>" "$scratch/growth-report.md"
mkdir -p "$scratch/audit"
cat >"$scratch/audit/remote-scan-previous.json" <<'JSON'
{
  "id": "previous-remote",
  "createdAt": "2026-07-07T18:00:00Z",
  "preset": "vps-general",
  "target": {
    "id": "prod-vps",
    "input": "prod-vps",
    "alias": "prod-vps",
    "resolvedUser": "deploy",
    "resolvedHost": "203.0.113.10",
    "resolvedPort": 22,
    "knownHostsState": "known",
    "fingerprint": "ssh-ed25519:fixture"
  },
  "diskFilesystems": [],
  "inodeFilesystems": [],
  "findings": [
    {
      "id": "Remote storage:/home/deploy/private-client/cache",
      "remotePath": "/home/deploy/private-client/cache",
      "displayPath": "/home/deploy/private-client/cache",
      "bucket": "Remote storage",
      "allocatedBytes": 100,
      "safetyClass": "reviewRequired",
      "actionKind": "openGuidance",
      "evidence": [{"kind": "remote.fixture", "message": "Previous fixture evidence."}],
      "recommendedNextAction": "reviewInFinder"
    },
    {
      "id": "Journald logs:/var/log/journal",
      "remotePath": "/var/log/journal",
      "displayPath": "/var/log/journal",
      "bucket": "Journald logs",
      "allocatedBytes": 20,
      "safetyClass": "safeAfterCondition",
      "actionKind": "nativeToolCommand",
      "evidence": [{"kind": "remote.fixture", "message": "Previous fixture evidence."}],
      "recommendedNextAction": "useNativeTool"
    }
  ],
  "nativeGuidance": [],
  "commands": [],
  "nonClaims": ["No cleanup was executed on the remote target."]
}
JSON
cat >"$scratch/audit/remote-scan-current.json" <<'JSON'
{
  "id": "current-remote",
  "createdAt": "2026-07-07T19:00:00Z",
  "preset": "vps-general",
  "target": {
    "id": "prod-vps",
    "input": "prod-vps",
    "alias": "prod-vps",
    "resolvedUser": "deploy",
    "resolvedHost": "203.0.113.10",
    "resolvedPort": 22,
    "knownHostsState": "known",
    "fingerprint": "ssh-ed25519:fixture"
  },
  "diskFilesystems": [],
  "inodeFilesystems": [],
  "findings": [
    {
      "id": "Remote storage:/home/deploy/private-client/cache",
      "remotePath": "/home/deploy/private-client/cache",
      "displayPath": "/home/deploy/private-client/cache",
      "bucket": "Remote storage",
      "allocatedBytes": 180,
      "safetyClass": "reviewRequired",
      "actionKind": "openGuidance",
      "evidence": [{"kind": "remote.fixture", "message": "Current fixture evidence."}],
      "recommendedNextAction": "reviewInFinder"
    },
    {
      "id": "Journald logs:/var/log/journal",
      "remotePath": "/var/log/journal",
      "displayPath": "/var/log/journal",
      "bucket": "Journald logs",
      "allocatedBytes": 10,
      "safetyClass": "safeAfterCondition",
      "actionKind": "nativeToolCommand",
      "evidence": [{"kind": "remote.fixture", "message": "Current fixture evidence."}],
      "recommendedNextAction": "useNativeTool"
    }
  ],
  "nativeGuidance": [],
  "commands": [],
  "nonClaims": ["No cleanup was executed on the remote target."]
}
JSON
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" remote history list --json >"$scratch/remote-history-list.json"
grep -q '"current-remote"' "$scratch/remote-history-list.json"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" remote history diff --limit 5 --current-id current-remote --previous-id previous-remote >"$scratch/remote-history-diff.txt"
grep -q "Remote growth diff" "$scratch/remote-history-diff.txt"
grep -q "Remote storage" "$scratch/remote-history-diff.txt"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" remote history report --current-id current-remote --previous-id previous-remote --path-style redacted --output "$scratch/remote-growth-report.md"
grep -q "# Ryddi Remote Growth Report" "$scratch/remote-growth-report.md"
grep -q "<path redacted>" "$scratch/remote-growth-report.md"
if grep -q "private-client" "$scratch/remote-growth-report.md"; then
  echo "remote growth report leaked redacted path component" >&2
  exit 1
fi
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" remote dogfood --from-audit prod-vps --path-style redacted --output "$scratch/remote-dogfood-report.md"
grep -q "# Ryddi Remote Dogfood Report" "$scratch/remote-dogfood-report.md"
grep -q "No cleanup was executed" "$scratch/remote-dogfood-report.md"
grep -q "<path redacted>" "$scratch/remote-dogfood-report.md"
if grep -q "private-client" "$scratch/remote-dogfood-report.md"; then
  echo "remote dogfood report leaked redacted path component" >&2
  exit 1
fi
RYDDI_REPORT_ROOT="$scratch/reports" "$app/Contents/MacOS/reclaimer" report --path "$root/Tests" --limit 5 --output "$scratch/evidence-report.md" --ignore-user-policy --path-style redacted --redact-user-text
grep -q "# Ryddi Evidence Report" "$scratch/evidence-report.md"
grep -q "Explicit Non-Claims" "$scratch/evidence-report.md"
grep -q "<path redacted>" "$scratch/evidence-report.md"
grep -q "Report privacy was applied" "$scratch/evidence-report.md"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" plan --path "$receipt_fixture" --min-size 1 --max-depth 1 --output "$scratch/plan-report.md" --path-style redacted --no-lsof
grep -q "# Ryddi Plan Report" "$scratch/plan-report.md"
grep -q "Selected Actions" "$scratch/plan-report.md"
grep -q "does not execute cleanup" "$scratch/plan-report.md"
grep -q "<path redacted>" "$scratch/plan-report.md"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" plan --path "$receipt_fixture" --min-size 1 --max-depth 1 --save-audit --no-lsof >"$scratch/saved-plan-smoke.txt"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" plans export --output "$scratch/saved-plan-report.md" --path-style redacted
grep -q "# Ryddi Plan Report" "$scratch/saved-plan-report.md"
grep -q "Report privacy was applied" "$scratch/saved-plan-report.md"
grep -q "<path redacted>" "$scratch/saved-plan-report.md"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" execute --dry-run --path "$receipt_fixture" --min-size 1 --max-depth 1 --save-audit --no-lsof >"$scratch/receipt-dry-run-smoke.txt"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" receipts export --output "$scratch/receipt-report.md" --path-style redacted
grep -q "# Ryddi Receipt Report" "$scratch/receipt-report.md"
grep -q "does not execute cleanup" "$scratch/receipt-report.md"
grep -q "<path redacted>" "$scratch/receipt-report.md"
holding_fixture="$scratch/holding/2026-01-01T00-00-00Z"
mkdir -p "$holding_fixture"
printf 'held cache\n' >"$holding_fixture/cache.bin"
cat >"$holding_fixture/.reclaimer-hold.json" <<JSON
{
  "allocatedSize" : 11,
  "heldAt" : "2026-01-01T00:00:00Z",
  "isDirectory" : false,
  "originalPath" : "$scratch/original-cache.bin"
}
JSON
RYDDI_AUDIT_ROOT="$scratch/audit" RYDDI_HOLDING_ROOT="$scratch/holding" "$app/Contents/MacOS/reclaimer" recovery --json --limit 20 >"$scratch/recovery-smoke.json"
grep -q '"restorableCount" : 0' "$scratch/recovery-smoke.json"
grep -q '"state" : "manualReview"' "$scratch/recovery-smoke.json"
grep -q '"state" : "dryRunOnly"' "$scratch/recovery-smoke.json"
if RYDDI_HOLDING_ROOT="$scratch/holding" "$app/Contents/MacOS/reclaimer" recovery restore "2026-01-01T00-00-00Z/cache.bin" --to "$scratch/restored-cache.bin" >"$scratch/recovery-restore-smoke.txt" 2>"$scratch/recovery-restore-smoke.err"; then
  echo "recovery restore unexpectedly succeeded despite manual-only holding recovery" >&2
  exit 1
fi
grep -q "manual Finder" "$scratch/recovery-restore-smoke.err"
test -f "$holding_fixture/cache.bin"
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" containers --json --timeout 2 --save-audit >"$scratch/containers-smoke.json"
RYDDI_CONFIG_ROOT="$scratch/config" "$app/Contents/MacOS/reclaimer" policy protect "$root/Tests" --reason "release smoke" >"$scratch/policy-protect-smoke.txt"
RYDDI_CONFIG_ROOT="$scratch/config" "$app/Contents/MacOS/reclaimer" policy list --json >"$scratch/policy-list-smoke.json"
RYDDI_CONFIG_ROOT="$scratch/config" "$app/Contents/MacOS/reclaimer" policy export --output "$scratch/policy-export.json"
grep -q '"schemaVersion" : 1' "$scratch/policy-export.json"
grep -q "private local paths" "$scratch/policy-export.json"
RYDDI_CONFIG_ROOT="$scratch/config-import" "$app/Contents/MacOS/reclaimer" policy import "$scratch/policy-export.json" --json >"$scratch/policy-import-smoke.json"
grep -q '"mode" : "merge"' "$scratch/policy-import-smoke.json"
grep -q '"finalRuleCount" : 1' "$scratch/policy-import-smoke.json"
RYDDI_CONFIG_ROOT="$scratch/config-import" "$app/Contents/MacOS/reclaimer" policy exclude "$root/Sources" --reason "replace smoke" >"$scratch/policy-extra-smoke.txt"
RYDDI_CONFIG_ROOT="$scratch/config-import" "$app/Contents/MacOS/reclaimer" policy import "$scratch/policy-export.json" --replace --json >"$scratch/policy-replace-smoke.json"
grep -q '"mode" : "replace"' "$scratch/policy-replace-smoke.json"
grep -q '"finalRuleCount" : 1' "$scratch/policy-replace-smoke.json"
if grep -q "replace smoke" "$scratch/policy-replace-smoke.json"; then
  echo "policy import --replace retained a local-only rule" >&2
  exit 1
fi
audit_fixture="$scratch/audit-fixture"
mkdir -p "$audit_fixture"
printf 'old plan\n' >"$audit_fixture/plan-old.json"
printf 'old remote scan\n' >"$audit_fixture/remote-scan-old.json"
printf 'unknown audit note\n' >"$audit_fixture/unknown-old.json"
touch -t 202001010101 "$audit_fixture/plan-old.json" "$audit_fixture/remote-scan-old.json" "$audit_fixture/unknown-old.json"
RYDDI_AUDIT_ROOT="$audit_fixture" "$app/Contents/MacOS/reclaimer" audit summary --json >"$scratch/audit-summary-smoke.json"
grep -q '"totalKnownFileCount" : 2' "$scratch/audit-summary-smoke.json"
grep -q '"unknownFileCount" : 1' "$scratch/audit-summary-smoke.json"
RYDDI_AUDIT_ROOT="$audit_fixture" "$app/Contents/MacOS/reclaimer" audit prune --dry-run --older-than-days 30 --keep-recent 0 --json >"$scratch/audit-prune-smoke.json"
grep -q '"dryRun" : true' "$scratch/audit-prune-smoke.json"
grep -q '"kind" : "plan"' "$scratch/audit-prune-smoke.json"
grep -q '"kind" : "remote-scan"' "$scratch/audit-prune-smoke.json"
test -f "$audit_fixture/plan-old.json"
test -f "$audit_fixture/remote-scan-old.json"

echo "==> Checking code signing state"
signing_state="unsigned developer preview"
notarization_state="not requested"
spctl_state="not assessed"
codesign_verified="false"
hardened_runtime="false"
notarization_status="not requested"
stapler_validated="false"
gatekeeper_status="not assessed"
signing_identity="unsigned"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --verify --deep --strict --verbose=2 "$app"
  codesign_verified="true"
  signing_details="$(codesign -dv --verbose=4 "$app" 2>&1 || true)"
  signing_identity="$(sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' <<<"$signing_details" | head -n 1)"
  signing_identity="${signing_identity:-$CODESIGN_IDENTITY}"
  if ! grep -qi "runtime" <<<"$signing_details"; then
    echo "signed app does not report Hardened Runtime in codesign details" >&2
    exit 1
  fi
  hardened_runtime="true"
  signing_state="signed with Hardened Runtime"
elif codesign --verify --deep --strict --verbose=2 "$app" >"$scratch/codesign-verify.txt" 2>&1; then
  signing_state="pre-signed outside this script"
  codesign_verified="true"
  signing_details="$(codesign -dv --verbose=4 "$app" 2>&1 || true)"
  if grep -qi "runtime" <<<"$signing_details"; then
    hardened_runtime="true"
  fi
  signing_identity="$(sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' <<<"$signing_details" | head -n 1)"
  signing_identity="${signing_identity:-pre-signed}"
else
  if [[ "$signing_required" == "required" ]]; then
    echo "RYDDI_RELEASE_SIGNING=required but app is unsigned." >&2
    exit 1
  fi
  echo "CODESIGN_IDENTITY not set; treating artifact as unsigned developer preview."
fi

if [[ "$signing_required" == "required" ]]; then
  echo "==> Notarizing signed app"
  "$root/Scripts/notarize-app.sh" "$app"
  notary_status_file="$dist/Ryddi-notary-status.json"
  notary_submission_file="$dist/Ryddi-notary-submission.txt"
  if [[ ! -f "$notary_status_file" ]] || ! grep -Eq '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$notary_status_file"; then
    echo "notarization did not produce an Accepted status JSON: $notary_status_file" >&2
    exit 1
  fi
  notary_submission="$(cat "$notary_submission_file" 2>/dev/null || true)"
  notarization_state="accepted and stapled"
  notarization_status="Accepted"
  stapler_validated="true"
  spctl --assess --type execute --verbose "$app"
  spctl_state="accepted"
  gatekeeper_status="accepted"
  codesign --verify --deep --strict --verbose=2 "$app"
else
  notary_status_file=""
  notary_submission=""
fi

commit="unknown"
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  commit="$(git -C "$root" rev-parse HEAD)"
fi
notary_status_manifest="not applicable"
if [[ -n "$notary_status_file" ]]; then
  notary_status_manifest="dist/$(basename "$notary_status_file")"
fi

echo "==> Staging release artifact and trust evidence"
stage_release_artifact
artifact_sha="$(awk '{print $1}' "$checksum_path")"

echo "==> Release check complete"
echo "$zip_path"
echo "$checksum_path"
echo "$manifest_path"
