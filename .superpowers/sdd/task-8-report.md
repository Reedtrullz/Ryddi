# Task 8: Ryddi v0.3.1 Release Readiness

## Status

Implementation and local unsigned release gates are complete. Signed publication remains intentionally pending an exact clean commit, exact-head CI, Developer ID signing, Apple notarization acceptance, stapling, Gatekeeper acceptance, and installed-app readback.

## Changes

- Aligned package, release-check, signing-doctor, workflow, docs, and release notes on `v0.3.1` build `4`.
- Made the signed workflow fail closed unless the checked-out ref is the exact `v0.3.1` tag, version is `0.3.1`, build is `4`, and `HEAD` resolves to the tag commit before certificate import.
- Added packaged Accessibility proof for visible scan progress, cancellation to idle, absence of a late cancelled result, a following successful scan, one receipt-bounded Trash action, immediate row reconciliation, Verify Cleanup, and protected-fixture preservation.
- Kept the deterministic scan delay test-only: it requires a validated temporary E2E scope and is bounded to `1...2_000` milliseconds.
- Added `docs/releases/v0.3.1.md` with install evidence and explicit non-claims.

## TDD Evidence

- RED: `PackageAppScriptTests` produced 11 expected failures for stale `v0.3.0 (3)` identity and missing exact-tag checks.
- RED: `AppE2EFixtureTests` produced 15 expected failures for missing progress, cancellation, late-commit, protected-fixture, and current-flow proof.
- GREEN: focused package, app E2E fixture, accessibility contract, and signing-doctor tests all pass.

## Verification

- `swift test --scratch-path "$PWD/.build"`: 600 tests passed, 1 intentional skip, 0 failures.
- `swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors`: passed.
- `bash -n Scripts/*.sh`: passed.
- `git diff --check`: passed.
- `RYDDI_REQUIRE_PACKAGED_AX_E2E=1 Scripts/release-check.sh`: passed.
- Preview bundle metadata: `CFBundleShortVersionString=0.3.1`, `CFBundleVersion=4`.
- Preview checksum: verified with `shasum -a 256 -c`.
- Packaged AX proof: cancellation and normal scan checkpoints passed; candidate row removed; cleanup verification visible; protected browser profile, Codex session, and app bundle hashes remained unchanged.
- Responsive AX/screenshots: required controls remained contained at 980x680, 1280x800, and 1600x1000.

## Non-Claims

- The current `Ryddi-developer-preview.zip` is unsigned, was built from a dirty pre-commit worktree, and is not a release.
- No signing, notarization, stapling, Gatekeeper, GitHub CI, publication, or `/Applications` install claim is made here.
- E2E cleanup was restricted to disposable fixtures and a receipt-verified Trash artifact.

## Next Gate

Commit the release-preparation changes, require a clean worktree, push the exact commit, verify exact-head CI, then create and verify the immutable `v0.3.1` tag before running the signed/notarized release gate.
