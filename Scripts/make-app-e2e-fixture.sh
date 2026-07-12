#!/usr/bin/env bash
set -euo pipefail

fail_unsafe() {
  echo "unsafe E2E fixture root: $1" >&2
  exit 2
}

if [[ "$#" -ne 1 ]]; then
  echo "usage: Scripts/make-app-e2e-fixture.sh /absolute/temporary/fixture-root" >&2
  exit 2
fi

requested_root="$1"
if [[ "$requested_root" != /* ]]; then
  fail_unsafe "path must be absolute"
fi

case "$requested_root" in
  /|/Users|/Users/*|/Applications|/Applications/*|/Library|/Library/*|/System|/System/*)
    fail_unsafe "$requested_root is protected"
    ;;
esac

if [[ -n "${HOME:-}" ]]; then
  case "$requested_root" in
    "$HOME"|"$HOME"/*)
      fail_unsafe "$requested_root is inside HOME"
      ;;
  esac
fi

parent="$(dirname "$requested_root")"
name="$(basename "$requested_root")"
if [[ "$name" == "." || "$name" == ".." || ! -d "$parent" ]]; then
  fail_unsafe "parent must already exist"
fi

resolved_parent="$(cd "$parent" && pwd -P)"
fixture_root="$resolved_parent/$name"
temporary_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
case "$fixture_root" in
  "$temporary_root"/*|/private/tmp/*)
    ;;
  *)
    fail_unsafe "$fixture_root is not under a temporary directory"
    ;;
esac

if [[ -L "$fixture_root" ]]; then
  fail_unsafe "$fixture_root is a symbolic link"
fi
if [[ -e "$fixture_root" && ! -d "$fixture_root" ]]; then
  fail_unsafe "$fixture_root is not a directory"
fi
if [[ -d "$fixture_root" ]] && find "$fixture_root" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  fail_unsafe "$fixture_root is not empty"
fi

cache_dir="$fixture_root/Library/Caches/Codex"
review_dir="$fixture_root/Downloads"
browser_profile_dir="$fixture_root/Library/Application Support/Google/Chrome/Default"
codex_session_dir="$fixture_root/.codex/sessions"
app_contents="$fixture_root/Applications/Ryddi E2E Fixture.app/Contents"
app_macos="$app_contents/MacOS"

mkdir -p \
  "$cache_dir" \
  "$review_dir" \
  "$browser_profile_dir" \
  "$codex_session_dir" \
  "$app_macos"

dd if=/dev/zero of="$cache_dir/cache.bin" bs=1024 count=32 2>/dev/null
dd if=/dev/zero of="$review_dir/large-review.bin" bs=1024 count=64 2>/dev/null
printf 'protected browser profile fixture\n' >"$browser_profile_dir/Login Data"
printf 'protected Codex session fixture\n' >"$codex_session_dir/e2e-session.jsonl"
ln -s "cache.bin" "$cache_dir/symlink-candidate"

cat >"$app_contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.ryddi-e2e-fixture</string>
  <key>CFBundleDisplayName</key>
  <string>Ryddi E2E Fixture</string>
  <key>CFBundleName</key>
  <string>Ryddi E2E Fixture</string>
  <key>CFBundleExecutable</key>
  <string>RyddiE2EFixture</string>
</dict>
</plist>
PLIST

cat >"$app_macos/RyddiE2EFixture" <<'EXECUTABLE'
#!/bin/sh
exit 0
EXECUTABLE
chmod 700 "$app_macos/RyddiE2EFixture"

touch -t 202401010101 \
  "$review_dir/large-review.bin" \
  "$browser_profile_dir/Login Data" \
  "$codex_session_dir/e2e-session.jsonl"

cat >"$fixture_root/.ryddi-e2e-fixture" <<'MANIFEST'
schema=ryddi.app-e2e-fixture.v1
safe_cache=Library/Caches/Codex/cache.bin
review_file=Downloads/large-review.bin
browser_profile=Library/Application Support/Google/Chrome/Default/Login Data
codex_session=.codex/sessions/e2e-session.jsonl
symlink_candidate=Library/Caches/Codex/symlink-candidate
app_bundle=Applications/Ryddi E2E Fixture.app
MANIFEST

echo "$fixture_root"
