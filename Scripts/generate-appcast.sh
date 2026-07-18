#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:-}"
output="${2:-$root/appcast.xml}"
account="${RYDDI_SPARKLE_KEY_ACCOUNT:-ed25519}"
private_key="${RYDDI_SPARKLE_PRIVATE_KEY:-}"

if [[ -z "$archive" || ! -f "$archive" ]]; then
  echo "usage: Scripts/generate-appcast.sh /path/to/Ryddi-vX.Y.Z-update.zip [output.xml]" >&2
  exit 2
fi

archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
archive_name="$(basename "$archive")"
if [[ ! "$archive_name" =~ ^Ryddi-v([0-9]+\.[0-9]+\.[0-9]+)-update\.zip$ ]]; then
  echo "update archive must be named Ryddi-vX.Y.Z-update.zip" >&2
  exit 2
fi
version="${BASH_REMATCH[1]}"

generate_appcast="$root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
sign_update="$root/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ ! -x "$generate_appcast" || ! -x "$sign_update" ]]; then
  echo "Sparkle tools are missing; run swift package resolve first." >&2
  exit 1
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/ryddi-appcast.XXXXXX")"
cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

cp "$archive" "$scratch/$archive_name"
if [[ -f "$output" ]]; then
  cp "$output" "$scratch/appcast.xml"
fi

release_notes="$root/docs/releases/v$version.md"
if [[ -f "$release_notes" ]]; then
  cp "$release_notes" "$scratch/Ryddi-v$version-update.md"
fi

generate_arguments=(
  --download-url-prefix "https://github.com/Reedtrullz/Ryddi/releases/download/v$version/"
  --link "https://github.com/Reedtrullz/Ryddi/releases/tag/v$version"
  --embed-release-notes
  --maximum-versions 3
  --maximum-deltas 0
  -o "$scratch/appcast.xml"
  "$scratch"
)

if [[ -n "$private_key" ]]; then
  printf '%s' "$private_key" | "$generate_appcast" --ed-key-file - "${generate_arguments[@]}"
  printf '%s' "$private_key" | "$sign_update" --ed-key-file - --verify "$scratch/appcast.xml"
else
  "$generate_appcast" --account "$account" "${generate_arguments[@]}"
  "$sign_update" --account "$account" --verify "$scratch/appcast.xml"
fi
xmllint --noout "$scratch/appcast.xml"
if ! grep -F "Ryddi-v$version-update.zip" "$scratch/appcast.xml" >/dev/null; then
  echo "generated appcast does not reference the update archive" >&2
  exit 1
fi
if ! grep -F 'sparkle:edSignature=' "$scratch/appcast.xml" >/dev/null; then
  echo "generated appcast is missing the archive EdDSA signature" >&2
  exit 1
fi
if ! grep -F '<!-- sparkle-signatures:' "$scratch/appcast.xml" >/dev/null; then
  echo "generated appcast is missing the signed-feed signature" >&2
  exit 1
fi

mkdir -p "$(dirname "$output")"
cp "$scratch/appcast.xml" "$output"
echo "$output"
