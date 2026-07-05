# Ryddi Release Checklist

This project is intended for direct macOS distribution outside the Mac App Store. A public release should be explicit about whether it is an unsigned developer preview or a signed/notarized build.

## Developer Preview

- [ ] `swift test --scratch-path "$PWD/.build"` passes.
- [ ] `Scripts/package-app.sh` produces `dist/Ryddi.app`.
- [ ] App launches locally.
- [ ] `reclaimer overview --path Tests --limit 5` prints a bounded overview.
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
- [ ] Release notes say VM/container disks, browser profiles, GarageBand/Logic assets, Codex memories, and Codex sessions are not deleted automatically.
