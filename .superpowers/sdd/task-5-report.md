# Task 5 Implementer Report - IMPLEMENTATION COMPLETE PENDING REVIEW

## Status

Task 5 operation-based scope access evidence is implemented and locally verified
from clean committed base `7607bdc7c3ffa7269688eab9ff0bd2ca8f3eb177` on
`feature/ryddi-v0.3.1-correctness`. The implementation is complete pending
independent review. The commit containing this report uses the requested message
`fix: verify scope access with real operations`.

## Starting State

```text
HEAD: 7607bdc7c3ffa7269688eab9ff0bd2ca8f3eb177
branch: feature/ryddi-v0.3.1-correctness
available disk: 58Gi
```

The committed baseline matched exactly. The worktree already contained the two
required Task 5 test files as untracked concurrent work:

```text
?? Tests/MacDiskReclaimerAppTests/PermissionRefreshTests.swift
?? Tests/ReclaimerCoreTests/ScopeAccessProbeTests.swift
```

They were preserved, reviewed, used as the test-first surface, and strengthened.
They were not reset or attributed to this session.

## RED Evidence

Both required commands ran before production edits.

```bash
swift test --scratch-path "$PWD/.build" --filter ScopeAccessProbeTests
```

Exit `1`. SwiftPM failed to compile on the intended missing Task 5 contracts,
including `ScopeAccessProbeResult`, `PermissionReportLoading`, the probe-aware
`ScopeAccessSummary` initializer, and dashboard permission loader/task injection.

```bash
swift test --scratch-path "$PWD/.build" --filter PermissionRefreshTests
```

Exit `1` with the same expected missing dashboard contracts, including no
`PermissionReportLoading`, no `permissionReportLoader` dependency argument, and
no `permissionRefreshTask` surface.

## Implementation

- Added `ScopeAccessOperation`, `ScopeAccessProbeResult`, `ScopeAccessProbing`,
  and `FileManagerScopeAccessProbe`.
- Metadata identifies the object type first. Directories perform a listing and
  immediately discard returned names. Regular files are opened read-only and
  closed without reading. Every other filesystem type stops after metadata, so
  FIFO, device, socket, and symbolic-link paths are never opened.
- Nested POSIX `ENOENT`/`ENOTDIR` map to missing, `EACCES`/`EPERM` map to denied,
  and every other or non-POSIX failure remains unknown. Direct Cocoa 257 is not
  treated as POSIX `EACCES`.
- Evidence stores only operation, optional numeric POSIX code, and fixed sanitized
  detail. Directory entry names, file contents, paths from errors, and raw
  `userInfo` are not retained in operation evidence.
- Extended `ScopeAccessSummary` with defaulted optional evidence fields and
  explicit legacy decoding. Extended `ScanCoverage` with a backward-compatible
  `rootsUnknown` counter.
- Routed the same probe contract through `PermissionAdvisor`,
  `FindingAnalytics.overview`, `FileScanner`, and `BoundedFileTreeWalker` while
  preserving existing public `PermissionAdvisor` and `FileScanner` call shapes.
- Missing roots remain non-degrading. Unknown roots degrade coverage separately
  and produce unknown evidence instead of being counted as permission denied.
- Added injectable `PermissionReportLoading`. Dashboard refresh runs in a utility
  detached task and accepts results only for the latest request ID. Scope changes,
  scan results, and screenshot fixtures cannot be overwritten by stale refreshes.
- Preserved Task 4 audit snapshot loading and `PermissionCoverageTransition`
  behavior.
- Extracted `PermissionOnboardingView` and added the exact states `Access verified`,
  `Permission required`, `Unavailable on this Mac`, and `Check failed`.
- Kept `Open Full Disk Access`, `Reveal Ryddi`, `Copy App Path`, `Refresh Access`,
  and added `Relaunch Ryddi`, including the relaunch-may-be-required explanation.
  No synthetic Full Disk Access toggle was added.

## Files Changed

- `.superpowers/sdd/progress.md`
- `.superpowers/sdd/task-5-report.md`
- `Sources/ReclaimerCore/ScopeAccessProbe.swift`
- `Sources/ReclaimerCore/PermissionAdvisor.swift`
- `Sources/ReclaimerCore/FindingAnalytics.swift`
- `Sources/ReclaimerCore/Scanner.swift`
- `Sources/ReclaimerCore/BoundedFileTreeWalker.swift`
- `Sources/ReclaimerCore/ScanCoverage.swift`
- `Sources/MacDiskReclaimerApp/DashboardDependencies.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel+AuditAndRecovery.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`
- `Sources/MacDiskReclaimerApp/PermissionOnboardingView.swift`
- `Sources/MacDiskReclaimerApp/DashboardDemoData.swift`
- `Sources/MacDiskReclaimerApp/PathActions.swift`
- `Tests/ReclaimerCoreTests/ScopeAccessProbeTests.swift`
- `Tests/MacDiskReclaimerAppTests/PermissionRefreshTests.swift`
- `Tests/ReclaimerCoreTests/ScanCoverageSemanticsTests.swift`
- `Tests/ReclaimerCoreTests/MacDiskReclaimerAppPermissionAccessTests.swift`
- `Tests/ReclaimerCoreTests/AppAccessibilityContractTests.swift`

## GREEN And Regression Evidence

```bash
swift test --scratch-path "$PWD/.build" --filter ScopeAccessProbeTests
```

Exit `0`: 13 tests, 0 failures.

```bash
swift test --scratch-path "$PWD/.build" --filter PermissionRefreshTests
```

Exit `0`: 3 tests, 0 failures.

```bash
swift test --scratch-path "$PWD/.build" --filter Permission
```

Exit `0`: 23 tests, 0 failures.

```bash
swift test --scratch-path "$PWD/.build" --filter ScanCoverageSemanticsTests
```

Exit `0`: 4 tests, 0 failures.

```bash
swift test --scratch-path "$PWD/.build" --filter BoundedScanTests
```

Exit `0`: 5 tests, 0 failures.

The combined preservation filter for `PermissionCoverageTransitionTests`,
`ScanPresentationSnapshotTests`, `RuntimeTrustDashboardContractTests`,
`ReleaseTrustEvidenceTests`, `BoundedFileTreeWalkerTests`, and
`DashboardAuditLoadingTests` exited `0`: 28 tests, 1 existing release-only skip,
0 failures.

After a fresh disk check still reported `58Gi` available:

```bash
swift test --scratch-path "$PWD/.build"
```

Exit `0`: 584 tests, 1 existing release-only performance skip, 0 failures.

```bash
swift build --scratch-path "$PWD/.build"
```

Exit `0`: build complete.

```bash
git diff --check
```

Exit `0` with no output.

## Self-Review

- Confirmed special files stop after metadata and a real FIFO fixture completes
  without opening or blocking.
- Confirmed nested POSIX normalization and direct Cocoa 257 separation.
- Confirmed detail strings cannot include directory entries, file contents, error
  paths, or raw error metadata.
- Confirmed legacy `ScanSnapshot` and `ScanCoverage` JSON decode with absent new
  fields.
- Confirmed repeated taps and scope changes reject older permission completions.
- Confirmed Task 4 audit-loading tests remain green.

## Concerns

- The two required test files pre-existed as untracked concurrent work. RED was
  observed before production edits, but this report does not claim authorship of
  their initial contents.
- No remaining correctness concern was found in the requested Task 5 scope.

## Non-Claims

- No claim is made that Full Disk Access itself is enabled.
- No real user scan, cleanup, SSH, keychain operation, install, signing,
  notarization, push, CI, or release operation was performed.
- No packaged-app or manual UI run was performed; UI coverage here is build and
  source-contract based.
- `~/.codex/config.toml` was not modified.
