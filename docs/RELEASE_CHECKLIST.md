# Ryddi Release Checklist

This project is intended for direct macOS distribution outside the Mac App Store. A public release should be explicit about whether it is an unsigned developer preview or a signed/notarized build.

## Developer Preview

- [ ] `Scripts/release-check.sh` passes and produces a zip, checksum, and release manifest.
- [ ] `swift test --scratch-path "$PWD/.build"` passes.
- [ ] `Scripts/package-app.sh` produces `dist/Ryddi.app`.
- [ ] `dist/Ryddi-developer-preview.zip` exists and preserves `Ryddi.app` as its parent item.
- [ ] `dist/Ryddi-developer-preview.zip.sha256` exists and matches the generated zip.
- [ ] `dist/Ryddi-release-manifest.txt` records bundle id, version, rules resource path, signing state, performed verification, and non-claims.
- [ ] App launches locally.
- [ ] `reclaimer status --json` reports disk pressure/free-space metadata without scanning content.
- [ ] `reclaimer overview --path Tests --limit 5` prints a bounded overview.
- [ ] `reclaimer overview --json --path Tests --limit 5` includes bounded `mapNodes`.
- [ ] `reclaimer history record --path Tests --limit 5` saves a local-only snapshot.
- [ ] `reclaimer history list --limit 5` and `reclaimer history diff --group category --limit 5` read local-only snapshots.
- [ ] `reclaimer duplicates --path FIXTURE --min-size 1 --json` groups same-content regular files, skips protected paths, and emits no cleanup plan.
- [ ] `reclaimer apps --path FIXTURE_APPS --home FIXTURE_HOME --min-size 1 --json` reports installed app support files and orphan candidates without emitting a cleanup plan.
- [ ] App Visual Map and Growth History render without changing reclaim gates.
- [ ] App Duplicate Review scans bounded roots and does not enable Reclaim or modify the dry-run plan.
- [ ] App Apps & Leftovers review scans bounded app roots and does not enable Reclaim or modify the dry-run plan.
- [ ] App menu bar status item shows disk pressure and report-only scan controls without enabling cleanup actions.
- [ ] Manual GitHub Actions workflow `Release Preview Artifact` uploads the unsigned preview zip, checksum, and manifest when run.
- [ ] README states that the build is unsigned if `CODESIGN_IDENTITY` is unset.
- [ ] Release notes list non-claims: no notarization, no Full Disk Access guarantee, no real cleanup performed by packaging.

## Signed And Notarized Build

- [ ] `CODESIGN_IDENTITY` is set to a Developer ID Application certificate.
- [ ] `Scripts/package-app.sh` signs `dist/Ryddi.app` with Hardened Runtime.
- [ ] `Scripts/notarize-app.sh dist/Ryddi.app` completes successfully.
- [ ] `spctl --assess --type execute --verbose dist/Ryddi.app` accepts the app.
- [ ] `codesign --verify --deep --strict --verbose=2 dist/Ryddi.app` passes.
- [ ] GitHub release artifact and checksum are uploaded.

## Trust And Safety Notes

- [ ] `PRIVACY.md` is current.
- [ ] `docs/COMPETITIVE_RESEARCH.md` does not overclaim implemented features.
- [ ] CI is green on the release commit.
- [ ] Release notes say automation is report-first.
- [ ] Release notes say menu bar status is disk-pressure/report-only, not RAM cleaning or performance optimization.
- [ ] Release notes say duplicate review uses local hashes and does not automatically select or delete duplicates.
- [ ] Release notes say Apps & Leftovers is review-only and does not uninstall apps or delete app support files.
- [ ] Release notes say VM/container disks, browser profiles, GarageBand/Logic assets, Codex memories, and Codex sessions are not deleted automatically.
