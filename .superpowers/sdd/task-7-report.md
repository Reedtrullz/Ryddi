# Task 7 Report: CLI And Explicit Bundle Signing Hardening

## Result

Complete. JSON output failures now propagate through the CLI's existing error path, and package signing explicitly signs the nested `reclaimer` executable before the enclosing app bundle. Deep signing is not used; deep verification remains required.

## TDD Evidence

- RED: `testEncodedJSONPropagatesEncoderFailure` initially failed to compile because `encodedJSON` did not exist.
- RED: `testPackageSignsNestedCLIThenAppWithoutDeepSigning` initially failed because packaging still used `codesign --force --deep` and did not explicitly sign the nested CLI.
- GREEN: `swift test --scratch-path "$PWD/.build" --filter ReclaimerCLITests` passed 30 tests.
- GREEN: `swift test --scratch-path "$PWD/.build" --filter PackageAppScriptTests` passed 14 tests.
- GREEN: `bash -n Scripts/package-app.sh Scripts/release-check.sh` passed.

## Full Verification

- Disk guard: 57 GiB available on `/System/Volumes/Data`.
- `swift test --scratch-path "$PWD/.build"`: 598 tests, 1 intentional release-only skip, 0 failures.
- `swift build --scratch-path "$PWD/.build"`: passed.
- `git diff --check`: passed.
- Source scan found no `try!` under `Sources/reclaimer`.
- Signing scan confirms `--deep` is used for verification only.

## Review Notes

- Every `printJSON` caller now uses `try`, and command handlers already propagate errors to the top-level nonzero CLI exit path.
- `encodedJSON` preserves pretty-printed, sorted-key, ISO-8601 output while converting encoder and UTF-8 failures into `CLIError.message`.
- `release-check.sh` verifies both the nested CLI and app for newly signed, pre-signed, and accepted-notarization paths.
- No release or notarization claim was made by this task.
