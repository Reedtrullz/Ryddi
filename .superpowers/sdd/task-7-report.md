# Task 7 Report - Release-Check And Docs

## Summary

- Added packaged `reclaimer remote dogfood --from-audit` smoke coverage to `Scripts/release-check.sh` using disposable saved remote audit records under the release-check scratch directory.
- Updated remote dogfood and release-check documentation in the owned docs/privacy surfaces to state that `--from-audit` is read-only, packages saved local evidence only, does not reconnect over SSH, and does not mutate a server.
- Verified the docs scan and full `Scripts/release-check.sh` pass locally.

## Commands Run

```bash
rg -n "remote dogfood --from-audit" Scripts/release-check.sh README.md FEATURES.md docs/REMOTE_TARGETS.md docs/RELEASE_CHECKLIST.md PRIVACY.md
rg -n "bundled reclaimer remote dogfood --from-audit on disposable saved remote audit records" dist/Ryddi-release-manifest.txt Scripts/release-check.sh 2>/dev/null
rg -n "remote dogfood|--from-audit|remote execute|StrictHostKeyChecking=no|password" README.md FEATURES.md PRIVACY.md docs
df -h /System/Volumes/Data
./Scripts/release-check.sh
git diff --check
git status --short
```

## Results

- Initial red check: `remote dogfood --from-audit` wording was absent from the owned release-check/docs files before the patch.
- Docs scan: passed for the requested search. User-facing docs now mention remote dogfood and `--from-audit`; unsafe phrases in `docs/` appear in deferred/non-goal planning text rather than user-facing instructions.
- Disk headroom gate: `/System/Volumes/Data` had `74Gi` available on `2026-07-07` before running release-check.
- `./Scripts/release-check.sh`: passed.
  - `swift test --scratch-path "$root/.build"` passed with `139` tests and `0` failures.
  - Packaged CLI smoke passed, including:
    - `reclaimer remote history list/diff/report` on disposable saved remote scan audit records
    - `reclaimer remote dogfood --from-audit prod-vps --path-style redacted --output "$scratch/remote-dogfood-report.md"`
  - The new packaged smoke wrote a redacted remote dogfood Markdown report and rejected leaking the `private-client` path component.
  - Release-check produced:
    - `dist/Ryddi-developer-preview.zip`
    - `dist/Ryddi-developer-preview.zip.sha256`
    - `dist/Ryddi-release-manifest.txt`
- `git diff --check`: passed.

## Concerns / Non-Claims

- Apple Developer signing/notarization is still pending. This run verified only the unsigned developer-preview lane; it does not prove a signed public release.
- `swift test` / packaging still emit the existing SwiftPM warning about two unhandled fixture files:
  - `Tests/ReclaimerCoreTests/Fixtures/remote-debian-minimal.txt`
  - `Tests/ReclaimerCoreTests/Fixtures/remote-ubuntu-24-docker.txt`
- Remote dogfood remains report-first only. This task did not add remote cleanup, SSH reconnect for `--from-audit`, or any server mutation path.
