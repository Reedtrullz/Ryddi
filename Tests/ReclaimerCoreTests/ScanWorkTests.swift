import XCTest
import Darwin
@testable import ReclaimerCore

@MainActor
final class ScanWorkTests: XCTestCase {
    func testDrainsOutputLargerThanPipeCapacity() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/awk")
        process.arguments = ["BEGIN { for (i=0; i<20000; i++) print \"0123456789\" }"]
        let output = try BoundedScanProcess.run(process, timeout: 5, maximumOutputBytes: 300_000)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.data.count, 220_000)
        XCTAssertFalse(process.isRunning)
    }

    func testOutputLimitStopsProducer() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        XCTAssertThrowsError(try BoundedScanProcess.run(process, timeout: 5, maximumOutputBytes: 1024)) {
            XCTAssertEqual($0 as? ScanWorkError, .outputLimit)
        }
        XCTAssertFalse(process.isRunning)
    }

    func testDeadlineKillsTermResistantProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; while :; do :; done"]
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try BoundedScanProcess.run(process, timeout: 0.15, maximumOutputBytes: 1024)) {
            XCTAssertEqual($0 as? ScanWorkError, .timedOut)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(kill(process.processIdentifier, 0), -1)
    }

    func testOwnerCancellationReachesDetachedBlockedProcess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ryddi-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pidURL = root.appendingPathComponent("pid")
        let worker = Task {
            try await runCancellableScan {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", "trap '' TERM; echo $$ > \"$1\"; while :; do :; done", "fixture", pidURL.path]
                return try BoundedScanProcess.run(process, timeout: 5, maximumOutputBytes: 1024)
            }
        }
        defer { worker.cancel() }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: pidURL.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let start = ProcessInfo.processInfo.systemUptime
        worker.cancel()
        do { _ = try await worker.value; XCTFail("Cancelled work must not publish success") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
        XCTAssertEqual(kill(pid, 0), -1)
    }

    func testBudgetCountsNonCandidatesAndHashesAcrossGroups() throws {
        var budget = ScanBudget(maximumEntries: 2, maximumHashBytes: 3)
        try budget.visitEntry()
        try budget.visitEntry()
        XCTAssertThrowsError(try budget.visitEntry()) { XCTAssertEqual($0 as? ScanWorkError, .entryLimit) }
        try budget.hash(2)
        try budget.hash(1)
        XCTAssertThrowsError(try budget.hash(1)) { XCTAssertEqual($0 as? ScanWorkError, .hashLimit) }
        XCTAssertThrowsError(try ScanBudget(timeout: 0).check()) { XCTAssertEqual($0 as? ScanWorkError, .timedOut) }
    }

    func testDeepAuditLimitsNeverReturnCompleteLookingRecommendations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ryddi-bounds-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["a", "b"] {
            let directory = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in ["first.bin", "second.bin"] {
                try Data(repeating: 1, count: 10).write(to: directory.appendingPathComponent(name))
            }
        }
        XCTAssertThrowsError(try DeepAuditScanner(maximumEntries: 1).scan(path: root.path)) {
            XCTAssertEqual($0 as? ScanWorkError, .entryLimit)
        }
        XCTAssertThrowsError(try DeepAuditScanner(maximumHashBytes: 30).scan(path: root.path)) {
            XCTAssertEqual($0 as? ScanWorkError, .hashLimit)
        }
        XCTAssertThrowsError(try DeepAuditScanner(timeout: 0).scan(path: root.path)) {
            XCTAssertEqual($0 as? ScanWorkError, .timedOut)
        }
    }

    func testExcessFastRootsFailBeforeStartingFilesystemWork() async throws {
        let scanner = FastScanner(ruleEngine: try RuleEngine.bundled())
        do {
            _ = try await scanner.scan(roots: Array(repeating: ScanRoot(name: "Fixture", path: "/missing-fixture"), count: 129))
            XCTFail("Root limit must be explicit")
        } catch { XCTAssertEqual(error as? ScanWorkError, .entryLimit) }
    }
}
