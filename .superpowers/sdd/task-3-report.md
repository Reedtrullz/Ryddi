# Task 3 Report: Remote Dogfood Audit Storage

## Implementation Summary

Implemented remote dogfood persistence and lookup in `Sources/ReclaimerCore/AuditStore.swift`.

- Added `save(remoteDogfoodReport:)` to write `remote-dogfood-<id>.json` files.
- Added `recentRemoteDogfoodReports(limit:)` to list persisted dogfood reports newest-first.
- Added `latestRemoteScanReport(matching:)` and `latestRemoteProbeReport(matching:)` to find the newest stored evidence for a target.
- Added `remoteTargetsMatch(_:_: )` so target matching works by `id` and by resolved host/user/port.

Added a focused regression test in `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift` that:

- persists a probe, scan, and derived dogfood report,
- verifies the dogfood report round-trips from storage,
- verifies the latest scan/probe evidence is returned for the target.

## TDD Evidence

### RED

Ran:

```bash
swift test --scratch-path "$PWD/.build" --filter AuditStoreRoundTripsRemoteDogfood
```

Observed compile failures before implementation:

- `AuditStore` had no member `save(remoteDogfoodReport:)`.
- `AuditStore` had no member `recentRemoteDogfoodReports`.
- `AuditStore` had no member `latestRemoteScanReport`.
- `AuditStore` had no member `latestRemoteProbeReport`.

### GREEN

Ran the same focused test after implementation:

```bash
swift test --scratch-path "$PWD/.build" --filter AuditStoreRoundTripsRemoteDogfood
```

Result: passed.

## Tests

- Focused test passed: `testAuditStoreRoundTripsRemoteDogfoodReportsAndFindsLatestTargetEvidence`
- No broader suite was run for this task.

## Files Changed

- `Sources/ReclaimerCore/AuditStore.swift`
- `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`

## Self-Review

The implementation stays inside the requested scope and follows the existing audit-store storage pattern. The new lookup helpers reuse the current newest-first listing behavior rather than introducing new persistence machinery.

## Concerns

- Target matching is intentionally permissive across `id` and resolved host/user/port so stored probe/scan evidence can still be found when the alias or input string changes.
- I did not run the full test suite, only the focused regression test requested by the task brief.

## Follow-up Regression

Added coverage for the reviewer finding that unresolved targets could cross-match when all resolved fields were `nil`.

### RED

Ran:

```bash
swift test --scratch-path "$PWD/.build" --filter AuditStore
```

Observed failures before the matcher fix:

- `testAuditStoreDoesNotCrossMatchUnresolvedRemoteTargets` returned probe/scan evidence for an unrelated unresolved target.

### GREEN

Ran the same focused slice after the matcher fix:

```bash
swift test --scratch-path "$PWD/.build" --filter AuditStore
```

Result: passed.

## Updated Files

- `Sources/ReclaimerCore/AuditStore.swift`
- `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift`
