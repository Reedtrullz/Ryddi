import XCTest
@testable import ReclaimerCore

final class TrashConfirmationModelTests: XCTestCase {
    func testConfirmationListsSelectedItemsConditionsAndNonClaims() {
        let finding = Finding(
            scopeName: "Fixture",
            path: "/Users/example/Library/Caches/Codex/cache.bin",
            displayName: "cache.bin",
            logicalSize: 40,
            allocatedSize: 64,
            isDirectory: false,
            safetyClass: .autoSafe,
            actionKind: .trash,
            ruleMatches: [],
            evidence: []
        )
        let plan = ReclaimPlan(
            mode: PlanMode.autoSafeOnly.rawValue,
            items: [ReclaimPlanItem(
                finding: finding,
                selected: true,
                proposedAction: .trash,
                conditions: [PlanCondition(kind: .openFileClear, message: "No open handles", isSatisfied: true)],
                estimatedImmediateReclaim: 64
            )],
            dryRunSummary: []
        )

        let model = TrashConfirmationModel.build(
            plan: plan,
            pathStyle: .homeRelative,
            homeDirectory: URL(fileURLWithPath: "/Users/example")
        )

        XCTAssertEqual(model.itemCount, 1)
        XCTAssertEqual(model.totalAllocatedBytes, 64)
        XCTAssertEqual(model.items.first?.displayPath, "~/Library/Caches/Codex/cache.bin")
        XCTAssertEqual(model.items.first?.conditions, ["No open handles"])
        XCTAssertTrue(model.nonClaims.contains { $0.localizedCaseInsensitiveContains("does not immediately") })
        XCTAssertTrue(model.nonClaims.contains { $0.localizedCaseInsensitiveContains("final checks") })
        XCTAssertTrue(model.nonClaims.contains { $0.localizedCaseInsensitiveContains("atomic") })
    }
}
