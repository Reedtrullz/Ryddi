import XCTest

final class AppAccessibilityContractTests: XCTestCase {
    func testRequiredAccessibilityIdentifiersExistInSplitAppSources() throws {
        let source = try appSource()
        let requiredIdentifiers = [
            "home.primary-action",
            "home.scan",
            "guided-map.breadcrumb",
            "guided-map.outline",
            "cleanup-review.select-safe",
            "cleanup-review.check-safely",
            "cleanup-review.move-to-trash",
            "scan-progress",
            "cancel-scan-button",
            "trash-confirmation.reviewed",
            "trash-confirmation.confirm",
            "trash-confirmation.cancel",
            "trash-execution.result",
            "permissions.open-full-disk-access",
            "review-queues.list",
            "remote-targets.probe-button",
            "remote-targets.scan-button",
            "remote-targets.export-redacted-button"
        ]

        for identifier in requiredIdentifiers {
            XCTAssertTrue(
                source.contains("\"\(identifier)\""),
                "Missing stable app accessibility identifier: \(identifier)"
            )
        }
    }

    func testE2ELaunchContractIsTemporaryRootOnlyAndFailClosed() throws {
        let source = try appSource()

        XCTAssertTrue(source.contains("RYDDI_E2E_MODE"))
        XCTAssertTrue(source.contains("RYDDI_E2E_SCOPE_ROOT"))
        XCTAssertTrue(source.contains("RYDDI_E2E_SCAN_DELAY_MILLISECONDS"))
        XCTAssertTrue(source.contains("(1...2_000).contains(value)"))
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
        XCTAssertTrue(source.contains("var permissionReport = PermissionAdvisor.report(scopes: [])"))
    }

    private func appSource() throws -> String {
        let directory = repoRoot().appendingPathComponent("Sources/MacDiskReclaimerApp")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        )
        return try enumerator.compactMap { $0 as? URL }
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
