# Task 2: Core Remote Dogfood Report

## Implementation Summary

Added `RemoteDogfoodReport` and `RemoteDogfoodReportBuilder` in `Sources/ReclaimerCore/RemoteDogfoodReport.swift`.
The builder composes probe, scan, and growth evidence into a read-only dogfood summary with:

- target metadata
- probe and scan identifiers
- growth report linkage
- disk pressure summary
- finding counts and total bytes
- review queue counts
- combined command receipts
- explicit non-claims
- markdown output that respects `ReportPrivacyOptions`

Updated `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift` with a focused remote dogfood composition test.

## TDD Evidence

### RED

Added `testRemoteDogfoodReportComposesScanGrowthAndRedactsPaths()`.

Verified failure with:

```bash
swift test --scratch-path "$PWD/.build" --filter RemoteDogfood
```

Observed compiler failure:

- `cannot find 'RemoteDogfoodReportBuilder' in scope`

### GREEN

Implemented `Sources/ReclaimerCore/RemoteDogfoodReport.swift`.

Re-ran:

```bash
swift test --scratch-path "$PWD/.build" --filter RemoteDogfood
```

Result: focused dogfood test passed.

## Tests

- Focused test command: `swift test --scratch-path "$PWD/.build" --filter RemoteDogfood`
- Result: 1 test passed, 0 failures

## Files Changed

- `Sources/ReclaimerCore/RemoteDogfoodReport.swift`
- `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`

## Self-Review

- The new report is read-only and report-first; it does not add any cleanup behavior.
- Path redaction is honored in markdown output through `ReportPrivacyOptions`.
- Non-claims explicitly say the report does not prove current state or cleanup safety.
- The implementation stays scoped to the requested core model/builder and test.

## Concerns

- No live remote target was exercised; verification was limited to the focused unit test.
- Review queue counts are derived from `recommendedNextAction` groupings, which matches the current report shape but was not separately validated outside the test fixture.

## Review Fix

Patched `RemoteDogfoodReportBuilder` so redacted markdown no longer prints the target alias/input or resolved host. Redacted exports now show shareable placeholders instead of `prod-vps` or `203.0.113.10`.

Added regression assertions in `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift` to verify the redacted markdown contains `<target redacted>` and `<host redacted>` and does not leak the private target metadata.

### Verification

```bash
swift test --scratch-path "$PWD/.build" --filter RemoteDogfood
```

Output:

- Build complete
- `testRemoteDogfoodReportComposesScanGrowthAndRedactsPaths` passed
- Executed 1 test, 0 failures

## Files Changed For Fix

- `Sources/ReclaimerCore/RemoteDogfoodReport.swift`
- `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`

## Re-Review Fix

Sanitized the `RemoteDogfoodReport` object itself when privacy is not full, so redacted exports no longer keep raw target metadata or command previews in Codable/SwiftUI/AuditStore-facing state.

### Verification

```bash
swift test --scratch-path "$PWD/.build" --filter RemoteDogfood
```

Output:

- Build complete
- `testRemoteDogfoodReportComposesScanGrowthAndRedactsPaths` passed
- `testRemoteDogfoodReportKeepsFullDetailsWhenPrivacyIsFull` passed
- Executed 2 tests, 0 failures

## Privacy Re-Review Fix

Updated `RemoteDogfoodReportBuilder` so `diskPressureSummary` is rendered through `ReportPrivacyOptions`, preventing redacted exports from leaking raw remote mount paths like `/srv/private-client/uploads`.

Added `testRemoteDogfoodReportRedactsDiskPressureMountPaths()` with a private mount fixture and a full-privacy assertion in `testRemoteDogfoodReportKeepsFullDetailsWhenPrivacyIsFull()` to prove redacted mode shows `<path redacted>` while full mode keeps the real mount path.

### Verification

```bash
swift test --scratch-path "$PWD/.build" --filter RemoteDogfood
```

Output:

- Build complete
- `testRemoteDogfoodReportComposesScanGrowthAndRedactsPaths` passed
- `testRemoteDogfoodReportKeepsFullDetailsWhenPrivacyIsFull` passed
- `testRemoteDogfoodReportRedactsDiskPressureMountPaths` passed
- Executed 3 tests, 0 failures
