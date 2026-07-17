import XCTest
import ReclaimerCore
@testable import MacDiskReclaimerApp

final class ExplorePresentationTests: XCTestCase {
    func testTypedFiltersMatchCategorySizeEvidenceAndSearch() {
        let snapshot = GuidedMapSnapshot(
            scanID: "scan",
            capturedAt: Date(),
            scopeDescription: "Test",
            volumeCapacityBytes: 10_000,
            volumeAvailableBytes: 1_000,
            measuredAllocatedBytes: 9_000,
            evidenceState: .complete,
            rootID: "root",
            nodes: [
                node("root", name: "Root", bytes: 9_000, category: .otherMeasured),
                node("app", name: "Large App", bytes: 6_000, category: .applications),
                node("cache", name: "Tiny Cache", bytes: 100, category: .caches)
            ]
        )
        var filter = ExploreFilter()
        filter.category = .applications
        filter.searchText = "large"
        XCTAssertEqual(filter.matchingIDs(in: snapshot), ["root", "app"])
        filter.minimumSize = .fiveGigabytes
        XCTAssertEqual(filter.matchingIDs(in: snapshot), ["root"])
    }

    private func node(
        _ id: String,
        name: String,
        bytes: Int64,
        category: GuidedMapCategory
    ) -> GuidedMapNode {
        GuidedMapNode(
            id: id,
            parentID: id == "root" ? nil : "root",
            path: "/\(id)",
            displayName: name,
            allocatedBytes: bytes,
            category: category,
            measurementState: .complete,
            kind: id == "root" ? .aggregate : .item,
            childIDs: []
        )
    }
}
