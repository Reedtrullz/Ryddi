import XCTest
@testable import ReclaimerCore

final class TrashExecutionReadinessTests: XCTestCase {
    func testMatchingCleanTrashDryRunIsReady() {
        let context = fixture(action: .trash)
        XCTAssertEqual(
            TrashExecutionReadiness.evaluate(
                session: context.session,
                plan: context.plan,
                dryRunReceipt: context.receipt
            ).state,
            .ready
        )
    }

    func testDeleteCachePlanIsNotExecutable() {
        let context = fixture(action: .deleteCache)
        XCTAssertEqual(
            TrashExecutionReadiness.evaluate(
                session: context.session,
                plan: context.plan,
                dryRunReceipt: context.receipt
            ).state,
            .ineligibleSelection
        )
    }

    func testStaleSessionIsNotReady() {
        let context = fixture(action: .trash)
        let stale = ScanSession(
            id: context.session.id,
            createdAt: context.session.createdAt,
            updatedAt: context.session.updatedAt,
            appVersion: context.session.appVersion,
            ruleVersion: context.session.ruleVersion,
            preset: context.session.preset,
            scopeDigest: context.session.scopeDigest,
            policyDigest: context.session.policyDigest,
            findingDigest: context.session.findingDigest,
            planDigest: "different-plan",
            dryRunReceiptID: context.receipt.id,
            stage: .dryRunReady
        )
        XCTAssertEqual(
            TrashExecutionReadiness.evaluate(session: stale, plan: context.plan, dryRunReceipt: context.receipt).state,
            .staleEvidence
        )
    }

    private func fixture(action: ActionKind) -> (session: ScanSession, plan: ReclaimPlan, receipt: ExecutionReceipt) {
        let finding = Finding(
            scopeName: "Fixture",
            path: "/tmp/ryddi-readiness-fixture",
            displayName: "Fixture cache",
            logicalSize: 100,
            allocatedSize: 100,
            isDirectory: true,
            safetyClass: .autoSafe,
            actionKind: action,
            ruleMatches: [],
            evidence: []
        )
        let plan = ReclaimPlan(
            id: "plan-v1",
            mode: PlanMode.autoSafeOnly.rawValue,
            items: [ReclaimPlanItem(
                finding: finding,
                selected: true,
                proposedAction: action,
                conditions: [],
                estimatedImmediateReclaim: 100
            )],
            dryRunSummary: []
        )
        let receipt = ExecutionReceipt(
            id: "receipt-v1",
            ruleVersion: "rules-v1",
            mode: ExecutionMode.dryRun.rawValue,
            beforeFreeBytes: 1_000,
            afterFreeBytes: 1_000,
            actions: [ExecutionActionReceipt(
                path: finding.path,
                action: action,
                status: "dry-run",
                message: "Would perform action.",
                reclaimedBytes: 100
            )],
            userConfirmed: false
        )
        let session = ScanSession(
            id: "session-v1",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopeDigest: "scope-v1",
            findingDigest: "findings-v1",
            planDigest: plan.id,
            dryRunReceiptID: receipt.id,
            stage: .dryRunReady
        )
        return (session, plan, receipt)
    }
}
