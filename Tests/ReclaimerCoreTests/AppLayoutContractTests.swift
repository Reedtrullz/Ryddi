import XCTest

final class AppLayoutContractTests: XCTestCase {
    func testSplitDashboardRetainsSmallWindowContainmentContracts() throws {
        let app = try source("MacDiskReclaimerApp.swift")
        let dashboard = try source("DashboardView.swift")
        let sidebar = try source("DashboardSidebarView.swift")
        let content = try source("DashboardContentViews.swift")
        let layout = try source("RyddiWindowLayout.swift")

        XCTAssertTrue(app.contains("RyddiWindowLayout.minimumContentWidth"))
        XCTAssertTrue(app.contains("RyddiWindowLayout.minimumContentHeight"))
        XCTAssertTrue(app.contains(".windowResizability(.contentMinSize)"))
        XCTAssertTrue(sidebar.contains(".navigationSplitViewColumnWidth(min:"))
        XCTAssertTrue(dashboard.contains("NavigationSplitView"))
        XCTAssertTrue(content.contains("struct OverviewView: View"))
        XCTAssertTrue(content.contains("ScrollView"))
        XCTAssertTrue(dashboard.contains(".toolbar"))
        XCTAssertTrue(dashboard.contains("Menu {"))
        XCTAssertTrue(layout.contains("GridItem(.adaptive(minimum:"))
        XCTAssertTrue(content.contains(".lineLimit("))
        XCTAssertTrue(content.contains(".truncationMode("))
    }

    private func source(_ filename: String) throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
