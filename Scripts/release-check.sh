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
