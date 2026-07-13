import XCTest
@testable import ReclaimerCore

final class PermissionCoverageTransitionTests: XCTestCase {
    func testRefreshTransitionsFromDegradedToCompleteUsingCurrentProbe() {
        let previous = report(readable: 1, denied: 1)
        let current = report(readable: 2, denied: 0)
        var reporterCalls = 0

        let transition = PermissionCoverageTransition.refresh(previous: previous, scopes: []) { _ in
            reporterCalls += 1
            return current
        }

        XCTAssertEqual(reporterCalls, 1)
        XCTAssertEqual(transition.previous.coverageLevel, .degraded)
        XCTAssertEqual(transition.current.coverageLevel, .complete)
        XCTAssertTrue(transition.coverageChanged)
    }

    func testRefreshTransitionsFromCompleteToDegradedAndDetectsCountChanges() {
        let previous = report(readable: 2, denied: 0)
        let current = report(readable: 1, denied: 1)

        let transition = PermissionCoverageTransition.refresh(previous: previous, scopes: []) { _ in current }

        XCTAssertEqual(transition.current.deniedCount, 1)
        XCTAssertEqual(transition.current.coverageLevel, .degraded)
        XCTAssertTrue(transition.coverageChanged)
    }

    func testRefreshWithEquivalentEvidenceIsStable() {
        let report = report(readable: 2, denied: 0)
        let transition = PermissionCoverageTransition.refresh(previous: report, scopes: []) { _ in report }

        XCTAssertFalse(transition.coverageChanged)
    }

    private func report(readable: Int, denied: Int) -> PermissionAdvisorReport {
        PermissionAdvisorReport(
            coverageLevel: denied == 0 ? .complete : .degraded,
            readableCount: readable,
            deniedCount: denied,
            missingCount: 0,
            unknownCount: 0,
            totalCount: readable + denied,
            readableFraction: Double(readable) / Double(max(1, readable + denied)),
            scopeSummaries: [],
            recommendedActions: [],
            nonClaims: []
        )
    }
}
