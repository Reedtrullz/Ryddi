# Task 4 Implementer Report - COMPLETE PENDING REVIEW

## Status

Task 4, "Single-Pass Off-Main Audit Snapshot," is implemented and locally verified from base `ab2c477e5012639aa28fdcf804c7f1561efd8eec`. The implementation is ready for the Task 4 spec and quality review.

## Preserved RED Evidence

The interrupted implementer recorded these commands before the requested APIs existed:

```bash
swift test --scratch-path "$PWD/.build" --filter AuditStoreSnapshotTests
swift test --scratch-path "$PWD/.build" --filter DashboardAuditLoadingTests
```

Both exited `1` during compilation. The recorded failures named the missing `AuditStoreSnapshot`, `AuditDirectoryReading`, `AuditDecoding`, `JSONAuditDecoder`, `AuditSnapshotLoading`, injected loader argument, and async audit-loading surface. This resumption preserves that RED evidence as a handoff record; it did not recreate or strengthen the pre-implementation claim.

During recovery, the first core-filter runs also exposed two incomplete test fixtures: `ScanSession.updatedAt` was in the wrong argument position, and `RecoveryCenterReport` was asserted through a nonexistent `receipts` property. Those fixtures were corrected against the real APIs. Before the app loader existed, SwiftPM also compiled the already-RED app test target while running the core filter and reported the expected missing `AuditSnapshotLoading` surface.

## Implementation

- Added immutable `AuditStoreSnapshot` state and a typed audit-file index.
- `snapshot(limitPerKind:)` performs one injected direct-child directory read, classifies each child once, sorts each kind once, caps before decode, and carries scan-session warnings.
- Existing `recent*` and scan-session wrappers use the shared typed index/decode helpers. Legacy scan-session result ordering remains decoded-`updatedAt` based, while snapshot mode keeps its single indexed sort.
- Typed prefix values serialize back to the existing string kinds for prune-plan JSON, and confirmed pruning still revalidates the current kind and filesystem identity before Trash.
- Added `AuditSnapshotLoading` to `DashboardDependencies`; the live loader creates one snapshot.
- `DashboardModel.loadAudit()` is async, runs the synchronous loader in a utility detached task, uses the `.auditLoad` UUID as commit authority, and applies one snapshot without suspension on the main actor.
- Snapshot application updates all audit-backed model state, derives remote comparison state without another audit read, and calls recovery derivation exactly once after assignment.
- Removed the obsolete scan-session-only startup read and a redundant remote dogfood audit lookup.
- Updated every existing `loadAudit()` caller to await it directly or from a SwiftUI `Task`; duplicate post-load recovery calls were removed.
- `AuditHistoryView.swift` required no edit because it has no direct `loadAudit()` caller and reads the snapshot-backed model state.

## Files Changed

- `.superpowers/sdd/task-4-report.md`
- `.superpowers/sdd/progress.md`
- `Sources/ReclaimerCore/AuditStore.swift`
- `Sources/ReclaimerCore/AuditStoreHygiene.swift`
- `Sources/ReclaimerCore/AuditStoreSnapshot.swift`
- `Sources/MacDiskReclaimerApp/DashboardDependencies.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel+AuditAndRecovery.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel+Remote.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel+Reviews.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`
- `Sources/MacDiskReclaimerApp/DashboardView.swift`
- `Tests/ReclaimerCoreTests/AuditStoreSnapshotTests.swift`
- `Tests/MacDiskReclaimerAppTests/DashboardAuditLoadingTests.swift`

## Final Verification

All commands ran from the Task 4 worktree with repo-local `.build`.

```bash
swift test --scratch-path "$PWD/.build" --filter AuditStoreSnapshotTests
```

Exit `0`: 3 tests, 0 failures.

```bash
swift test --scratch-path "$PWD/.build" --filter DashboardAuditLoadingTests
```

Exit `0`: 2 tests, 0 failures.

```bash
swift test --scratch-path "$PWD/.build" --filter Audit
```

Exit `0`: 47 tests, 0 failures.

Before the full loop:

```bash
df -h /System/Volumes/Data
```

Reported `59Gi` available, above the `30Gi` stop threshold.

```bash
swift test --scratch-path "$PWD/.build"
```

Exit `0`: 563 tests, 1 existing skip, 0 failures.

```bash
swift build --scratch-path "$PWD/.build"
```

Exit `0`: build complete.

```bash
git diff --check
```

Exit `0` with no output.

## Self-Review

- Confirmed `snapshot(limitPerKind:)` has one `auditIndex()` construction and the directory spy observes exactly one read.
- Confirmed each generic decode prefixes indexed records before reading `Data` or invoking the decoder.
- Confirmed scan-session snapshot warnings survive decode failures and legacy `listScanSessionsResult` behavior remains covered.
- Confirmed known-prefix ordering still distinguishes `native-tool-execution-` from `native-tool-` and prune JSON keeps the same raw string values.
- Confirmed symlinks, directories, packages, volumes, unknown files, stale identities, and legacy identity-free candidates remain excluded or fail closed.
- Confirmed no independent startup audit-history read remains and all `loadAudit()` call sites await the async API.
- Confirmed snapshot application has no suspension point, stale operation IDs cannot apply or finish a newer load, and recovery is derived once at the end.

## Non-Claims

- No real cleanup or user audit-data mutation was performed.
- No remote SSH target was contacted.
- No app install, signing, notarization, packaging, push, CI, deploy, or release work was performed.
- No packaged-app, Accessibility, or manual UI run was performed for this unit-focused task.
