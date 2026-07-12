import Foundation
import XCTest

final class SharedScanContractTests: XCTestCase {
    func testAppInjectsOneDashboardModelIntoWindowAndMenuBar() throws {
        let app = try source("Sources/MacDiskReclaimerApp/MacDiskReclaimerApp.swift")

        XCTAssertTrue(app.contains("@State private var appModel = RyddiAppModel()"))
        XCTAssertTrue(app.contains("DashboardView(model: appModel.dashboard)"))
        XCTAssertTrue(app.contains("StatusMenuView(model: appModel.dashboard"))
    }

    func testMenuBarDoesNotOwnIndependentScannerOrScopeDefaults() throws {
        let status = try source("Sources/MacDiskReclaimerApp/StatusMenuView.swift")

        XCTAssertFalse(status.contains("final class StatusMenuModel"))
        XCTAssertFalse(status.contains("FileScanner("))
        XCTAssertFalse(status.contains("DefaultScopes.scopes"))
        XCTAssertTrue(status.contains("await scanAction()"))
        XCTAssertTrue(status.contains("Open Ryddi to review"))
    }

    func testAppModelRoutesMenuScanThroughSharedDashboard() throws {
        let appModel = try source("Sources/MacDiskReclaimerApp/RyddiAppModel.swift")

        XCTAssertTrue(appModel.contains("let dashboard: DashboardModel"))
        XCTAssertTrue(appModel.contains("func scanFromMenuBar() async"))
        XCTAssertTrue(appModel.contains("await dashboard.scan()"))
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
