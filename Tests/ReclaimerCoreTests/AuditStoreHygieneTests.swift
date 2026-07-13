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

    func testAuditPruneDryRunIsNonDestructiveAndConfirmedPruneTrashesOnlyReviewedFiles() throws {
        let root = tempRoot.appendingPathComponent("audit", isDirectory: true)
        let trasher = RecordingAuditTrasher()
        let store = AuditStore(root: root, trasher: trasher)
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
        XCTAssertTrue(plan.candidates.allSatisfy { $0.filesystemIdentity != nil })
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
        XCTAssertEqual(Set(receipt.deletedFileIDs), Set(["plan-old.json", "remote-scan-old.json"]))
        XCTAssertTrue(receipt.errors.isEmpty, receipt.errors.joined(separator: "\n"))
        XCTAssertEqual(Set(trasher.trashed.map(\.lastPathComponent)), Set(receipt.deletedFileIDs))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPlan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldScan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentProbe.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path))
    }

    func testAuditPruneReceiptListsDeletedFileIDsWithoutFullPaths() throws {
        let root = tempRoot.appendingPathComponent("audit", isDirectory: true)
        let store = AuditStore(root: root, trasher: RecordingAuditTrasher())
        _ = try writeFixture("plan-old.json", bytes: 10, daysAgo: 90, root: root)

        let plan = store.prunePlan(policy: AuditRetentionPolicy(olderThanDays: 30, keepRecent: 0), now: Date(timeIntervalSince1970: 2_000_000_000))
        let receipt = try store.prune(plan: plan, dryRun: false)

        XCTAssertEqual(receipt.deletedFileIDs, ["plan-old.json"])
        XCTAssertTrue(receipt.deletedFileIDs.allSatisfy { !$0.contains("/") })
    }

    func testAuditPruneExcludesKnownLookingDirectoriesAndPackages() throws {
        let root = tempRoot.appendingPathComponent("audit", isDirectory: true)
        let store = AuditStore(root: root, trasher: RecordingAuditTrasher())
        let directory = root.appendingPathComponent("plan-old.json", isDirectory: true)
        let package = root.appendingPathComponent("receipt-old.json", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let directoryMarker = directory.appendingPathComponent("keep.txt")
        let packageMarker = package.appendingPathComponent("keep.txt")
        try "keep directory".write(to: directoryMarker, atomically: true, encoding: .utf8)
        try "keep package".write(to: packageMarker, atomically: true, encoding: .utf8)
        var packageValues = URLResourceValues()
        packageValues.isPackage = true
        var mutablePackage = package
        try mutablePackage.setResourceValues(packageValues)
        let oldDate = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: package.path)

        let plan = store.prunePlan(
            policy: AuditRetentionPolicy(olderThanDays: 30, keepRecent: 0),
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let receipt = try store.prune(plan: plan, dryRun: false)

        XCTAssertFalse(plan.candidates.contains { $0.path == directory.path })
        XCTAssertFalse(plan.candidates.contains { $0.path == package.path })
        XCTAssertEqual(receipt.deletedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryMarker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageMarker.path))
    }

    func testAuditPruneLeavesModifiedRegularFileUntouched() throws {
        let root = tempRoot.appendingPathComponent("audit", isDirectory: true)
        let store = AuditStore(root: root, trasher: RecordingAuditTrasher())
        let file = try writeFixture("plan-modified.json", bytes: 16, daysAgo: 90, root: root)
        let plan = store.prunePlan(
            policy: AuditRetentionPolicy(olderThanDays: 30, keepRecent: 0),
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )

        try Data(repeating: 4, count: 16).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_900_000_000)],
            ofItemAtPath: file.path
        )
        let receipt = try store.prune(plan: plan, dryRun: false)

        XCTAssertEqual(receipt.deletedCount, 0)
        XCTAssertTrue(receipt.errors.contains { $0.localizedCaseInsensitiveContains("identity changed") }, receipt.errors.joined(separator: "\n"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testAuditPruneLeavesSameMetadataReplacementUntouched() throws {
        let root = tempRoot.appendingPathComponent("audit", isDirectory: true)
        let store = AuditStore(root: root, trasher: RecordingAuditTrasher())
        let file = try writeFixture("receipt-replaced.json", bytes: 12, daysAgo: 90, root: root)
        let plan = store.prunePlan(
            policy: AuditRetentionPolicy(olderThanDays: 30, keepRecent: 0),
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let candidate = try XCTUnwrap(plan.candidates.first)

        try FileManager.default.removeItem(at: file)
        try Data(repeating: 12, count: 12).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: try XCTUnwrap(candidate.modifiedAt)],
            ofItemAtPath: file.path
        )
        let receipt = try store.prune(plan: plan, dryRun: false)

        XCTAssertEqual(receipt.deletedCount, 0)
        XCTAssertTrue(receipt.errors.contains { $0.localizedCaseInsensitiveContains("identity changed") }, receipt.errors.joined(separator: "\n"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testLegacyAuditPruneCandidateWithoutIdentityDecodesButCannotDelete() throws {
        let root = tempRoot.appendingPathComponent("audit", isDirectory: true)
        let store = AuditStore(root: root, trasher: RecordingAuditTrasher())
        let file = try writeFixture("plan-legacy.json", bytes: 10, daysAgo: 90, root: root)
        let json = """
        {
          "path": "\(file.path)",
          "kind": "plan",
          "bytes": 10,
          "modifiedAt": null
        }
        """
        let candidate = try JSONDecoder().decode(AuditPruneCandidate.self, from: Data(json.utf8))
        let plan = AuditPrunePlan(
            id: "legacy-plan",
            createdAt: Date(timeIntervalSince1970: 2_000_000_000),
            rootPath: root.path,
            policy: AuditRetentionPolicy(olderThanDays: 30, keepRecent: 0),
            candidates: [candidate],
            skippedUnknownPaths: [],
            skippedSymlinkPaths: []
        )

        XCTAssertNil(candidate.filesystemIdentity)
        let receipt = try store.prune(plan: plan, dryRun: false)

        XCTAssertEqual(receipt.deletedCount, 0)
        XCTAssertTrue(receipt.errors.contains { $0.localizedCaseInsensitiveContains("no filesystem identity") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testAuditRetentionDefaultMatchesFirstClassActionPolicy() {
        let policy = AuditRetentionPolicy()

        XCTAssertEqual(policy.olderThanDays, 30)
        XCTAssertEqual(policy.keepRecent, 100)
        XCTAssertEqual(policy, SafeActionPlanner.defaultAuditRetention)
    }

    func testSavedAuditEvidenceUsesPrivatePermissions() throws {
        let root = tempRoot.appendingPathComponent("private-audit", isDirectory: true)
        let store = AuditStore(root: root, trasher: RecordingAuditTrasher())
        let plan = ReclaimPlan(
            mode: "report-only",
            items: [],
            dryRunSummary: []
        )

        let url = try store.save(plan: plan)
        let rootMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)
        let fileMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)

        XCTAssertEqual(rootMode.intValue & 0o777, 0o700)
        XCTAssertEqual(fileMode.intValue & 0o777, 0o600)
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

private final class RecordingAuditTrasher: Trashing, @unchecked Sendable {
    private(set) var trashed: [URL] = []

    func trashItem(at url: URL) throws -> URL {
        trashed.append(url.standardizedFileURL)
        try FileManager.default.removeItem(at: url)
        return URL(fileURLWithPath: "/Trash").appendingPathComponent(url.lastPathComponent)
    }
}
