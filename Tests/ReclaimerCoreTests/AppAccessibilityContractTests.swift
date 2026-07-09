import XCTest

final class AppAccessibilityContractTests: XCTestCase {
    func testRequiredAccessibilityIdentifiersExistInSplitAppSources() throws {
        let source = try appSource()
        let requiredIdentifiers = [
            "summary.primary-action",
            "summary.scan-button",
            "summary.plan-button",
            "summary.dry-run-button",
            "summary.reclaim-button",
            "permissions.open-full-disk-access",
            "review-queues.list",
            "remote-targets.probe-button",
            "remote-targets.scan-button",
            "remote-targets.export-redacted-button"
        ]

        for identifier in requiredIdentifiers {
            XCTAssertTrue(
                source.contains(".accessibilityIdentifier(\"\(identifier)\")"),
                "Missing stable app accessibility identifier: \(identifier)"
            )
        }
    }

    func testE2ELaunchContractIsTemporaryRootOnlyAndFailClosed() throws {
        let source = try appSource()

        XCTAssertTrue(source.contains("RYDDI_E2E_MODE"))
        XCTAssertTrue(source.contains("RYDDI_E2E_SCOPE_ROOT"))
        XCTAssertTrue(source.contains("FileManager.default.temporaryDirectory"))
        XCTAssertTrue(source.contains("resolvingSymlinksInPath"))
        XCTAssertTrue(source.contains("temporaryPath + \"/\""))
        for protectedPath in ["/", "/Users", "/Applications", "/Library", "/System"] {
            XCTAssertTrue(source.contains("\"\(protectedPath)\""), "Missing protected E2E root: \(protectedPath)")
        }
        XCTAssertTrue(source.contains("homeDirectoryForCurrentUser"))
        XCTAssertTrue(source.contains("e2eValidationError"))
        XCTAssertTrue(source.contains("configureE2EScope"))
        XCTAssertTrue(source.contains("if e2eScopeRoot != nil"))
        XCTAssertTrue(source.contains("if !DashboardLaunchOptions.isE2EModeRequested"))
        XCTAssertTrue(source.contains("return PermissionAdvisor.report(scopes: [])"))
    }

    private func appSource() throws -> String {
        let directory = repoRoot().appendingPathComponent("Sources/MacDiskReclaimerApp")
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
