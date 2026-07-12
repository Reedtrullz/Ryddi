import XCTest
@testable import ReclaimerCore

final class RemoteCoverageTests: XCTestCase {
    func testAllFailedCommandsCreateUnreachableCoverage() throws {
        let commands = [
            RemoteCoverageFixtures.command(
                id: "scan.df",
                exitCode: 255,
                timedOut: false,
                stderr: ["ssh: Could not resolve hostname"]
            )
        ]

        let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: nil)

        XCTAssertEqual(coverage.level, .unreachable)
        XCTAssertEqual(coverage.successfulCommandIDs, [])
        XCTAssertEqual(coverage.failedCommandIDs, ["scan.df"])
        XCTAssertTrue(coverage.explanation.localizedCaseInsensitiveContains("unreachable"))
    }

    func testMissingCommandReceiptsCreatePartialUnknownCoverage() throws {
        let coverage = RemoteScanCoverageBuilder.build(commands: [], osSummary: nil)

        XCTAssertEqual(coverage.level, .partial)
        XCTAssertEqual(coverage.successfulCommandIDs, [])
        XCTAssertTrue(coverage.explanation.localizedCaseInsensitiveContains("cannot be proven"))
    }

    func testMixedCommandResultsCreatePartialCoverage() throws {
        let commands = [
            RemoteCoverageFixtures.command(
                id: "scan.df",
                exitCode: 0,
                timedOut: false,
                stdout: ["Filesystem 1024-blocks Used Available Capacity Mounted on"]
            ),
            RemoteCoverageFixtures.command(
                id: "scan.docker-df",
                exitCode: 1,
                timedOut: false,
                stderr: ["permission denied"]
            )
        ]

        let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: "Linux")

        XCTAssertEqual(coverage.level, .partial)
        XCTAssertEqual(coverage.successfulCommandIDs, ["scan.df"])
        XCTAssertEqual(coverage.failedCommandIDs, ["scan.docker-df"])
        XCTAssertEqual(coverage.permissionDeniedCommandIDs, ["scan.docker-df"])
    }

    func testSuccessfulCoreCommandsCreateCompleteCoverage() throws {
        let commands = [
            RemoteCoverageFixtures.command(id: "scan.df", exitCode: 0, timedOut: false),
            RemoteCoverageFixtures.command(id: "scan.inodes", exitCode: 0, timedOut: false),
            RemoteCoverageFixtures.command(id: "scan.du", exitCode: 0, timedOut: false)
        ]

        let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: "Linux")

        XCTAssertEqual(coverage.level, .complete)
        XCTAssertEqual(coverage.failedCommandIDs, [])
    }

    func testRespondingNonLinuxTargetCreatesUnsupportedCoverage() throws {
        let commands = [
            RemoteCoverageFixtures.command(id: "scan.df", exitCode: 0, timedOut: false)
        ]

        let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: "Darwin 25.0 arm64")

        XCTAssertEqual(coverage.level, .unsupported)
        XCTAssertTrue(coverage.explanation.localizedCaseInsensitiveContains("linux"))
        XCTAssertEqual(coverage.row("Linux detected")?.status, .failed)
    }

    func testHostKeyMissingCreatesCoverageWarningRow() throws {
        let commands = [
            RemoteCoverageFixtures.command(id: "scan.df", exitCode: 0, timedOut: false)
        ]
        let target = RemoteTargetReference(input: "prod-vps", knownHostsState: "missing")

        let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: "Linux", target: target)

        XCTAssertEqual(coverage.row("Host key verified")?.status, .warning)
        XCTAssertTrue(coverage.row("Host key verified")?.detail.contains("StrictHostKeyChecking=yes") == true)
    }

    func testSSHTimeoutCreatesFailedConnectedRow() throws {
        let commands = [
            RemoteCoverageFixtures.command(id: "scan.df", exitCode: nil, timedOut: true)
        ]

        let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: nil)

        XCTAssertEqual(coverage.level, .unreachable)
        XCTAssertEqual(coverage.timedOutCommandIDs, ["scan.df"])
        XCTAssertEqual(coverage.row("Connected")?.status, .failed)
        XCTAssertTrue(coverage.row("Connected")?.detail.localizedCaseInsensitiveContains("timed out") == true)
    }

    func testPermissionDeniedCreatesWarningCoverageRow() throws {
        let commands = [
            RemoteCoverageFixtures.command(
                id: "scan.docker-df",
                exitCode: 1,
                timedOut: false,
                stderr: ["permission denied while connecting to Docker socket"]
            )
        ]

        let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: "Linux")

        XCTAssertEqual(coverage.permissionDeniedCommandIDs, ["scan.docker-df"])
        XCTAssertEqual(coverage.row("Docker inventory readable")?.status, .warning)
        XCTAssertTrue(coverage.row("Docker inventory readable")?.detail.localizedCaseInsensitiveContains("permissions") == true)
    }

    func testUnavailableDockerAndJournaldCreateWarningRows() throws {
        let commands = [
            RemoteCoverageFixtures.command(
                id: "scan.docker-df",
                exitCode: 127,
                timedOut: false,
                stderr: ["docker: command not found"]
            ),
            RemoteCoverageFixtures.command(
                id: "scan.journal",
                exitCode: 127,
                timedOut: false,
                stderr: ["journalctl: command not found"]
            ),
            RemoteCoverageFixtures.command(
                id: "scan.apt",
                exitCode: 127,
                timedOut: false,
                stderr: ["du: cannot access '/var/cache/apt/archives': No such file or directory"]
            )
        ]

        let coverage = RemoteScanCoverageBuilder.build(commands: commands, osSummary: "Linux")

        XCTAssertEqual(coverage.row("Docker inventory readable")?.status, .warning)
        XCTAssertEqual(coverage.row("Journald readable")?.status, .warning)
        XCTAssertEqual(coverage.row("Apt cache readable")?.status, .warning)
    }

    func testRemoteScanReportDecodesOldAuditWithoutCoverage() throws {
        let json = """
        {
          "id": "legacy-scan",
          "createdAt": "2026-07-08T12:00:00Z",
          "preset": "vps-general",
          "target": {
            "id": "prod-vps",
            "input": "prod-vps",
            "alias": "prod-vps",
            "resolvedUser": "deploy",
            "resolvedHost": "203.0.113.10",
            "resolvedPort": 22,
            "knownHostsState": "known",
            "fingerprint": "ssh-ed25519:fixture"
          },
          "diskFilesystems": [],
          "inodeFilesystems": [],
          "findings": [],
          "nativeGuidance": [],
          "commands": [
            {
              "commandID": "scan.df",
              "displayCommand": "ssh prod-vps df -Pk",
              "exitCode": 0,
              "timedOut": false,
              "stdoutPreview": [],
              "stderrPreview": [],
              "redactionApplied": false
            }
          ],
          "nonClaims": ["No cleanup was executed on the remote target."]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(RemoteScanReport.self, from: Data(json.utf8))

        XCTAssertEqual(report.id, "legacy-scan")
        XCTAssertEqual(report.coverage.level, .complete)
        XCTAssertEqual(report.continuityWarnings, [])
    }

    func testRemoteReportBuilderShowsCoverageAndContinuityWarnings() throws {
        let report = RemoteScanReport(
            preset: .vpsGeneral,
            target: RemoteTargetReference(input: "prod-vps", alias: "prod-vps"),
            diskFilesystems: [],
            inodeFilesystems: [],
            findings: [],
            nativeGuidance: [],
            commands: [
                RemoteCoverageFixtures.command(id: "scan.df", exitCode: 255, timedOut: false)
            ],
            coverage: RemoteScanCoverage(
                level: .unreachable,
                successfulCommandIDs: [],
                failedCommandIDs: ["scan.df"],
                timedOutCommandIDs: [],
                permissionDeniedCommandIDs: [],
                explanation: "The target was unreachable or all evidence commands failed."
            ),
            continuityWarnings: [
                RemoteTargetContinuityWarning(
                    field: "fingerprint",
                    previousValue: "ssh-ed25519:old",
                    currentValue: "ssh-ed25519:new",
                    severity: "warning"
                )
            ],
            nonClaims: RemoteScanReport.defaultNonClaims
        )

        let markdown = RemoteReportBuilder.build(report: report).markdown

        XCTAssertTrue(markdown.contains("## Coverage"))
        XCTAssertTrue(markdown.contains("- Level: unreachable"))
        XCTAssertTrue(markdown.contains("| Check | Status | Detail |"))
        XCTAssertTrue(markdown.contains("## Target Continuity"))
        XCTAssertTrue(markdown.contains("fingerprint"))
    }

    func testTargetContinuityWarnsWhenConcreteIdentityChanges() throws {
        let previous = RemoteTargetReference(
            input: "prod-vps",
            alias: "prod-vps",
            resolvedUser: "deploy",
            resolvedHost: "203.0.113.10",
            resolvedPort: 22,
            knownHostsState: "known",
            fingerprint: "ssh-ed25519:old"
        )
        let current = RemoteTargetReference(
            input: "prod-vps",
            alias: "prod-vps",
            resolvedUser: "root",
            resolvedHost: "203.0.113.11",
            resolvedPort: 2222,
            knownHostsState: "known",
            fingerprint: "ssh-ed25519:new"
        )

        let warnings = RemoteTargetContinuity.warnings(previous: previous, current: current)

        XCTAssertEqual(warnings.map(\.field), ["host", "user", "port", "fingerprint"])
        XCTAssertTrue(warnings.allSatisfy { $0.severity == "warning" })
    }

    func testAuditStorePreviousRemoteScanSkipsUnreachableReports() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-remote-coverage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AuditStore(root: root)
        let target = RemoteTargetReference(
            input: "prod-vps",
            alias: "prod-vps",
            resolvedUser: "deploy",
            resolvedHost: "203.0.113.10",
            resolvedPort: 22,
            knownHostsState: "known",
            fingerprint: "ssh-ed25519:fixture"
        )

        let reachableOld = RemoteCoverageFixtures.scan(
            id: "reachable-old",
            target: target,
            createdAt: Date(timeIntervalSince1970: 10),
            coverage: RemoteScanCoverage(
                level: .complete,
                successfulCommandIDs: ["scan.df"],
                failedCommandIDs: [],
                timedOutCommandIDs: [],
                permissionDeniedCommandIDs: [],
                explanation: "Core remote evidence commands completed."
            )
        )
        let unreachableNewer = RemoteCoverageFixtures.scan(
            id: "unreachable-newer",
            target: target,
            createdAt: Date(timeIntervalSince1970: 20),
            coverage: RemoteScanCoverage(
                level: .unreachable,
                successfulCommandIDs: [],
                failedCommandIDs: ["scan.df"],
                timedOutCommandIDs: [],
                permissionDeniedCommandIDs: [],
                explanation: "The target was unreachable or all evidence commands failed."
            )
        )
        let current = RemoteCoverageFixtures.scan(
            id: "current",
            target: target,
            createdAt: Date(timeIntervalSince1970: 30),
            coverage: RemoteScanCoverage(
                level: .complete,
                successfulCommandIDs: ["scan.df"],
                failedCommandIDs: [],
                timedOutCommandIDs: [],
                permissionDeniedCommandIDs: [],
                explanation: "Core remote evidence commands completed."
            )
        )

        _ = try store.save(remoteScanReport: reachableOld)
        _ = try store.save(remoteScanReport: unreachableNewer)
        _ = try store.save(remoteScanReport: current)

        let previous = store.latestPreviousRemoteScanReport(
            forConcreteTarget: target,
            excludingReportID: current.id
        )

        XCTAssertEqual(previous?.id, reachableOld.id)
    }
}

private extension RemoteScanCoverage {
    func row(_ label: String) -> RemoteCoverageRow? {
        rows.first { $0.label == label }
    }
}

private enum RemoteCoverageFixtures {
    static func command(
        id: String,
        exitCode: Int32?,
        timedOut: Bool,
        stdout: [String] = [],
        stderr: [String] = []
    ) -> RemoteCommandResult {
        RemoteCommandResult(
            commandID: id,
            displayCommand: id,
            exitCode: exitCode,
            timedOut: timedOut,
            stdoutPreview: stdout,
            stderrPreview: stderr,
            redactionApplied: true
        )
    }

    static func scan(
        id: String,
        target: RemoteTargetReference,
        createdAt: Date,
        coverage: RemoteScanCoverage
    ) -> RemoteScanReport {
        RemoteScanReport(
            id: id,
            createdAt: createdAt,
            preset: .vpsGeneral,
            target: target,
            diskFilesystems: [],
            inodeFilesystems: [],
            findings: [],
            nativeGuidance: [],
            commands: [],
            coverage: coverage,
            nonClaims: RemoteScanReport.defaultNonClaims
        )
    }
}
