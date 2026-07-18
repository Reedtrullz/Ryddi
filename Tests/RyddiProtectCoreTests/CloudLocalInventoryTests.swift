import Foundation
import XCTest
import Darwin
@testable import RyddiProtectCore

final class CloudLocalInventoryTests: XCTestCase {
    func testConfirmationRejectsBroadRootAndChangedIdentity() throws {
        let home = try temporaryDirectory()
        let candidate = try makeCandidate(at: home, provider: .mega)
        XCTAssertThrowsError(try CloudStorageRootConfirmation.confirm(candidate, home: home)) {
            XCTAssertEqual($0 as? CloudRootConfirmationError, .unsafeBroadRoot)
        }

        let cloudContainer = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudContainer, withIntermediateDirectories: true)
        let containerCandidate = try makeCandidate(at: cloudContainer, provider: .mega)
        XCTAssertThrowsError(try CloudStorageRootConfirmation.confirm(containerCandidate, home: home)) {
            XCTAssertEqual($0 as? CloudRootConfirmationError, .unsafeBroadRoot)
        }

        let root = home.appendingPathComponent("MEGA", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let changed = try makeCandidate(at: root, provider: .mega)
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(try CloudStorageRootConfirmation.confirm(changed, home: home)) {
            XCTAssertEqual($0 as? CloudRootConfirmationError, .identityChanged)
        }
    }

    func testInventoryIsBoundedAndBuildsAllocatedLargeAndStaleQueues() throws {
        let home = try temporaryDirectory()
        let root = home.appendingPathComponent("Dropbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeFile(root.appendingPathComponent("large.bin"), bytes: 8_192, modifiedAt: Date(timeIntervalSince1970: 1_000))
        try writeFile(root.appendingPathComponent("small.txt"), bytes: 100, modifiedAt: Date(timeIntervalSince1970: 9_000))
        let confirmed = try CloudStorageRootConfirmation.confirm(try makeCandidate(at: root), home: home)

        let report = CloudLocalInventoryScanner().scan(
            root: confirmed,
            options: CloudLocalInventoryOptions(maximumEntries: 10, reviewLimit: 1, staleAge: 1_000),
            now: Date(timeIntervalSince1970: 10_000)
        )

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.fileCount, 2)
        XCTAssertEqual(report.logicalBytes, 8_292)
        XCTAssertGreaterThan(report.allocatedBytes, 0)
        XCTAssertEqual(report.largeFiles.map(\.relativePath), ["large.bin"])
        XCTAssertEqual(report.staleFiles.map(\.relativePath), ["large.bin"])
        XCTAssertTrue(report.nonClaims.contains { $0.contains("never opens file contents") })
    }

    func testInventoryDoesNotFollowDirectorySymlink() throws {
        let home = try temporaryDirectory()
        let root = home.appendingPathComponent("Dropbox", isDirectory: true)
        let outside = home.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try writeFile(outside.appendingPathComponent("private.bin"), bytes: 4_096)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked-outside"),
            withDestinationURL: outside
        )
        let confirmed = try CloudStorageRootConfirmation.confirm(try makeCandidate(at: root), home: home)

        let report = CloudLocalInventoryScanner().scan(root: confirmed)

        XCTAssertEqual(report.skippedSymbolicLinkCount, 1)
        XCTAssertEqual(report.fileCount, 0)
        XCTAssertEqual(report.logicalBytes, 0)
    }

    func testHardLinksDoNotMultiplyAllocatedBytesOrReviewRows() throws {
        let home = try temporaryDirectory()
        let root = home.appendingPathComponent("Dropbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.bin")
        try writeFile(original, bytes: 8_192)
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("linked.bin"))
        let confirmed = try CloudStorageRootConfirmation.confirm(try makeCandidate(at: root), home: home)

        let report = CloudLocalInventoryScanner().scan(root: confirmed)

        XCTAssertEqual(report.fileCount, 2)
        XCTAssertEqual(report.logicalBytes, 16_384)
        XCTAssertEqual(report.sharedFileIdentityCount, 1)
        XCTAssertEqual(report.largeFiles.count, 1)
        XCTAssertGreaterThan(report.allocatedBytes, 0)
        XCTAssertLessThanOrEqual(report.allocatedBytes, report.logicalBytes)
    }

    func testEntryLimitReturnsExplicitPartialReport() throws {
        let home = try temporaryDirectory()
        let root = home.appendingPathComponent("GoogleDrive-test", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeFile(root.appendingPathComponent("one"), bytes: 1)
        try writeFile(root.appendingPathComponent("two"), bytes: 1)
        let confirmed = try CloudStorageRootConfirmation.confirm(
            try makeCandidate(at: root, provider: .googleDrive),
            home: home
        )

        let report = CloudLocalInventoryScanner().scan(
            root: confirmed,
            options: CloudLocalInventoryOptions(maximumEntries: 1)
        )

        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.scannedEntryCount, 1)
        XCTAssertEqual(report.issues, [.entryLimitReached])
    }

    func testDepthAndDirectoryBoundsDoNotDisappearFromCoverage() throws {
        let home = try temporaryDirectory()
        let root = home.appendingPathComponent("Dropbox", isDirectory: true)
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = first.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try writeFile(second.appendingPathComponent("deep.bin"), bytes: 1_000)
        let confirmed = try CloudStorageRootConfirmation.confirm(try makeCandidate(at: root), home: home)

        let depthReport = CloudLocalInventoryScanner().scan(
            root: confirmed,
            options: CloudLocalInventoryOptions(maximumDepth: 0)
        )
        XCTAssertEqual(depthReport.fileCount, 0)
        XCTAssertEqual(depthReport.issues, [.depthLimitReached])

        let directoryReport = CloudLocalInventoryScanner().scan(
            root: confirmed,
            options: CloudLocalInventoryOptions(maximumDirectories: 1, maximumDepth: 10)
        )
        XCTAssertEqual(directoryReport.fileCount, 0)
        XCTAssertEqual(directoryReport.issues, [.directoryLimitReached])
    }

    func testZeroDurationReturnsExplicitPartialReportWithoutTraversal() throws {
        let home = try temporaryDirectory()
        let root = home.appendingPathComponent("Dropbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeFile(root.appendingPathComponent("untouched.bin"), bytes: 1_000)
        let confirmed = try CloudStorageRootConfirmation.confirm(try makeCandidate(at: root), home: home)

        let report = CloudLocalInventoryScanner().scan(
            root: confirmed,
            options: CloudLocalInventoryOptions(maximumDuration: 0)
        )

        XCTAssertEqual(report.scannedEntryCount, 0)
        XCTAssertEqual(report.issues, [.timeLimitReached])
    }

    func testChangedRootAfterConfirmationFailsClosed() throws {
        let home = try temporaryDirectory()
        let root = home.appendingPathComponent("Dropbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let confirmed = try CloudStorageRootConfirmation.confirm(try makeCandidate(at: root), home: home)
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeFile(root.appendingPathComponent("replacement.bin"), bytes: 10_000)

        let report = CloudLocalInventoryScanner().scan(root: confirmed)

        XCTAssertFalse(report.resultsAreTrusted)
        XCTAssertEqual(report.logicalBytes, 0)
        XCTAssertEqual(report.largeFiles, [])
        XCTAssertEqual(report.issues, [.rootUnavailable])
    }

    private func makeCandidate(
        at url: URL,
        provider: CloudProviderKind = .dropbox
    ) throws -> CloudStorageRootCandidate {
        let report = CloudStorageRootDiscovery().discover(
            home: url.deletingLastPathComponent(),
            userSelectedMegaRoots: provider == .mega ? [url] : []
        )
        if let candidate = report.candidates.first(where: { $0.url == url.standardizedFileURL }) {
            return candidate
        }
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw CocoaError(.fileReadNoSuchFile) }
        return CloudStorageRootCandidate(
            provider: provider,
            url: url,
            displayName: url.lastPathComponent,
            origin: .userSelected,
            identity: CloudRootIdentity(deviceID: UInt64(value.st_dev), inode: UInt64(value.st_ino))
        )
    }

    private func writeFile(_ url: URL, bytes: Int, modifiedAt: Date = Date()) throws {
        try Data(repeating: 0x5a, count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
