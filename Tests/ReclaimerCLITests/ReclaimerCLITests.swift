import Darwin
import Foundation
import XCTest
@testable import ReclaimerCore
@testable import reclaimer

final class ReclaimerCLITests: XCTestCase {
    private var auditRoot: URL!
    private var readableScope: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiReclaimerCLITests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        auditRoot = base.appendingPathComponent("audit", isDirectory: true)
        readableScope = base.appendingPathComponent("readable-scope", isDirectory: true)
        try FileManager.default.createDirectory(at: auditRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: readableScope, withIntermediateDirectories: true)
        setenv("RYDDI_AUDIT_ROOT", auditRoot.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("RYDDI_AUDIT_ROOT")
        let base = auditRoot.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.removeItem(at: base)
        }
    }

    func testSessionLatestJSONPrintsLatestSavedScanSession() throws {
        let store = AuditStore(root: auditRoot)
        try store.saveScanSession(makeSession(id: "session-old", updatedAt: Date(timeIntervalSince1970: 1_000)))
        try store.saveScanSession(makeSession(id: "session-new", updatedAt: Date(timeIntervalSince1970: 2_000)))

        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["session", "latest", "--json"])
        }

        let session = try JSONDecoder.ryddi.decode(ScanSession.self, from: Data(output.utf8))
        XCTAssertEqual(session.id, "session-new")
        XCTAssertEqual(session.stage, .scanned)
    }

    func testSessionLatestTextPrintsNoScanSessionMessage() throws {
        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["session", "latest"])
        }

        XCTAssertEqual(
            output,
            """
            No scan session has been recorded yet.
            Next: run `reclaimer scan --preset developer`.

            """
        )
    }

    func testScanCommandSavesScanSessionVisibleToSessionLatest() throws {
        try "scan fixture".write(
            to: readableScope.appendingPathComponent("scan-session-fixture.txt"),
            atomically: true,
            encoding: .utf8
        )

        _ = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: [
                "scan",
                "--path", readableScope.path,
                "--min-size", "1",
                "--no-lsof",
                "--json"
            ])
        }

        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["session", "latest", "--json"])
        }

        let session = try JSONDecoder.ryddi.decode(ScanSession.self, from: Data(output.utf8))
        XCTAssertEqual(session.stage, .scanned)
        XCTAssertEqual(session.preset, .developer)
        XCTAssertFalse(session.scopeDigest.isEmpty)
        XCTAssertNotNil(session.policyDigest)
        XCTAssertNotNil(session.findingDigest)
        XCTAssertNil(session.planDigest)
        XCTAssertNil(session.dryRunReceiptID)
    }

    func testPlanSaveAuditRecordsPlanReadyScanSession() throws {
        try writeCodexCacheFixture()

        _ = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: scanFixtureArguments(command: "plan") + [
                "--no-lsof",
                "--save-audit",
                "--json"
            ])
        }

        let store = AuditStore(root: auditRoot)
        let plan = try XCTUnwrap(store.recentPlans(limit: 1).first)
        let session = try XCTUnwrap(try store.latestScanSession())
        XCTAssertEqual(session.stage, .planReady)
        XCTAssertEqual(session.planDigest, plan.id)
        XCTAssertNil(session.dryRunReceiptID)
        XCTAssertFalse(plan.items.filter(\.selected).isEmpty)
    }

    func testExecuteDryRunSaveAuditRecordsDryRunReadyScanSession() throws {
        try writeCodexCacheFixture()

        _ = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: scanFixtureArguments(command: "execute") + [
                "--dry-run",
                "--no-lsof",
                "--save-audit",
                "--json"
            ])
        }

        let store = AuditStore(root: auditRoot)
        let receipt = try XCTUnwrap(store.recentReceipts(limit: 1).first)
        let session = try XCTUnwrap(try store.latestScanSession())
        XCTAssertEqual(session.stage, .dryRunReady)
        XCTAssertNotNil(session.planDigest)
        XCTAssertEqual(session.dryRunReceiptID, receipt.id)
        XCTAssertTrue(receipt.actions.contains { $0.status == "dry-run" })
    }

    func testExecuteYesIsRejectedAndDoesNotDeleteFixture() throws {
        let cache = try writeCodexCacheFixture()

        XCTAssertThrowsError(try ReclaimerCLI.run(arguments: scanFixtureArguments(command: "execute") + [
                "--yes",
                "--save-audit",
                "--json"
            ])) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("dry-run only"), String(describing: error))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }

    func testExecuteYesAfterSavedDryRunIsRejectedAndPreservesFixture() throws {
        let cache = try writeCodexCacheFixture()

        _ = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: scanFixtureArguments(command: "execute") + [
                "--dry-run",
                "--save-audit",
                "--json"
            ])
        }

        XCTAssertThrowsError(try ReclaimerCLI.run(arguments: scanFixtureArguments(command: "execute") + [
                "--yes",
                "--save-audit",
                "--json"
            ])) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("dry-run only"), String(describing: error))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))

        let session = try XCTUnwrap(try AuditStore(root: auditRoot).latestScanSession())
        XCTAssertEqual(session.stage, .dryRunReady)
        XCTAssertNotNil(session.dryRunReceiptID)
    }

    func testScheduleUninstallWithUnloadIsRejectedBeforeAnyLaunchctlMutation() throws {
        XCTAssertThrowsError(try ReclaimerCLI.run(arguments: ["schedule", "uninstall", "--unload"])) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("will not unload or remove"), error.localizedDescription)
        }
    }

    func testHelpAdvertisesCoreExecutionAsDryRunOnly() throws {
        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["help"])
        }

        XCTAssertTrue(output.contains("execute --dry-run"))
        XCTAssertFalse(output.contains("\n              execute --yes "))
        XCTAssertTrue(output.contains("Core execution is dry-run-only"))
        XCTAssertFalse(output.contains("recovery restore HOLDING_ID [--to PATH]"))
        XCTAssertFalse(output.contains("holding restore ID [--to PATH]"))
        XCTAssertFalse(output.contains("holding expire [--older-than-days N] [--yes]"))
        XCTAssertTrue(output.contains("Holding-area recovery is manual Finder work"))
    }

    func testDryRunReadySessionGuidanceDoesNotSuggestRejectedCoreExecuteYes() {
        let session = makeSession(
            id: "session-dry-run-ready",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            stage: .dryRunReady,
            planDigest: "plan-fixture",
            dryRunReceiptID: "receipt-fixture"
        )

        let guidance = nextScanSessionCommand(session)

        XCTAssertFalse(guidance.contains("execute --yes"), guidance)
        XCTAssertTrue(guidance.localizedCaseInsensitiveContains("manual"), guidance)
    }

    func testAuditPruneTextDefaultsToRecoverablePreview() throws {
        let plan = AuditPrunePlan(
            id: "audit-plan",
            createdAt: Date(timeIntervalSince1970: 1_000),
            rootPath: auditRoot.path,
            policy: AuditRetentionPolicy(olderThanDays: 30, keepRecent: 10),
            candidates: [
                AuditPruneCandidate(
                    path: auditRoot.appendingPathComponent("receipt-old.json").path,
                    kind: "receipt",
                    bytes: 1_024,
                    modifiedAt: Date(timeIntervalSince1970: 1)
                )
            ],
            skippedUnknownPaths: [],
            skippedSymlinkPaths: []
        )
        let receipt = AuditPruneReceipt(
            id: "audit-receipt",
            createdAt: Date(timeIntervalSince1970: 1_001),
            dryRun: true,
            planID: plan.id,
            deletedCount: 0,
            deletedBytes: 0,
            errors: []
        )

        let output = try captureStandardOutput {
            printAuditPruneResult(plan: plan, receipt: receipt)
        }

        XCTAssertTrue(output.contains("Ryddi audit retention preview"), output)
        XCTAssertTrue(output.localizedCaseInsensitiveContains("review only"), output)
        XCTAssertTrue(output.contains("--yes"), output)
        XCTAssertTrue(output.localizedCaseInsensitiveContains("Trash"), output)
        XCTAssertFalse(output.contains("Deleted:"), output)
    }

    func testPermissionGuideOutputRefusesExistingFileWithoutOverwritingIt() throws {
        let output = readableScope.appendingPathComponent("permission-guide.md")
        try "keep this file".write(to: output, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try ReclaimerCLI.run(arguments: [
                "permissions",
                "guide",
                "--path", readableScope.path,
                "--output", output.path
            ])
        ) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("already exists"), error.localizedDescription)
        }

        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "keep this file")
    }

    func testRecoveryTextGuidesHeldItemsToFinderWithoutRestoreCommand() throws {
        let holdingRoot = readableScope.appendingPathComponent("holding", isDirectory: true)
        let heldDirectory = holdingRoot.appendingPathComponent("2026-01-01T00-00-00Z", isDirectory: true)
        let heldFile = heldDirectory.appendingPathComponent("cache.bin")
        try FileManager.default.createDirectory(at: heldDirectory, withIntermediateDirectories: true)
        try Data("held cache".utf8).write(to: heldFile)
        try """
        {
          "originalPath": "\(readableScope.appendingPathComponent("original-cache.bin").path)",
          "heldAt": "2026-01-01T00:00:00Z",
          "allocatedSize": 10,
          "isDirectory": false
        }
        """.write(
            to: heldDirectory.appendingPathComponent(".reclaimer-hold.json"),
            atomically: true,
            encoding: .utf8
        )
        setenv("RYDDI_HOLDING_ROOT", holdingRoot.path, 1)
        defer { unsetenv("RYDDI_HOLDING_ROOT") }

        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["recovery", "--limit", "5"])
        }

        XCTAssertTrue(output.localizedCaseInsensitiveContains("manual review"), output)
        XCTAssertTrue(output.localizedCaseInsensitiveContains("Finder"), output)
        XCTAssertFalse(output.contains("Restore: reclaimer recovery restore"), output)
    }

    func testSessionExplainPrintsCurrentStateAndBlockedReasons() throws {
        let session = makeSession(
            id: "session-invalid",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            stage: .invalidated,
            findingDigest: nil,
            invalidationReasons: [.findingsChanged, .rulesChanged]
        )
        try AuditStore(root: auditRoot).saveScanSession(session)

        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["session", "explain"])
        }

        XCTAssertTrue(output.contains("Session: session-invalid"))
        XCTAssertTrue(output.contains("Stage: invalidated"))
        XCTAssertTrue(output.contains("Blocked reasons"))
        XCTAssertTrue(output.contains("findingsChanged"))
        XCTAssertTrue(output.contains("rulesChanged"))
        XCTAssertTrue(output.contains("Next: run `reclaimer scan --preset developer`"))
    }

    func testActionsJSONIncludesStableNonClaims() throws {
        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["actions", "--json", "--path", readableScope.path])
        }

        let report = try JSONDecoder.ryddi.decode(ActionCenterReport.self, from: Data(output.utf8))
        XCTAssertEqual(report.primaryAction?.kind, .runScan)
        XCTAssertFalse(report.nonClaims.isEmpty)
        XCTAssertTrue(report.nonClaims.contains { $0.localizedCaseInsensitiveContains("does not perform cleanup") })
    }

    func testActionsJSONIncludesPartialScanSessionHistoryWarningWhenAuditHistoryIsUnreadable() throws {
        try "{ this is not valid json".write(
            to: auditRoot.appendingPathComponent("scan-session-v1-corrupt.json"),
            atomically: true,
            encoding: .utf8
        )

        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["actions", "--json", "--path", readableScope.path])
        }

        let report = try JSONDecoder.ryddi.decode(ActionCenterReport.self, from: Data(output.utf8))
        XCTAssertTrue(report.nonClaims.contains { note in
            note.localizedCaseInsensitiveContains("session history")
                && note.localizedCaseInsensitiveContains("partially unreadable")
                && note.contains("scan-session-v1-corrupt.json")
        })
    }

    func testActionsPresetGeneralTextStartsWithPrimaryActionAndBlockedReasons() throws {
        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["actions", "--preset", "general", "--path", readableScope.path])
        }

        XCTAssertTrue(output.hasPrefix("Primary action: Run Scan\n"), output)
        XCTAssertTrue(output.contains("Blocked reasons"))
        XCTAssertTrue(output.contains("No scan session evidence is available."))
        XCTAssertTrue(output.contains("Non-claims"))
    }

    func testNativeReceiptsListAndExportSavedDryRunReceipt() throws {
        try writeHomebrewCacheFixture()

        try withFakeBrew(stdout: "Would remove fake bottle\n") {
            _ = try captureStandardOutput {
                try ReclaimerCLI.run(arguments: [
                    "native",
                    "run",
                    "--command-id", "brew.preview",
                    "--dry-run",
                    "--save-audit",
                    "--json"
                ] + nativeFixtureOptions())
            }
        }

        let listOutput = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["native", "receipts", "list", "--json"])
        }
        let receipts = try JSONDecoder.ryddi.decode([NativeToolExecutionReceipt].self, from: Data(listOutput.utf8))
        let receipt = try XCTUnwrap(receipts.first)
        XCTAssertEqual(receipt.command.id, "brew.preview")
        XCTAssertEqual(receipt.mode, .dryRun)
        XCTAssertEqual(receipt.status, "dry-run")

        let exportOutput = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: [
                "native", "receipts", "export",
                "--id", String(receipt.id.prefix(8)),
                "--path-style", "redacted",
                "--json"
            ])
        }
        let report = try JSONDecoder.ryddi.decode(NativeToolExecutionReceiptReport.self, from: Data(exportOutput.utf8))
        XCTAssertEqual(report.receiptID, receipt.id)
        XCTAssertEqual(report.commandID, "brew.preview")
        XCTAssertFalse(report.markdown.contains(readableScope.path))
        XCTAssertTrue(report.markdown.contains("<path redacted>"))
        XCTAssertTrue(report.nonClaims.contains { $0.localizedCaseInsensitiveContains("does not execute cleanup") })
    }

    func testNativeRunPreviewCommandWithYesRemainsBlocked() throws {
        try writeHomebrewCacheFixture()

        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: [
            "native",
            "run",
            "--command-id", "brew.preview",
            "--yes",
            "--json"
            ] + nativeFixtureOptions())
        }
        let receipt = try JSONDecoder.ryddi.decode(NativeToolExecutionReceipt.self, from: Data(output.utf8))
        XCTAssertEqual(receipt.status, "blocked")
        XCTAssertTrue(receipt.message.localizedCaseInsensitiveContains("same-process"))
    }

    func testNativeHomebrewDryRunSaveAuditCreatesExportableNativeReceipt() throws {
        let homebrewCache = try writeHomebrewCacheFixture()

        try withFakeBrew(stdout: "Would remove fake bottle\n") {
            _ = try captureStandardOutput {
                try ReclaimerCLI.run(arguments: [
                    "native",
                    "homebrew",
                    "cleanup",
                    "--dry-run",
                    "--save-audit",
                    "--finding-path", homebrewCache.path,
                    "--json"
                ])
            }
        }

        let listOutput = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["native", "receipts", "list", "--json"])
        }
        let receipts = try JSONDecoder.ryddi.decode([NativeToolExecutionReceipt].self, from: Data(listOutput.utf8))
        let receipt = try XCTUnwrap(receipts.first)
        XCTAssertEqual(receipt.command.id, "brew.preview")
        XCTAssertEqual(receipt.findingPath, homebrewCache.path)
        XCTAssertEqual(receipt.status, "dry-run")
        XCTAssertEqual(receipt.output?.stdoutPreview, ["Would remove fake bottle"])

        let exportOutput = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: [
                "native", "receipts", "export",
                "--id", String(receipt.id.prefix(8)),
                "--path-style", "redacted",
                "--json"
            ])
        }
        let report = try JSONDecoder.ryddi.decode(NativeToolExecutionReceiptReport.self, from: Data(exportOutput.utf8))
        XCTAssertEqual(report.commandID, "brew.preview")
        XCTAssertTrue(report.markdown.contains("Would remove fake bottle"))
        XCTAssertFalse(report.markdown.contains(homebrewCache.path))
    }

    func testNativeRunCleanupCreatesFreshSameProcessPreview() throws {
        let homebrewCache = try writeHomebrewCacheFixture()

        try withFakeBrew(stdout: "Homebrew fake output\n") {
            let output = try captureStandardOutput {
                try ReclaimerCLI.run(arguments: [
                    "native",
                    "run",
                    "--command-id", "brew.cleanup",
                    "--finding-path", homebrewCache.path,
                    "--yes",
                    "--json"
                ] + nativeFixtureOptions())
            }

            let receipt = try JSONDecoder.ryddi.decode(NativeToolExecutionReceipt.self, from: Data(output.utf8))
            XCTAssertEqual(receipt.command.id, "brew.cleanup")
            XCTAssertEqual(receipt.mode, .perform)
            XCTAssertEqual(receipt.status, "done")
            XCTAssertTrue(receipt.userConfirmed)
            XCTAssertEqual(receipt.output?.stdoutPreview, ["Homebrew fake output"])
        }
    }

    func testNativeRunCleanupDoesNotRequirePersistedPreviewReceipt() throws {
        let homebrewCache = try writeHomebrewCacheFixture()

        try withFakeBrew(stdout: "fresh same-process output\n") {
            let output = try captureStandardOutput {
                try ReclaimerCLI.run(arguments: [
                "native",
                "run",
                "--command-id", "brew.cleanup",
                "--finding-path", homebrewCache.path,
                "--yes",
                "--json"
                ] + nativeFixtureOptions())
            }
            let receipt = try JSONDecoder.ryddi.decode(NativeToolExecutionReceipt.self, from: Data(output.utf8))
            XCTAssertEqual(receipt.status, "done")
            XCTAssertEqual(receipt.output?.stdoutPreview, ["fresh same-process output"])
        }
    }

    func testNativeHomebrewPerformCreatesFreshSameProcessPreview() throws {
        let homebrewCache = try writeHomebrewCacheFixture()

        try withFakeBrew(stdout: "fresh homebrew output\n") {
            let output = try captureStandardOutput {
                try ReclaimerCLI.run(arguments: [
                "native",
                "homebrew",
                "cleanup",
                "--yes",
                "--finding-path", homebrewCache.path,
                "--json"
                ])
            }
            let receipt = try JSONDecoder.ryddi.decode(NativeActionReceipt.self, from: Data(output.utf8))
            XCTAssertEqual(receipt.mode, .perform)
            XCTAssertNil(receipt.skippedReason)
        }
    }

    func testNativeHomebrewPerformIgnoresPersistedPreviewEvidence() throws {
        let homebrewCache = try writeHomebrewCacheFixture()

        try withFakeBrew(stdout: "Homebrew fake output\n") {
            _ = try captureStandardOutput {
                try ReclaimerCLI.run(arguments: [
                    "native",
                    "homebrew",
                    "cleanup",
                    "--dry-run",
                    "--save-audit",
                    "--finding-path", homebrewCache.path,
                    "--json"
                ])
            }

            let output = try captureStandardOutput {
                try ReclaimerCLI.run(arguments: [
                    "native",
                    "homebrew",
                    "cleanup",
                    "--yes",
                    "--finding-path", homebrewCache.path,
                    "--json"
                ])
            }
            let receipt = try JSONDecoder.ryddi.decode(NativeActionReceipt.self, from: Data(output.utf8))

            XCTAssertEqual(receipt.mode, .perform)
            XCTAssertEqual(receipt.commandDisplay, ["brew", "cleanup"])
            XCTAssertEqual(receipt.exitCode, 0)
            XCTAssertNil(receipt.skippedReason)
        }
    }

    func testNativeHomebrewFailureThrowsAfterSavingFailedReceipt() throws {
        let homebrewCache = try writeHomebrewCacheFixture()

        try withFakeBrew(stdout: "Homebrew failed\n", exitCode: 23) {
            XCTAssertThrowsError(
                try captureStandardOutput {
                    try ReclaimerCLI.run(arguments: [
                        "native",
                        "homebrew",
                        "cleanup",
                        "--dry-run",
                        "--save-audit",
                        "--finding-path", homebrewCache.path,
                        "--json"
                    ])
                }
            ) { error in
                XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("homebrew command failed"), error.localizedDescription)
            }
        }

        let receipt = try XCTUnwrap(AuditStore(root: auditRoot).recentNativeToolExecutionReceipts(limit: 1).first)
        XCTAssertEqual(receipt.status, "failed")
        XCTAssertEqual(receipt.output?.exitCode, 23)
    }

    func testNativeRunHomebrewPreviewFailureThrowsAfterSavingFailedReceipt() throws {
        try writeHomebrewCacheFixture()

        try withFakeBrew(stdout: "Homebrew preview failed\n", exitCode: 24) {
            XCTAssertThrowsError(
                try captureStandardOutput {
                    try ReclaimerCLI.run(arguments: [
                        "native",
                        "run",
                        "--command-id", "brew.preview",
                        "--dry-run",
                        "--save-audit",
                        "--json"
                    ] + nativeFixtureOptions())
                }
            ) { error in
                XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("native command failed"), error.localizedDescription)
            }
        }

        let receipt = try XCTUnwrap(AuditStore(root: auditRoot).recentNativeToolExecutionReceipts(limit: 1).first)
        XCTAssertEqual(receipt.status, "failed")
        XCTAssertEqual(receipt.output?.exitCode, 24)
    }

    func testActionsJSONIncludesSavedNativeReceiptReviewAction() throws {
        let receipt = NativeToolExecutionReceipt(
            id: "native-receipt-cli-v1",
            createdAt: Date(timeIntervalSince1970: 10),
            ruleVersion: "rules-v1",
            mode: .dryRun,
            status: "dry-run",
            findingPath: readableScope.appendingPathComponent("Library/Caches/Homebrew").path,
            category: "Developer cache",
            command: NativeToolCommand(
                id: "brew.preview",
                command: "brew cleanup -n",
                purpose: "Preview Homebrew cleanup.",
                risk: .inspect,
                requiresReview: false,
                expectedEffect: "Shows what Homebrew would remove."
            ),
            invocation: ToolCommandInvocation(executable: "brew", arguments: ["cleanup", "-n"]),
            beforeFreeBytes: 100,
            afterFreeBytes: 100,
            output: nil,
            userConfirmed: false,
            message: "Fixture native preview.",
            nonClaims: NativeToolExecutor.nonClaims
        )
        _ = try AuditStore(root: auditRoot).save(nativeToolExecutionReceipt: receipt)

        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: ["actions", "--json", "--path", readableScope.path])
        }

        let report = try JSONDecoder.ryddi.decode(ActionCenterReport.self, from: Data(output.utf8))
        let nativeAction = try XCTUnwrap(report.actions.first { $0.id == "native-tool-receipt.\(receipt.id)" })
        XCTAssertEqual(nativeAction.title, "Review Native Preview")
        XCTAssertFalse(nativeAction.isDestructive)
        XCTAssertTrue(nativeAction.sourceIDs.contains("brew.preview"))
    }

    func testAppUninstallYesIsRejectedAsDryRunOnly() throws {
        let appRoot = readableScope.appendingPathComponent("Applications", isDirectory: true)
        let home = readableScope.appendingPathComponent("Home", isDirectory: true)
        let app = appRoot.appendingPathComponent("No Authorization.app", isDirectory: true)
        try createAppBundle(
            at: app,
            bundleIdentifier: "com.example.no-authorization",
            displayName: "No Authorization"
        )

        XCTAssertThrowsError(
            try captureStandardOutput {
                try ReclaimerCLI.run(arguments: [
                    "apps", "uninstall",
                    "--yes",
                    "--app", app.path,
                    "--path", appRoot.path,
                    "--home", home.path,
                    "--min-size", "1",
                    "--json"
                ])
            }
        ) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("dry-run only"), String(describing: error))
            XCTAssertTrue(error.localizedDescription.contains("--dry-run"), String(describing: error))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    func testAppUninstallYesCannotConsumePersistedDryRunEvidence() throws {
        let appRoot = readableScope.appendingPathComponent("Applications", isDirectory: true)
        let home = readableScope.appendingPathComponent("Home", isDirectory: true)
        let app = appRoot.appendingPathComponent("Authorized CLI.app", isDirectory: true)
        try createAppBundle(
            at: app,
            bundleIdentifier: "com.example.authorized-cli",
            displayName: "Authorized CLI"
        )
        let commonArguments = [
            "--app", app.path,
            "--path", appRoot.path,
            "--home", home.path,
            "--min-size", "1",
            "--json"
        ]

        let dryRunOutput = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: [
                "apps", "uninstall",
                "--dry-run",
                "--no-lsof",
                "--save-audit"
            ] + commonArguments)
        }
        let dryRun = try JSONDecoder.ryddi.decode(AppUninstallExecutionReceipt.self, from: Data(dryRunOutput.utf8))
        XCTAssertEqual(dryRun.status, "dry-run")
        XCTAssertNotNil(dryRun.authorizationDigest)

        XCTAssertThrowsError(try ReclaimerCLI.run(arguments: [
                "apps", "uninstall",
                "--yes"
            ] + commonArguments)) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("dry-run only"), String(describing: error))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
    }

    private func makeSession(
        id: String,
        updatedAt: Date,
        stage: ScanSessionStage = .scanned,
        findingDigest: String? = "findings-v1",
        planDigest: String? = nil,
        dryRunReceiptID: String? = nil,
        invalidationReasons: [ScanSessionInvalidationReason] = []
    ) -> ScanSession {
        ScanSession(
            id: id,
            createdAt: Date(timeIntervalSince1970: 500),
            updatedAt: updatedAt,
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopeDigest: "scope-v1",
            policyDigest: "policy-v1",
            findingDigest: findingDigest,
            planDigest: planDigest,
            dryRunReceiptID: dryRunReceiptID,
            executionReceiptID: nil,
            stage: stage,
            invalidationReasons: invalidationReasons
        )
    }

    @discardableResult
    private func writeCodexCacheFixture() throws -> URL {
        let cache = readableScope.appendingPathComponent("Library/Caches/Codex", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4_096).write(to: cache.appendingPathComponent("cache.bin"))
        return cache
    }

    @discardableResult
    private func writeHomebrewCacheFixture() throws -> URL {
        let cache = readableScope.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 4_096).write(to: cache.appendingPathComponent("bottle.tar.gz"))
        return cache
    }

    private func createAppBundle(at url: URL, bundleIdentifier: String, displayName: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleDisplayName": displayName,
            "CFBundleName": displayName,
            "CFBundleExecutable": displayName
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 8, count: 512).write(to: macOS.appendingPathComponent(displayName))
    }

    private func scanFixtureArguments(command: String) -> [String] {
        [
            command,
            "--path", readableScope.path,
            "--min-size", "1",
            "--max-depth", "6"
        ]
    }

    private func nativeFixtureOptions() -> [String] {
        [
            "--path", readableScope.path,
            "--min-size", "1",
            "--max-depth", "6",
            "--no-lsof"
        ]
    }

    private func withFakeBrew(stdout: String, exitCode: Int32 = 0, _ body: () throws -> Void) throws {
        let bin = auditRoot.deletingLastPathComponent().appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let brew = bin.appendingPathComponent("brew")
        let escaped = stdout.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        printf '%s' '\(escaped)'
        exit \(exitCode)
        """.write(to: brew, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(brew.path, S_IRWXU), 0)

        let oldPath = getenv("PATH").map { String(cString: $0) }
        let oldTestRoot = getenv("RYDDI_TEST_NATIVE_TOOL_ROOT").map { String(cString: $0) }
        setenv("PATH", "\(bin.path):\(oldPath ?? "")", 1)
        setenv("RYDDI_TEST_NATIVE_TOOL_ROOT", bin.path, 1)
        defer {
            if let oldPath {
                setenv("PATH", oldPath, 1)
            } else {
                unsetenv("PATH")
            }
            if let oldTestRoot {
                setenv("RYDDI_TEST_NATIVE_TOOL_ROOT", oldTestRoot, 1)
            } else {
                unsetenv("RYDDI_TEST_NATIVE_TOOL_ROOT")
            }
        }
        try body()
    }

    private func captureStandardOutput(_ body: () throws -> Void) throws -> String {
        let original = dup(STDOUT_FILENO)
        XCTAssertGreaterThanOrEqual(original, 0)
        var fds = [Int32](repeating: 0, count: 2)
        XCTAssertEqual(pipe(&fds), 0)

        fflush(stdout)
        dup2(fds[1], STDOUT_FILENO)
        close(fds[1])

        do {
            try body()
            fflush(stdout)
            dup2(original, STDOUT_FILENO)
            close(original)
        } catch {
            fflush(stdout)
            dup2(original, STDOUT_FILENO)
            close(original)
            close(fds[0])
            throw error
        }

        let data = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true).readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private extension JSONDecoder {
    static var ryddi: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
