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

    func testSummaryUsesActionCenterReport() throws {
        let app = try appSource()
        let guided = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp/GuidedSummaryView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            app.contains("GuidedSummaryView("),
            "The Summary screen should render the Action Center before lower-priority detail panels."
        )
        XCTAssertTrue(
            app.contains("actionCenterReport"),
            "DashboardModel should expose the shared core ActionCenterReport instead of duplicating next-action logic in SwiftUI."
        )
        XCTAssertTrue(
            guided.contains("ActionCenterReport"),
            "The Summary view should consume ActionCenterReport from ReclaimerCore."
        )
        XCTAssertTrue(
            guided.contains("report.primaryAction"),
            "The Action Center Summary view should present one primary action from ReclaimerCore."
        )
        XCTAssertTrue(
            guided.contains("performActionCenterCommand"),
            "Action Center command routing should be explicit so primary actions cannot silently become inert."
        )
    }

    func testReviewQueueRowsShowTypedSessionAwareEvidence() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("model.recordReviewSelection(queue.queueID)"),
            "Selecting a review queue should record a typed reviewed ScanSession transition."
        )
        XCTAssertTrue(
            source.contains("reviewQueueNextAction"),
            "Review queue rows should derive next-action text from typed queue semantics."
        )
        XCTAssertTrue(
            source.contains("reviewQueueBlockedReason"),
            "Review queue rows should explain why Reclaim remains blocked for that queue."
        )
        XCTAssertTrue(
            source.contains("Text(\"Next action\")") && source.contains("Text(\"Why blocked\")"),
            "Review queue rows should label the next action and blocked reason explicitly."
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

    func testAgentRetentionShowsPlanPreviewLane() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("AgentRetentionPlanPreviewView("),
            "The AI Agent Storage retention report should show a preview plan lane, not only recommendations."
        )
        XCTAssertTrue(
            source.contains("AgentRetentionPlanBuilder.build"),
            "Agent retention planning should use ReclaimerCore plan-preview logic."
        )
    }

    func testScreenshotDemoModeIsExplicitAndRedacted() throws {
        let app = try appSource()
        let demo = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardDemoData.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            app.contains("RYDDI_SCREENSHOT_DEMO"),
            "Screenshot proof mode must be controlled by an explicit environment flag."
        )
        XCTAssertTrue(
            app.contains("RYDDI_SCREENSHOT_SECTION"),
            "Screenshot capture should be able to open stable sections without UI automation clicks."
        )
        XCTAssertTrue(
            demo.contains("/Users/ryddi-demo"),
            "Screenshot fixture paths should be synthetic and clearly non-local."
        )
        XCTAssertTrue(
            demo.contains("<path redacted>"),
            "Remote screenshot fixture should demonstrate redacted remote paths."
        )
        XCTAssertFalse(
            demo.contains("/Users/reidar"),
            "Screenshot fixture data must not embed the local user's real home path."
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
