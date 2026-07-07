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
touch -t 202401010101 "$downloads_fixture/FixtureInstaller.dmg" "$downloads_fixture/old-note.txt"
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
printf '{"packageManager":"npm@10.8.0","scripts":{"build":"vite build","clean":"rimraf dist .next","test:coverage":"vitest --coverage","bad script":"echo unsafe"}}\n' >"$project_web/package.json"
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
git -C "$project_web" add .gitignore package.json package-lock.json src/index.ts
git -C "$project_web" commit -qm "fixture"
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
printf '{"packageManager":"pnpm@9.2.0","workspaces":["apps/*","packages/*"]}\n' >"$project_mono/package.json"
printf 'packages:\n  - "apps/*"\n  - "packages/*"\n' >"$project_mono/pnpm-workspace.yaml"
printf 'lockfile\n' >"$project_mono/pnpm-lock.yaml"
printf '{"scripts":{"build":"vite build","clean":"rimraf dist"}}\n' >"$project_mono_web/package.json"
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
RYDDI_AUDIT_ROOT="$scratch/audit" "$app/Contents/MacOS/reclaimer" native run --dry-run --json \
  --path "$scratch/native-fixture/Library/Caches/Homebrew" \
  --command-id brew.preview \
  --min-size 1 \
  --max-depth 3 \
  --save-audit >"$scratch/native-run-dry-run.json"
grep -q '"status" : "dry-run"' "$scratch/native-run-dry-run.json"
grep -q '"command" : "brew cleanup -n"' "$scratch/native-run-dry-run.json"
grep -q "Dry run only" "$scratch/native-run-dry-run.json"
grep -q "only one explicitly selected native-tool command" "$scratch/native-run-dry-run.json"
find "$scratch/audit" -name 'native-tool-execution-*.json' -print -quit | grep -q 'native-tool-execution-'
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
grep -q "Downloads Review is report-only" "$scratch/downloads-smoke.json"
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
grep -q '"workspaceSummaries"' "$scratch/projects-smoke.json"
grep -q '"workspaceRootCount" : 1' "$scratch/projects-smoke.json"
grep -q '"workspaceInfo"' "$scratch/projects-smoke.json"
grep -q '"kind" : "pnpm"' "$scratch/projects-smoke.json"
grep -q '"rootName" : "MonoRepo"' "$scratch/projects-smoke.json"
grep -q '"workspace-detected"' "$scratch/projects-smoke.json"
grep -q '"command" : "pnpm install --frozen-lockfile"' "$scratch/projects-smoke.json"
grep -q '"command" : "pnpm run build"' "$scratch/projects-smoke.json"
grep -q '"packageScripts"' "$scratch/projects-smoke.json"
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
grep -q '"restorableCount" : 1' "$scratch/recovery-smoke.json"
grep -q '"state" : "restorableFromHolding"' "$scratch/recovery-smoke.json"
grep -q '"state" : "dryRunOnly"' "$scratch/recovery-smoke.json"
RYDDI_HOLDING_ROOT="$scratch/holding" "$app/Contents/MacOS/reclaimer" recovery restore "2026-01-01T00-00-00Z/cache.bin" --to "$scratch/restored-cache.bin" >"$scratch/recovery-restore-smoke.txt"
grep -q "restored:" "$scratch/recovery-restore-smoke.txt"
test -f "$scratch/restored-cache.bin"
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
- bundled reclaimer scopes --preset general and scopes --json --preset all
- bundled reclaimer rules and rules --json
- bundled reclaimer agents --json on disposable Codex/Claude/Cursor/Ollama fixture
- bundled reclaimer agents retention --json on disposable Codex/Claude/Cursor/Ollama fixture
- bundled reclaimer native --json and native run --dry-run --json on disposable Homebrew fixture
- bundled reclaimer trash --json on disposable Trash fixture, with audit save and no emptying
- bundled reclaimer downloads --json on disposable Downloads fixture, with audit save and no file moves/deletes
- bundled reclaimer browsers --json on disposable browser cache/profile fixture, with audit save and no profile/cache mutation
- bundled reclaimer packages --json on disposable package cache/config fixture, with audit save and no cache/config mutation
- bundled reclaimer projects --json on disposable project dependency/build fixture, with audit save and no source/dependency mutation
- bundled reclaimer device-backups --json on disposable MobileSync backup fixture, with audit save and no backup mutation
- bundled reclaimer xcode --json on disposable Xcode developer fixture, with audit save and no Xcode state mutation
- bundled reclaimer permissions --json --path Tests
- bundled reclaimer permissions guide --path Tests --output permissions-guide.md
- bundled reclaimer active --json --path Tests --save-audit with temporary audit root
- bundled reclaimer overview --path Tests --limit 5 --sort reclaim --group safety
- bundled reclaimer explain on disposable Codex cache fixture with text and JSON explanation output
- bundled reclaimer queues --path Tests --limit 5, queues --json, and queues --queue unknown
- bundled reclaimer large --path disposable fixture with text and JSON review output
- bundled reclaimer archive --path disposable fixture with text, JSON, and redacted Markdown review output
- bundled reclaimer drilldown --json on disposable nested fixture
- bundled reclaimer apps uninstall-preview and apps uninstall --dry-run on a disposable app fixture, with redacted Markdown and saved JSON audit
- bundled reclaimer history record twice on a disposable fixture plus redacted history report --output growth-report.md
- bundled reclaimer report --path Tests --limit 5 --output evidence-report.md with redacted path privacy
- bundled reclaimer plan --path disposable fixture --output plan-report.md with redacted path privacy
- bundled reclaimer plan --save-audit on disposable fixture plus redacted plans export --output saved-plan-report.md
- bundled reclaimer execute --dry-run --save-audit on disposable fixture plus redacted receipts export --output receipt-report.md
- bundled reclaimer recovery --json and recovery restore with disposable audit and holding roots
- bundled reclaimer containers --json --timeout 2 --save-audit with temporary audit root
- bundled reclaimer policy protect/list/export/import/replace with temporary config roots
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
