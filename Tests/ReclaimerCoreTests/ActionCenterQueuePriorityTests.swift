import XCTest
@testable import ReclaimerCore

final class ActionCenterQueuePriorityTests: XCTestCase {
    func testSafeMaintenanceOutranksMuchLargerValuableHistory() throws {
        let megabyte: Int64 = 1_024 * 1_024
        let gigabyte: Int64 = 1_024 * megabyte
        let report = actionCenterReport(queues: [
            queue(.valuableHistory, allocatedSize: 35 * gigabyte),
            queue(.safeMaintenance, allocatedSize: 120 * megabyte)
        ])

        let primary = try XCTUnwrap(report.primaryAction)
        XCTAssertEqual(primary.sourceIDs, [ReviewQueueID.safeMaintenance.rawValue])
        XCTAssertEqual(primary.estimatedReclaimBytes, 120 * megabyte)
    }

    func testReviewQueuesFollowCleanupFlowOrder() throws {
        let expectedOrder: [ReviewQueueID] = [
            .safeMaintenance,
            .quitAppFirst,
            .useNativeTool,
            .unknown,
            .valuableHistory,
            .personalAppAssets
        ]
        let queues = expectedOrder.enumerated().map { index, queueID in
            queue(queueID, allocatedSize: Int64(index + 1) * 1_000)
        }

        for index in expectedOrder.indices {
            let report = actionCenterReport(queues: Array(queues[index...]))
            let primary = try XCTUnwrap(report.primaryAction)
            XCTAssertEqual(
                primary.sourceIDs,
                [expectedOrder[index].rawValue],
                "Unexpected winner for remaining queues starting at \(expectedOrder[index].rawValue)"
            )
        }
    }

    func testProtectedHistoryQueueNeverBecomesReclaimCTAWhileActionableQueueExists() throws {
        let historyQueue = queue(.valuableHistory, allocatedSize: 35 * 1_024 * 1_024 * 1_024)
        let safeQueue = queue(.safeMaintenance, allocatedSize: 120 * 1_024 * 1_024)

        let actionableReport = actionCenterReport(queues: [historyQueue, safeQueue])
        let actionablePrimary = try XCTUnwrap(actionableReport.primaryAction)
        XCTAssertEqual(actionablePrimary.sourceIDs, [ReviewQueueID.safeMaintenance.rawValue])

        let reviewOnlyReport = actionCenterReport(queues: [historyQueue])
        let reviewOnlyPrimary = try XCTUnwrap(reviewOnlyReport.primaryAction)
        XCTAssertEqual(reviewOnlyPrimary.title, "Review Valuable History")
        XCTAssertEqual(reviewOnlyPrimary.estimatedReclaimBytes, 0)
        XCTAssertFalse(reviewOnlyPrimary.isDestructive)
    }

    private func actionCenterReport(queues: [ReviewQueueSummary]) -> ActionCenterReport {
        ActionCenterBuilder.build(input: ActionCenterInput(
            permissionReport: PermissionAdvisorReport(
                coverageLevel: .complete,
                readableCount: 1,
                deniedCount: 0,
                missingCount: 0,
                unknownCount: 0,
                totalCount: 1,
                readableFraction: 1,
                scopeSummaries: [],
                recommendedActions: [],
                nonClaims: []
            ),
            latestScanSession: ScanSession(
                id: "session-scanned",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2),
                appVersion: "0.3.0",
                ruleVersion: "rules-v1",
                preset: .developer,
                scopeDigest: "scope-v1",
                policyDigest: "policy-v1",
                findingDigest: "findings-v1",
                planDigest: nil,
                dryRunReceiptID: nil,
                executionReceiptID: nil,
                stage: .scanned
            ),
            reviewQueueReport: ReviewQueueReport(
                generatedAt: Date(timeIntervalSince1970: 3),
                queues: queues
            ),
            generatedAt: Date(timeIntervalSince1970: 3)
        ))
    }

    private func queue(_ queueID: ReviewQueueID, allocatedSize: Int64) -> ReviewQueueSummary {
        ReviewQueueSummary(
            queueID: queueID,
            rows: [TopOffenderRow(finding: finding(for: queueID, allocatedSize: allocatedSize))]
        )
    }

    private func finding(for queueID: ReviewQueueID, allocatedSize: Int64) -> Finding {
        let attributes: (category: String, safetyClass: SafetyClass, actionKind: ActionKind)
        switch queueID {
        case .safeMaintenance:
            attributes = ("Cache", .autoSafe, .deleteCache)
        case .quitAppFirst:
            attributes = ("Cache", .safeAfterCondition, .deleteCache)
        case .useNativeTool:
            attributes = ("Developer Tool", .reviewRequired, .nativeToolCommand)
        case .unknown:
            attributes = ("Unknown", .reviewRequired, .openGuidance)
        case .valuableHistory:
            attributes = ("Session History", .preserveByDefault, .openGuidance)
        case .personalAppAssets:
            attributes = ("Personal Assets", .neverTouch, .openGuidance)
        }
        return Finding(
            scopeName: "Fixture",
            path: "/Users/example/\(queueID.rawValue)",
            displayName: queueID.title,
            logicalSize: allocatedSize,
            allocatedSize: allocatedSize,
            isDirectory: true,
            safetyClass: attributes.safetyClass,
            actionKind: attributes.actionKind,
            ruleMatches: [RuleMatch(
                ruleID: "fixture.\(queueID.rawValue)",
                title: queueID.title,
                category: attributes.category,
                safetyClass: attributes.safetyClass,
                actionKind: attributes.actionKind,
                evidence: ["Fixture evidence"]
            )],
            evidence: [Evidence(kind: "fixture", message: "Fixture evidence")]
        )
    }
}
