# Ryddi Current Evidence And Scan Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure every dashboard claim, primary action, coverage label, and menu-bar result belongs to the current scan request and cannot be confused with historical audit evidence.

**Architecture:** Add explicit current-evidence and scan-operation contracts in `ReclaimerCore`, then make one app-scoped `ScanCoordinator` own scan requests and derived presentation state. Historical plans and receipts remain available only in Audit History. Views consume immutable snapshots and never read the audit store or recompute scan-wide analytics during body evaluation.

**Tech Stack:** Swift 6, SwiftUI Observation, SwiftPM, CryptoKit digests, XCTest, macOS 14+.

## Global Constraints

- Run `df -h /System/Volumes/Data` before long test loops and stop below `30Gi` free.
- Use `swift test --scratch-path "$PWD/.build"` and `swift build --scratch-path "$PWD/.build"`.
- Preserve decoding compatibility for existing `ScanCoverage`, `ScanSession`, plans, and receipts.
- Never use an audit-history item as evidence for the current scan unless its IDs are bound by the current `ScanSession`.
- Scope, rule, and policy changes invalidate current evidence immediately.
- Late scan results may be saved as history only if explicitly designed; they must never replace the visible current request.
- No cleanup behavior changes in this plan.

---

## Task 1: Current-Evidence Resolver

**Files:**
- Create: `Sources/ReclaimerCore/CurrentEvidence.swift`
- Create: `Tests/ReclaimerCoreTests/CurrentEvidenceTests.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel.swift`

**Interfaces:**

```swift
public struct CurrentEvidenceSnapshot: Hashable, Sendable {
    public let session: ScanSession?
    public let plan: ReclaimPlan?
    public let dryRunReceipt: ExecutionReceipt?
    public let executionReceipt: ExecutionReceipt?
    public let rejectedEvidence: [CurrentEvidenceRejection]
}

public enum CurrentEvidenceResolver {
    public static func resolve(
        session: ScanSession?,
        plan: ReclaimPlan?,
        dryRunReceipt: ExecutionReceipt?,
        executionReceipt: ExecutionReceipt?
    ) -> CurrentEvidenceSnapshot
}
```

- [ ] Write failing tests proving a plan is current only when `session.planDigest == plan.id` and the session is not invalidated.
- [ ] Write failing tests proving dry-run and execution receipts are current only when their IDs match `dryRunReceiptID` and `executionReceiptID` respectively.
- [ ] Write a failing test proving a historical plan/receipt with a newer timestamp is rejected when IDs do not match.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter CurrentEvidenceTests`; expect failures because the resolver does not exist.
- [ ] Implement `CurrentEvidenceResolver` as a pure fail-closed function. Include typed rejection reasons such as `.missingSession`, `.planDigestMismatch`, `.receiptIDMismatch`, and `.sessionInvalidated`.
- [ ] Replace `plan ?? recentPlans.first` and receipt fallbacks in `trustReadinessReport`, `guidedWorkflowReport`, and `actionCenterReport` with `currentEvidence` values.
- [ ] Keep `recentPlans` and `recentReceipts` visible only in Audit History and recovery evidence views.
- [ ] Run the focused test and `swift test --scratch-path "$PWD/.build"`; expect all tests to pass.
- [ ] Commit: `fix: bind dashboard evidence to current scan session`

## Task 2: Request Identity And Stale-Result Rejection

**Files:**
- Create: `Sources/ReclaimerCore/ScanRequestIdentity.swift`
- Create: `Tests/ReclaimerCoreTests/ScanRequestIdentityTests.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardView.swift`

**Interfaces:**

```swift
public struct ScanRequestIdentity: Hashable, Sendable {
    public let id: UUID
    public let preset: ScanScopePreset
    public let scopeDigest: String
    public let ruleVersion: String
    public let policyDigest: String
}

@MainActor
final class ScanCoordinator {
    private(set) var activeRequest: ScanRequestIdentity?
    func begin(_ request: ScanRequestIdentity)
    func accepts(_ request: ScanRequestIdentity) -> Bool
    func invalidate(reason: ScanSessionInvalidationReason)
    func finish(_ request: ScanRequestIdentity)
}
```

- [ ] Write a failing async test with two scans where scan A finishes after scan B; only B may commit findings, coverage, overview, or session.
- [ ] Write failing tests proving preset, saved-scope, template, and user-rule changes invalidate the active request.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter ScanRequestIdentityTests`; expect failures.
- [ ] Capture preset, scopes, rule version, and policy digest once before detaching scan work.
- [ ] Guard every post-scan state commit with `coordinator.accepts(request)`; return a typed `.superseded` outcome for stale work.
- [ ] Disable scan configuration controls while a request is active. Keep navigation and read-only history available.
- [ ] Add a Cancel button that invalidates the request and discards its result; cancellation need not interrupt a blocking filesystem call in v0.3.
- [ ] Add accessibility identifiers `scan-mode-picker`, `saved-scope-picker`, `scan-button`, and `cancel-scan-button`.
- [ ] Run focused and full tests; expect no stale commit and no regression.
- [ ] Commit: `fix: reject superseded scan results`

## Task 3: Typed Cleanup-Flow Priority

**Files:**
- Modify: `Sources/ReclaimerCore/ActionCenter.swift`
- Modify: `Sources/ReclaimerCore/FindingAnalytics.swift`
- Create: `Tests/ReclaimerCoreTests/ActionCenterQueuePriorityTests.swift`

**Interfaces:**

```swift
public enum CleanupFlowStage: Int, Codable, CaseIterable, Hashable, Sendable {
    case safeCleanup = 0
    case needsUserAction = 1
    case inspectOrKeep = 2
}

public extension ReviewQueueID {
    var cleanupFlowStage: CleanupFlowStage { get }
    var actionPriority: Int { get }
}
```

- [ ] Write a failing test where `valuableHistory` has 35 GB and `safeMaintenance` has 120 MB; the primary action must be Safe Maintenance.
- [ ] Write failing tests for the exact order: Safe Maintenance, Quit App First, Use Native Tool, Unknown, Valuable History, Personal/App Assets.
- [ ] Write a failing test proving zero-reclaim protected/history queues never become a reclaim CTA while an actionable queue exists.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter ActionCenterQueuePriorityTests`; expect current allocated-byte sorting to fail.
- [ ] Replace `compareReviewQueues` with stage-first, action-priority-second, reclaim-bytes-third ordering.
- [ ] Give keep/inspect queues non-destructive titles such as `Review Valuable History`; do not call them reclaim opportunities.
- [ ] Preserve JSON compatibility by adding fields with decoding defaults rather than renaming existing queue IDs.
- [ ] Run focused and full tests.
- [ ] Commit: `fix: prioritize actionable cleanup queues`

## Task 4: Truthful Coverage Semantics

**Files:**
- Modify: `Sources/ReclaimerCore/ScanCoverage.swift`
- Modify: `Sources/ReclaimerCore/Scanner.swift`
- Modify: `Sources/ReclaimerCore/PermissionAdvisor.swift`
- Create: `Tests/ReclaimerCoreTests/ScanCoverageSemanticsTests.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardContentViews.swift` (`PermissionOnboardingView`)

**Interfaces:**

```swift
public struct ScanCoverage: Codable, Hashable, Sendable {
    // Existing fields remain.
    public let rootsMissing: Int
    public let rootsPermissionDenied: Int
}
```

- [ ] Write a backward-compatibility test proving old JSON decodes both new counters as zero.
- [ ] Write a failing test proving a configured optional path that does not exist increments `rootsMissing` and does not degrade coverage.
- [ ] Write failing tests proving `EACCES`/`EPERM` increments `rootsPermissionDenied` and yields `.degraded`.
- [ ] Write a test proving item-budget exhaustion yields `.bounded`, independently of missing roots.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter ScanCoverageSemanticsTests`; expect failure.
- [ ] Split `recordDeniedRoot()` into `recordMissingRoot()` and `recordPermissionDeniedRoot()`; classify `fileExists == false` as missing and enumerator/read failures as denied.
- [ ] Keep legacy `rootsDenied` encoded as the permission-denied count for compatibility; explain missing optional roots separately in evidence.
- [ ] Make `PermissionAdvisor` and scan coverage use the same `ScopeReadability` classification.
- [ ] Update UI copy to show `Unavailable on this Mac` separately from `Permission required` and provide System Settings guidance only for the latter.
- [ ] Run focused and full tests.
- [ ] Commit: `fix: distinguish missing scopes from denied access`

## Task 5: Immutable Presentation Snapshot

**Files:**
- Create: `Sources/ReclaimerCore/ScanPresentationSnapshot.swift`
- Create: `Tests/ReclaimerCoreTests/ScanPresentationSnapshotTests.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardModel+ScanPlan.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardContentViews.swift`

**Interfaces:**

```swift
public struct ScanPresentationSnapshot: Sendable {
    public let overview: ScanOverview
    public let reviewQueues: ReviewQueueReport
    public let topOffenders: TopOffenderTable
    public let largeOldReview: LargeOldReviewReport
    public let archiveReview: ArchiveReviewReport
    public let actionCenter: ActionCenterReport
}
```

- [ ] Write tests proving one snapshot is deterministic for the same findings and clock.
- [ ] Add a performance regression test around a 5,000-finding fixture with a generous release-build threshold stored in the test name and comments.
- [ ] Run focused tests and record the pre-change timing in the commit message body.
- [ ] Build the snapshot in detached work immediately after a scan or filter change, then publish it once on the main actor.
- [ ] Replace `actionCenterScanSessionHistory` disk reads during computed-property evaluation with asynchronously loaded `auditHistoryState`.
- [ ] Replace view-time calls to `FindingAnalytics`, large-file, and archive builders with snapshot fields.
- [ ] Show a lightweight `Updating results` state while a replacement snapshot is being built; retain the previous snapshot until atomic replacement.
- [ ] Run focused/full tests and `swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors`.
- [ ] Commit: `perf: publish immutable scan presentation snapshots`

## Task 6: Shared Dashboard And Menu-Bar Scan Coordinator

**Files:**
- Create: `Sources/MacDiskReclaimerApp/RyddiAppModel.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Modify: `Sources/MacDiskReclaimerApp/DashboardView.swift`
- Modify: `Sources/MacDiskReclaimerApp/StatusMenuView.swift`
- Create: `Tests/ReclaimerCoreTests/SharedScanContractTests.swift`

**Interfaces:**

```swift
@MainActor @Observable
final class RyddiAppModel {
    let dashboard: DashboardModel
    let scanCoordinator: ScanCoordinator
    func scanFromMenuBar() async
}
```

- [ ] Write a failing contract test proving a menu scan uses the same preset, saved scope, user rules, and policy digest as the dashboard.
- [ ] Write a failing test proving a completed menu scan updates the same current session and presentation snapshot shown by the dashboard.
- [ ] Run the focused test; expect the independent `StatusMenuModel` path to fail.
- [ ] Create one app-scoped model in the SwiftUI `App` scene and inject it into both `WindowGroup` and `MenuBarExtra`.
- [ ] Remove the independent menu scanner. Keep menu-specific formatting in a small view adapter only.
- [ ] Make the menu say `Open Ryddi to review` after scan; it must not expose cleanup execution.
- [ ] Run focused/full tests and launch the packaged app for a dashboard/menu smoke.
- [ ] Commit: `refactor: share scan state across app surfaces`

## Task 7: Runtime Acceptance And Documentation

**Files:**
- Modify: `README.md`
- Modify: `FEATURES.md`
- Modify: `docs/RELEASE_CHECKLIST.md`
- Modify: `Scripts/app-e2e-smoke.sh`

- [ ] Add fixture acceptance: before any scan, Safe Reclaim is empty and historical receipts are labeled historical.
- [ ] Add fixture acceptance: changing scope during an active scan is disabled; programmatic invalidation causes the late result to be discarded.
- [ ] Add fixture acceptance: missing optional scopes do not show Full Disk Access warnings.
- [ ] Add fixture acceptance: the primary queue is selected by cleanup stage, not largest allocated bytes.
- [ ] Update docs to distinguish Current Session, Audit History, and optional unavailable scopes.
- [ ] Run `df -h /System/Volumes/Data`.
- [ ] Run `swift test --scratch-path "$PWD/.build"`.
- [ ] Run `swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors`.
- [ ] Run `Scripts/app-e2e-smoke.sh` and `git diff --check`.
- [ ] Commit: `docs: define current evidence and scan consistency gates`

## Completion Criteria

- The app never presents historical plan/receipt values as current reclaim evidence.
- A superseded scan cannot mutate visible dashboard state.
- Safe/actionable queues outrank larger protected/history queues.
- Missing optional roots and denied roots are represented differently everywhere.
- Dashboard and menu bar share one scan request and current session.
- No scan-wide analytics or audit-store I/O occurs from SwiftUI computed body paths.
