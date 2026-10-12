import XCTest
@testable import ReclaimerCore

final class LogicalStorageEstimateTests: XCTestCase {
    private func rec(_ path: String, _ bytes: Int64, safe: Bool = false) -> ReclaimRecommendation {
        ReclaimRecommendation(path: path, category: .dependencyCache, reclaimableBytes: bytes,
                              safetyScore: safe ? 0.9 : 0.5, effortScore: 1, description: "Fixture",
                              action: safe ? .moveToTrash : .reviewRequired)
    }
    private func report(_ recs: [ReclaimRecommendation], complete: Bool = true) -> AuditReport {
        AuditReport(scannedPaths: ["/fixture"], recommendations: recs,
                    coverage: [ScanCoverage(path: "/fixture", status: complete ? .complete : .partial)])
    }
    func testNestedAndDuplicateFindingsRetainedWithoutAddingTheirBytes() {
        let recs = [rec("/fixture/cache", 100), rec("/fixture/cache/nested", 70),
                    rec("/fixture/cache/nested/file", 30), rec("/fixture/cache/nested/file", 30),
                    rec("/fixture/cache-other", 40)]
        let r = report(recs)
        XCTAssertEqual(r.storageEstimate.logicalBytes, 140)
        XCTAssertEqual(r.needsReviewBytes, 140)
        XCTAssertEqual(r.recommendations, recs)
        XCTAssertEqual(report(recs.reversed()).totalBytes, 140)
    }
    func testSmallParentSamePathAndDotComponentsDoNotHideDescendantEvidence() {
        let r = report([rec("/fixture/cache", 10), rec("/fixture/cache/a", 30),
                        rec("/fixture/cache/b", 40), rec("/fixture/cache/./a", 50)])
        XCTAssertEqual(r.totalBytes, 90)
    }
    func testEligibleSelectionAndReviewSubtotalsAreNotAdded() {
        let safe = rec("/fixture/cache/a", 40, safe: true), review = rec("/fixture/cache", 100)
        let r = report([safe, review])
        XCTAssertEqual(r.totalBytes, 100)
        XCTAssertEqual(r.safeToReclaimBytes, 40)
        XCTAssertEqual(r.needsReviewBytes, 100)
        XCTAssertEqual(r.selectedLogicalBytes(ids: [safe.id, review.id]), 40)
        XCTAssertEqual(report([safe, review], complete: false).selectedLogicalBytes(ids: [safe.id]), 0)
        XCTAssertEqual(report([safe], complete: false).reclaimableBytes, 0)
    }
    func testOverflowCapsAndNegativeInputsDoNotWrap() {
        let r = report([rec("/fixture/a", Int64.max), rec("/fixture/b", 1), rec("/fixture/c", -10)])
        XCTAssertEqual(r.totalBytes, Int64.max)
        XCTAssertTrue(r.storageEstimate.saturated)
    }
    func testJSONAndTextExplicitlySeparateLogicalFromUnknownPhysicalAllocation() throws {
        let r = report([rec("/fixture/cache", 100)])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: AuditReportFormatter.json(report: r)) as? [String: Any])
        let estimate = try XCTUnwrap(json["storageEstimate"] as? [String: Any])
        XCTAssertEqual(estimate["basis"] as? String, "logical-path-union-estimate")
        XCTAssertTrue(estimate["allocatedBytes"] is NSNull)
        XCTAssertTrue(estimate["physicalReclaimedBytes"] is NSNull)
        let text = AuditReportFormatter.plainText(report: r)
        for term in ["logical", "hardlinks", "clones", "cloud placeholders", "Trash retains", "do not add"] {
            XCTAssertTrue(text.contains(term), term)
        }
        XCTAssertFalse(text.contains("Safe to reclaim now"))
    }
    func testLegacyInflatedNumericTotalsAreRecomputedAndCoverageStaysFailClosed() throws {
        let r = report([rec("/fixture/cache", 100), rec("/fixture/cache/a", 50)])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: AuditReportFormatter.json(report: r)) as? [String: Any])
        json["totalBytes"] = 999; json["bloatBytes"] = 999; json["reclaimableBytes"] = 999
        json.removeValue(forKey: "storageEstimate"); json.removeValue(forKey: "coverage")
        let legacy = try JSONDecoder().decode(AuditReport.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.totalBytes, 100)
        XCTAssertEqual(legacy.reclaimableBytes, 0)
        XCTAssertFalse(legacy.hasCompleteCoverage)
        XCTAssertEqual(legacy.recommendations.count, 2)
    }
}
