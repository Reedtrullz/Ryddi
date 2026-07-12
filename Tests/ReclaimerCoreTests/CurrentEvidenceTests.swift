import XCTest
@testable import ReclaimerCore

final class CurrentEvidenceTests: XCTestCase {
    func testPlanIsCurrentOnlyWhenSessionDigestMatches() {
        let matchingPlan = makePlan(id: "plan-current", createdAt: Date(timeIntervalSince1970: 10))
        let newerHistoricalPlan = makePlan(id: "plan-history", createdAt: Date(timeIntervalSince1970: 20))
        let session = makeSession(planID: matchingPlan.id)

        let current = CurrentEvidenceResolver.resolve(
            session: session,
            plan: matchingPlan,
            dryRunReceipt: nil,
            executionReceipt: nil
        )
        let stale = CurrentEvidenceResolver.resolve(
            session: session,
            plan: newerHistoricalPlan,
            dryRunReceipt: nil,
            executionReceipt: nil
        )

        XCTAssertEqual(current.plan?.id, matchingPlan.id)
        XCTAssertNil(stale.plan)
        XCTAssertTrue(stale.rejectedEvidence.contains(.planDigestMismatch))
    }

    func testReceiptIDsMustMatchCurrentSessionEvenWhenHistoricalReceiptIsNewer() {
        let plan = makePlan(id: "plan-current", createdAt: Date(timeIntervalSince1970: 10))
        let currentDryRun = makeReceipt(id: "receipt-current", createdAt: Date(timeIntervalSince1970: 20), mode: ExecutionMode.dryRun.rawValue)
        let newerHistoricalReceipt = makeReceipt(id: "receipt-history", createdAt: Date(timeIntervalSince1970: 30), mode: ExecutionMode.dryRun.rawValue)
        let session = makeSession(planID: plan.id, dryRunReceiptID: currentDryRun.id, stage: .dryRunReady)

        let current = CurrentEvidenceResolver.resolve(
            session: session,
            plan: plan,
            dryRunReceipt: currentDryRun,
            executionReceipt: nil
        )
        let stale = CurrentEvidenceResolver.resolve(
            session: session,
            plan: plan,
            dryRunReceipt: newerHistoricalReceipt,
            executionReceipt: nil
        )

        XCTAssertEqual(current.dryRunReceipt?.id, currentDryRun.id)
        XCTAssertNil(stale.dryRunReceipt)
        XCTAssertTrue(stale.rejectedEvidence.contains(.dryRunReceiptIDMismatch))
    }

    func testExecutionReceiptRequiresMatchingExecutionReceiptID() {
        let plan = makePlan(id: "plan-current", createdAt: Date(timeIntervalSince1970: 10))
        let receipt = makeReceipt(id: "execution-current", createdAt: Date(timeIntervalSince1970: 20), mode: ExecutionMode.perform.rawValue)
        let session = makeSession(planID: plan.id, executionReceiptID: receipt.id, stage: .executed)

        let snapshot = CurrentEvidenceResolver.resolve(
            session: session,
            plan: plan,
            dryRunReceipt: nil,
            executionReceipt: receipt
        )

        XCTAssertEqual(snapshot.executionReceipt?.id, receipt.id)
    }

    func testInvalidatedSessionRejectsAllSuppliedEvidence() {
        let plan = makePlan(id: "plan-current", createdAt: Date(timeIntervalSince1970: 10))
        let receipt = makeReceipt(id: "receipt-current", createdAt: Date(timeIntervalSince1970: 20), mode: ExecutionMode.dryRun.rawValue)
        let session = ScanSession(
            appVersion: "0.3.0",
            ruleVersion: "rules",
            preset: .developer,
            scopeDigest: "scope",
            findingDigest: "findings",
            planDigest: plan.id,
            dryRunReceiptID: receipt.id,
            stage: .invalidated,
            invalidationReasons: [.policyChanged]
        )

        let snapshot = CurrentEvidenceResolver.resolve(
            session: session,
            plan: plan,
            dryRunReceipt: receipt,
            executionReceipt: nil
        )

        XCTAssertNil(snapshot.plan)
        XCTAssertNil(snapshot.dryRunReceipt)
        XCTAssertTrue(snapshot.rejectedEvidence.contains(.sessionInvalidated))
    }

    func testMissingSessionRejectsSuppliedEvidence() {
        let snapshot = CurrentEvidenceResolver.resolve(
            session: nil,
            plan: makePlan(id: "plan", createdAt: Date()),
            dryRunReceipt: nil,
            executionReceipt: nil
        )

        XCTAssertNil(snapshot.plan)
        XCTAssertEqual(snapshot.rejectedEvidence, [.missingSession])
    }

    private func makeSession(
        planID: String,
        dryRunReceiptID: String? = nil,
        executionReceiptID: String? = nil,
        stage: ScanSessionStage = .planReady
    ) -> ScanSession {
        ScanSession(
            appVersion: "0.3.0",
            ruleVersion: "rules",
            preset: .developer,
            scopeDigest: "scope",
            findingDigest: "findings",
            planDigest: planID,
            dryRunReceiptID: dryRunReceiptID,
            executionReceiptID: executionReceiptID,
            stage: stage
        )
    }

    private func makePlan(id: String, createdAt: Date) -> ReclaimPlan {
        ReclaimPlan(
            id: id,
            createdAt: createdAt,
            mode: PlanMode.autoSafeOnly.rawValue,
            items: [],
            dryRunSummary: []
        )
    }

    private func makeReceipt(id: String, createdAt: Date, mode: String) -> ExecutionReceipt {
        ExecutionReceipt(
            id: id,
            createdAt: createdAt,
            ruleVersion: "rules",
            mode: mode,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: [],
            userConfirmed: false
        )
    }
}
