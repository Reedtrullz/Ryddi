import XCTest
import ReclaimerCore
@testable import MacDiskReclaimerApp

@MainActor
final class HomeJourneyTests: XCTestCase {
    func testReviewStartsEmptyAndSelectionRequiresExplicitToggle() {
        let model = DashboardModel(dependencies: .testing(
            scanService: EmptyScanService(),
            guidedMapStore: MemoryGuidedMapStore()
        ))
        model.findings = [finding("one"), finding("two")]

        XCTAssertTrue(model.reviewSelectionIDs.isEmpty)
        model.toggleReviewSelection("one")
        XCTAssertEqual(model.reviewSelectionIDs, ["one"])
        model.toggleReviewSelection("one")
        XCTAssertTrue(model.reviewSelectionIDs.isEmpty)
    }

    func testScopedReviewStartsAndEndsEmptyAndRejectsHiddenFindings() async {
        let model = DashboardModel(dependencies: .testing(
            scanService: EmptyScanService(),
            guidedMapStore: MemoryGuidedMapStore()
        ))
        model.findings = [finding("visible"), finding("hidden")]
        model.reviewSelectionIDs = ["visible", "hidden"]

        model.beginReviewSession(visibleFindingIDs: ["visible"])

        XCTAssertTrue(model.reviewSelectionIDs.isEmpty)

        model.toggleReviewSelection("hidden")
        XCTAssertTrue(model.reviewSelectionIDs.isEmpty)

        model.toggleReviewSelection("visible")
        XCTAssertEqual(model.reviewSelectionIDs, ["visible"])

        await model.selectSafeMaintenance(among: ["visible"])

        XCTAssertTrue(model.reviewSelectionIDs.isSubset(of: ["visible"]))
        XCTAssertFalse(model.reviewSelectionIDs.contains("hidden"))

        model.endReviewSession()

        XCTAssertTrue(model.reviewSelectionIDs.isEmpty)
        XCTAssertNil(model.reviewScopeFindingIDs)
    }

    func testPresentationRefreshPreservesLatestGuidedMap() async {
        let model = DashboardModel(dependencies: .testing(
            scanService: EmptyScanService(),
            guidedMapStore: MemoryGuidedMapStore()
        ))
        let map = GuidedMapSnapshot(
            scanID: "refresh-map",
            capturedAt: Date(timeIntervalSince1970: 1),
            scopeDescription: "Test",
            volumeCapacityBytes: 100,
            volumeAvailableBytes: 50,
            measuredAllocatedBytes: 50,
            evidenceState: .complete,
            rootID: "root",
            nodes: []
        )
        model.latestGuidedMap = map

        await model.refreshPresentationSnapshot()

        XCTAssertEqual(model.presentationSnapshot?.guidedMap, map)
    }

    func testMapSelectionContractContainsNoCleanupAuthority() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("Sources/MacDiskReclaimerApp/GuidedMap")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let source = try files
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertFalse(source.contains("PlanBuilder"))
        XCTAssertFalse(source.contains("prepareTrashExecution"))
        XCTAssertFalse(source.contains("buildPlan"))

        let breadcrumb = try String(
            contentsOf: root
                .appendingPathComponent("Sources/MacDiskReclaimerApp/GuidedMap/GuidedMapBreadcrumbView.swift"),
            encoding: .utf8
        )
        let outline = try String(
            contentsOf: root
                .appendingPathComponent("Sources/MacDiskReclaimerApp/GuidedMap/GuidedMapOutlineView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(breadcrumb.contains("ScrollView(.horizontal)"))
        XCTAssertTrue(outline.contains("GuidedMapBreadcrumbView"))
        XCTAssertTrue(outline.contains("Show contents of \\(node.displayName)"))
    }

    private func finding(_ id: String) -> Finding {
        Finding(
            id: id,
            scopeName: "Test",
            path: "/tmp/\(id)",
            displayName: id,
            logicalSize: 100,
            allocatedSize: 100,
            isDirectory: false,
            safetyClass: .autoSafe,
            actionKind: .trash,
            ruleMatches: [],
            evidence: []
        )
    }
}

private struct EmptyScanService: ScanServicing {
    func scanWithCoverage(
        scopes: [ScanScope],
        options: ScanOptions,
        control: ScanControl
    ) -> ScanResult {
        ScanResult(
            findings: [],
            coverage: ScanCoverage(
                state: .complete,
                requestedItemBudget: 0,
                measuredItemCount: 0,
                skippedItemCount: 0,
                rootsVisited: 0,
                rootsDenied: 0,
                maximumMeasurementDepth: 0
            )
        )
    }
}

private final class MemoryGuidedMapStore: GuidedMapPersisting, @unchecked Sendable {
    var snapshot: GuidedMapSnapshot?
    func loadLatest() -> GuidedMapSnapshot? { snapshot }
    func save(_ snapshot: GuidedMapSnapshot) throws { self.snapshot = snapshot }
}
