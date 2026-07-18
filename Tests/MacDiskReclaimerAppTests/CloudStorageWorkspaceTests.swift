import Foundation
import XCTest
@testable import MacDiskReclaimerApp
import RyddiProtectCore

@MainActor
final class CloudStorageWorkspaceTests: XCTestCase {
    func testDashboardRequiresConfirmationBeforeLocalInventoryAndClearsItOnUnconfirm() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("MEGA", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 4_096).write(to: root.appendingPathComponent("local.bin"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
        let candidate = try XCTUnwrap(
            CloudStorageRootDiscovery()
                .discover(userSelectedMegaRoots: [root])
                .candidates
                .first(where: { $0.url == root.standardizedFileURL })
        )
        let model = DashboardModel()

        await model.scanConfirmedCloudStorageRoot(candidate)
        XCTAssertNil(model.cloudLocalInventoryReports[candidate.id])
        XCTAssertTrue(model.error?.contains("Confirm") == true)

        model.confirmCloudStorageRoot(candidate)
        XCTAssertNotNil(model.confirmedCloudStorageRoots[candidate.id])
        await model.scanConfirmedCloudStorageRoot(candidate)
        XCTAssertEqual(model.cloudLocalInventoryReports[candidate.id]?.fileCount, 1)
        XCTAssertNil(model.error)

        model.unconfirmCloudStorageRoot(candidate)
        XCTAssertNil(model.confirmedCloudStorageRoots[candidate.id])
        XCTAssertNil(model.cloudLocalInventoryReports[candidate.id])

        model.selectedMegaCloudRoots = [root]
        model.cloudStorageRootDiscovery = CloudStorageRootDiscoveryReport(
            cloudStorageContainer: root.deletingLastPathComponent(),
            candidates: [candidate],
            rejectedSymlinks: [],
            unreadableRoots: [],
            nonClaims: []
        )
        model.forgetSelectedMegaCloudRoot(candidate)
        XCTAssertTrue(model.selectedMegaCloudRoots.isEmpty)
        XCTAssertTrue(model.cloudStorageRootDiscovery?.candidates.isEmpty == true)
    }
}
