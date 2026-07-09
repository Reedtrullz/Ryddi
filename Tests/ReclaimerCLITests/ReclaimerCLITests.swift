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
