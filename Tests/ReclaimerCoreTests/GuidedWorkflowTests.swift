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

    func testCompleteCoverageWithoutFindingsSelectsScan() throws {
        let input = GuidedWorkflowFixtures.input(
            permissionCoverage: .complete,
            findings: [],
            latestPlan: nil,
            latestReceipt: nil
        )

        let report = GuidedWorkflowBuilder.build(input: input)

        XCTAssertEqual(report.currentStep, .scan)
        XCTAssertEqual(report.primaryAction.kind, .runScan)
        XCTAssertFalse(report.primaryAction.isDestructive)
    }

    func testSafeFindingsWithoutPlanSelectsCreateSafePlan() throws {
        let finding = GuidedWorkflowFixtures.finding(nextAction: .safeMaintenance, allocatedSize: 1_000_000_000)
        let input = GuidedWorkflowFixtures.input(
            permissionCoverage: .complete,
            findings: [finding],
            latestPlan: nil,
            latestReceipt: nil
        )

        let report = GuidedWorkflowBuilder.build(input: input)

        XCTAssertEqual(report.currentStep, .createPlan)
        XCTAssertEqual(report.primaryAction.kind, .createSafePlan)
        XCTAssertEqual(report.primaryAction.estimatedBytes, 1_000_000_000)
        XCTAssertEqual(report.safetyTotals[.safeMaintenance], 1_000_000_000)
    }

    func testReviewOnlyFindingsWithoutPlanSelectsReviewQueues() throws {
        let finding = GuidedWorkflowFixtures.finding(nextAction: .protectByDefault, allocatedSize: 5_000_000_000)
        let input = GuidedWorkflowFixtures.input(
            permissionCoverage: .complete,
            findings: [finding],
            latestPlan: nil,
            latestReceipt: nil
        )

        let report = GuidedWorkflowBuilder.build(input: input)

        XCTAssertEqual(report.currentStep, .reviewFindings)
        XCTAssertEqual(report.primaryAction.kind, .openReviewQueues)
        XCTAssertEqual(report.primaryAction.estimatedBytes, 5_000_000_000)
        XCTAssertEqual(report.safetyTotals[.protectByDefault], 5_000_000_000)
    }

    func testPlanWithoutReceiptSelectsDryRun() throws {
        let finding = GuidedWorkflowFixtures.finding(nextAction: .safeMaintenance, allocatedSize: 750_000_000)
        let input = GuidedWorkflowFixtures.input(
            permissionCoverage: .complete,
            findings: [finding],
            latestPlan: GuidedWorkflowFixtures.plan(expectedReclaim: 750_000_000),
            latestReceipt: nil
        )

        let report = GuidedWorkflowBuilder.build(input: input)

        XCTAssertEqual(report.currentStep, .dryRun)
        XCTAssertEqual(report.primaryAction.kind, .runDryRun)
        XCTAssertEqual(report.primaryAction.estimatedBytes, 750_000_000)
        XCTAssertFalse(report.primaryAction.isDestructive)
    }

    func testDryRunReceiptWithSelectedPlanRoutesToManualReviewWithoutDestructiveAction() throws {
        let finding = GuidedWorkflowFixtures.finding(nextAction: .safeMaintenance, allocatedSize: 300_000_000)
        let input = GuidedWorkflowFixtures.input(
            permissionCoverage: .complete,
            findings: [finding],
            latestPlan: GuidedWorkflowFixtures.plan(expectedReclaim: 300_000_000),
            latestReceipt: GuidedWorkflowFixtures.receipt(mode: ExecutionMode.dryRun.rawValue, status: "dry-run")
        )

        let report = GuidedWorkflowBuilder.build(input: input)

        XCTAssertEqual(report.currentStep, .reclaimOrExport)
        XCTAssertEqual(report.primaryAction.kind, .openReviewQueues)
        XCTAssertEqual(report.primaryAction.title, "Review Safe Plan")
        XCTAssertEqual(report.primaryAction.estimatedBytes, 300_000_000)
        XCTAssertFalse(report.primaryAction.isDestructive)
        XCTAssertTrue(report.explanation.localizedCaseInsensitiveContains("manual"))
        XCTAssertTrue(report.secondaryActions.contains { $0.kind == .exportReport })
    }

    func testExecutedReceiptSelectsRecoveryReview() throws {
        let finding = GuidedWorkflowFixtures.finding(nextAction: .safeMaintenance, allocatedSize: 300_000_000)
        let input = GuidedWorkflowFixtures.input(
            permissionCoverage: .complete,
            findings: [finding],
            latestPlan: GuidedWorkflowFixtures.plan(expectedReclaim: 300_000_000),
            latestReceipt: GuidedWorkflowFixtures.receipt(mode: ExecutionMode.perform.rawValue, status: "done")
        )

        let report = GuidedWorkflowBuilder.build(input: input)

        XCTAssertEqual(report.currentStep, .recovery)
        XCTAssertEqual(report.primaryAction.kind, .openRecovery)
        XCTAssertFalse(report.primaryAction.isDestructive)
    }
}

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
                readableCount: permissionCoverage == .complete ? 27 : 19,
                deniedCount: permissionCoverage == .complete ? 0 : 8,
                missingCount: 0,
                unknownCount: 0,
                totalCount: 27,
                readableFraction: permissionCoverage == .complete ? 1.0 : 19.0 / 27.0,
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
        let safetyClass: SafetyClass
        let actionKind: ActionKind
        switch nextAction {
        case .safeMaintenance:
            safetyClass = .autoSafe
            actionKind = .trash
        case .quitAppFirst:
            safetyClass = .safeAfterCondition
            actionKind = .trash
        case .useNativeTool:
            safetyClass = .safeAfterCondition
            actionKind = .nativeToolCommand
        case .reviewInFinder, .archiveCandidate:
            safetyClass = .reviewRequired
            actionKind = .openGuidance
        case .protectByDefault:
            safetyClass = .preserveByDefault
            actionKind = .reportOnly
        case .doNotTouch:
            safetyClass = .neverTouch
            actionKind = .reportOnly
        }
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

    static func receipt(mode: String, status: String) -> ExecutionReceipt {
        ExecutionReceipt(
            ruleVersion: "fixture",
            mode: mode,
            beforeFreeBytes: 100_000_000_000,
            afterFreeBytes: status == "done" ? 100_300_000_000 : nil,
            actions: [
                ExecutionActionReceipt(path: "/tmp/ryddi-fixture", action: .trash, status: status, message: "Fixture")
            ],
            userConfirmed: mode == ExecutionMode.perform.rawValue
        )
    }
}
