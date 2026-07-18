#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/ryddi-release-trust-smoke.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

export RYDDI_RELEASE_CHECK_LIBRARY_ONLY=1
# shellcheck source=../../Scripts/release-check.sh
source "$root/Scripts/release-check.sh"

dist="$scratch/dist"
app="$dist/Ryddi.app"
mkdir -p "$app/Contents/MacOS"
printf 'fixture app\n' >"$app/Contents/MacOS/Ryddi"

artifact_basename="Ryddi-v0.3.0"
zip_path="$dist/$artifact_basename.zip"
checksum_path="$zip_path.sha256"
update_zip_path="$dist/$artifact_basename-update.zip"
update_checksum_path="$update_zip_path.sha256"
manifest_path="$dist/Ryddi-release-manifest.txt"
stage_dir="$dist/$artifact_basename"
bundle_version="0.3.0"
bundle_build="3"
commit="0123456789abcdef"
source_dirty="false"
signing_identity="Developer ID Application: Ryddi Test (TEAM123)"
notary_submission="fixture-submission"
notarization_status="Accepted"
stapler_validated="true"
gatekeeper_status="accepted"
codesign_verified="true"
hardened_runtime="true"
signing_required="required"

stage_release_artifact

test -d "$stage_dir/Ryddi.app"
test -f "$stage_dir/Ryddi-release-manifest.txt"
test -f "$stage_dir/Ryddi-checksums.sha256"
test -f "$zip_path"
test -f "$checksum_path"
(cd "$dist" && shasum -a 256 -c "$(basename "$checksum_path")")
(cd "$stage_dir" && shasum -a 256 -c Ryddi-checksums.sha256)
! grep -F "$root" "$checksum_path"
! grep -Eq '/Users/[^[:space:]]+' "$checksum_path"
grep -qx 'version=0.3.0' "$stage_dir/Ryddi-release-manifest.txt"
grep -qx 'build=3' "$stage_dir/Ryddi-release-manifest.txt"
grep -qx 'source_commit=0123456789abcdef' "$stage_dir/Ryddi-release-manifest.txt"
grep -qx 'source_dirty=false' "$stage_dir/Ryddi-release-manifest.txt"
grep -qx 'signing_identity=Developer ID Application: Ryddi Test (TEAM123)' "$stage_dir/Ryddi-release-manifest.txt"
grep -qx 'notarization_submission_id=fixture-submission' "$stage_dir/Ryddi-release-manifest.txt"
grep -qx 'notarization_status=Accepted' "$stage_dir/Ryddi-release-manifest.txt"
grep -qx 'stapler_validated=true' "$stage_dir/Ryddi-release-manifest.txt"
grep -qx 'gatekeeper=accepted' "$stage_dir/Ryddi-release-manifest.txt"
grep -Eq '^sha256=[0-9a-f]{64}$' "$stage_dir/Ryddi-release-manifest.txt"

rm "$stage_dir/Ryddi-release-manifest.txt"
if archive_staged_release; then
  echo "archive unexpectedly succeeded without a release manifest" >&2
  exit 1
fi

artifact_basename="Ryddi-v0.3.0"
signing_required="optional"
if stage_release_artifact; then
  echo "unsigned preview unexpectedly used a versioned artifact name" >&2
  exit 1
fi

artifact_basename="Ryddi-developer-preview"
stage_dir="$dist/$artifact_basename"
zip_path="$dist/$artifact_basename.zip"
checksum_path="$zip_path.sha256"
update_zip_path="$dist/$artifact_basename-update.zip"
update_checksum_path="$update_zip_path.sha256"
stage_release_artifact
grep -qx 'release_kind=unsigned-preview' "$stage_dir/Ryddi-release-manifest.txt"
grep -qx 'signing_identity=unsigned' "$stage_dir/Ryddi-release-manifest.txt"

echo "release trust smoke passed"
