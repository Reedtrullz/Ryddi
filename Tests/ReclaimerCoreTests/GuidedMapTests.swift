import XCTest
@testable import ReclaimerCore

final class GuidedMapTests: XCTestCase {
    func testBuildProducesDeterministicNonOverlappingAccounting() throws {
        let children = [
            finding(id: "child-a", path: "/scope/a", bytes: 60),
            finding(id: "child-b", path: "/scope/b", bytes: 30)
        ]
        let parent = finding(id: "parent", path: "/scope", bytes: 100, isDirectory: true)
        let drill = DiskDrillDownBuilder.build(
            findings: [parent] + children,
            scopes: [ScanScope(name: "Test", root: URL(fileURLWithPath: "/scope"))],
            childLimit: 8,
            generatedAt: Date(timeIntervalSince1970: 10)
        )
        let input = GuidedMapInput(
            scanID: "scan-1",
            capturedAt: Date(timeIntervalSince1970: 10),
            scopeDescription: "Test",
            coverage: coverage(.complete),
            diskStatus: diskStatus(total: 200, free: 100),
            drillDown: drill
        )

        let first = GuidedMapBuilder.build(input: input)
        let second = GuidedMapBuilder.build(input: input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.evidenceState, .complete)
        let parentNode = try XCTUnwrap(first.nodes.first { $0.path == "/scope" })
        let childrenTotal = first.nodes
            .filter { $0.parentID == parentNode.id }
            .reduce(Int64(0)) { $0 + $1.allocatedBytes }
        XCTAssertEqual(childrenTotal, parentNode.allocatedBytes)
        XCTAssertTrue(first.nodes.contains { $0.kind == .parentRemainder && $0.allocatedBytes == 10 })
    }

    func testDegradedCoverageShowsLimitedVisibilityWithoutActionState() {
        let drill = DiskDrillDownBuilder.build(
            findings: [finding(id: "one", path: "/scope/one", bytes: 20)],
            scopes: [],
            generatedAt: Date(timeIntervalSince1970: 20)
        )
        let map = GuidedMapBuilder.build(input: GuidedMapInput(
            scanID: "scan-2",
            capturedAt: Date(timeIntervalSince1970: 20),
            scopeDescription: "Limited test",
            coverage: coverage(.degraded),
            diskStatus: diskStatus(total: 100, free: 40),
            drillDown: drill
        ))

        XCTAssertEqual(map.evidenceState, .limited)
        XCTAssertEqual(map.measuredAllocatedBytes, 20)
        XCTAssertEqual(map.nodes.first { $0.kind == .limitedVisibility }?.allocatedBytes, 40)
    }

    func testSnapshotRoundTrips() throws {
        let drill = DiskDrillDownBuilder.build(
            findings: [finding(id: "one", path: "/scope/one", bytes: 20)],
            scopes: []
        )
        let map = GuidedMapBuilder.build(input: GuidedMapInput(
            scanID: "scan-3",
            capturedAt: Date(timeIntervalSince1970: 30),
            scopeDescription: "Round trip",
            coverage: coverage(.bounded),
            diskStatus: diskStatus(total: 100, free: 50),
            drillDown: drill
        ))
        XCTAssertEqual(try JSONDecoder().decode(GuidedMapSnapshot.self, from: JSONEncoder().encode(map)), map)
    }

    private func finding(id: String, path: String, bytes: Int64, isDirectory: Bool = false) -> Finding {
        Finding(
            id: id,
            scopeName: "Test",
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            logicalSize: bytes,
            allocatedSize: bytes,
            isDirectory: isDirectory,
            safetyClass: .reviewRequired,
            actionKind: .reportOnly,
            ruleMatches: [],
            evidence: []
        )
    }

    private func coverage(_ state: ScanCoverageState) -> ScanCoverage {
        ScanCoverage(
            state: state,
            requestedItemBudget: 100,
            measuredItemCount: 3,
            skippedItemCount: state == .complete ? 0 : 1,
            rootsVisited: 1,
            rootsDenied: state == .degraded ? 1 : 0,
            maximumMeasurementDepth: 3
        )
    }

    private func diskStatus(total: Int64, free: Int64) -> DiskStatusSnapshot {
        DiskStatusSnapshot(
            path: "/",
            volumeName: "Test disk",
            totalBytes: total,
            freeBytes: free,
            importantFreeBytes: free,
            availableBytes: free,
            pressure: .healthy,
            notes: []
        )
    }
}
