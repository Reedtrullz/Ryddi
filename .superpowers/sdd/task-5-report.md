# Task 5 Implementer Report - REVIEW FIXES COMPLETE PENDING RE-REVIEW

## Status

Task 5 operation-based scope access evidence and the independent-review fixes are
implemented and locally verified on `feature/ryddi-v0.3.1-correctness`. The review
fix pass started from clean committed HEAD
`2b806ef65c1233275792cc213874fc822b5dffa7` and is complete pending re-review. The
review-fix commit uses the requested message `fix: preserve scope access evidence`.

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
- Metadata identifies the object type first. Directories use a bounded POSIX
  `opendir`/single-`readdir`/`closedir` access operation without converting or
  retaining entry names. Regular files are opened read-only and closed without
  reading. Every other filesystem type stops after metadata, so FIFO, device,
  socket, and symbolic-link paths are never opened.
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

Exit `0` with no output after the report and progress updates.

```bash
git diff --check
```

Exit `0` with no output.

## Independent Review Fix Pass

### Review-Fix Starting State

```text
HEAD: 2b806ef65c1233275792cc213874fc822b5dffa7
branch: feature/ryddi-v0.3.1-correctness
available disk before verification: 54Gi
```

The worktree was clean and matched the requested review base. No reset or revert
was performed.

### Review-Fix RED Evidence

The focused tests were added before review-fix production edits. These commands
each exited `1` on the intended missing contracts:

```bash
swift test --scratch-path "$PWD/.build" --filter ScopeAccessProbeTests
swift test --scratch-path "$PWD/.build" --filter BoundedFileTreeWalkerTests
swift test --scratch-path "$PWD/.build" --filter ScanCoverageSemanticsTests
swift test --scratch-path "$PWD/.build" --filter ScanPresentationSnapshotTests
swift test --scratch-path "$PWD/.build" --filter PathActionsTests
```

Exact RED diagnostics included:

- `cannot find type 'DirectoryAccessOperating' in scope` and extra
  `directoryAccessOperation` initializer arguments;
- `ScanCoverage` had no member `scopeAccessSummaries`;
- `ScanPresentationSnapshot.build` rejected the `scopeAccessProbe` behavioral-spy
  argument;
- `RelaunchCommandRunning`, `ApplicationTerminating`, and
  `RelaunchApplicationFailure` did not exist, and relaunch accepted no injectable
  arguments.

Because SwiftPM compiles all test targets before applying a test filter, the
missing relaunch and coverage contracts appeared together in several RED command
outputs. The failures were compile-time contract failures, not unrelated runtime
failures.

### Review-Fix Implementation

- Replaced `contentsOfDirectory(atPath:)` in the scope probe with a bounded POSIX
  directory access operation. It calls `opendir`, invokes `readdir` at most once,
  discards the `dirent` pointer, checks `errno`, and closes the directory handle.
  An injected operation spy proves one call with an entry limit of one and proves
  the old name-materializing FileManager API is not called.
- Centralized nested POSIX normalization in `ScopeReadability`. `ENOENT` and
  `ENOTDIR` remain missing, `EACCES` and `EPERM` remain denied, all other errors
  remain unknown, and direct Cocoa 257 remains unknown without nested POSIX
  evidence.
- Classified traversal-time metadata and listing failures through the same
  contract. Post-probe missing roots remain missing and non-degrading; unknown
  failures degrade as unknown and do not create permission/FDA evidence.
- Added optional backward-compatible `ScanCoverage.scopeAccessSummaries`. New
  scans populate it from the one scanner probe pass; legacy decoded coverage
  defaults to `nil` and retains fallback behavior.
- Made `FindingAnalytics`, `ScanPresentationSnapshot`, and scanner-backed CLI
  overview/report/history/trust flows consume the carried summaries. A
  state-changing counting probe proves one call per scope and byte-for-byte equal
  coverage/presentation summaries.
- Made relaunch await `/usr/bin/open` completion and require exit status zero
  before termination. Launch failure and nonzero exit keep Ryddi running and
  return a typed failure; the Permissions UI surfaces that failure in an alert.
  Behavioral tests use injected command and terminator seams and never run a real
  relaunch.

### Review-Fix Files Changed

- `.superpowers/sdd/progress.md`
- `.superpowers/sdd/task-5-report.md`
- `Sources/ReclaimerCore/ScopeAccessProbe.swift`
- `Sources/ReclaimerCore/PermissionAdvisor.swift`
- `Sources/ReclaimerCore/BoundedFileTreeWalker.swift`
- `Sources/ReclaimerCore/ScanCoverage.swift`
- `Sources/ReclaimerCore/FindingAnalytics.swift`
- `Sources/ReclaimerCore/ScanPresentationSnapshot.swift`
- `Sources/MacDiskReclaimerApp/PathActions.swift`
- `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`
- `Sources/reclaimer/AuditCommands.swift`
- `Sources/reclaimer/ReclaimerCLI.swift`
- `Sources/reclaimer/ReportCommands.swift`
- `Sources/reclaimer/ReviewCommands.swift`
- `Tests/ReclaimerCoreTests/ScopeAccessProbeTests.swift`
- `Tests/ReclaimerCoreTests/BoundedFileTreeWalkerTests.swift`
- `Tests/ReclaimerCoreTests/ScanCoverageSemanticsTests.swift`
- `Tests/ReclaimerCoreTests/ScanPresentationSnapshotTests.swift`
- `Tests/MacDiskReclaimerAppTests/PathActionsTests.swift`

### Review-Fix GREEN And Preservation Evidence

```text
ScopeAccessProbeTests: 13 tests, 0 failures
PermissionRefreshTests: 3 tests, 0 failures
ScanCoverageSemanticsTests: 4 tests, 0 failures
ScanPresentationSnapshotTests: 4 tests, 1 existing release-only skip, 0 failures
PathActionsTests: 3 tests, 0 failures
BoundedFileTreeWalkerTests: 5 tests, 0 failures
Permission filter: 25 tests, 0 failures
BoundedScanTests: 5 tests, 0 failures
Compatibility filter: 6 tests, 0 failures
Task 4/presentation preservation bundle: 31 tests, 1 existing skip, 0 failures
```

After a fresh disk check still reported `54Gi` available:

```bash
swift test --scratch-path "$PWD/.build"
```

Exit `0`: 590 tests, 1 existing release-only performance skip, 0 failures.

```bash
swift build --scratch-path "$PWD/.build"
```

Exit `0`: build complete.

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
- Confirmed scanner coverage and presentation use identical operation summaries
  without a second probe.
- Confirmed relaunch termination occurs only after successful command completion.

## Concerns

- The two required test files pre-existed as untracked concurrent work. RED was
  observed before production edits, but this report does not claim authorship of
  their initial contents.
- The live `/usr/bin/open` runner and packaged alert were not exercised because a
  real relaunch and packaged manual/AX proof are explicitly outside this pass.

## Non-Claims

- No claim is made that Full Disk Access itself is enabled.
- No real user scan, cleanup, SSH, keychain operation, install, signing,
  notarization, push, CI, or release operation was performed.
- No packaged-app or manual UI/AX run was performed; UI/action coverage here is
  behavioral model/action tests plus build and existing contract tests.
- `~/.codex/config.toml` was not modified.
