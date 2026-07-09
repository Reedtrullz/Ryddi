## 2026-07-09 Task 6 Implementation

Status: DONE

Files changed:
- `Sources/ReclaimerCore/AuditStore.swift`
- `Sources/ReclaimerCore/ActionCenter.swift`
- `Sources/reclaimer/ReclaimerCLI.swift`
- `Tests/ReclaimerCoreTests/ScanSessionTests.swift`
- `Tests/ReclaimerCoreTests/ActionCenterTests.swift`
- `Tests/ReclaimerCLITests/ReclaimerCLITests.swift`

Tests run:
- `df -h /System/Volumes/Data` (83Gi available)
- `swift test --scratch-path "$PWD/.build" --filter ScanSession` (20 tests, 0 failures)
- `swift run --scratch-path .build reclaimer session latest` (printed the required no-session guidance)
- `git diff --check`

Self-review notes:
- Added `AuditStoreScanSessionListResult` and typed `AuditStoreScanSessionWarning` so corrupt scan-session files surface path, kind, and safe local-display message while readable sessions still sort by `updatedAt`.
- Kept `AuditStore.listScanSessions(limit:)` and `latestScanSession()` backward-compatible by delegating through the result API and returning readable sessions only.
- Preserved legacy unversioned `scan-session-*.json` reads and covered no-session, legacy-only, corrupt-only, and valid-after-corrupt histories.
- Added `ActionCenterInput.sessionHistoryWarnings` with a default and one `ActionCenterReport.nonClaims` entry for partially unreadable scan-session history; CLI `actions` now passes the warning result through.
- Pinned exact `reclaimer session latest` no-session text in CLI tests.

Concerns:
- None.

## 2026-07-09 Task 6 Review Fixes

Status: DONE

Files changed:
- `Sources/ReclaimerCore/ScanSession.swift`
- `Sources/reclaimer/ReclaimerCLI.swift`
- `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- `Tests/ReclaimerCLITests/ReclaimerCLITests.swift`
- `Tests/ReclaimerCoreTests/MacDiskReclaimerAppLayoutTests.swift`
- `Tests/ReclaimerCoreTests/ScanSessionTests.swift`

Tests run:
- `df -h /System/Volumes/Data` (81Gi available)
- `swift test --scratch-path "$PWD/.build" --filter ScanSession` (24 tests, 0 failures)
- `swift test --scratch-path "$PWD/.build" --filter 'ScanCommand|ScanSessionApp'` (3 tests, 0 failures)
- `swift run --scratch-path .build reclaimer session latest` (printed the required no-session guidance)
- `git diff --check`

Self-review notes:
- Added `ScanSessionEvidenceBuilder` so scan sessions use typed deterministic evidence digests for scope, policy, and findings.
- CLI `scan` now saves a durable scanned `ScanSession` with the same scopes, rule version, user policy, and prepared findings used for scan output; CLI regression proves `session latest --json` sees it.
- App `DashboardModel.scan()` and its refresh path now persist the recorded scan session through `AuditStore.saveScanSession(_:)`.
- App Summary now reads `AuditStore.listScanSessionsResult(limit: 1)`, falls back to the saved latest session when no current in-memory session exists, and passes typed session-history warnings into `ActionCenterInput`.
- Execute-safe gating in `ActionCenter` was not changed.

Concerns:
- App scan persistence is covered with a source-level test rather than a full model integration test because the dashboard model is embedded in the SwiftUI app source.
