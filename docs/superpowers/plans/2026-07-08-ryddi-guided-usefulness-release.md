# Ryddi Guided Usefulness Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Ryddi's guided usefulness release slice so the app opens with one obvious safe next action, cleanup plans rely on machine-verifiable gates, local reclaim lanes stay preview-first, remote reports cannot misrepresent degraded evidence, and release trust is backed by typed manifest proof.

**Architecture:** Keep `ReclaimerCore` as the source of truth for workflow state, safety, remote coverage, release evidence, and report semantics. The CLI exposes proof paths for every app claim, while SwiftUI renders the same core reports as a calm decision cockpit. No root helper, cloud service, destructive remote action, or broad UI rewrite is introduced in this slice.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM, macOS 14+, system OpenSSH, local JSON audit records, shell release scripts, GitHub Actions, direct macOS distribution.

## Global Constraints

- Minimum OS remains macOS 14+.
- Keep scans local; no telemetry, path upload, remote AI analysis, root helper, or Mac App Store sandboxing.
- Remote Targets remain read-only/report-first; do not add any destructive remote command path.
- Preserve GarageBand/Logic assets, browser profiles, VM/container disks, Codex sessions/memories/config/auth, credentials, app state DBs, databases, backups, and unknown user data by default.
- Before long build/test loops, run `df -h /System/Volumes/Data`; stop if free space is below `50Gi`.
- Use `swift test --scratch-path "$PWD/.build"` and `swift build --scratch-path "$PWD/.build"`.
- SwiftUI must remain usable at narrow desktop widths; prefer adaptive stacks, scroll views, and clipped labels over fixed-width table layouts.
- Release claims must distinguish unsigned local debug builds, signed builds, notarization-submitted builds, and signed/notarized/stapled/Gatekeeper-accepted builds.
- Documentation must describe Ryddi as general Mac cleanup plus developer-first depth, not as developer-only tooling.

---

## File Structure

- Create `Sources/ReclaimerCore/GuidedWorkflow.swift`
  - Owns one-primary-action workflow state and Summary recommendations.
- Create `Tests/ReclaimerCoreTests/GuidedWorkflowTests.swift`
  - Tests workflow step selection from permission, scan, plan, receipt, and trust inputs.
- Create `Sources/MacDiskReclaimerApp/GuidedSummaryView.swift`
  - Owns the Summary proof ladder and adaptive layout.
- Modify `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
  - Replaces inline Summary composition with `GuidedSummaryView`.
- Modify `Sources/ReclaimerCore/Models.swift`
  - Adds typed age/retention gate evidence to rule matches and plans.
- Modify `Sources/ReclaimerCore/Rules.swift`
  - Decodes numeric age/retention gate metadata from bundled and user rules.
- Modify `Sources/ReclaimerCore/PlanBuilder.swift`
  - Evaluates gate evidence without using English condition copy as authority.
- Modify `Sources/ReclaimerCore/Resources/rules.json`
  - Adds typed age/retention metadata only to rules that can prove it.
- Create `Tests/ReclaimerCoreTests/PlanGateEvidenceTests.swift`
  - Tests age, retention, open-handle, native-tool, and final-classification gates.
- Create `Sources/ReclaimerCore/PackageReclaimLane.swift`
  - Converts package-cache reports into native-tool preview plans.
- Create `Tests/ReclaimerCoreTests/PackageReclaimLaneTests.swift`
  - Tests package manager guidance and dry-run-only behavior.
- Create `Sources/ReclaimerCore/AgentRetentionPlan.swift`
  - Converts eligible AI-agent retention recommendations into preview-first local plans.
- Create `Tests/ReclaimerCoreTests/AgentRetentionPlanTests.swift`
  - Tests protected Codex state, review-heavy sessions, and eligible cache/log retention.
- Modify `Sources/ReclaimerCore/RemoteTarget.swift`
  - Adds backward-compatible remote scan coverage and target continuity types.
- Modify `Sources/ReclaimerCore/RemoteScan.swift`
  - Computes coverage from command outcomes and marks unreachable/partial scans.
- Modify `Sources/ReclaimerCore/RemoteReportExport.swift`
  - Shows coverage and target continuity in Markdown reports.
- Modify `Sources/reclaimer/RemoteCommands.swift`
  - Blocks misleading default saves/exports for unreachable scans and binds exports to selected targets.
- Create `Tests/ReclaimerCoreTests/RemoteCoverageTests.swift`
  - Tests unreachable, partial, complete, unsupported, and target-identity change cases.
- Create `Sources/ReclaimerCore/ReleaseTrustEvidence.swift`
  - Parses and classifies release manifest trust proof.
- Modify `Sources/ReclaimerCore/TrustReadiness.swift`
  - Uses typed release evidence instead of substring state.
- Modify `Sources/reclaimer/main.swift`
  - Adds release trust JSON/text proof command if no focused command file already owns it.
- Create `Tests/ReclaimerCoreTests/ReleaseTrustEvidenceTests.swift`
  - Tests manifest states and the `"not notarized"` false-positive class.
- Modify `README.md`, `FEATURES.md`, `PRIVACY.md`
  - Updates start-here journey, general cleanup framing, privacy boundaries, and release trust copy.
- Create `docs/GETTING_STARTED.md`
  - First-run guide for normal Mac users and developer users.
- Create `docs/SUPPORT_DIAGNOSTICS.md`
  - Redacted diagnostics command guide and report contents.
- Create `SECURITY.md`
  - Local-first security model and vulnerability reporting.
- Create `.github/ISSUE_TEMPLATE/bug_report.yml`
  - Crash, scan coverage, and broken workflow report form.
- Create `.github/ISSUE_TEMPLATE/unsafe_classification.yml`
  - Safety classification report form.
- Create `.github/ISSUE_TEMPLATE/remote_target.yml`
  - Remote target evidence report form.
- Create `.github/ISSUE_TEMPLATE/feature_request.yml`
  - General feature request form.

## Task 1: Guided Workflow Core

**Files:**
- Create: `Sources/ReclaimerCore/GuidedWorkflow.swift`
- Create: `Tests/ReclaimerCoreTests/GuidedWorkflowTests.swift`

**Interfaces:**
- Consumes: `DiskStatusSnapshot`, `PermissionAdvisorReport`, `ReclaimPlan`, `ExecutionReceipt`, `TrustReadinessReport`, `Finding`, `ReviewNextAction`.
- Produces:

```swift
public enum GuidedWorkflowStep: String, Codable, CaseIterable, Hashable, Sendable {
    case reviewPermissions
    case scan
    case reviewFindings
    case createPlan
    case dryRun
    case reclaimOrExport
    case recovery
}

public enum GuidedWorkflowActionKind: String, Codable, Hashable, Sendable {
    case openPermissions
    case runScan
    case openReviewQueues
    case createSafePlan
    case runDryRun
    case reclaimSafely
    case exportReport
    case openRecovery
}

public struct GuidedWorkflowAction: Codable, Hashable, Sendable {
    public let kind: GuidedWorkflowActionKind
    public let title: String
    public let reason: String
    public let estimatedBytes: Int64
    public let isDestructive: Bool
}

public struct GuidedWorkflowReport: Codable, Hashable, Sendable {
    public let currentStep: GuidedWorkflowStep
    public let primaryAction: GuidedWorkflowAction
    public let secondaryActions: [GuidedWorkflowAction]
    public let safetyTotals: [ReviewNextAction: Int64]
    public let explanation: String
}

public struct GuidedWorkflowInput: Sendable {
    public let diskStatus: DiskStatusSnapshot
    public let permissionSummary: PermissionAdvisorReport
    public let findings: [Finding]
    public let latestPlan: ReclaimPlan?
    public let latestReceipt: ExecutionReceipt?
    public let trustReadiness: TrustReadinessReport?
}

public enum GuidedWorkflowBuilder {
    public static func build(input: GuidedWorkflowInput) -> GuidedWorkflowReport
}
```

- [ ] **Step 1: Write the permission-degraded failing test**

```swift
import XCTest
@testable import ReclaimerCore

final class GuidedWorkflowTests: XCTestCase {
    func testPermissionDegradedSelectsPermissionReview() throws {
        let input = GuidedWorkflowFixtures.input(
            permissionCoverage: .degraded,
            findings: [],
            latestPlan: nil,
            latestReceipt: nil
        )

        let report = GuidedWorkflowBuilder.build(input: input)

        XCTAssertEqual(report.currentStep, .reviewPermissions)
        XCTAssertEqual(report.primaryAction.kind, .openPermissions)
        XCTAssertFalse(report.primaryAction.isDestructive)
        XCTAssertTrue(report.explanation.localizedCaseInsensitiveContains("coverage"))
    }
}
```

- [ ] **Step 2: Add fixture helpers in the same test file**

```swift
private enum GuidedWorkflowFixtures {
    static func input(
        permissionCoverage: PermissionCoverageLevel,
        findings: [Finding],
        latestPlan: ReclaimPlan?,
        latestReceipt: ExecutionReceipt?
    ) -> GuidedWorkflowInput {
        GuidedWorkflowInput(
            diskStatus: DiskStatusSnapshot(
                path: "/System/Volumes/Data",
                totalBytes: 500_000_000_000,
                freeBytes: 100_000_000_000,
                importantFreeBytes: 100_000_000_000,
                availableBytes: 100_000_000_000,
                pressure: .healthy,
                notes: []
            ),
            permissionSummary: PermissionAdvisorReport(
                coverageLevel: permissionCoverage,
                readableCount: 19,
                deniedCount: permissionCoverage == .complete ? 0 : 8,
                missingCount: 0,
                unknownCount: 0,
                totalCount: 27,
                readableFraction: 19.0 / 27.0,
                scopeSummaries: [],
                recommendedActions: [],
                nonClaims: []
            ),
            findings: findings,
            latestPlan: latestPlan,
            latestReceipt: latestReceipt,
            trustReadiness: nil
        )
    }

    static func finding(nextAction: ReviewNextAction, allocatedSize: Int64) -> Finding {
        let safetyClass: SafetyClass = nextAction == .safeMaintenance ? .autoSafe : .preserveByDefault
        let actionKind: ActionKind = nextAction == .safeMaintenance ? .trash : .reportOnly
        let match = RuleMatch(
            ruleID: "fixture.\(nextAction.rawValue)",
            title: nextAction.label,
            category: nextAction.label,
            safetyClass: safetyClass,
            actionKind: actionKind,
            evidence: ["Fixture evidence"],
            conditions: [],
            conditionGates: [],
            recovery: nil
        )
        return Finding(
            scopeName: "Fixture",
            path: "/tmp/ryddi-fixture-\(nextAction.rawValue)",
            displayName: nextAction.label,
            logicalSize: allocatedSize,
            allocatedSize: allocatedSize,
            isDirectory: true,
            safetyClass: safetyClass,
            actionKind: actionKind,
            ruleMatches: [match],
            evidence: [Evidence(kind: "fixture", message: "Fixture evidence")]
        )
    }

    static func plan(expectedReclaim: Int64) -> ReclaimPlan {
        let finding = finding(nextAction: .safeMaintenance, allocatedSize: expectedReclaim)
        let item = ReclaimPlanItem(
            finding: finding,
            selected: true,
            proposedAction: .trash,
            conditions: [],
            estimatedImmediateReclaim: expectedReclaim
        )
        return ReclaimPlan(mode: PlanMode.autoSafeOnly.rawValue, items: [item], dryRunSummary: [])
    }
}
```

- [ ] **Step 3: Run the focused test and confirm the missing symbols fail**

Run: `swift test --scratch-path "$PWD/.build" --filter GuidedWorkflowTests`

Expected: FAIL with missing `GuidedWorkflowInput` or `GuidedWorkflowBuilder`.

- [ ] **Step 4: Implement the workflow types and permission-first builder branch**

```swift
import Foundation

public enum GuidedWorkflowStep: String, Codable, CaseIterable, Hashable, Sendable {
    case reviewPermissions
    case scan
    case reviewFindings
    case createPlan
    case dryRun
    case reclaimOrExport
    case recovery
}

public enum GuidedWorkflowActionKind: String, Codable, Hashable, Sendable {
    case openPermissions
    case runScan
    case openReviewQueues
    case createSafePlan
    case runDryRun
    case reclaimSafely
    case exportReport
    case openRecovery
}

public struct GuidedWorkflowAction: Codable, Hashable, Sendable {
    public let kind: GuidedWorkflowActionKind
    public let title: String
    public let reason: String
    public let estimatedBytes: Int64
    public let isDestructive: Bool

    public init(kind: GuidedWorkflowActionKind, title: String, reason: String, estimatedBytes: Int64 = 0, isDestructive: Bool = false) {
        self.kind = kind
        self.title = title
        self.reason = reason
        self.estimatedBytes = estimatedBytes
        self.isDestructive = isDestructive
    }
}

public struct GuidedWorkflowReport: Codable, Hashable, Sendable {
    public let currentStep: GuidedWorkflowStep
    public let primaryAction: GuidedWorkflowAction
    public let secondaryActions: [GuidedWorkflowAction]
    public let safetyTotals: [ReviewNextAction: Int64]
    public let explanation: String
}

public struct GuidedWorkflowInput: Sendable {
    public let diskStatus: DiskStatusSnapshot
    public let permissionSummary: PermissionAdvisorReport
    public let findings: [Finding]
    public let latestPlan: ReclaimPlan?
    public let latestReceipt: ExecutionReceipt?
    public let trustReadiness: TrustReadinessReport?
}

public enum GuidedWorkflowBuilder {
    public static func build(input: GuidedWorkflowInput) -> GuidedWorkflowReport {
        if input.permissionSummary.coverageLevel != .complete {
            return GuidedWorkflowReport(
                currentStep: .reviewPermissions,
                primaryAction: GuidedWorkflowAction(
                    kind: .openPermissions,
                    title: "Review Access",
                    reason: "\(input.permissionSummary.readableCount) of \(input.permissionSummary.totalCount) scopes are readable."
                ),
                secondaryActions: [
                    GuidedWorkflowAction(kind: .runScan, title: "Scan Anyway", reason: "Use currently readable locations.")
                ],
                safetyTotals: safetyTotals(for: input.findings),
                explanation: "Scan coverage is degraded, so Ryddi should review access before promising cleanup results."
            )
        }

        return GuidedWorkflowReport(
            currentStep: .scan,
            primaryAction: GuidedWorkflowAction(kind: .runScan, title: "Scan", reason: "No current scan evidence is available."),
            secondaryActions: [],
            safetyTotals: safetyTotals(for: input.findings),
            explanation: "Run a scan to build current local evidence."
        )
    }

    private static func safetyTotals(for findings: [Finding]) -> [ReviewNextAction: Int64] {
        findings.reduce(into: [:]) { totals, finding in
            totals[finding.reviewNextAction, default: 0] += finding.allocatedSize
        }
    }
}
```

- [ ] **Step 5: Add tests for scan, review, plan, dry-run, and reclaim/export states**

```swift
func testFindingsWithoutPlanSelectsReviewQueues() throws {
    let finding = GuidedWorkflowFixtures.finding(nextAction: .safeMaintenance, allocatedSize: 1_000_000_000)
    let input = GuidedWorkflowFixtures.input(permissionCoverage: .complete, findings: [finding], latestPlan: nil, latestReceipt: nil)

    let report = GuidedWorkflowBuilder.build(input: input)

    XCTAssertEqual(report.currentStep, .reviewFindings)
    XCTAssertEqual(report.primaryAction.kind, .openReviewQueues)
    XCTAssertEqual(report.safetyTotals[.safeMaintenance], 1_000_000_000)
}

func testPlanWithoutReceiptSelectsDryRun() throws {
    let input = GuidedWorkflowFixtures.input(
        permissionCoverage: .complete,
        findings: [GuidedWorkflowFixtures.finding(nextAction: .safeMaintenance, allocatedSize: 1_000_000_000)],
        latestPlan: GuidedWorkflowFixtures.plan(expectedReclaim: 1_000_000_000),
        latestReceipt: nil
    )

    let report = GuidedWorkflowBuilder.build(input: input)

    XCTAssertEqual(report.currentStep, .dryRun)
    XCTAssertEqual(report.primaryAction.kind, .runDryRun)
    XCTAssertFalse(report.primaryAction.isDestructive)
}
```

- [ ] **Step 6: Extend builder branches for all tested states**

```swift
if input.findings.isEmpty {
    return GuidedWorkflowReport(
        currentStep: .scan,
        primaryAction: GuidedWorkflowAction(kind: .runScan, title: "Scan", reason: "No current scan evidence is available."),
        secondaryActions: [],
        safetyTotals: safetyTotals(for: input.findings),
        explanation: "Run a scan to build current local evidence."
    )
}

if input.latestPlan == nil {
    let safeBytes = safetyTotals(for: input.findings)[.safeMaintenance, default: 0]
    let actionKind: GuidedWorkflowActionKind = safeBytes > 0 ? .createSafePlan : .openReviewQueues
    return GuidedWorkflowReport(
        currentStep: safeBytes > 0 ? .createPlan : .reviewFindings,
        primaryAction: GuidedWorkflowAction(
            kind: actionKind,
            title: safeBytes > 0 ? "Create Safe Plan" : "Review Findings",
            reason: safeBytes > 0 ? "Auto-safe evidence is available." : "Findings need human review.",
            estimatedBytes: safeBytes
        ),
        secondaryActions: [GuidedWorkflowAction(kind: .openReviewQueues, title: "Review Queues", reason: "Inspect protected and conditional items.")],
        safetyTotals: safetyTotals(for: input.findings),
        explanation: safeBytes > 0 ? "Ryddi can build a dry-run plan from safe maintenance findings." : "Ryddi found storage, but it needs review before planning."
    )
}

if input.latestReceipt == nil {
    return GuidedWorkflowReport(
        currentStep: .dryRun,
        primaryAction: GuidedWorkflowAction(kind: .runDryRun, title: "Dry Run", reason: "Preview the current plan before cleanup.", estimatedBytes: input.latestPlan?.expectedImmediateReclaim ?? 0),
        secondaryActions: [GuidedWorkflowAction(kind: .exportReport, title: "Export Report", reason: "Share evidence without changing files.")],
        safetyTotals: safetyTotals(for: input.findings),
        explanation: "A plan exists. Dry-run it before any reclaim action."
    )
}
```

- [ ] **Step 7: Run the focused workflow tests**

Run: `swift test --scratch-path "$PWD/.build" --filter GuidedWorkflowTests`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReclaimerCore/GuidedWorkflow.swift Tests/ReclaimerCoreTests/GuidedWorkflowTests.swift
git commit -m "feat: add guided workflow state"
```

## Task 2: SwiftUI Summary Proof Ladder

**Files:**
- Create: `Sources/MacDiskReclaimerApp/GuidedSummaryView.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`

**Interfaces:**
- Consumes: `GuidedWorkflowReport`, current app actions for scan, plan, dry-run, export, reclaim, permissions, and recovery.
- Produces:

```swift
struct GuidedSummaryView: View {
    let report: GuidedWorkflowReport
    let diskStatus: DiskStatusSnapshot
    let topFindings: [Finding]
    let onAction: (GuidedWorkflowActionKind) -> Void
}
```

- [ ] **Step 1: Create a SwiftUI preview host with narrow-width coverage**

```swift
#Preview("Guided Summary Narrow") {
    GuidedSummaryView(
        report: GuidedSummaryPreviewData.report,
        diskStatus: GuidedSummaryPreviewData.diskStatus,
        topFindings: GuidedSummaryPreviewData.findings,
        onAction: { _ in }
    )
    .frame(width: 520, height: 720)
}
```

- [ ] **Step 2: Implement adaptive layout using a scroll view and view-that-fits**

```swift
import SwiftUI
import ReclaimerCore

struct GuidedSummaryView: View {
    let report: GuidedWorkflowReport
    let diskStatus: DiskStatusSnapshot
    let topFindings: [Finding]
    let onAction: (GuidedWorkflowActionKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                diskHeader
                primaryActionBand
                safetyTotals
                largestDecisions
            }
            .padding(20)
            .frame(maxWidth: 1260, alignment: .leading)
        }
    }

    private var diskHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Disk Status").font(.headline)
            Text(ByteCountFormatter.string(fromByteCount: diskStatus.displayFreeBytes ?? 0, countStyle: .file) + " free")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.75)
                .lineLimit(2)
            Text(diskStatus.path).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 3: Add primary and secondary action buttons with stable sizing**

```swift
private var primaryActionBand: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(report.explanation)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons }
            VStack(alignment: .leading, spacing: 10) { actionButtons }
        }
    }
}

@ViewBuilder
private var actionButtons: some View {
    Button {
        onAction(report.primaryAction.kind)
    } label: {
        Label(report.primaryAction.title, systemImage: iconName(for: report.primaryAction.kind))
            .frame(minWidth: 150)
    }
    .buttonStyle(.borderedProminent)

    ForEach(report.secondaryActions, id: \.self) { action in
        Button {
            onAction(action.kind)
        } label: {
            Label(action.title, systemImage: iconName(for: action.kind))
                .frame(minWidth: 132)
        }
        .buttonStyle(.bordered)
    }
}
```

- [ ] **Step 4: Wire `MacDiskReclaimerApp.swift` Summary to `GuidedWorkflowBuilder`**

```swift
private var guidedWorkflowReport: GuidedWorkflowReport {
    GuidedWorkflowBuilder.build(
        input: GuidedWorkflowInput(
            diskStatus: diskStatus,
            permissionSummary: permissionReport,
            findings: currentFindings,
            latestPlan: currentPlan,
            latestReceipt: latestReceipt,
            trustReadiness: trustReport
        )
    )
}
```

- [ ] **Step 5: Route action kinds to existing app methods**

```swift
private func performGuidedAction(_ kind: GuidedWorkflowActionKind) {
    switch kind {
    case .openPermissions:
        selectedSidebarItem = .permissions
    case .runScan:
        runScan()
    case .openReviewQueues:
        selectedSidebarItem = .reviewQueues
    case .createSafePlan:
        buildPlan()
    case .runDryRun:
        runDryRun()
    case .reclaimSafely:
        runReclaim()
    case .exportReport:
        exportReport()
    case .openRecovery:
        selectedSidebarItem = .recoveryCenter
    }
}
```

- [ ] **Step 6: Run app build**

Run: `swift build --scratch-path "$PWD/.build"`

Expected: PASS.

- [ ] **Step 7: Manually smoke small and normal windows**

Run: `open .build/debug/Ryddi.app`

Expected: Summary shows one primary action, content scrolls instead of overlapping, and the sidebar remains usable at narrow width.

- [ ] **Step 8: Commit**

```bash
git add Sources/MacDiskReclaimerApp/GuidedSummaryView.swift Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift
git commit -m "feat: guide summary next action"
```

## Task 3: Machine-Verifiable Cleanup Gates

**Files:**
- Modify: `Sources/ReclaimerCore/Models.swift`
- Modify: `Sources/ReclaimerCore/Rules.swift`
- Modify: `Sources/ReclaimerCore/PlanBuilder.swift`
- Modify: `Sources/ReclaimerCore/Resources/rules.json`
- Create: `Tests/ReclaimerCoreTests/PlanGateEvidenceTests.swift`

**Interfaces:**
- Consumes: existing `PlanConditionKind`, `PlanCondition`, `ReclaimerRule`, `RuleMatch`, `Finding`.
- Produces:

```swift
public struct RuleGateEvidence: Codable, Hashable, Sendable {
    public let minimumAgeDays: Int?
    public let retentionPolicy: String?
    public let retentionDays: Int?
    public let nativeToolName: String?
    public let nativePreviewAvailable: Bool
}

public struct RuleMatch: Codable, Hashable, Sendable {
    public let ruleID: String
    public let title: String
    public let category: String
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let evidence: [String]
    public let conditions: [String]
    public let conditionGates: [PlanConditionKind]
    public let gateEvidence: RuleGateEvidence
    public let recovery: String?
}
```

- [ ] **Step 1: Write age gate fail-closed test**

```swift
import XCTest
@testable import ReclaimerCore

final class PlanGateEvidenceTests: XCTestCase {
    func testMinimumAgeGateWithoutNumericEvidenceDoesNotAutoSelect() throws {
        let finding = PlanGateFixtures.finding(
            conditionGates: [.minimumAgeRequired],
            gateEvidence: RuleGateEvidence(
                minimumAgeDays: nil,
                retentionPolicy: nil,
                retentionDays: nil,
                nativeToolName: nil,
                nativePreviewAvailable: false
            ),
            modificationAgeDays: 90
        )

        let plan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [finding], mode: .autoSafeOnly)

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertFalse(plan.items[0].selected)
        XCTAssertTrue(plan.items[0].conditions.contains { $0.kind == .minimumAgeRequired && !$0.isSatisfied })
    }
}

private struct AlwaysClearOpenFileChecker: OpenFileChecking {
    func status(for url: URL) -> OpenFileStatus {
        OpenFileStatus(isOpen: false, checkedRecursively: true, checkedPath: url.path)
    }
}

private enum PlanGateFixtures {
    static func finding(
        conditionGates: [PlanConditionKind],
        gateEvidence: RuleGateEvidence,
        modificationAgeDays: Int
    ) -> Finding {
        let modifiedAt = Calendar.current.date(byAdding: .day, value: -modificationAgeDays, to: Date())
        let match = RuleMatch(
            ruleID: "fixture.age-gate",
            title: "Fixture cache",
            category: "Developer cache",
            safetyClass: .autoSafe,
            actionKind: .trash,
            evidence: ["Fixture cache evidence"],
            conditions: [],
            conditionGates: conditionGates,
            gateEvidence: gateEvidence,
            recovery: nil
        )
        return Finding(
            scopeName: "Fixture",
            path: "/tmp/ryddi-fixture-cache",
            displayName: "ryddi-fixture-cache",
            logicalSize: 1_000_000,
            allocatedSize: 1_000_000,
            isDirectory: true,
            modificationDate: modifiedAt,
            safetyClass: .autoSafe,
            actionKind: .trash,
            ruleMatches: [match],
            evidence: [Evidence(kind: "fixture", message: "Fixture cache evidence")]
        )
    }
}
```

- [ ] **Step 2: Write age gate satisfied test**

```swift
func testMinimumAgeGateWithEvidenceSelectsOldEnoughCache() throws {
    let finding = PlanGateFixtures.finding(
        conditionGates: [.minimumAgeRequired, .openFileClear, .notSymbolicLink],
        gateEvidence: RuleGateEvidence(
            minimumAgeDays: 30,
            retentionPolicy: "cache-30-day",
            retentionDays: 30,
            nativeToolName: nil,
            nativePreviewAvailable: false
        ),
        modificationAgeDays: 45
    )

    let plan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [finding], mode: .autoSafeOnly)

    XCTAssertEqual(plan.items.count, 1)
    XCTAssertEqual(plan.items.first?.selected, true)
    XCTAssertEqual(plan.items.first?.conditions.map(\.kind).contains(.minimumAgeRequired), true)
}
```

- [ ] **Step 3: Add gate evidence model and backward-compatible decoding**

```swift
public struct RuleGateEvidence: Codable, Hashable, Sendable {
    public let minimumAgeDays: Int?
    public let retentionPolicy: String?
    public let retentionDays: Int?
    public let nativeToolName: String?
    public let nativePreviewAvailable: Bool

    public init(
        minimumAgeDays: Int? = nil,
        retentionPolicy: String? = nil,
        retentionDays: Int? = nil,
        nativeToolName: String? = nil,
        nativePreviewAvailable: Bool = false
    ) {
        self.minimumAgeDays = minimumAgeDays
        self.retentionPolicy = retentionPolicy
        self.retentionDays = retentionDays
        self.nativeToolName = nativeToolName
        self.nativePreviewAvailable = nativePreviewAvailable
    }
}
```

- [ ] **Step 4: Extend rule decoding**

```swift
public struct ReclaimerRule: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let priority: Int
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let match: RuleMatchSpec
    public let evidence: [String]
    public let conditions: [String]
    public let conditionGates: [PlanConditionKind]
    public let gateEvidence: RuleGateEvidence
    public let recovery: String?
}

private enum CodingKeys: String, CodingKey {
    case id
    case title
    case category
    case priority
    case safetyClass
    case actionKind
    case match
    case evidence
    case conditions
    case conditionGates
    case gateEvidence
    case recovery
}

public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    category = try container.decode(String.self, forKey: .category)
    priority = try container.decode(Int.self, forKey: .priority)
    safetyClass = try container.decode(SafetyClass.self, forKey: .safetyClass)
    actionKind = try container.decode(ActionKind.self, forKey: .actionKind)
    match = try container.decode(RuleMatchSpec.self, forKey: .match)
    evidence = try container.decode([String].self, forKey: .evidence)
    conditions = try container.decodeIfPresent([String].self, forKey: .conditions) ?? []
    conditionGates = try container.decodeIfPresent([PlanConditionKind].self, forKey: .conditionGates) ?? []
    gateEvidence = try container.decodeIfPresent(RuleGateEvidence.self, forKey: .gateEvidence) ?? RuleGateEvidence()
    recovery = try container.decodeIfPresent(String.self, forKey: .recovery)
}
```

- [ ] **Step 5: Update `PlanBuilder.isGateSatisfied`**

```swift
case .minimumAgeRequired:
    guard let minimumAgeDays = finding.ruleMatches.first?.gateEvidence.minimumAgeDays else {
        return false
    }
    guard let modifiedAt = finding.modificationDate else {
        return false
    }
    let age = Date().timeIntervalSince(modifiedAt)
    return age >= Double(minimumAgeDays) * 86_400
case .nativeToolRequired:
    return finding.ruleMatches.first?.gateEvidence.nativePreviewAvailable == true
```

- [ ] **Step 6: Update selected bundled rules**

```json
{
  "id": "npm-cache-stale",
  "safetyClass": "autoSafe",
  "actionKind": "nativeToolCommand",
  "conditionGates": ["openFileClear", "minimumAgeRequired", "nativeToolRequired", "finalClassificationRequired"],
  "gateEvidence": {
    "minimumAgeDays": 30,
    "retentionPolicy": "package-cache-30-day",
    "retentionDays": 30,
    "nativeToolName": "npm",
    "nativePreviewAvailable": true
  }
}
```

- [ ] **Step 7: Run focused and full rule tests**

Run: `swift test --scratch-path "$PWD/.build" --filter PlanGateEvidence`

Expected: PASS.

Run: `swift test --scratch-path "$PWD/.build" --filter PlanBuilder`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReclaimerCore/Models.swift Sources/ReclaimerCore/Rules.swift Sources/ReclaimerCore/PlanBuilder.swift Sources/ReclaimerCore/Resources/rules.json Tests/ReclaimerCoreTests/PlanGateEvidenceTests.swift
git commit -m "feat: require typed cleanup gate evidence"
```

## Task 4: Package Cache Native Reclaim Lane

**Files:**
- Create: `Sources/ReclaimerCore/PackageReclaimLane.swift`
- Create: `Tests/ReclaimerCoreTests/PackageReclaimLaneTests.swift`
- Modify: `Sources/reclaimer/main.swift` or existing focused package command file if present
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`

**Interfaces:**
- Consumes: `PackageCacheReviewReport`, `PackageCacheSummary`, `NativeToolGuidance`, `NativeToolReport`.
- Produces:

```swift
public struct PackageReclaimLaneReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let managerReports: [PackageReclaimManagerReport]
    public let totalPreviewBytes: Int64
    public let nonClaims: [String]
}

public struct PackageReclaimManagerReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let managerName: String
    public let cacheBytes: Int64
    public let previewCommand: [String]
    public let cleanupCommand: [String]
    public let previewOnly: Bool
    public let explanation: String
}

public enum PackageReclaimLaneBuilder {
    public static func build(from report: PackageCacheReviewReport) -> PackageReclaimLaneReport
}
```

- [ ] **Step 1: Write package lane preview-only test**

```swift
import XCTest
@testable import ReclaimerCore

final class PackageReclaimLaneTests: XCTestCase {
    func testNpmCacheProducesPreviewOnlyNativeLane() throws {
        let report = PackageCacheFixtures.report(manager: "npm", bytes: 2_000_000_000)

        let lane = PackageReclaimLaneBuilder.build(from: report)

        XCTAssertEqual(lane.totalPreviewBytes, 2_000_000_000)
        XCTAssertEqual(lane.managerReports.first?.managerName, "npm")
        XCTAssertEqual(lane.managerReports.first?.previewOnly, true)
        XCTAssertTrue(lane.nonClaims.contains("No package cache cleanup was executed."))
    }
}
```

- [ ] **Step 2: Write unsupported manager test**

```swift
func testUnsupportedManagerStaysManualGuidance() throws {
    let report = PackageCacheFixtures.report(manager: "unknownpkg", bytes: 500_000_000)

    let lane = PackageReclaimLaneBuilder.build(from: report)

    XCTAssertEqual(lane.totalPreviewBytes, 0)
    XCTAssertTrue(lane.managerReports.allSatisfy(\.previewOnly))
    XCTAssertTrue(lane.managerReports.first?.cleanupCommand.isEmpty == true)
}

private enum PackageCacheFixtures {
    static func report(manager: String, bytes: Int64) -> PackageCacheReviewReport {
        PackageCacheReviewReport(
            totalLogicalSize: bytes,
            totalAllocatedSize: bytes,
            itemCount: 1,
            displayedItemCount: 1,
            candidateBytes: bytes,
            rootSummaries: [],
            managerSummaries: [PackageCacheSummary(name: manager, itemCount: 1, allocatedSize: bytes)],
            kindSummaries: [],
            largestItems: [],
            protectedConfigRoots: [],
            guidance: ["Fixture guidance"],
            nonClaims: ["Fixture report did not clean anything."]
        )
    }
}
```

- [ ] **Step 3: Implement package lane builder**

```swift
import Foundation

public struct PackageReclaimLaneReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let managerReports: [PackageReclaimManagerReport]
    public let totalPreviewBytes: Int64
    public let nonClaims: [String]
}

public struct PackageReclaimManagerReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let managerName: String
    public let cacheBytes: Int64
    public let previewCommand: [String]
    public let cleanupCommand: [String]
    public let previewOnly: Bool
    public let explanation: String
}

public enum PackageReclaimLaneBuilder {
    public static func build(from report: PackageCacheReviewReport) -> PackageReclaimLaneReport {
        let managers = report.managerSummaries.map { summary in
            managerReport(for: summary)
        }
        return PackageReclaimLaneReport(
            generatedAt: Date(),
            managerReports: managers,
            totalPreviewBytes: managers.filter { !$0.previewCommand.isEmpty }.reduce(0) { $0 + $1.cacheBytes },
            nonClaims: [
                "No package cache cleanup was executed.",
                "Native tools may report different reclaim after their own accounting.",
                "Commands must be reviewed before cleanup."
            ]
        )
    }

    private static func managerReport(for summary: PackageCacheSummary) -> PackageReclaimManagerReport {
        let commands = commands(for: summary.name)
        return PackageReclaimManagerReport(
            id: summary.name,
            managerName: summary.name,
            cacheBytes: summary.allocatedSize,
            previewCommand: commands.preview,
            cleanupCommand: commands.cleanup,
            previewOnly: true,
            explanation: commands.preview.isEmpty ? "Manual review required." : "Native preview available."
        )
    }
}
```

- [ ] **Step 4: Add allowlisted preview commands**

```swift
private static func commands(for manager: String) -> (preview: [String], cleanup: [String]) {
    switch manager.lowercased() {
    case "homebrew", "brew":
        return (["brew", "cleanup", "-n"], ["brew", "cleanup"])
    case "npm":
        return (["npm", "cache", "verify"], ["npm", "cache", "clean", "--force"])
    case "pnpm":
        return (["pnpm", "store", "status"], ["pnpm", "store", "prune"])
    case "yarn":
        return (["yarn", "cache", "dir"], ["yarn", "cache", "clean"])
    case "cargo":
        return (["cargo", "cache", "--help"], ["cargo", "cache", "-a"])
    default:
        return ([], [])
    }
}
```

- [ ] **Step 5: Expose CLI proof command**

```swift
case "package-lane":
    let report = try PackageCacheReviewScanner().scan()
    let lane = PackageReclaimLaneBuilder.build(from: report)
    print(try JSONEncoder.ryddiPretty.encodeToString(lane))
```

- [ ] **Step 6: Add Summary quick lane card**

```swift
PackageLaneCard(report: packageReclaimLaneReport) {
    selectedSidebarItem = .packageCaches
}
```

- [ ] **Step 7: Run focused tests and build**

Run: `swift test --scratch-path "$PWD/.build" --filter PackageReclaimLane`

Expected: PASS.

Run: `swift build --scratch-path "$PWD/.build"`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReclaimerCore/PackageReclaimLane.swift Tests/ReclaimerCoreTests/PackageReclaimLaneTests.swift Sources/reclaimer/main.swift Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift
git commit -m "feat: add package cache preview lane"
```

## Task 5: AI-Agent Retention Plan Lane

**Files:**
- Create: `Sources/ReclaimerCore/AgentRetentionPlan.swift`
- Create: `Tests/ReclaimerCoreTests/AgentRetentionPlanTests.swift`
- Modify: `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`

**Interfaces:**
- Consumes: `AgentRetentionReport`, `AgentRetentionRecommendation`, `Finding`, `ReclaimPlan`.
- Produces:

```swift
public struct AgentRetentionPlanPreview: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let selectedBytes: Int64
    public let protectedBytes: Int64
    public let reviewBytes: Int64
    public let plan: ReclaimPlan
    public let protectedReasons: [String]
    public let nonClaims: [String]
}

public enum AgentRetentionPlanBuilder {
    public static func build(report: AgentRetentionReport, matchingFindings: [Finding]) -> AgentRetentionPlanPreview
}
```

- [ ] **Step 1: Write protected Codex state test**

```swift
import XCTest
@testable import ReclaimerCore

final class AgentRetentionPlanTests: XCTestCase {
    func testCodexSessionsRemainProtectedByDefault() throws {
        let report = AgentRetentionFixtures.report(category: "sessions", bytes: 8_000_000_000)
        let findings = [AgentRetentionFixtures.finding(pathSuffix: "sessions", safetyClass: .preserveByDefault)]

        let preview = AgentRetentionPlanBuilder.build(report: report, matchingFindings: findings)

        XCTAssertTrue(preview.plan.items.isEmpty)
        XCTAssertEqual(preview.protectedBytes, 8_000_000_000)
        XCTAssertTrue(preview.protectedReasons.contains { $0.localizedCaseInsensitiveContains("sessions") })
    }
}
```

- [ ] **Step 2: Write eligible cache/log retention test**

```swift
func testEligibleAgentCacheBuildsTrashPreviewPlan() throws {
    let report = AgentRetentionFixtures.report(category: "logs", bytes: 750_000_000)
    let finding = AgentRetentionFixtures.finding(
        pathSuffix: "logs",
        safetyClass: .autoSafe,
        actionKind: .trash,
        conditionGates: [.openFileClear, .minimumAgeRequired, .finalClassificationRequired],
        minimumAgeDays: 30,
        modificationAgeDays: 60
    )

    let preview = AgentRetentionPlanBuilder.build(report: report, matchingFindings: [finding])

    XCTAssertEqual(preview.plan.items.count, 1)
    XCTAssertEqual(preview.selectedBytes, 750_000_000)
    XCTAssertTrue(preview.nonClaims.contains("No AI-agent storage cleanup was executed."))
}

private enum AgentRetentionFixtures {
    static func report(category: String, bytes: Int64) -> AgentRetentionReport {
        let cleanup = category == "logs"
        let recommendation = AgentRetentionRecommendation(
            id: "fixture-\(category)",
            owner: "Codex",
            bucket: cleanup ? .reclaimableCache : .valuableHistory,
            path: "/Users/reidar/.codex/\(category)",
            displayName: category,
            allocatedSize: bytes,
            ageDays: cleanup ? 60 : 1,
            recommendation: cleanup ? .cleanupPlan : .protect,
            actionKind: cleanup ? .trash : .reportOnly,
            eligibleForCleanupPlan: cleanup,
            reason: cleanup ? "Fixture stale cache/log data." : "Fixture protected history.",
            nextSteps: []
        )
        return AgentRetentionReport(
            profile: .balanced,
            profileSummary: AgentRetentionProfile.balanced.summary,
            reviewedItemCount: 1,
            totalBytes: bytes,
            cleanupCandidateBytes: cleanup ? bytes : 0,
            compressionCandidateBytes: 0,
            protectedBytes: cleanup ? 0 : bytes,
            summaries: [],
            recommendations: [recommendation],
            nonClaims: []
        )
    }

    static func finding(
        pathSuffix: String,
        safetyClass: SafetyClass,
        actionKind: ActionKind = .reportOnly,
        conditionGates: [PlanConditionKind] = [],
        minimumAgeDays: Int? = nil,
        modificationAgeDays: Int = 0
    ) -> Finding {
        let modifiedAt = Calendar.current.date(byAdding: .day, value: -modificationAgeDays, to: Date())
        let match = RuleMatch(
            ruleID: "fixture.agent.\(pathSuffix)",
            title: "Agent fixture",
            category: "Codex",
            safetyClass: safetyClass,
            actionKind: actionKind,
            evidence: ["Fixture agent evidence"],
            conditions: [],
            conditionGates: conditionGates,
            gateEvidence: RuleGateEvidence(minimumAgeDays: minimumAgeDays),
            recovery: nil
        )
        return Finding(
            scopeName: "AI Agent Storage",
            path: "/Users/reidar/.codex/\(pathSuffix)",
            displayName: pathSuffix,
            logicalSize: 750_000_000,
            allocatedSize: 750_000_000,
            isDirectory: true,
            modificationDate: modifiedAt,
            ownerHint: "Codex",
            safetyClass: safetyClass,
            actionKind: actionKind,
            ruleMatches: [match],
            evidence: [Evidence(kind: "fixture", message: "Fixture agent evidence")]
        )
    }
}
```

- [ ] **Step 3: Implement preview builder using existing plan builder**

```swift
import Foundation

public struct AgentRetentionPlanPreview: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let selectedBytes: Int64
    public let protectedBytes: Int64
    public let reviewBytes: Int64
    public let plan: ReclaimPlan
    public let protectedReasons: [String]
    public let nonClaims: [String]
}

public enum AgentRetentionPlanBuilder {
    public static func build(report: AgentRetentionReport, matchingFindings: [Finding]) -> AgentRetentionPlanPreview {
        let eligible = matchingFindings.filter { finding in
            finding.safetyClass == .autoSafe && (finding.ownerHint ?? "").localizedCaseInsensitiveContains("codex")
        }
        let plan = PlanBuilder().buildPlan(from: eligible, mode: .autoSafeOnly)
        let selectedBytes = plan.items.filter(\.selected).reduce(0) { $0 + $1.estimatedImmediateReclaim }
        let protectedBytes = report.recommendations
            .filter { !$0.eligibleForCleanupPlan }
            .reduce(0) { $0 + $1.allocatedSize }

        return AgentRetentionPlanPreview(
            generatedAt: Date(),
            selectedBytes: selectedBytes,
            protectedBytes: protectedBytes,
            reviewBytes: max(0, report.totalBytes - selectedBytes - protectedBytes),
            plan: plan,
            protectedReasons: report.recommendations.filter { !$0.eligibleForCleanupPlan }.map(\.reason),
            nonClaims: [
                "No AI-agent storage cleanup was executed.",
                "Sessions, memories, config, auth, and state databases are protected by default.",
                "Execution rechecks classification, symlinks, age gates, and active file handles."
            ]
        )
    }
}
```

- [ ] **Step 4: Add app card and review lane**

```swift
AgentRetentionPreviewCard(preview: agentRetentionPreview) {
    selectedSidebarItem = .aiAgentStorage
}
```

- [ ] **Step 5: Run focused tests and build**

Run: `swift test --scratch-path "$PWD/.build" --filter AgentRetentionPlan`

Expected: PASS.

Run: `swift build --scratch-path "$PWD/.build"`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReclaimerCore/AgentRetentionPlan.swift Tests/ReclaimerCoreTests/AgentRetentionPlanTests.swift Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift
git commit -m "feat: preview ai agent retention plans"
```

## Task 6: Remote Coverage And Target Identity

**Files:**
- Modify: `Sources/ReclaimerCore/RemoteTarget.swift`
- Modify: `Sources/ReclaimerCore/RemoteScan.swift`
- Modify: `Sources/ReclaimerCore/RemoteReportExport.swift`
- Modify: `Sources/reclaimer/RemoteCommands.swift`
- Modify: `Sources/MacDiskReclaimerApp/RemoteTargetsView.swift` if present, otherwise `Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift`
- Create: `Tests/ReclaimerCoreTests/RemoteCoverageTests.swift`

**Interfaces:**
- Consumes: `RemoteCommandResult`, `RemoteProbeReport`, `RemoteScanReport`, `RemoteTargetReference`, `AuditStore`.
- Produces:

```swift
public enum RemoteScanCoverageLevel: String, Codable, Hashable, Sendable {
    case complete
    case partial
    case unreachable
    case unsupported
}

public struct RemoteScanCoverage: Codable, Hashable, Sendable {
    public let level: RemoteScanCoverageLevel
    public let successfulCommandIDs: [String]
    public let failedCommandIDs: [String]
    public let timedOutCommandIDs: [String]
    public let permissionDeniedCommandIDs: [String]
    public let explanation: String
}

public struct RemoteTargetContinuityWarning: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let field: String
    public let previousValue: String
    public let currentValue: String
    public let severity: String
}
```

- [ ] **Step 1: Write unreachable scan test**

```swift
import XCTest
@testable import ReclaimerCore

final class RemoteCoverageTests: XCTestCase {
    func testAllFailedCommandsCreateUnreachableCoverage() throws {
        let commands = [
            RemoteCoverageFixtures.command(id: "df-blocks", exitCode: 255, timedOut: false, stderr: ["ssh: Could not resolve hostname"])
        ]

        let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: nil)

        XCTAssertEqual(coverage.level, .unreachable)
        XCTAssertEqual(coverage.successfulCommandIDs, [])
        XCTAssertEqual(coverage.failedCommandIDs, ["df-blocks"])
        XCTAssertTrue(coverage.explanation.localizedCaseInsensitiveContains("unreachable"))
    }
}
```

- [ ] **Step 2: Write partial and complete coverage tests**

```swift
func testMixedCommandResultsCreatePartialCoverage() throws {
    let commands = [
        RemoteCoverageFixtures.command(id: "df-blocks", exitCode: 0, timedOut: false, stdout: ["Filesystem 1024-blocks Used Available Capacity Mounted on"]),
        RemoteCoverageFixtures.command(id: "docker-system-df", exitCode: 1, timedOut: false, stderr: ["permission denied"])
    ]

    let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: "Linux")

    XCTAssertEqual(coverage.level, .partial)
    XCTAssertEqual(coverage.successfulCommandIDs, ["df-blocks"])
    XCTAssertEqual(coverage.permissionDeniedCommandIDs, ["docker-system-df"])
}

func testSuccessfulCoreCommandsCreateCompleteCoverage() throws {
    let commands = [
        RemoteCoverageFixtures.command(id: "df-blocks", exitCode: 0, timedOut: false),
        RemoteCoverageFixtures.command(id: "df-inodes", exitCode: 0, timedOut: false),
        RemoteCoverageFixtures.command(id: "du-roots", exitCode: 0, timedOut: false)
    ]

    let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: "Linux")

    XCTAssertEqual(coverage.level, .complete)
}

private enum RemoteCoverageFixtures {
    static func command(
        id: String,
        exitCode: Int32?,
        timedOut: Bool,
        stdout: [String] = [],
        stderr: [String] = []
    ) -> RemoteCommandResult {
        RemoteCommandResult(
            commandID: id,
            displayCommand: id,
            exitCode: exitCode,
            timedOut: timedOut,
            stdoutPreview: stdout,
            stderrPreview: stderr,
            redactionApplied: true
        )
    }
}
```

- [ ] **Step 3: Add coverage types and backward-compatible scan decoding**

```swift
public struct RemoteScanReport: Codable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let preset: RemoteScanPreset
    public let target: RemoteTargetReference
    public let diskFilesystems: [RemoteFilesystemSummary]
    public let inodeFilesystems: [RemoteFilesystemSummary]
    public let findings: [RemoteStorageFinding]
    public let nativeGuidance: [RemoteNativeGuidance]
    public let commands: [RemoteCommandResult]
    public let coverage: RemoteScanCoverage
    public let continuityWarnings: [RemoteTargetContinuityWarning]
    public let nonClaims: [String]
}
```

- [ ] **Step 4: Implement `RemoteScanCoverageBuilder`**

```swift
public enum RemoteScanCoverageBuilder {
    public static func build(commands: [RemoteCommandResult], osSummary: String?) -> RemoteScanCoverage {
        let successful = commands.filter { $0.exitCode == 0 }.map(\.commandID)
        let timedOut = commands.filter(\.timedOut).map(\.commandID)
        let permissionDenied = commands
            .filter { result in
                result.stderrPreview.contains { $0.localizedCaseInsensitiveContains("permission denied") }
            }
            .map(\.commandID)
        let failed = commands.filter { $0.exitCode != 0 || $0.timedOut }.map(\.commandID)

        if successful.isEmpty {
            return RemoteScanCoverage(level: .unreachable, successfulCommandIDs: [], failedCommandIDs: failed, timedOutCommandIDs: timedOut, permissionDeniedCommandIDs: permissionDenied, explanation: "The target was unreachable or all evidence commands failed.")
        }

        if let osSummary, !osSummary.localizedCaseInsensitiveContains("linux") {
            return RemoteScanCoverage(level: .unsupported, successfulCommandIDs: successful, failedCommandIDs: failed, timedOutCommandIDs: timedOut, permissionDeniedCommandIDs: permissionDenied, explanation: "The target responded, but the selected preset is Linux VPS focused.")
        }

        if failed.isEmpty {
            return RemoteScanCoverage(level: .complete, successfulCommandIDs: successful, failedCommandIDs: [], timedOutCommandIDs: [], permissionDeniedCommandIDs: [], explanation: "Core evidence commands completed.")
        }

        return RemoteScanCoverage(level: .partial, successfulCommandIDs: successful, failedCommandIDs: failed, timedOutCommandIDs: timedOut, permissionDeniedCommandIDs: permissionDenied, explanation: "Some remote evidence commands failed, timed out, or lacked permission.")
    }
}
```

- [ ] **Step 5: Bind CLI saves and exports to coverage and target identity**

```swift
if report.coverage.level == .unreachable && saveAudit {
    throw CLIError.remoteTargetUnreachable("Remote scan is unreachable; rerun probe or pass an explicit degraded-report export path.")
}

let selected = try auditStore.selectedRemoteScanReport(forAuditQuery: RemoteAuditQuery(target: targetReference, reportID: requestedReportID))
guard selected.target.id == targetReference.id else {
    throw CLIError.remoteTargetMismatch("Requested export does not match the selected remote target.")
}
```

- [ ] **Step 6: Add target continuity warnings**

```swift
public enum RemoteTargetContinuity {
    public static func warnings(previous: RemoteTargetReference, current: RemoteTargetReference) -> [RemoteTargetContinuityWarning] {
        [
            warning(field: "host", previous: previous.resolvedHost, current: current.resolvedHost),
            warning(field: "user", previous: previous.resolvedUser, current: current.resolvedUser),
            warning(field: "port", previous: previous.resolvedPort.map(String.init), current: current.resolvedPort.map(String.init)),
            warning(field: "fingerprint", previous: previous.fingerprint, current: current.fingerprint)
        ].compactMap { $0 }
    }
}
```

- [ ] **Step 7: Show coverage in Markdown and app**

```swift
lines.append("## Coverage")
lines.append("")
lines.append("- Level: \(report.coverage.level.rawValue)")
lines.append("- Explanation: \(markdownInline(report.coverage.explanation))")
lines.append("- Successful commands: \(report.coverage.successfulCommandIDs.count)")
lines.append("- Failed commands: \(report.coverage.failedCommandIDs.count)")
```

- [ ] **Step 8: Run focused tests and safe CLI smoke**

Run: `swift test --scratch-path "$PWD/.build" --filter RemoteCoverage`

Expected: PASS.

Run: `swift run --scratch-path .build reclaimer remote probe definitely-not-a-real-ryddi-host --json`

Expected: nonzero exit, no password prompt, clear unreachable message.

- [ ] **Step 9: Commit**

```bash
git add Sources/ReclaimerCore/RemoteTarget.swift Sources/ReclaimerCore/RemoteScan.swift Sources/ReclaimerCore/RemoteReportExport.swift Sources/reclaimer/RemoteCommands.swift Sources/MacDiskReclaimerApp Tests/ReclaimerCoreTests/RemoteCoverageTests.swift
git commit -m "feat: mark remote scan coverage explicitly"
```

## Task 7: Typed Release Trust Evidence

**Files:**
- Create: `Sources/ReclaimerCore/ReleaseTrustEvidence.swift`
- Modify: `Sources/ReclaimerCore/TrustReadiness.swift`
- Modify: `Sources/reclaimer/main.swift`
- Modify: `Scripts/release-check.sh`
- Create: `Tests/ReclaimerCoreTests/ReleaseTrustEvidenceTests.swift`

**Interfaces:**
- Consumes: `Ryddi-release-manifest.txt`, existing `TrustReadinessReport`, release scripts.
- Produces:

```swift
public enum ReleaseTrustState: String, Codable, Hashable, Sendable {
    case localDebug
    case signedOnly
    case notarizationSubmitted
    case notarizationAccepted
    case stapledAndAccepted
    case invalid
    case missingManifest
}

public struct ReleaseTrustEvidence: Codable, Hashable, Sendable {
    public let state: ReleaseTrustState
    public let version: String?
    public let buildNumber: String?
    public let artifactName: String?
    public let artifactSHA256: String?
    public let sourceCommit: String?
    public let codesignVerified: Bool
    public let hardenedRuntime: Bool
    public let notarizationStatus: String?
    public let stapleValidated: Bool
    public let gatekeeperAccepted: Bool
    public let manifestPath: String?
    public let warnings: [String]
}

public enum ReleaseTrustEvidenceParser {
    public static func parseManifest(text: String, path: String?) -> ReleaseTrustEvidence
}
```

- [ ] **Step 1: Write false-positive notarization test**

```swift
import XCTest
@testable import ReclaimerCore

final class ReleaseTrustEvidenceTests: XCTestCase {
    func testNotNotarizedDoesNotBecomeReady() throws {
        let manifest = """
        version=0.2.0
        build=2
        codesign_verified=true
        notarization_status=not notarized
        stapled=false
        gatekeeper=not assessed
        """

        let evidence = ReleaseTrustEvidenceParser.parseManifest(text: manifest, path: "/tmp/Ryddi-release-manifest.txt")

        XCTAssertNotEqual(evidence.state, .stapledAndAccepted)
        XCTAssertFalse(evidence.gatekeeperAccepted)
        XCTAssertEqual(evidence.notarizationStatus, "not notarized")
    }
}
```

- [ ] **Step 2: Write accepted manifest test**

```swift
func testAcceptedStapledGatekeeperManifestIsReleaseReady() throws {
    let manifest = """
    version=0.2.0
    build=2
    artifact=Ryddi-v0.2.0.zip
    sha256=abc123
    source_commit=96c0d50
    codesign_verified=true
    hardened_runtime=true
    notarization_status=Accepted
    stapled=true
    gatekeeper=accepted
    """

    let evidence = ReleaseTrustEvidenceParser.parseManifest(text: manifest, path: "/tmp/Ryddi-release-manifest.txt")

    XCTAssertEqual(evidence.state, .stapledAndAccepted)
    XCTAssertTrue(evidence.codesignVerified)
    XCTAssertTrue(evidence.stapleValidated)
    XCTAssertTrue(evidence.gatekeeperAccepted)
}
```

- [ ] **Step 3: Implement manifest parser with exact keys**

```swift
import Foundation

public enum ReleaseTrustEvidenceParser {
    public static func parseManifest(text: String, path: String?) -> ReleaseTrustEvidence {
        let fields = Dictionary(uniqueKeysWithValues: text.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
        })

        let codesign = fields["codesign_verified"] == "true"
        let runtime = fields["hardened_runtime"] == "true"
        let notarization = fields["notarization_status"]
        let stapled = fields["stapled"] == "true"
        let gatekeeper = fields["gatekeeper"] == "accepted"
        let state = stateFor(codesign: codesign, runtime: runtime, notarization: notarization, stapled: stapled, gatekeeper: gatekeeper)

        return ReleaseTrustEvidence(
            state: state,
            version: fields["version"],
            buildNumber: fields["build"],
            artifactName: fields["artifact"],
            artifactSHA256: fields["sha256"],
            sourceCommit: fields["source_commit"],
            codesignVerified: codesign,
            hardenedRuntime: runtime,
            notarizationStatus: notarization,
            stapleValidated: stapled,
            gatekeeperAccepted: gatekeeper,
            manifestPath: path,
            warnings: warningsFor(state: state)
        )
    }
}
```

- [ ] **Step 4: Replace trust readiness substring checks**

```swift
let releaseAction = TrustReadinessAction(
    id: "release-trust",
    title: "Release trust",
    detail: releaseTrustEvidence.state == .stapledAndAccepted
        ? "Signed, notarized, stapled, and Gatekeeper accepted."
        : releaseTrustEvidence.warnings.joined(separator: " "),
    severity: releaseTrustEvidence.state == .stapledAndAccepted ? .ready : .warning
)
```

- [ ] **Step 5: Make `release-check.sh` manifest keys parseable**

```bash
{
  printf 'version=%s\n' "$RYDDI_VERSION"
  printf 'build=%s\n' "$RYDDI_BUILD_NUMBER"
  printf 'artifact=%s.zip\n' "$RYDDI_ARTIFACT_BASENAME"
  printf 'sha256=%s\n' "$artifact_sha"
  printf 'source_commit=%s\n' "$(git rev-parse --short HEAD)"
  printf 'codesign_verified=%s\n' "$codesign_verified"
  printf 'hardened_runtime=%s\n' "$hardened_runtime"
  printf 'notarization_status=%s\n' "$notarization_status"
  printf 'stapled=%s\n' "$stapled"
  printf 'gatekeeper=%s\n' "$gatekeeper_status"
} > "$manifest"
```

- [ ] **Step 6: Add CLI proof command**

```swift
case "release-trust":
    let manifestPath = options.value(for: "--manifest") ?? "dist/Ryddi-release-manifest.txt"
    let text = try String(contentsOfFile: manifestPath, encoding: .utf8)
    let evidence = ReleaseTrustEvidenceParser.parseManifest(text: text, path: manifestPath)
    print(try JSONEncoder.ryddiPretty.encodeToString(evidence))
```

- [ ] **Step 7: Run tests and script syntax check**

Run: `swift test --scratch-path "$PWD/.build" --filter ReleaseTrustEvidence`

Expected: PASS.

Run: `bash -n Scripts/release-check.sh`

Expected: exit `0`.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReclaimerCore/ReleaseTrustEvidence.swift Sources/ReclaimerCore/TrustReadiness.swift Sources/reclaimer/main.swift Scripts/release-check.sh Tests/ReclaimerCoreTests/ReleaseTrustEvidenceTests.swift
git commit -m "feat: parse release trust evidence"
```

## Task 8: Public Onboarding And Support Docs

**Files:**
- Modify: `README.md`
- Modify: `FEATURES.md`
- Modify: `PRIVACY.md`
- Create: `docs/GETTING_STARTED.md`
- Create: `docs/SUPPORT_DIAGNOSTICS.md`
- Create: `SECURITY.md`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/unsafe_classification.yml`
- Create: `.github/ISSUE_TEMPLATE/remote_target.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`

**Interfaces:**
- Consumes: design spec, current CLI commands, trust/release behavior, remote target boundaries.
- Produces: public docs that explain first-run flow, general Mac cleanup, developer cleanup, privacy, support diagnostics, issue intake, and vulnerability reporting.

- [ ] **Step 1: Update README opening**

```markdown
# Ryddi

Ryddi is a local-first Mac disk reclaim assistant for people who want evidence before cleanup. It covers general Mac cleanup such as Downloads, Trash, apps and leftovers, browser caches, large files, and device backups, with deeper developer lanes for package caches, Xcode, containers, AI-agent storage, and remote VPS reports.

Ryddi's default posture is review-first:

- scan locally
- explain safety
- build dry-run plans
- prefer native cleanup tools
- preserve valuable or unknown data by default
```

- [ ] **Step 2: Add getting-started guide**

```markdown
# Getting Started With Ryddi

## First Run

1. Open Ryddi.
2. Review the Summary card.
3. If coverage is degraded, open Permissions and grant Full Disk Access to the installed Ryddi app.
4. Run Scan.
5. Review Safe Maintenance, Quit App First, Use Native Tool, Valuable History, Protected, and Unknown queues.
6. Create a dry-run plan before reclaiming space.

## General Mac Cleanup

Start with Downloads, Trash, Apps and Leftovers, Browser Caches, Large and Old Files, and Device Backups.

## Developer Cleanup

Review Package Caches, Project Dependencies, Xcode, Containers, AI Agent Storage, and Remote Targets.
```

- [ ] **Step 3: Add support diagnostics guide**

```markdown
# Support Diagnostics

Ryddi support diagnostics should be local and redacted by default.

Recommended command:

```bash
reclaimer dogfood --preset general --path-style redacted --output ryddi-diagnostics.md
```

The report includes disk status, scan coverage, review queues, selected dry-run summary, active-handle summary, protected buckets, and explicit non-claims. It does not execute cleanup, grant permissions, or promise exact reclaim.
```

- [ ] **Step 4: Add security policy**

```markdown
# Security Policy

Ryddi is local-first. It does not upload file paths, remote command output, telemetry, cleanup reports, SSH keys, passwords, sudo credentials, or tokens.

Remote Targets use the system OpenSSH client and existing SSH configuration. Ryddi does not store private keys or request password prompts.

Report vulnerabilities through GitHub Security Advisories when available, or open an issue without secrets and request a private contact path.
```

- [ ] **Step 5: Add issue template for unsafe classifications**

```yaml
name: Unsafe classification
description: Report a file or directory that Ryddi classified too aggressively or too conservatively.
title: "[Safety]: "
labels: ["safety", "classification"]
body:
  - type: textarea
    id: evidence
    attributes:
      label: Evidence
      description: Paste redacted report lines, rule ID, safety class, next action, and why it looks wrong.
    validations:
      required: true
  - type: checkboxes
    id: privacy
    attributes:
      label: Privacy check
      options:
        - label: I removed secrets, tokens, and private paths before posting.
          required: true
```

- [ ] **Step 6: Run docs consistency scan**

Run: `rg -n "one-click|guaranteed reclaim|remote cleanup|uploads paths|not notarized.*ready" README.md FEATURES.md PRIVACY.md docs SECURITY.md .github/ISSUE_TEMPLATE`

Expected: no matches that claim unsafe behavior.

- [ ] **Step 7: Commit**

```bash
git add README.md FEATURES.md PRIVACY.md docs/GETTING_STARTED.md docs/SUPPORT_DIAGNOSTICS.md SECURITY.md .github/ISSUE_TEMPLATE
git commit -m "docs: add guided onboarding and support"
```

## Task 9: Final Verification And Release Readiness Gate

**Files:**
- Modify only files required by verification fixes.

**Interfaces:**
- Consumes: all task outputs.
- Produces: evidence that the branch is ready for review or merge.

- [ ] **Step 1: Check disk headroom**

Run: `df -h /System/Volumes/Data`

Expected: available space is at least `50Gi`.

- [ ] **Step 2: Run focused tests**

```bash
swift test --scratch-path "$PWD/.build" --filter GuidedWorkflow
swift test --scratch-path "$PWD/.build" --filter PlanGateEvidence
swift test --scratch-path "$PWD/.build" --filter PackageReclaimLane
swift test --scratch-path "$PWD/.build" --filter AgentRetentionPlan
swift test --scratch-path "$PWD/.build" --filter RemoteCoverage
swift test --scratch-path "$PWD/.build" --filter ReleaseTrustEvidence
```

Expected: all commands exit `0`.

- [ ] **Step 3: Run full Swift test and build**

```bash
swift test --scratch-path "$PWD/.build"
swift build --scratch-path "$PWD/.build"
```

Expected: both commands exit `0`.

- [ ] **Step 4: Run release and script checks**

```bash
bash -n Scripts/package-app.sh Scripts/notarize-app.sh Scripts/release-check.sh
Scripts/release-check.sh
```

Expected: shell syntax passes and unsigned preview release check exits `0`.

- [ ] **Step 5: Run remote failure smoke**

```bash
swift run --scratch-path .build reclaimer remote probe definitely-not-a-real-ryddi-host --json
```

Expected: command exits nonzero, does not prompt, and reports unreachable or resolution failure.

- [ ] **Step 6: Run docs scans**

```bash
rg -n "one-click|guaranteed reclaim|uploads paths|not notarized.*ready" README.md FEATURES.md PRIVACY.md docs SECURITY.md .github/ISSUE_TEMPLATE
rg -n "Developer-only|developer only" README.md FEATURES.md docs
```

Expected: no unsafe claims; no docs describe Ryddi as developer-only.

- [ ] **Step 7: Check whitespace and temp leftovers**

```bash
git diff --check
du -sh /private/tmp/[Vv]ifty* 2>/dev/null || true
du -sh /private/tmp/Ryddi* 2>/dev/null || true
```

Expected: `git diff --check` exits `0`; temp checks do not reveal large owned leftovers from this work.

- [ ] **Step 8: Install and smoke app**

```bash
Scripts/package-app.sh
rm -rf /Applications/Ryddi.app
ditto dist/Ryddi.app /Applications/Ryddi.app
open /Applications/Ryddi.app
```

Expected: app opens, Summary fits narrow and normal windows, one primary action is visible, and remote destructive controls are absent.

- [ ] **Step 9: Commit verification fixes**

```bash
git status --short
git add -A
git commit -m "test: verify guided usefulness release"
```

Expected: commit is created only if verification required code, test, doc, or script fixes.

## Parallel Worker Goals

Use these prompts with `parallel-goals-for-a-task` or `superpowers:subagent-driven-development`.

```text
/goal App proof ladder and next safe action

Context:
Build Ryddi's guided usefulness release slice in Swift 6, SwiftUI, SwiftPM, and repo documentation. Ryddi must open to one obvious safe next action, explain scan coverage and safety totals, and keep cleanup review-first. Preserve the existing local-first trust model, macOS 14+ floor, and no telemetry/no root-helper boundaries.

Deliverable:
Create `GuidedWorkflow.swift`, `GuidedWorkflowTests.swift`, and `GuidedSummaryView.swift`; wire Summary in the app to show one primary action, secondary safe actions, disk status, safety totals, and top decisions.

Boundaries:
Own guided workflow core and Summary view wiring only. Do not change cleanup execution semantics, remote scan behavior, release scripts, or public docs beyond labels required by the Summary.

Verification:
`swift test --scratch-path "$PWD/.build" --filter GuidedWorkflow`
`swift build --scratch-path "$PWD/.build"`
Manual app smoke at narrow and normal window widths.
```

```text
/goal Machine-verifiable cleanup gates

Context:
Ryddi must select cleanup plan items from typed, machine-verifiable evidence rather than English condition text. Existing `PlanConditionKind` gates remain fail-closed, and executor final revalidation remains strict.

Deliverable:
Add `RuleGateEvidence`, decode it from rules, propagate it through rule matches, and update `PlanBuilder` so age, retention, native-tool, open-handle, symlink, and final-classification gates are checked from typed evidence.

Boundaries:
Own `Models.swift`, `Rules.swift`, `PlanBuilder.swift`, `rules.json`, and `PlanGateEvidenceTests.swift`. Do not add broad reclaim lanes or UI changes.

Verification:
`swift test --scratch-path "$PWD/.build" --filter PlanGateEvidence`
`swift test --scratch-path "$PWD/.build" --filter PlanBuilder`
```

```text
/goal Package and AI-agent safe reclaim lanes

Context:
Ryddi should become more useful without becoming reckless. Package caches should prefer native preview commands. AI-agent storage should protect sessions, memories, config, auth, and state while offering preview-first cleanup only for eligible stale caches/logs.

Deliverable:
Create `PackageReclaimLane.swift` and `AgentRetentionPlan.swift` with focused tests and app cards that surface preview-first reclaim opportunities.

Boundaries:
Own package and AI-agent lane files, tests, and narrow UI cards. Do not alter Docker/Colima cleanup, remote cleanup, release trust, or executor safety rules.

Verification:
`swift test --scratch-path "$PWD/.build" --filter PackageReclaimLane`
`swift test --scratch-path "$PWD/.build" --filter AgentRetentionPlan`
`swift build --scratch-path "$PWD/.build"`
```

```text
/goal Remote coverage and target identity

Context:
Remote Targets must be report-first and trustworthy. Failed SSH commands cannot be shown as a clean empty report, and remote exports/history must be bound to the selected target identity.

Deliverable:
Add `RemoteScanCoverage`, `RemoteScanCoverageBuilder`, and target continuity warnings; wire coverage into remote scan reports, Markdown export, CLI save/export behavior, and app remote UI.

Boundaries:
Own remote coverage and target identity semantics. Do not add any destructive remote action or SSH credential management.

Verification:
`swift test --scratch-path "$PWD/.build" --filter RemoteCoverage`
`swift run --scratch-path .build reclaimer remote probe definitely-not-a-real-ryddi-host --json`
```

```text
/goal v0.2 release trust proof

Context:
Ryddi release trust must be typed and manifest-backed. A string like `not notarized` must never be treated as a ready notarized release.

Deliverable:
Create `ReleaseTrustEvidence.swift`, update `TrustReadiness.swift`, make `release-check.sh` write parseable manifest keys, and add CLI JSON proof for release trust.

Boundaries:
Own release evidence parsing and trust readiness. Do not publish a GitHub Release or claim signed/notarized readiness without accepted notarization, stapling, Gatekeeper assessment, and manifest proof.

Verification:
`swift test --scratch-path "$PWD/.build" --filter ReleaseTrustEvidence`
`bash -n Scripts/release-check.sh`
`Scripts/release-check.sh`
```

```text
/goal Public onboarding and support docs

Context:
Ryddi should be understandable as a general Mac cleaner with developer-first depth. Public docs must explain what Ryddi will and will not do, how to grant access, how to gather redacted diagnostics, and how to report safety issues.

Deliverable:
Update README, FEATURES, PRIVACY, add Getting Started, Support Diagnostics, SECURITY, and GitHub issue templates.

Boundaries:
Own docs and issue templates only. Do not claim remote cleanup, exact reclaim, telemetry upload, or signed/notarized release status unless the manifest proves it.

Verification:
`rg -n "one-click|guaranteed reclaim|uploads paths|not notarized.*ready" README.md FEATURES.md PRIVACY.md docs SECURITY.md .github/ISSUE_TEMPLATE`
`git diff --check`
```

## Execution Notes

- Use small commits after each task.
- Prefer focused files over adding more code to `MacDiskReclaimerApp.swift` when the touched view can stand alone.
- Keep degraded states visible in app and CLI output; do not convert degraded evidence into success.
- Run the smallest focused test before broad tests.
- Signed `v0.2.0` publication remains gated on current-head signing, notarization acceptance, stapling validation, Gatekeeper acceptance, manifest proof, and CI readback.
