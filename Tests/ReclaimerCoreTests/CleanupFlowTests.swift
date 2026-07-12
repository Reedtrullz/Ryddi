import XCTest
@testable import ReclaimerCore

final class CleanupFlowTests: XCTestCase {
    func testQueueStagesSeparateCleanupFromProtectedReview() {
        XCTAssertEqual(ReviewQueueID.safeMaintenance.cleanupFlowStage, .safeCleanup)
        XCTAssertEqual(ReviewQueueID.quitAppFirst.cleanupFlowStage, .needsAction)
        XCTAssertEqual(ReviewQueueID.useNativeTool.cleanupFlowStage, .needsAction)
        XCTAssertEqual(ReviewQueueID.valuableHistory.cleanupFlowStage, .keepOrInspect)
        XCTAssertEqual(ReviewQueueID.personalAppAssets.cleanupFlowStage, .keepOrInspect)
        XCTAssertEqual(ReviewQueueID.unknown.cleanupFlowStage, .keepOrInspect)
    }

    func testPrecomputedQueueReportBuildsDetailWithoutFindingRescan() {
        let findings = (0..<24).map { index in
            Finding(
                scopeName: "Fixture",
                path: "/tmp/ryddi-cleanup-flow/cache-\(index)",
                displayName: "cache-\(index)",
                logicalSize: Int64(index + 1),
                allocatedSize: Int64(index + 1),
                isDirectory: true,
                isSymbolicLink: false,
                safetyClass: .autoSafe,
                actionKind: .deleteCache,
                ruleMatches: [],
                evidence: []
            )
        }
        let report = FindingAnalytics.reviewQueueReport(
            findings: findings,
            limitPerQueue: 20,
            now: Date(timeIntervalSince1970: 10)
        )

        let detail = report.detailReport(for: .safeMaintenance, limit: 8)

        XCTAssertEqual(detail.queueID, .safeMaintenance)
        XCTAssertEqual(detail.count, 24)
        XCTAssertEqual(detail.rowCount, 8)
        XCTAssertEqual(detail.rows.map(\.allocatedSize), Array((17...24).reversed()).map(Int64.init))
    }

    func testReviewSelectionReusesExistingFindingDigest() {
        let scanned = ScanSession(
            id: "session",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            appVersion: "0.3.0",
            ruleVersion: "rules",
            preset: .developer,
            scopeDigest: "scope",
            policyDigest: "policy",
            findingDigest: "already-computed",
            stage: .scanned
        )

        let reviewed = scanned.recordReviewSelection(updatedAt: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(reviewed.stage, .reviewed)
        XCTAssertEqual(reviewed.findingDigest, "already-computed")
    }
}
