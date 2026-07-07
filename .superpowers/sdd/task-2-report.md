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
