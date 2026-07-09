import XCTest
@testable import ReclaimerCore

final class RemoteCommandCardTests: XCTestCase {
    func testJournaldFindingBuildsInspectAndManualVacuumCards() throws {
        let cards = RemoteCommandCardBuilder.build(for: [
            finding(bucket: "Journald logs", path: "/var/log/journal")
        ])

        XCTAssertTrue(cards.contains { $0.displayCommand == "journalctl --disk-usage" && $0.kind == .inspect })
        XCTAssertTrue(cards.contains { $0.displayCommand.contains("journalctl --vacuum-time=14d") && $0.kind == .manualCleanup })
        XCTAssertTrue(cards.allSatisfy { $0.nonClaims.contains { $0.contains("does not execute") } })
    }

    func testAPTCacheBuildsCleanAndAutoremoveDryRunCards() throws {
        let cards = RemoteCommandCardBuilder.build(for: [
            finding(bucket: "APT cache", path: "/var/cache/apt/archives")
        ])

        XCTAssertTrue(cards.contains { $0.displayCommand == "sudo apt-get clean" && $0.kind == .manualCleanup })
        XCTAssertTrue(cards.contains { $0.displayCommand == "sudo apt-get autoremove --dry-run" && $0.kind == .dryRun })
    }

    func testDockerImagesBuildInspectAndManualPruneCards() throws {
        let cards = RemoteCommandCardBuilder.build(for: [
            finding(bucket: "Docker images", path: "docker://images"),
            finding(bucket: "Docker build cache", path: "docker://build-cache")
        ])

        XCTAssertTrue(cards.contains { $0.displayCommand == "docker system df -v" && $0.kind == .inspect })
        XCTAssertTrue(cards.contains { $0.displayCommand == "docker system prune" && $0.kind == .manualCleanup })
    }

    func testDockerVolumesArePreserveReviewAndDoNotEmitPruneCard() throws {
        let cards = RemoteCommandCardBuilder.build(for: [
            finding(bucket: "Docker volumes", path: "docker://volumes", safety: .preserveByDefault, next: .protectByDefault)
        ])

        XCTAssertTrue(cards.contains { $0.displayCommand == "docker volume ls" && $0.kind == .preserveReview })
        XCTAssertFalse(cards.contains { $0.displayCommand.contains("prune") })
    }

    func testOldDeployReleasesBuildInspectOnlyCard() throws {
        let cards = RemoteCommandCardBuilder.build(for: [
            finding(bucket: "Old deploy releases", path: "/srv/app/releases/2026-01-01")
        ])

        XCTAssertTrue(cards.contains { $0.displayCommand.contains("find /opt /srv /var/www") && $0.kind == .inspect })
        XCTAssertFalse(cards.contains { $0.displayCommand.localizedCaseInsensitiveContains("rm ") })
        XCTAssertFalse(cards.contains { $0.displayCommand.localizedCaseInsensitiveContains("delete") })
    }

    func testRemoteScanReportDecodesOldAuditWithoutCommandCards() throws {
        let report = RemoteScanReport(
            preset: .vpsGeneral,
            target: RemoteTargetReference(input: "prod-vps"),
            diskFilesystems: [],
            inodeFilesystems: [],
            findings: [finding(bucket: "APT cache", path: "/var/cache/apt/archives")],
            nativeGuidance: [],
            commands: [],
            nonClaims: RemoteScanReport.defaultNonClaims
        )
        let encoded = try JSONEncoder().encode(report)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "commandCards")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(RemoteScanReport.self, from: legacyData)

        XCTAssertTrue(decoded.commandCards.contains { $0.displayCommand == "sudo apt-get clean" })
    }

    func testRemoteReportBuilderEscapesCommandCardMarkdownCells() throws {
        let card = RemoteManualCommandCard(
            id: "fixture",
            title: "Inspect | command",
            kind: .inspect,
            displayCommand: "printf 'a|b\nc'",
            risk: .reviewRequired,
            explanation: "Line one | line two\nline three",
            prerequisites: [],
            nonClaims: RemoteCommandCardBuilder.defaultNonClaims
        )
        let report = RemoteScanReport(
            preset: .vpsGeneral,
            target: RemoteTargetReference(input: "prod-vps"),
            diskFilesystems: [],
            inodeFilesystems: [],
            findings: [],
            nativeGuidance: [],
            commandCards: [card],
            commands: [],
            nonClaims: RemoteScanReport.defaultNonClaims
        )

        let markdown = RemoteReportBuilder.build(report: report).markdown

        XCTAssertTrue(markdown.contains("Inspect \\| command"))
        XCTAssertTrue(markdown.contains("printf 'a\\|b c'"))
        XCTAssertTrue(markdown.contains("Line one \\| line two line three"))
    }

    func testRemoteReportBuilderCanOmitCommandCards() throws {
        let report = RemoteScanReport(
            preset: .vpsGeneral,
            target: RemoteTargetReference(input: "prod-vps"),
            diskFilesystems: [],
            inodeFilesystems: [],
            findings: [finding(bucket: "Docker images", path: "docker://images")],
            nativeGuidance: [],
            commands: [],
            nonClaims: RemoteScanReport.defaultNonClaims
        )

        let markdown = RemoteReportBuilder.build(report: report, includeCommandCards: false).markdown

        XCTAssertFalse(markdown.contains("## Manual Command Cards"))
        XCTAssertFalse(markdown.contains("docker system prune"))
    }

    private func finding(
        bucket: String,
        path: String,
        safety: SafetyClass = .safeAfterCondition,
        next: ReviewNextAction = .useNativeTool
    ) -> RemoteStorageFinding {
        RemoteStorageFinding(
            remotePath: path,
            displayPath: path,
            bucket: bucket,
            allocatedBytes: 1_024,
            safetyClass: safety,
            actionKind: .nativeToolCommand,
            evidence: [Evidence(kind: "remote.fixture", message: "Fixture evidence.")],
            recommendedNextAction: next
        )
    }
}
