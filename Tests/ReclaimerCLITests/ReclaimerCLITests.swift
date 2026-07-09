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

    func testExecuteYesWithoutDryRunSkipsAsStaleAndDoesNotDeleteFixture() throws {
        let cache = try writeCodexCacheFixture()

        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: scanFixtureArguments(command: "execute") + [
                "--yes",
                "--save-audit",
                "--json"
            ])
        }

        let receipt = try JSONDecoder.ryddi.decode(ExecutionReceipt.self, from: Data(output.utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(receipt.actions.contains { action in
            action.status == "skipped"
                && action.message.localizedCaseInsensitiveContains("stale scan session")
        })
        XCTAssertTrue(receipt.errors.contains { $0.localizedCaseInsensitiveContains("stale scan session") })

        let session = try XCTUnwrap(try AuditStore(root: auditRoot).latestScanSession())
        XCTAssertEqual(session.stage, .scanned)
        XCTAssertNil(session.dryRunReceiptID)
    }

    func testExecuteYesAfterSavedDryRunDeletesFixtureAndRecordsExecution() throws {
        let cache = try writeCodexCacheFixture()

        _ = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: scanFixtureArguments(command: "execute") + [
                "--dry-run",
                "--save-audit",
                "--json"
            ])
        }

        let output = try captureStandardOutput {
            try ReclaimerCLI.run(arguments: scanFixtureArguments(command: "execute") + [
                "--yes",
                "--save-audit",
                "--json"
            ])
        }

        let receipt = try JSONDecoder.ryddi.decode(ExecutionReceipt.self, from: Data(output.utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(receipt.actions.contains { $0.status == "done" && $0.action == .deleteCache })

        let session = try XCTUnwrap(try AuditStore(root: auditRoot).latestScanSession())
        XCTAssertEqual(session.stage, .executed)
        XCTAssertEqual(session.executionReceiptID, receipt.id)
        XCTAssertNil(session.invalidationReasons.first)
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

    private func scanFixtureArguments(command: String) -> [String] {
        [
            command,
            "--path", readableScope.path,
            "--min-size", "1",
            "--max-depth", "6"
        ]
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
