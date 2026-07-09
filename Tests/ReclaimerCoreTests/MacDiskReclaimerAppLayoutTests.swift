import XCTest

final class MacDiskReclaimerAppLayoutTests: XCTestCase {
    func testDashboardNavigationUsesTypedSectionsAndSceneStorage() throws {
        let dashboardSource = try dashboardViewSource()
        let sectionSource = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardSection.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sectionSource.contains("enum DashboardSection: String, CaseIterable, Identifiable, Hashable"))
        XCTAssertTrue(sectionSource.contains("case summary = \"Summary\""))
        XCTAssertTrue(sectionSource.contains("case remoteTargets = \"RemoteTargets\""))
        XCTAssertTrue(sectionSource.contains("static func fromLegacyID(_ rawValue: String) -> DashboardSection"))
        XCTAssertTrue(dashboardSource.contains("@SceneStorage(\"dashboard.selectedSectionID\")"))
        XCTAssertFalse(dashboardSource.contains("@State private var selectedSection ="))
        XCTAssertFalse(dashboardSource.contains("selectedSection == \""))
    }

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

    func testDashboardRegistersSceneCommandsAndFocusedActions() throws {
        let source = try appSource()
        let commands = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardCommands.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(commands.contains("struct DashboardCommandActions"))
        XCTAssertTrue(commands.contains("FocusedValueKey"))
        XCTAssertTrue(commands.contains("struct DashboardCommands: Commands"))
        XCTAssertTrue(commands.contains("CommandMenu(\"Ryddi\")"))
        XCTAssertTrue(commands.contains("keyboardShortcut(\"r\""))
        XCTAssertTrue(commands.contains("keyboardShortcut(\"d\", modifiers: [.command, .option])"))
        XCTAssertTrue(source.contains(".commands {\n            DashboardCommands()\n        }"))
        XCTAssertTrue(source.contains(".focusedSceneValue(\\.dashboardCommandActions"))
    }

    func testDashboardSidebarUsesNativeSelectionAndKeepsDetailsOutOfSourceList() throws {
        let source = try appSource()
        let sidebar = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp/DashboardSidebarView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sidebar.contains("struct DashboardSidebarView: View"))
        XCTAssertTrue(sidebar.contains("List(selection:"))
        XCTAssertTrue(sidebar.contains(".listStyle(.sidebar)"))
        XCTAssertTrue(sidebar.contains(".tag(section)"))
        XCTAssertFalse(sidebar.contains("DisclosureGroup"))
        XCTAssertFalse(sidebar.contains("FindingRow("))
        XCTAssertFalse(source.contains("private func sidebarRow("))
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

    func testScanSessionAppSummaryPassesHistoryWarningsToActionCenter() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("listScanSessionsResult(limit: 1)"),
            "DashboardModel Summary should read scan-session history with typed warnings instead of ignoring corrupt audit files."
        )
        XCTAssertTrue(
            source.contains("sessionHistoryWarnings:") && source.contains(".warnings"),
            "DashboardModel actionCenterReport should pass scan-session history warnings into ActionCenterInput."
        )
        XCTAssertTrue(
            source.contains("latestScanSession: actionCenterScanSession,"),
            "The Summary should pass only the app's current loaded scan session as current evidence, so first-run users still get a primary Scan action."
        )
        XCTAssertFalse(
            source.contains("latestScanSession: actionCenterScanSession ?? scanSessionHistory.sessions.first"),
            "Saved audit history should provide warnings only; it must not suppress the primary Scan action when no scan is loaded in the app."
        )
    }

    func testAppSummaryPassesNativeReceiptsToActionCenter() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("recentNativeToolExecutionReceipts.first"),
            "DashboardModel Summary should pass the latest saved native command receipt into ActionCenterInput."
        )
        XCTAssertTrue(
            source.contains("latestNativeToolExecutionReceipt:"),
            "Action Center wiring should treat native command receipts as first-class saved evidence."
        )
    }

    func testAuditHistoryShowsNativeReceiptEvidenceFields() throws {
        let source = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp/AuditHistoryView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("receipt.command.command"))
        XCTAssertTrue(source.contains("receipt.findingPath"))
        XCTAssertTrue(source.contains("receipt.command.risk.label"))
        XCTAssertTrue(source.contains("receipt.nonClaims.first"))
        XCTAssertTrue(
            source.contains("receipt.mode == .perform, let after = receipt.afterFreeBytes"),
            "Native dry-run receipt rows should not show an After-free value that looks like reclaim happened."
        )
    }

    func testNativeCommandButtonsUseSavedPreviewGate() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("nativePerformBlockReason(receipt: nativeReceipt, command: command)"),
            "Native command detail rows should ask DashboardModel whether perform mode is currently allowed."
        )
        XCTAssertTrue(
            source.contains("NativeToolExecutor.performBlockReason(for: selection.command)"),
            "The app should use ReclaimerCore's explicit native perform allowlist check before showing Run."
        )
        XCTAssertTrue(
            source.contains("NativeToolExecutor.savedDryRunReceiptExists("),
            "The app should require saved native dry-run evidence before perform mode."
        )
        XCTAssertTrue(
            source.contains("Run requires a saved dry-run receipt"),
            "The blocked state should tell the user to create saved preview evidence first."
        )
    }

    func testActionCenterRoutesNativeReceiptReviewsToAuditHistory() throws {
        let guided = try String(
            contentsOf: repoRoot()
                .appendingPathComponent("Sources/MacDiskReclaimerApp/GuidedSummaryView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            guided.contains("native-tool-receipt.") && guided.contains("? \"Audit\" : \"Packages\""),
            "Action Center native receipt review actions should open Audit History, while native package guidance can still open Package Caches."
        )
    }

    func testScanSessionAppScanPersistsDurableSessionRecord() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("recordScanSession(updatedAt:"),
            "DashboardModel.scan() should keep recording the typed in-memory scan session."
        )
        XCTAssertTrue(
            source.contains("try AuditStore().saveScanSession(session)"),
            "DashboardModel.scan() should persist the typed ScanSession through AuditStore.saveScanSession(_:)."
        )
    }

    func testReviewQueueRowsShowTypedSessionAwareEvidence() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("modelRecordSelection(queue.queueID)") && source.contains("onSelect: { model.recordReviewSelection($0) }"),
            "Selecting a review queue should record a typed reviewed ScanSession transition."
        )
        XCTAssertTrue(
            source.contains("ReviewQueueRail(") && source.contains("ReviewQueueDecisionPanel("),
            "Review Queues should be organized as a queue rail plus selected-queue decision workspace."
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
            source.contains("Text(\"Next action\")") && source.contains("Label(\"Why blocked\""),
            "Review queue rows should label the next action and blocked reason explicitly."
        )
        XCTAssertTrue(
            source.contains("Label(\"Plan Eligible\"") && source.contains("Label(\"Dry Run\"") && source.contains("Label(\"Export\""),
            "The review workspace should expose preview-gated next actions without adding a destructive reclaim button."
        )
    }

    func testAppReviewUsesDecisionWorkspace() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("AppReviewWorkspace(") && source.contains("AppReviewGroupRail(") && source.contains("AppReviewDetailPanel("),
            "Apps & Leftovers should use an app-group rail plus selected app detail workspace instead of one long inline path list."
        )
        XCTAssertTrue(
            source.contains("AppReviewOptionStrip(") && source.contains("AppReviewSafetyStrip("),
            "The Apps review should expose scan options and safety boundaries before dense file details."
        )
        XCTAssertTrue(
            source.contains("Label(\"Preview Uninstall\", systemImage: \"doc.text.magnifyingglass\")"),
            "Uninstall should remain a preview/receipt-oriented action, not a destructive-looking primary trash action."
        )
        XCTAssertTrue(
            source.contains("Related files stay review-only"),
            "The Apps review must keep app support files framed as review-only unless a separate safe flow authorizes action."
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
        XCTAssertTrue(
            source.contains("Open Use Native Tool Review"),
            "The package preview lane should point users toward receipt-producing native dry-run review, not stop at command text."
        )
    }

    func testLargeOldReviewContentIsVerticallyScrollable() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("LargeOldReviewScrollContainer"),
            "Large & Old review can show many rows and should use a named vertical scroll container instead of clipping actions at compact heights."
        )
    }

    func testDryRunOwnsBusyStateThroughAutoPlan() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("buildPlanWithoutChangingWorkingState"),
            "runDryRun() should use an internal plan builder helper so auto-planning does not clear isWorking before execution finishes."
        )
        XCTAssertTrue(
            source.contains("if plan == nil {\n                await buildPlanWithoutChangingWorkingState()"),
            "runDryRun() should not call public buildPlan(), which toggles isWorking independently."
        )
        XCTAssertFalse(
            source.contains("if plan == nil {\n                await buildPlan()\n            }"),
            "Auto dry-run must not re-enable controls by calling buildPlan() inside runDryRun()."
        )
    }

    func testReclaimRefreshPreservesExecutedSessionState() throws {
        let source = try appSource()
        let helperStart = try XCTUnwrap(source.range(of: "private func refreshScanAfterReclaimPreservingExecutionSession"))
        let helperEnd = try XCTUnwrap(source[helperStart.lowerBound...].range(of: "\n    func exportEvidenceReport"))
        let helperSource = String(source[helperStart.lowerBound..<helperEnd.lowerBound])

        XCTAssertTrue(
            source.contains("refreshScanAfterReclaimPreservingExecutionSession"),
            "Post-reclaim refresh should not overwrite the executed session state shown by Summary."
        )
        XCTAssertFalse(
            helperSource.contains("recordScanSession"),
            "A successful reclaim should not replace the executed session with a plain scanned session immediately after receipt recording."
        )
    }

    func testAppPerformReclaimPassesCurrentScanSessionToExecutor() throws {
        let source = try appSource()
        let start = try XCTUnwrap(source.range(of: "func reclaimSelected() async"))
        let end = try XCTUnwrap(source[start.lowerBound...].range(of: "\n    func exportEvidenceReport"))
        let reclaimSource = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(
            reclaimSource.contains("let session = currentScanSession"),
            "The app perform path should capture the current ScanSession before hopping into the detached executor task."
        )
        XCTAssertTrue(
            reclaimSource.contains("ExecutorConfiguration(userPathPolicy: policy, currentScanSession: session)"),
            "The app perform path should pass the current ScanSession into ReclaimerExecutor just like dry-run does."
        )
        XCTAssertFalse(
            reclaimSource.contains("ExecutorConfiguration(userPathPolicy: policy)\n"),
            "Perform-mode reclaim must not drop the current ScanSession final gate."
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
            app.contains("case \"apps\", \"app-review\", \"apps-and-leftovers\":") && demo.contains("AppReviewReport("),
            "Screenshot demo mode should support the Apps & Leftovers cockpit with synthetic app review data."
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
        let appSourceDirectory = repoRoot().appendingPathComponent("Sources/MacDiskReclaimerApp")
        let swiftFiles = try FileManager.default.contentsOfDirectory(
            at: appSourceDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try swiftFiles.map {
            try String(contentsOf: $0, encoding: .utf8)
            }
        .joined(separator: "\n")
    }

    private func dashboardViewSource() throws -> String {
        let source = try appSource()
        let start = try XCTUnwrap(source.range(of: "struct DashboardView: View {"))
        let end = try XCTUnwrap(source.range(of: "\n}\n\nstruct OverviewView: View {"))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
