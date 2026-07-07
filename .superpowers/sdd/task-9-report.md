# Task 9 Report: Final Review Fixes For Remote Dogfood Matching

## Status

Implemented.

## Changes

- Tightened saved remote target matching in `Sources/ReclaimerCore/AuditStore.swift` so alias/id/input overlap no longer cross-matches when both sides have complete but different resolved `user@host:port`.
- Added a strict saved-audit selector that throws `AuditStore.RemoteAuditQueryError.ambiguousSavedTargetQuery(...)` when an id/input/alias query maps to more than one concrete target identity or more than one unresolved saved-target group.
- Updated `Sources/reclaimer/main.swift` so `remote dogfood --from-audit TARGET` uses the strict selector and surfaces an ambiguity error instead of silently picking the newest saved scan.
- Updated dogfood growth pairing to use `latestPreviousRemoteScanReport(forConcreteTarget:excludingReportID:)` so previous-scan selection follows concrete-target identity instead of raw `target.id`.
- Updated `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift` to reuse the same concrete-target helpers for saved remote growth and dogfood export/display instead of pairing by raw `target.id`.
- Added focused regression coverage in `Tests/ReclaimerCoreTests/ReclaimerCoreTests.swift` for:
  - resolved-host conflicts with shared alias/id/input,
  - ambiguous saved-scan lookup across concrete targets,
  - ambiguous saved-scan lookup across unresolved targets while preserving unique id lookup,
  - concrete probe pairing refusing same-id/different-host collisions,
  - previous-scan selection refusing same-id/different-host collisions.

## Verification

- `swift test --scratch-path "$PWD/.build" --filter 'ReclaimerCoreTests/(testAuditStoreDoesNotCrossMatchResolvedTargetsWhenAliasOrIDOverlap|testAuditStoreRejectsAmbiguousSavedRemoteScanQueryAcrossConcreteTargets|testAuditStoreSelectsConcreteProbeByResolvedIdentityInsteadOfSharedIDConflict|testAuditStorePreviousRemoteScanUsesConcreteIdentityInsteadOfSharedIDConflict)'`
  - Passed.
- `swift test --scratch-path "$PWD/.build" --filter 'ReclaimerCoreTests/(testAuditStore|testRemoteGrowthReportComparesSavedScansAndRedactsPaths|testRemoteDogfoodReportComposesScanGrowthAndRedactsPaths)'`
  - Passed.
- `swift build --scratch-path "$PWD/.build"`
  - Passed.

## Non-Claims

- No live SSH target was contacted.
- No remote cleanup command was executed.
