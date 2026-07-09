import XCTest
@testable import ReclaimerCore

final class AuditStoreHygieneTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiAuditHygieneTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testAuditStoreSummaryCountsKnownUnknownAndSymlinkFiles() throws {
        let root = tempRoot.appendingPathComponent("audit", isDirectory: true)
        let store = AuditStore(root: root)
        let oldPlan = try writeFixture("plan-old.json", bytes: 10, daysAgo: 90, root: root)
        let scan = try writeFixture("remote-scan-old.json", bytes: 20, daysAgo: 60, root: root)
        _ = try writeFixture("notes.txt", bytes: 30, daysAgo: 60, root: root)
        let symlink = root.appendingPathComponent("receipt-link.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: oldPlan)

        let summary = store.summary()

        XCTAssertEqual(summary.totalKnownFileCount, 2)
        XCTAssertEqual(summary.totalKnownBytes, 30)
        XCTAssertEqual(summary.unknownFileCount, 1)
        XCTAssertEqual(summary.symlinkCount, 1)
        XCTAssertEqual(summary.items.first { $0.kind == "plan" }?.fileCount, 1)
        XCTAssertEqual(summary.items.first { $0.kind == "remote-scan" }?.totalBytes, 20)
        XCTAssertTrue(summary.items.contains { $0.latestModifiedAt != nil })
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldPlan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scan.path))
    }

    func testAuditPruneDryRunAndConfirmedDeleteOnlyKnownEligibleJSON() throws {
        let root = tempRoot.appendingPathComponent("audit", isDirectory: true)
        let store = AuditStore(root: root)
        let oldPlan = try writeFixture("plan-old.json", bytes: 10, daysAgo: 90, root: root)
        let oldScan = try writeFixture("remote-scan-old.json", bytes: 20, daysAgo: 60, root: root)
        let recentProbe = try writeFixture("remote-probe-recent.json", bytes: 30, daysAgo: 1, root: root)
        let unknown = try writeFixture("unknown-old.json", bytes: 40, daysAgo: 90, root: root)
        let symlink = root.appendingPathComponent("receipt-link.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: oldPlan)

        let policy = AuditRetentionPolicy(olderThanDays: 30, keepRecent: 1)
        let plan = store.prunePlan(policy: policy, now: Date(timeIntervalSince1970: 2_000_000_000))

        XCTAssertEqual(Set(plan.candidates.map(\.path)), Set([oldPlan.path, oldScan.path]))
        XCTAssertEqual(plan.candidateCount, 2)
        XCTAssertEqual(plan.candidateBytes, 30)
        XCTAssertTrue(plan.skippedUnknownPaths.contains(unknown.path))
        XCTAssertTrue(plan.skippedSymlinkPaths.contains(symlink.path))

        let dryRun = try store.prune(plan: plan, dryRun: true)
        XCTAssertTrue(dryRun.dryRun)
        XCTAssertEqual(dryRun.deletedCount, 0)
        for url in [oldPlan, oldScan, recentProbe, unknown, symlink] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.path)
        }

        let receipt = try store.prune(plan: plan, dryRun: false)
        XCTAssertFalse(receipt.dryRun)
        XCTAssertEqual(receipt.deletedCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPlan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldScan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentProbe.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path))
    }

    func testAuditPruneReceiptListsDeletedFileIDsWithoutFullPaths() throws {
        let root = tempRoot.appendingPathComponent("audit", isDirectory: true)
        let store = AuditStore(root: root)
        _ = try writeFixture("plan-old.json", bytes: 10, daysAgo: 90, root: root)

        let plan = store.prunePlan(policy: AuditRetentionPolicy(olderThanDays: 30, keepRecent: 0), now: Date(timeIntervalSince1970: 2_000_000_000))
        let receipt = try store.prune(plan: plan, dryRun: false)

        XCTAssertEqual(receipt.deletedFileIDs, ["plan-old.json"])
        XCTAssertTrue(receipt.deletedFileIDs.allSatisfy { !$0.contains("/") })
    }

    func testAuditRetentionDefaultMatchesFirstClassActionPolicy() {
        let policy = AuditRetentionPolicy()

        XCTAssertEqual(policy.olderThanDays, 30)
        XCTAssertEqual(policy.keepRecent, 100)
        XCTAssertEqual(policy, SafeActionPlanner.defaultAuditRetention)
    }

    private func writeFixture(_ name: String, bytes: Int, daysAgo: Int, root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try Data(repeating: UInt8(bytes), count: bytes).write(to: url)
        let date = Date(timeIntervalSince1970: 2_000_000_000 - TimeInterval(daysAgo * 24 * 60 * 60))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }
}
