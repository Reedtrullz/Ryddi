import XCTest
@testable import ReclaimerCore

final class RedactionMatrixTests: XCTestCase {
    func testRemoteReportRedactsMatrixValuesAndEscapesMarkdownCells() throws {
        let report = sensitiveRemoteScanReport()
        let markdown = RemoteReportBuilder.build(
            report: report,
            privacy: ReportPrivacyOptions(pathStyle: .redacted, redactUserText: true)
        ).markdown

        assertRedacted(markdown)
        XCTAssertTrue(markdown.contains("<target redacted>"))
        XCTAssertTrue(markdown.contains("<host redacted>"))
        XCTAssertTrue(markdown.contains("<path redacted>"))
        XCTAssertTrue(markdown.contains("echo alpha\\|beta gamma"))
    }

    func testIssuePackageRedactsRemoteSummaryAndCommandPreviewLines() throws {
        let root = tempDirectory("redaction-audit")
        let output = tempDirectory("redaction-package")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let store = AuditStore(root: root)
        _ = try store.save(remoteScanReport: sensitiveRemoteScanReport())

        _ = try IssuePackageExporter.export(
            to: output,
            store: store,
            options: IssuePackageExportOptions(pathStyle: .redacted, includeLatestRemoteReport: true)
        )
        let packageText = try readPackageText(output)

        assertRedacted(packageText)
        XCTAssertTrue(packageText.contains("<target redacted>"))
        XCTAssertTrue(packageText.contains("<host redacted>"))
        XCTAssertTrue(packageText.contains("<path redacted>"))
    }

    private func sensitiveRemoteScanReport() -> RemoteScanReport {
        let target = RemoteTargetReference(
            input: "prod-racknerd",
            alias: "prod-racknerd",
            resolvedUser: "deploy",
            resolvedHost: "Racknerd.internal",
            resolvedPort: 22,
            knownHostsState: "known",
            fingerprint: "ssh-ed25519:fixture"
        )
        let commandCard = RemoteManualCommandCard(
            id: "fixture.command",
            title: "Inspect prod-cache",
            kind: .inspect,
            displayCommand: "echo alpha|beta\ngamma && docker inspect prod-cache",
            risk: .reviewRequired,
            explanation: "Review prod-cache before touching /srv/prod-app/releases/2026-01-01",
            prerequisites: ["Do not touch prod-cache until service impact is reviewed."],
            nonClaims: RemoteCommandCardBuilder.defaultNonClaims
        )
        return RemoteScanReport(
            id: "sensitive-scan",
            preset: .vpsGeneral,
            target: target,
            diskFilesystems: [
                RemoteFilesystemSummary(mount: "/home/deploy/private-home", filesystem: "/dev/vda1", usedBytes: 1_024, availableBytes: nil, capacityPercent: 80)
            ],
            inodeFilesystems: [],
            findings: [
                finding(path: "/home/deploy/private-home/cache", bucket: "Remote storage"),
                finding(path: "/srv/prod-app/releases/2026-01-01", bucket: "Old deploy releases"),
                finding(path: "docker://prod-cache", bucket: "Docker images")
            ],
            nativeGuidance: [
                RemoteNativeGuidance(
                    id: "deploy.review",
                    title: "Review prod deploy",
                    command: "ls -lah /srv/prod-app/releases/2026-01-01",
                    risk: "review",
                    summary: "Review Racknerd prod release directory."
                )
            ],
            commandCards: [commandCard],
            commands: [
                RemoteCommandResult(
                    commandID: "scan.df",
                    displayCommand: "ssh prod-racknerd df -Pk /home/deploy/private-home",
                    exitCode: 0,
                    timedOut: false,
                    stdoutPreview: ["prod-cache uses /srv/prod-app/releases/2026-01-01"],
                    stderrPreview: ["IdentityFile /Users/reidar/.ssh/id_ed25519 for Racknerd.internal"],
                    redactionApplied: false
                )
            ],
            nonClaims: RemoteScanReport.defaultNonClaims
        )
    }

    private func finding(path: String, bucket: String) -> RemoteStorageFinding {
        RemoteStorageFinding(
            remotePath: path,
            displayPath: path,
            bucket: bucket,
            allocatedBytes: 1_024,
            safetyClass: .reviewRequired,
            actionKind: .openGuidance,
            evidence: [Evidence(kind: "remote.fixture", message: "Fixture evidence.")],
            recommendedNextAction: .reviewInFinder
        )
    }

    private func assertRedacted(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for forbidden in [
            "/Users/reidar",
            "/home/deploy",
            "prod-racknerd",
            "Racknerd",
            "prod-cache",
            "/srv/prod-app/releases",
            "IdentityFile"
        ] {
            XCTAssertFalse(text.contains(forbidden), "leaked \(forbidden)", file: file, line: line)
        }
    }

    private func tempDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
    }

    private func readPackageText(_ output: URL) throws -> String {
        let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
        return try files
            .filter { $0.pathExtension == "json" || $0.pathExtension == "md" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
