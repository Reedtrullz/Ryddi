import XCTest
import ReclaimerCore
@testable import RyddiApp

@MainActor
final class CleanupReceiptPresentationTests: XCTestCase {
    private func receipt() -> CleanupReceipt {
        CleanupReceipt(entries: [CleanupReceiptEntry(sourcePath: "/fixture/source", outcome: .moved,
            recoveryPath: "/fixture/trash/source", detail: "Synthetic receipt only")])
    }

    func testFollowupReadOnlyFixtureAuditDoesNotDiscardReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = ScanEngine(), receipt = receipt()
        defer { engine.dismissCleanupReceipt(); engine.cancelAudit() }
        engine.presentCleanupReceipt(receipt)
        engine.runAudit(path: root.path)
        for _ in 0..<100 where engine.isAuditing {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(engine.isAuditing)
        XCTAssertEqual(engine.auditReport?.hasCompleteCoverage, true)
        XCTAssertEqual(engine.cleanupReceipt?.id, receipt.id)
        XCTAssertTrue(engine.showCleanupReceipt)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testOldExpiryCannotDiscardReplacementAndCurrentExpiryForgetsPaths() async {
        let engine = ScanEngine(), old = receipt(), current = receipt()
        engine.presentCleanupReceipt(old)
        engine.presentCleanupReceipt(current)
        engine.expireCleanupReceipt(id: old.id, at: old.completedAt.addingTimeInterval(1800))
        XCTAssertEqual(engine.cleanupReceipt?.id, current.id)
        engine.expireCleanupReceipt(id: current.id, at: current.completedAt.addingTimeInterval(1799))
        XCTAssertTrue(engine.showCleanupReceipt)
        engine.expireCleanupReceipt(id: current.id, at: current.completedAt.addingTimeInterval(1800))
        XCTAssertNil(engine.cleanupReceipt)
        XCTAssertFalse(engine.showCleanupReceipt)
    }

    func testDismissalAndExpiredPresentationRetainNoReceipt() async {
        let engine = ScanEngine()
        engine.presentCleanupReceipt(receipt())
        engine.dismissCleanupReceipt()
        XCTAssertNil(engine.cleanupReceipt)
        XCTAssertFalse(engine.showCleanupReceipt)
        engine.presentCleanupReceipt(CleanupReceipt(entries: [], completedAt: Date().addingTimeInterval(-1801)))
        XCTAssertNil(engine.cleanupReceipt)
        XCTAssertFalse(engine.showCleanupReceipt)
    }
}
