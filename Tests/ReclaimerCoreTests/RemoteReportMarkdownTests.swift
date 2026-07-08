import XCTest
@testable import ReclaimerCore

final class RemoteReportMarkdownTests: XCTestCase {
    func testRemoteReportBuilderEscapesMarkdownTableCells() throws {
        let finding = RemoteStorageFinding(
            remotePath: "/srv/private|client/cache\nwith-newline",
            displayPath: "/srv/private|client/cache\nwith-newline",
            bucket: "Remote|storage",
            allocatedBytes: 1_024,
            safetyClass: .reviewRequired,
            actionKind: .openGuidance,
            evidence: [Evidence(kind: "remote.fixture", message: "Fixture evidence.")],
            recommendedNextAction: .reviewInFinder
        )
        let report = RemoteScanReport(
            preset: .vpsGeneral,
            target: RemoteTargetReference(input: "prod-vps"),
            diskFilesystems: [],
            inodeFilesystems: [],
            findings: [finding],
            nativeGuidance: [],
            commands: [],
            nonClaims: ["No cleanup was executed by this report."]
        )

        let markdown = RemoteReportBuilder.build(report: report).markdown

        XCTAssertTrue(markdown.contains("Remote\\|storage"))
        XCTAssertTrue(markdown.contains("/srv/private\\|client/cache with-newline"))
        XCTAssertFalse(markdown.contains("/srv/private|client/cache\nwith-newline"))
    }
}
