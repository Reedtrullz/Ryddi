#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ryddi-storage-truth.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

available_kib="$(df -Pk /System/Volumes/Data | awk 'NR == 2 { print $4 }')"
minimum_kib=$((50 * 1024 * 1024))
if [[ -z "$available_kib" || "$available_kib" -lt "$minimum_kib" ]]; then
  echo "Ryddi storage-truth smoke requires at least 50 GiB free on /System/Volumes/Data." >&2
  exit 1
fi

fixture="$scratch/fixture"
mkdir -p \
  "$fixture/Library/Caches/Codex" \
  "$fixture/Library/Application Support/Google/Chrome/Default" \
  "$fixture/.codex/sessions" \
  "$fixture/.codex/memories" \
  "$fixture/.npm/_cacache" \
  "$fixture/.docker" \
  "$fixture/.colima/docker build cache" \
  "$fixture/Library/Application Support/Stremio-server/stremio-cache"

dd if=/dev/zero of="$fixture/Library/Caches/Codex/cache.bin" bs=1024 count=64 2>/dev/null
ln "$fixture/Library/Caches/Codex/cache.bin" "$fixture/Library/Caches/Codex/cache-clone.bin"
ln -s "cache.bin" "$fixture/Library/Caches/Codex/cache-link"
printf 'active history must stay protected\n' >"$fixture/.codex/sessions/session.jsonl"
printf 'valuable memory must stay protected\n' >"$fixture/.codex/memories/keep.md"
printf 'browser profile state must stay protected\n' >"$fixture/Library/Application Support/Google/Chrome/Default/Login Data"
printf 'npm shared cache\n' >"$fixture/.npm/_cacache/content.bin"
printf 'docker builder evidence\n' >"$fixture/.colima/docker build cache/entry"
printf 'named application cache\n' >"$fixture/Library/Application Support/Stremio-server/stremio-cache/entry"
touch -t 202401010101 \
  "$fixture/Library/Caches/Codex/cache.bin" \
  "$fixture/.npm/_cacache/content.bin" \
  "$fixture/.colima/docker build cache/entry"

protected_before="$(shasum -a 256 "$fixture/.codex/sessions/session.jsonl" | awk '{ print $1 }')"
profile_before="$(shasum -a 256 "$fixture/Library/Application Support/Google/Chrome/Default/Login Data" | awk '{ print $1 }')"

run_cli() {
  env \
    RYDDI_AUDIT_ROOT="$scratch/audit" \
    RYDDI_CONFIG_ROOT="$scratch/config" \
    RYDDI_SCAN_HISTORY_ROOT="$scratch/history" \
    RYDDI_REPORT_ROOT="$scratch/reports" \
    RYDDI_HOLDING_ROOT="$scratch/holding" \
    swift run --scratch-path "$root/.build" reclaimer "$@"
}

run_cli overview \
  --path "$fixture" \
  --min-size 1 \
  --max-depth 8 \
  --measurement-budget 24 \
  --measurement-depth 8 \
  --no-lsof \
  --json >"$scratch/overview.json"

grep -q '"scanCoverage"' "$scratch/overview.json"

run_cli scan \
  --path "$fixture" \
  --min-size 1 \
  --max-depth 8 \
  --measurement-budget 256 \
  --measurement-depth 8 \
  --no-lsof \
  --json >"$scratch/scan.json"

grep -q '"storageAccounting"' "$scratch/scan.json"
grep -q '"physicalReclaimStatus"' "$scratch/scan.json"
grep -q 'sharedCloneBacked' "$scratch/scan.json"
grep -q 'preserveByDefault' "$scratch/scan.json"

# This command only renders guidance. It must not launch Docker, npm, or any cleanup verb.
run_cli native --path "$fixture" --min-size 1 --max-depth 8 --no-lsof --json >"$scratch/native.json"
grep -q 'docker.builder-prune' "$scratch/native.json"
grep -q 'docker.prune-volumes' "$scratch/native.json"
grep -q 'npm.cache-clean' "$scratch/native.json"

[[ "$(shasum -a 256 "$fixture/.codex/sessions/session.jsonl" | awk '{ print $1 }')" == "$protected_before" ]]
[[ "$(shasum -a 256 "$fixture/Library/Application Support/Google/Chrome/Default/Login Data" | awk '{ print $1 }')" == "$profile_before" ]]

echo "Ryddi storage-truth smoke passed (fixture scan and native guidance were report-only)."
