import XCTest

final class MacDiskReclaimerAppPermissionAccessTests: XCTestCase {
    func testSummaryTrustWarningOffersPermissionActions() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("onReviewPermissions"),
            "The Summary trust card should offer a direct jump to the Permissions page when coverage is degraded."
        )
        XCTAssertTrue(
            source.contains("Open Full Disk Access"),
            "The Summary trust card should expose the macOS Full Disk Access settings action next to the warning."
        )
        XCTAssertTrue(
            source.contains("PermissionAccessBanner"),
            "The Summary page should surface a visible access banner before users dig into detailed trust cards."
        )
    }

    func testPermissionsPageProvidesAccessHelperActions() throws {
        let source = try appSource()

        XCTAssertTrue(
            source.contains("PermissionAccessHelperPanel"),
            "The Permissions page should include a focused access helper panel."
        )
        XCTAssertTrue(
            source.contains("Reveal Ryddi"),
            "Users need an easy way to find the installed app when adding it to Full Disk Access."
        )
        XCTAssertTrue(
            source.contains("Copy App Path"),
            "Users should be able to copy the exact app path for manual permission troubleshooting."
        )
        XCTAssertTrue(
            source.contains("Refresh Coverage"),
            "Users should be able to re-check permission coverage after changing macOS settings."
        )
        XCTAssertTrue(
            source.contains("report.coverageSummary"),
            "Permission views should use the core summary that separates access problems from optional missing roots."
        )
        XCTAssertTrue(
            source.contains("Optional missing roots"),
            "Missing developer/tool roots should be labelled as optional instead of blended into Full Disk Access failures."
        )
        XCTAssertTrue(
            source.contains("blockingUnavailableScopes"),
            "The access helper should separate denied/unknown blockers from non-blocking missing paths."
        )
    }

    private func appSource() throws -> String {
        let appSourceDirectory = repoRoot().appendingPathComponent("Sources/MacDiskReclaimerApp")
        let swiftFiles = try FileManager.default.contentsOfDirectory(
            at: appSourceDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try swiftFiles.map {
            try String(contentsOf: $0, encoding: .utf8)
        }
        .joined(separator: "\n")
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
