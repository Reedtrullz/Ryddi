import XCTest
@testable import MacDiskReclaimerApp

final class DashboardNavigationTests: XCTestCase {
    func testRegularUserNavigationHasExactlyThreeDestinations() {
        XCTAssertEqual(DashboardPrimaryDestination.allCases, [.home, .explore, .history])
    }

    func testLegacyDestinationsMigrateDeterministically() {
        XCTAssertEqual(DashboardPrimaryDestination.restoring("Summary"), .home)
        XCTAssertEqual(DashboardPrimaryDestination.restoring("Apps"), .explore)
        XCTAssertEqual(DashboardPrimaryDestination.restoring("Audit"), .history)
        XCTAssertEqual(DashboardPrimaryDestination.restoring("unknown"), .home)
    }
}
