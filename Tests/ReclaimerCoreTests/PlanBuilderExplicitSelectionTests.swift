import XCTest
@testable import ReclaimerCore

final class PlanBuilderExplicitSelectionTests: XCTestCase {
    func testEmptySelectionDoesNotImplicitlySelectEverything() throws {
        let plan = try builder.buildPlan(
            from: [finding(id: "one", path: "/tmp/one")],
            selectedFindingIDs: []
        )
        XCTAssertFalse(plan.items.contains(where: \.selected))
    }

    func testOnlyExplicitEligibleFindingIsSelected() throws {
        let findings = [
            finding(id: "one", path: "/tmp/one"),
            finding(id: "two", path: "/tmp/two")
        ]
        let plan = try builder.buildPlan(from: findings, selectedFindingIDs: ["two"])
        XCTAssertEqual(plan.items.filter(\.selected).map(\.finding.id), ["two"])
    }

    func testUnknownSelectionFailsClosed() {
        XCTAssertThrowsError(
            try builder.buildPlan(
                from: [finding(id: "one", path: "/tmp/one")],
                selectedFindingIDs: ["missing"]
            )
        ) { error in
            XCTAssertEqual(error as? PlanSelectionError, .unknownFindingIDs(["missing"]))
        }
    }

    func testFullFindingContextStillRejectsNestedSelection() throws {
        let findings = [
            finding(id: "parent", path: "/tmp/parent", isDirectory: true),
            finding(id: "child", path: "/tmp/parent/child")
        ]
        let plan = try builder.buildPlan(
            from: findings,
            selectedFindingIDs: ["parent", "child"]
        )
        XCTAssertEqual(plan.items.filter(\.selected).count, 1)
    }

    private var builder: PlanBuilder {
        PlanBuilder(openFileChecker: NoOpenFilesChecker())
    }

    private func finding(id: String, path: String, isDirectory: Bool = false) -> Finding {
        Finding(
            id: id,
            scopeName: "Test",
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            logicalSize: 100,
            allocatedSize: 100,
            isDirectory: isDirectory,
            safetyClass: .autoSafe,
            actionKind: .trash,
            ruleMatches: [],
            evidence: []
        )
    }
}
