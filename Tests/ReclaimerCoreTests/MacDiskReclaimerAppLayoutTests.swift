import XCTest

final class MacDiskReclaimerAppLayoutTests: XCTestCase {
    func testDashboardWindowUsesContentMinimumResizePolicy() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains(".windowResizability(.contentMinSize)"),
            "The main app window must respect DashboardView's minimum content size instead of allowing the sidebar/detail layout to collapse."
        )
        XCTAssertTrue(
            source.contains("RyddiWindowLayout.minimumContentWidth"),
            "The dashboard minimum width should be named and shared so future toolbar/layout edits keep the resize floor intentional."
        )
    }

    func testOverviewHasResponsiveSmallWindowContainment() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("DashboardResponsiveGrid.metricColumns"),
            "Metric cards should use adaptive columns so they wrap before forcing horizontal clipping."
        )
        XCTAssertTrue(
            source.contains("ViewThatFits(in: .horizontal)"),
            "Wide overview panel groups should degrade to stacked layouts before clipping."
        )
        XCTAssertTrue(
            source.contains("TopOffenderTableScrollContainer"),
            "The fixed-width offender rows should be wrapped in a reusable horizontally scrollable table container."
        )
    }

    func testSummaryUsesGuidedWorkflowPrimaryAction() throws {
        let app = try appSource()
        let guided = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp/GuidedSummaryView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            app.contains("GuidedSummaryView("),
            "The Summary screen should render the guided proof ladder before the row of secondary actions."
        )
        XCTAssertTrue(
            app.contains("guidedWorkflowReport"),
            "DashboardModel should expose the shared core workflow report instead of duplicating next-action logic in SwiftUI."
        )
        XCTAssertTrue(
            guided.contains("report.primaryAction"),
            "The guided Summary view should present one primary action from ReclaimerCore."
        )
        XCTAssertTrue(
            guided.contains("performGuidedAction"),
            "Guided action routing should be explicit so primary actions cannot silently become inert."
        )
    }

    func testPackageCacheReviewShowsPreviewLane() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("PackageReclaimLaneView("),
            "Package Cache Review should surface the native preview lane after a report is available."
        )
        XCTAssertTrue(
            source.contains("PackageReclaimLaneBuilder.build"),
            "The package preview lane should use ReclaimerCore instead of app-only command logic."
        )
    }

    private func appSource() throws -> String {
        try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift"),
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
