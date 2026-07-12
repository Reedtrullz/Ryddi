import Darwin
import XCTest
@testable import ReclaimerCore

final class IssuePackageExportTests: XCTestCase {
    func testRedactedIssuePackageIncludesManifestReportNonClaimsAndSummaries() throws {
        let root = tempDirectory("issue-package-audit")
        let output = tempDirectory("issue-package-output")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        let store = AuditStore(root: root)
        try store.saveScanSession(scanSession(id: "session-fixture"))
        _ = try store.save(remoteScanReport: remoteScanReport())

        let manifest = try IssuePackageExporter.export(
            to: output,
            store: store,
            options: IssuePackageExportOptions(
                pathStyle: .redacted,
                includeLatestRemoteReport: true,
                appVersion: "test-version",
                createdAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        XCTAssertEqual(Set(manifest.includedFiles), Set([
            "local-summary.json",
            "manifest.json",
            "non-claims.md",
            "remote-summary.json",
            "report.md"
        ]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("report.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("non-claims.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("local-summary.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("remote-summary.json").path))

        let packageText = try readPackageText(output)
        XCTAssertTrue(packageText.contains("session-fixture"))
        XCTAssertTrue(packageText.contains("<path redacted>"))
        XCTAssertTrue(packageText.contains("<target redacted>"))
        XCTAssertTrue(packageText.contains("No cleanup was executed"))
        XCTAssertFalse(packageText.contains("/home/deploy"))
        XCTAssertFalse(packageText.contains("/Users/reidar"))
        XCTAssertFalse(packageText.contains("prod-"))
        XCTAssertFalse(packageText.contains("Racknerd"))
        XCTAssertFalse(packageText.contains("BEGIN OPENSSH"))
        XCTAssertFalse(packageText.contains("IdentityFile"))
    }

    func testIssuePackageRefusesNonEmptyOutputWithoutReplace() throws {
        let root = tempDirectory("issue-package-audit")
        let output = tempDirectory("issue-package-output")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try "keep".write(to: output.appendingPathComponent("existing.txt"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try IssuePackageExporter.export(to: output, store: AuditStore(root: root))
        ) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("empty output directory"), error.localizedDescription)
        }
    }

    func testIssuePackageReplaceRejectsArbitraryNonEmptyDirectoryAndPreservesContents() throws {
        let root = tempDirectory("issue-package-audit")
        let output = tempDirectory("issue-package-output")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try "old".write(to: output.appendingPathComponent("existing.txt"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try IssuePackageExporter.export(
                to: output,
                store: AuditStore(root: root),
                options: IssuePackageExportOptions(replaceExisting: true)
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("disabled"), error.localizedDescription)
        }

        XCTAssertEqual(
            try String(contentsOf: output.appendingPathComponent("existing.txt"), encoding: .utf8),
            "old"
        )
    }

    func testIssuePackageRejectsProtectedOutputRoots() throws {
        let root = tempDirectory("issue-package-audit")
        defer { try? FileManager.default.removeItem(at: root) }
        let protectedOutputs = [
            URL(fileURLWithPath: "/"),
            FileManager.default.homeDirectoryForCurrentUser,
            URL(fileURLWithPath: "/Users"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Library"),
            URL(fileURLWithPath: "/System")
        ]

        for output in protectedOutputs {
            XCTAssertThrowsError(
                try IssuePackageExporter.export(to: output, store: AuditStore(root: root))
            ) { error in
                XCTAssertTrue(error.localizedDescription.contains("protected"), "\(output.path): \(error.localizedDescription)")
            }
        }
    }

    func testIssuePackageReplaceIsRefusedAndPreservesOwnedPackage() throws {
        let root = tempDirectory("issue-package-audit")
        let output = tempDirectory("issue-package-output")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }
        _ = try IssuePackageExporter.export(
            to: output,
            store: AuditStore(root: root),
            options: IssuePackageExportOptions(appVersion: "old")
        )
        let originalManifest = try Data(contentsOf: output.appendingPathComponent("manifest.json"))

        XCTAssertThrowsError(
            try IssuePackageExporter.export(
                to: output,
                store: AuditStore(root: root),
                options: IssuePackageExportOptions(replaceExisting: true, appVersion: "new")
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("disabled"), error.localizedDescription)
        }

        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("manifest.json")), originalManifest)
    }

    func testIssuePackageWritesStayBoundToVerifiedDirectoryAfterVisiblePathSwap() throws {
        let root = tempDirectory("issue-package-audit")
        let output = tempDirectory("issue-package-output")
        let movedOutput = tempDirectory("issue-package-moved-output")
        let unrelated = tempDirectory("issue-package-unrelated")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: movedOutput)
            try? FileManager.default.removeItem(at: unrelated)
        }
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        _ = try IssuePackageExporter.export(
            to: output,
            store: AuditStore(root: root),
            beforeFirstWrite: {
                try FileManager.default.moveItem(at: output, to: movedOutput)
                try FileManager.default.createSymbolicLink(at: output, withDestinationURL: unrelated)
            }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: movedOutput.appendingPathComponent("manifest.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unrelated.appendingPathComponent("manifest.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unrelated.appendingPathComponent("report.md").path))
    }

    func testIssuePackageRefusesPostValidationFileCollisionWithoutOverwritingIt() throws {
        let root = tempDirectory("issue-package-audit")
        let output = tempDirectory("issue-package-output")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: output)
        }

        XCTAssertThrowsError(
            try IssuePackageExporter.export(
                to: output,
                store: AuditStore(root: root),
                beforeFirstWrite: {
                    try "unrelated".write(
                        to: output.appendingPathComponent("report.md"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("already exists"), error.localizedDescription)
        }

        XCTAssertEqual(
            try String(contentsOf: output.appendingPathComponent("report.md"), encoding: .utf8),
            "unrelated"
        )
    }

    private func scanSession(id: String) -> ScanSession {
        ScanSession(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopeDigest: "scope-v1",
            policyDigest: "policy-v1",
            findingDigest: "findings-v1",
            stage: .scanned
        )
    }

    private func remoteScanReport() -> RemoteScanReport {
        RemoteScanReport(
            id: "remote-fixture",
            preset: .vpsGeneral,
            target: RemoteTargetReference(
                input: "prod-racknerd",
                alias: "prod-racknerd",
                resolvedUser: "deploy",
                resolvedHost: "Racknerd.example",
                resolvedPort: 22,
                knownHostsState: "known",
                fingerprint: "ssh-ed25519:fixture"
            ),
            diskFilesystems: [],
            inodeFilesystems: [],
            findings: [
                RemoteStorageFinding(
                    remotePath: "/home/deploy/Racknerd/prod-client/cache",
                    displayPath: "/home/deploy/Racknerd/prod-client/cache",
                    bucket: "Remote storage",
                    allocatedBytes: 1_024,
                    safetyClass: .reviewRequired,
                    actionKind: .openGuidance,
                    evidence: [Evidence(kind: "remote.fixture", message: "Fixture evidence.")],
                    recommendedNextAction: .reviewInFinder
                )
            ],
            nativeGuidance: [],
            commands: [
                RemoteCommandResult(
                    commandID: "scan.df",
                    displayCommand: "ssh prod-racknerd df -Pk",
                    exitCode: 0,
                    timedOut: false,
                    stdoutPreview: ["Filesystem 1024-blocks Used Available Capacity Mounted on"],
                    stderrPreview: ["IdentityFile /Users/reidar/.ssh/id_ed25519"],
                    redactionApplied: false
                )
            ],
            nonClaims: RemoteScanReport.defaultNonClaims
        )
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
