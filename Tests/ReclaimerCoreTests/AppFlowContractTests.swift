import XCTest

final class AppFlowContractTests: XCTestCase {
    func testAccessibilityIDsCoverPrimaryCleanupFlow() throws {
        let source = try appSource(named: "AccessibilityIDs.swift")
        for identifier in [
            "dashboard-sidebar",
            "scan-button",
            "cleanup-flow",
            "cleanup-flow-status",
            "summary.plan-button",
            "summary.dry-run-button",
            "summary.reclaim-button",
            "trash-confirmation.reviewed",
            "trash-confirmation.confirm",
            "trash-confirmation.cancel",
            "trash-execution.result"
        ] {
            XCTAssertTrue(source.contains("\"\(identifier)\""), identifier)
        }
    }

    func testLayoutClassBoundariesAreStable() throws {
        let source = try appSource(named: "ResponsiveLayout.swift")
        XCTAssertTrue(source.contains("width < 820"))
        XCTAssertTrue(source.contains("width < 1_180"))
        XCTAssertTrue(source.contains("case compact"))
        XCTAssertTrue(source.contains("case regular"))
        XCTAssertTrue(source.contains("case wide"))
    }

    func testCompactToolbarKeepsScanOutsideOverflowMenu() throws {
        let source = try appSource(named: "DashboardView.swift")
        let toolbar = try XCTUnwrap(source.range(of: ".toolbar {"))
        let scan = try XCTUnwrap(source.range(of: "AccessibilityID.scan", range: toolbar.lowerBound..<source.endIndex))
        let menu = try XCTUnwrap(source.range(of: "Menu {", range: scan.lowerBound..<source.endIndex))
        XCTAssertLessThan(scan.lowerBound, menu.lowerBound)
        XCTAssertTrue(source.contains("if layoutClass == .compact"))
    }

    func testPackagedE2EScopeUsesFocusedSafetyMatrixRoots() throws {
        let source = try appSource(named: "DashboardModel.swift")
        for path in [
            "Library/Caches/Codex",
            "Library/Application Support/Google/Chrome/Default",
            ".codex/sessions",
            "Applications/Ryddi E2E Fixture.app",
            "Downloads"
        ] {
            XCTAssertTrue(source.contains("\"\(path)\""), path)
        }
        XCTAssertTrue(source.contains("Self.e2eScopes(root: e2eScopeRoot)"))
    }

    func testPackagedAXHarnessChecksResponsiveContainment() throws {
        let source = try String(
            contentsOf: repoRoot().appendingPathComponent("Tests/AppE2E/RyddiAXHarness.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("assertResponsiveContainment"))
        XCTAssertTrue(source.contains("elementOutsideWindow"))
        XCTAssertTrue(source.contains("dashboard-sidebar"))
        XCTAssertTrue(source.contains("cleanup-flow-status"))
        XCTAssertTrue(source.contains("responsiveChecks"))
    }

    private func appSource(named name: String) throws -> String {
        try String(
            contentsOf: repoRoot().appendingPathComponent("Sources/MacDiskReclaimerApp/\(name)"),
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
