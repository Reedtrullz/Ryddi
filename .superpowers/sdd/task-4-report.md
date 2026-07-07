# Task 4 Report: CLI Remote Dogfood Command

## Implementation summary

- Added `remote dogfood` dispatch in `Sources/reclaimer/main.swift`.
- Added help text for:
  - `reclaimer remote dogfood TARGET [--json] [--timeout SECONDS] [--path-style full|home-relative|redacted] [--output PATH] [--save-audit]`
  - `reclaimer remote dogfood --from-audit TARGET [--json] [--path-style full|home-relative|redacted] [--output PATH] [--save-audit]`
- Implemented `remoteDogfood(args:)` in the CLI.
  - Validates report privacy options.
  - Requires `TARGET`.
  - Live path resolves the remote target, runs existing read-only probe/scan builders, and now fails non-zero if probe evidence shows the host could not be reached with read-only SSH commands.
  - `--from-audit` path does not call `RemoteTargetResolver` and does not invoke `ssh -G` or open SSH sessions. It matches saved local evidence using a local `RemoteTargetReference(input: targetInput, alias: targetInput)` and packages the latest saved remote scan plus optional latest saved probe.
  - Reuses existing saved scan history to attach an optional growth report for the same saved target id.
  - Supports `--json`, `--output`, and `--save-audit`.

## Tests and smokes

### Why no CLI unit test was added

- `ReclaimerCLI` lives in the executable target `reclaimer`.
- The existing test target is `ReclaimerCoreTests` with dependency on `ReclaimerCore` only.
- Adding CLI tests here would have required widening package/test visibility beyond this task's requested scope.

### Commands run

```bash
swift build --scratch-path "$PWD/.build"
```

Result:

- Passed.

```bash
swift run --scratch-path .build reclaimer remote dogfood definitely-not-a-real-ryddi-host --timeout 1 --json
```

Result:

- Exited non-zero quickly.
- Error: `Remote dogfood could not reach definitely-not-a-real-ryddi-host with read-only SSH commands; no cleanup was executed and no password prompt was requested.`

```bash
scratch=$(mktemp -d) && trap 'rm -rf "$scratch"' EXIT && \
RYDDI_AUDIT_ROOT="$scratch/audit" \
swift run --scratch-path .build reclaimer remote dogfood --from-audit definitely-not-a-real-ryddi-host --path-style redacted --json
```

Result:

- Exited non-zero quickly.
- Error: `remote dogfood --from-audit found no saved remote scan for definitely-not-a-real-ryddi-host`
- Confirms the `--from-audit` path is local-evidence driven and does not require saved SSH resolution to fail.

## Files changed

- `Sources/reclaimer/main.swift`

## Self-review

- Scope stayed inside the CLI entrypoint as requested.
- No SwiftUI, docs, release-check, or unrelated source files were modified.
- The live path now matches the task brief's failure semantics for unreachable hosts.
- The `--from-audit` branch intentionally avoids `RemoteTargetResolver` so it does not depend on `ssh -G`.
- Matching for `--from-audit` is strongest when saved reports used the same target input or alias id. This aligns with the task interpretation and existing `RemoteTargetReference` id defaults.

## Concerns

- There is still no direct automated CLI test coverage for `ReclaimerCLI.run(arguments:)` in the current package layout.
- `--from-audit` local matching depends on existing saved target ids/aliases; it does not attempt host/user/port reconciliation unless those identities are already present in the saved records selected by id match.

## Review Follow-up

- Replaced the audit lookup matcher so `remote dogfood --from-audit` now matches saved scan and probe records locally by target `id`, `input`, or `alias`.
- Kept the live `remote dogfood` path unchanged; only the `--from-audit` branch now uses local audit records without calling `RemoteTargetResolver`.
- The CLI now uses the latest matching saved scan and then the latest saved probe for that scan target when one exists.
- Updated the zero-argument `remote` error text to include `dogfood`.
- Added a regression test covering alias/id matching and latest-scan selection in `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`.
- Verification completed:
  - `swift build --scratch-path "$PWD/.build"`
  - `swift test --scratch-path "$PWD/.build" --filter ReclaimerCoreTests/testAuditStoreMatchesRemoteTargetsByIdInputAndAliasAndPrefersLatestScan`
  - shell smoke with `RYDDI_AUDIT_ROOT` temp JSON fixtures and `reclaimer remote dogfood --from-audit alias-prod-vps --path-style redacted --json`
  - shell check that `reclaimer remote` error text includes `dogfood`

## Fix Follow-up 2

- Restored resolved remote identity fallback in `AuditStore.latestRemoteScanReport(matching:)` and `latestRemoteProbeReport(matching:)` so saved host/user/port matches still work when ids or aliases drift.
- Added `AuditStore.latestRemoteProbeReport(forConcreteTarget:)` for the narrower `--from-audit` scan-to-probe pairing path.
- Updated `remote dogfood --from-audit` to attach a probe only when it belongs to the same concrete saved target as the selected scan, which prevents newer alias-colliding probes from a different target from being reused.
- Added a regression test that selects a scan by id and proves a newer probe from another target with the same alias is not paired.

### Commands run

```bash
df -h /System/Volumes/Data
```

Result:

- `73Gi` free before the Swift test/build loop.

```bash
swift test --scratch-path "$PWD/.build" --filter ReclaimerCoreTests/testAuditStoreMatchesResolvedTargetsByHostUserAndPortWhenIdsDiffer
```

Result:

- Failed before the fix with `XCTAssertEqual` mismatches for both saved probe and scan lookup, confirming the resolved-identity regression.

```bash
swift test --scratch-path "$PWD/.build" --filter 'ReclaimerCoreTests/(testAuditStoreMatchesResolvedTargetsByHostUserAndPortWhenIdsDiffer|testAuditStoreMatchesRemoteTargetsByIdInputAndAliasAndPrefersLatestScan|testAuditStoreSelectsProbeForSameConcreteTargetAsSelectedScan)'
```

Result:

- Passed after the fix: `Executed 3 tests, with 0 failures`.

```bash
swift build --scratch-path "$PWD/.build"
```

Result:

- Passed.
