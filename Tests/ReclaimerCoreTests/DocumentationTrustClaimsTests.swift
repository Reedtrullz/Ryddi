import XCTest

final class DocumentationTrustClaimsTests: XCTestCase {
    func testCurrentPublicDocsDescribeTheManualOnlyBoundaryPrecisely() throws {
        let root = repoRoot()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let features = try String(contentsOf: root.appendingPathComponent("FEATURES.md"), encoding: .utf8)
        let privacy = try String(contentsOf: root.appendingPathComponent("PRIVACY.md"), encoding: .utf8)
        let research = try String(contentsOf: root.appendingPathComponent("docs/COMPETITIVE_RESEARCH.md"), encoding: .utf8)

        XCTAssertTrue(readme.contains("Every `--output` export must name a new file in an existing directory"))
        XCTAssertTrue(features.contains("Ryddi refuses to overwrite or remove an existing schedule plist"))
        XCTAssertTrue(privacy.contains("Ryddi does not unload or remove a LaunchAgent plist automatically"))
        XCTAssertTrue(research.contains("Homebrew alone may execute after a fresh same-process preview"))
        XCTAssertFalse(research.contains("apps uninstall --dry-run/--yes can move"))
        XCTAssertFalse(research.contains("selected-app preview and app-bundle Trash execution"))
        XCTAssertFalse(privacy.contains("Remove the LaunchAgent from the app or CLI"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
