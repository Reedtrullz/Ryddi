# Task 8: Ryddi v0.3.1 Release Readiness

## Status

Complete. `v0.3.1 (4)` is merged, tagged, signed, notarized, stapled, published, downloaded, independently read back, installed in `/Applications`, and launched from the exact source-bound artifact.

## Changes

- Aligned package, release-check, signing-doctor, workflow, docs, and release notes on `v0.3.1` build `4`.
- Made the signed workflow fail closed unless the checked-out ref is the exact `v0.3.1` tag, version is `0.3.1`, build is `4`, and `HEAD` resolves to the tag commit before certificate import.
- Captured source commit and dirty state once, before the release check temporarily hides `.build`, and passed that immutable snapshot into package metadata and manifest generation.
- Added packaged Accessibility proof for visible scan progress, cancellation to idle, absence of a late cancelled result, a following successful scan, one receipt-bounded Trash action, immediate row reconciliation, Verify Cleanup, and protected-fixture preservation.
- Kept the deterministic scan delay test-only: it requires a validated temporary E2E scope and is bounded to `1...2_000` milliseconds.
- Added `docs/releases/v0.3.1.md` with install evidence and explicit non-claims.

## TDD Evidence

- RED: `PackageAppScriptTests` produced 11 expected failures for stale `v0.3.0 (3)` identity and missing exact-tag checks.
- RED: `AppE2EFixtureTests` produced 15 expected failures for missing progress, cancellation, late-commit, protected-fixture, and current-flow proof.
- RED: the clean-source preview exposed contradictory provenance (`Ryddi-build.json` clean, manifest dirty); the regression test then failed until provenance moved before the hidden-build-directory operation and was passed explicitly into packaging.
- GREEN: focused package, app E2E fixture, accessibility contract, and signing-doctor tests all pass.

## Verification

- `swift test --scratch-path "$PWD/.build"`: 601 tests passed, 1 intentional skip, 0 failures.
- `swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors`: passed.
- `bash -n Scripts/*.sh`: passed.
- `git diff --check`: passed.
- `RYDDI_REQUIRE_PACKAGED_AX_E2E=1 Scripts/release-check.sh`: passed.
- Preview bundle metadata: `CFBundleShortVersionString=0.3.1`, `CFBundleVersion=4`.
- Preview checksum: verified with `shasum -a 256 -c`.
- Packaged AX proof: cancellation and normal scan checkpoints passed; candidate row removed; cleanup verification visible; protected browser profile, Codex session, and app bundle hashes remained unchanged.
- Responsive AX/screenshots: required controls remained contained at 980x680, 1280x800, and 1600x1000.
- PR [#6](https://github.com/Reedtrullz/Ryddi/pull/6) merged as exact main/tag commit `da6f0d8d2646c796570a4b85cfc423d6d2937dc7`.
- PR CI [29364495803](https://github.com/Reedtrullz/Ryddi/actions/runs/29364495803) and main CI [29364716397](https://github.com/Reedtrullz/Ryddi/actions/runs/29364716397) passed. Exact-tag preview workflow [29365112746](https://github.com/Reedtrullz/Ryddi/actions/runs/29365112746) passed its hosted release-check and artifact job.
- Apple notarization submission `fb16b43c-39d6-4a03-8b81-31f80b273dd5` returned `Accepted`; nested CLI/app strict codesign, Hardened Runtime, staple validation, and Gatekeeper passed.
- Public [Ryddi v0.3.1](https://github.com/Reedtrullz/Ryddi/releases/tag/v0.3.1) assets passed fresh-download outer and staged checksums, manifest, source, version/build, signatures, staple, and Gatekeeper readback.
- Installed `/Applications/Ryddi.app` reports `0.3.1 (4)`, source `da6f0d8d2646c796570a4b85cfc423d6d2937dc7`, `sourceDirty=false`, and typed trust `stapledAndAccepted`.

## Non-Claims

- Any preview generated before the immutable-provenance fix is invalidated; unsigned developer previews are not releases.
- The GitHub self-hosted signed job was skipped because no release runner, enabling variable, or release secrets are configured. Signed proof is the local exact-tag gate; GitHub independently proved exact-tag unsigned reproducibility.
- E2E cleanup was restricted to disposable fixtures and a receipt-verified Trash artifact.
- No live SSH target or real user data was cleaned during release verification.

## Final State

All Task 8 gates are satisfied. Follow-on product work belongs to the separate v0.4 guided-cleanup plan.
