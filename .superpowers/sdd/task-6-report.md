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
