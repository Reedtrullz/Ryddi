import XCTest
@testable import ReclaimerCore

final class CleanupReceiptTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testSuccessfulFixtureMoveRecordsTheExactVerifiedRecoveryURLAndBytes() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("reviewed"), trash = root.appendingPathComponent("fixture-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let data = Data("private synthetic fixture".utf8)
        try data.write(to: source)
        let identity = try XCTUnwrap(FileIdentity.capture(path: source.path))
        let receipt = CleanupReceipt.perform(paths: [source.path]) { _ in
            try SessionTrashMover(trashDirectory: { _ in trash }).moveValidatedFileToTrash(source: source, scannedIdentity: identity)
        }
        let entry = try XCTUnwrap(receipt.entries.first), recovery = try XCTUnwrap(entry.recoveryPath)
        XCTAssertEqual(entry.outcome, .moved)
        XCTAssertEqual(URL(fileURLWithPath: recovery).deletingLastPathComponent().resolvingSymlinksInPath().path,
                       trash.resolvingSymlinksInPath().path)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: recovery)), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(receipt.summary, "1 moved, 0 retained, 0 failed")
        XCTAssertFalse(receipt.hasUnmovedItems)
    }

    func testRefusedRollbackRecordsRetainedStagingLocationAndKeepsForeignSource() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("reviewed"), trash = root.appendingPathComponent("fixture-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("reviewed bytes".utf8).write(to: source)
        let identity = try XCTUnwrap(FileIdentity.capture(path: source.path))
        let mover = SessionTrashMover(trashDirectory: { _ in trash }, checkpoint: { point, _ in
            if point == "staged" {
                try Data("foreign replacement".utf8).write(to: source)
                throw SessionTrashError.trashFailed
            }
        })
        let receipt = CleanupReceipt.perform(paths: [source.path]) { _ in
            try mover.moveValidatedFileToTrash(source: source, scannedIdentity: identity)
        }
        let entry = try XCTUnwrap(receipt.entries.first), path = try XCTUnwrap(entry.recoveryPath)
        XCTAssertEqual(entry.outcome, .retained)
        XCTAssertTrue(path.contains(".ryddi-trash-"))
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "reviewed bytes")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "foreign replacement")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
    }

    func testUnknownAndValidationFailuresDoNotInventARecoveryPath() {
        let receipt = CleanupReceipt.perform(paths: ["/fixture/unknown", "/fixture/changed"]) { path in
            if path.hasSuffix("unknown") { throw SessionTrashError.locationUnknown }
            throw SessionTrashError.sourceChanged
        }
        XCTAssertEqual(receipt.entries.map(\.outcome), [.failed, .failed])
        XCTAssertTrue(receipt.entries.allSatisfy { $0.recoveryPath == nil })
        XCTAssertTrue(receipt.hasUnmovedItems)
    }

    func testRedactedCopyOmitsNamesPathsAndErrorDetailsUnlessExplicitlyRequested() {
        let entry = CleanupReceiptEntry(sourcePath: "/private/person/secret-name", outcome: .retained,
            recoveryPath: "/private/person/staging", detail: "Error containing private-name")
        let receipt = CleanupReceipt(entries: [entry])
        let redacted = receipt.text()
        for text in ["/private", "person", "secret-name", "private-name", "staging"] {
            XCTAssertFalse(redacted.contains(text), text)
        }
        XCTAssertTrue(redacted.contains("Retained"))
        XCTAssertTrue(receipt.text(includePaths: true).contains(entry.sourcePath))
        XCTAssertTrue(receipt.text(includePaths: true).contains(entry.detail))
        XCTAssertTrue(redacted.contains("Physically reclaimed space is unverified"))
    }

    func testReceiptExpiresAtThirtyMinutesWithoutPersistence() {
        let date = Date(timeIntervalSince1970: 100)
        let receipt = CleanupReceipt(entries: [], completedAt: date)
        XCTAssertFalse(receipt.isExpired(at: date.addingTimeInterval(1799)))
        XCTAssertTrue(receipt.isExpired(at: date.addingTimeInterval(1800)))
        XCTAssertEqual(receipt.summary, "0 moved, 0 retained, 0 failed")
    }

    func testCancellationAfterAnAttemptKeepsAllRemainingOutcomesWithoutCallingOperations() {
        var calls = 0
        let receipt = CleanupReceipt.perform(paths: ["/fixture/a", "/fixture/b", "/fixture/c"]) { _ in
            calls += 1
            throw CancellationError()
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(receipt.entries.map(\.outcome), [.failed, .retained, .retained])
        XCTAssertNil(receipt.entries[0].recoveryPath)
        XCTAssertEqual(receipt.entries[1].recoveryPath, "/fixture/b")
        XCTAssertTrue(receipt.entries[1].detail.contains("Not attempted"))
    }

    func testAlreadyCancelledBatchDoesNotAttemptAnyMove() async {
        let result = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var calls = 0
            let receipt = CleanupReceipt.perform(paths: ["/fixture/a"]) { _ in
                calls += 1
                return URL(fileURLWithPath: "/fixture/trash/a")
            }
            return (receipt, calls)
        }.value
        XCTAssertEqual(result.1, 0)
        XCTAssertEqual(result.0.entries.first?.outcome, .retained)
    }
}
