# Task 4 Implementer Report - REVIEW FIX COMPLETE

## Status

Task 4 review fixes are implemented and locally verified from committed base
`860648f40b2422969fdb066da3812da3218e85c8`. The branch is ready for independent
re-review. The follow-up commit containing this report uses the requested message
`fix: preserve audit snapshot semantics`.

## Starting State

The requested HEAD and branch matched exactly, and disk space was above the stop
threshold:

```text
HEAD: 860648f40b2422969fdb066da3812da3218e85c8
branch: feature/ryddi-v0.3.1-correctness
available disk: 59Gi
```

The first `git status --short --branch` was not clean. It already contained
uncommitted changes in:

```text
M Sources/ReclaimerCore/AuditStore.swift
M Tests/ReclaimerCoreTests/AuditStoreSnapshotTests.swift
```

Those changes directly addressed reviewer findings 1 and 4. They were preserved,
reviewed, strengthened, and included; they were not reset or attributed to this
session.

## Fresh RED Evidence

Tests were added before the app implementation changes.

First RED command:

```bash
swift test --scratch-path "$PWD/.build" --filter DashboardAuditLoadingTests
```

Exit `1`. The suite built and ran 3 tests. The new presentation regression failed
with the expected stale state:

```text
DashboardAuditLoadingTests.swift:80: XCTAssertEqual failed: ("0") is not equal to ("1")
DashboardAuditLoadingTests.swift:82: XCTAssertTrue failed
Executed 3 tests, with 2 failures (0 unexpected)
```

This proved an accepted audit snapshot did not refresh an existing presentation,
so the new scan-session warning filename never reached Action Center non-claims.

Second RED command after adding the paired holding-and-audit regression:

```bash
swift test --scratch-path "$PWD/.build" --filter DashboardAuditLoadingTests
```

Exit `1` during compilation with the expected missing paired API:

```text
DashboardAuditLoadingTests.swift:98:39: error: value of type 'DashboardModel' has no member 'loadHoldingAndAudit'
```

Running the core filter at that RED point also exited `1` because SwiftPM compiled
the already-RED app test target and reported the same missing member.

The AuditStore throwing/order/data-reader implementation and its first focused
tests were already uncommitted at session start. This report does not claim fresh
RED chronology for those pre-existing edits.

## Implementation

- Made shared audit index construction throwing. The throwing legacy scan-session
  API uses `try`, while nonthrowing summary, snapshot, prune-plan, and `recent*`
  APIs use the explicit `auditIndexOrEmpty()` fallback.
- Restored deterministic legacy scan-session traversal by filename before decode,
  preserving filename-ordered warnings while keeping decoded sessions ordered by
  `updatedAt` and filename tie-break.
- Added the injected `AuditDataReading` boundary and routed generic and scan-session
  reads through it. The cap test now proves only the exact newest 20 receipt files
  are read, not merely that only 20 decodes occur.
- Added `loadHoldingAndAudit()`. Paired startup and Recovery Center refresh paths
  load holding records without deriving recovery, then derive recovery once after
  the accepted audit snapshot is atomically applied. Standalone Holding refresh
  still derives recovery immediately.
- After an accepted snapshot, `loadAudit()` now finishes `.auditLoad` before it
  conditionally refreshes an existing presentation. `apply(snapshot:)` remains
  synchronous and has no suspension point.
- Avoided a duplicate presentation rebuild in the dry-run path while preserving
  its first-presentation behavior.
- Strengthened dashboard loading tests to mutate real model state while the loader
  is blocked and to prove an older completion cannot clear or replace the newer
  `.auditLoad` activity ID.

## Files Changed

- `.superpowers/sdd/task-4-report.md`
- `.superpowers/sdd/progress.md`
- `Sources/ReclaimerCore/AuditStore.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel+AuditAndRecovery.swift`
- `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- `Sources/MacDiskReclaimerApp/DashboardView.swift`
- `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`
- `Tests/ReclaimerCoreTests/AuditStoreSnapshotTests.swift`
- `Tests/MacDiskReclaimerAppTests/DashboardAuditLoadingTests.swift`

No `.superpowers/sdd/reviews/` artifact was added.

## Final Verification

All commands ran from the Task 4 worktree with repo-local `.build`.

```bash
swift test --scratch-path "$PWD/.build" --filter AuditStoreSnapshotTests
```

Exit `0`: 6 tests, 0 failures.

```bash
swift test --scratch-path "$PWD/.build" --filter DashboardAuditLoadingTests
```

Exit `0`: 4 tests, 0 failures.

```bash
swift test --scratch-path "$PWD/.build" --filter Audit
```

Exit `0`: 52 tests, 0 failures.

```bash
df -h /System/Volumes/Data
```

Reported `59Gi` available, above the `30Gi` stop threshold.

```bash
swift test --scratch-path "$PWD/.build"
```

Exit `0`: 568 tests, 1 existing release-only performance skip, 0 failures.

```bash
swift build --scratch-path "$PWD/.build"
```

Exit `0`: build complete.

```bash
git diff --check
```

Exit `0` with no output.

## Self-Review

- Confirmed throwing and fallback audit-index paths are separated by API contract.
- Confirmed legacy warnings traverse lexical filenames and snapshot reads cap before
  file contents are loaded.
- Confirmed paired holding-and-audit call sites no longer derive against stale
  receipts and accepted snapshot application derives recovery once.
- Confirmed stale audit loaders neither apply state nor finish a newer activity.
- Confirmed presentation refresh happens after activity finish and outside atomic
  snapshot application.

## Concerns

- The two pre-existing uncommitted AuditStore files prevented a truthful fresh RED
  claim for findings 1 and 4; their behavior is covered by focused final tests.
- No remaining correctness concern was found in the requested review-fix scope.

## Non-Claims

- No real cleanup or user audit-data mutation was performed.
- No keychain operation, SSH connection, remote target, or cleanup command was run.
- No app install, package, signing, notarization, push, CI, deploy, or release work
  was performed.
- No packaged-app, Accessibility, or manual UI run was performed for this
  unit-focused follow-up.
