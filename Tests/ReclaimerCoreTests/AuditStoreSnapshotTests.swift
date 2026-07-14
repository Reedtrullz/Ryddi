import Foundation
import XCTest
@testable import ReclaimerCore

final class AuditStoreSnapshotTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiAuditStoreSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func testSnapshotIndexesAuditDirectoryOnce() throws {
        let writer = AuditStore(root: root)
        _ = try writer.save(plan: makePlan(id: "plan-one"))
        _ = try writer.save(plan: makePlan(id: "plan-two"))
        _ = try writer.save(receipt: makeReceipt(id: "receipt-one"))
        _ = try writer.save(receipt: makeReceipt(id: "receipt-two"))
        let directoryReader = SpyAuditDirectoryReader()
        let store = AuditStore(
            root: root,
            directoryReader: directoryReader,
            decoder: JSONAuditDecoder()
        )

        let snapshot = store.snapshot(limitPerKind: 20)

        XCTAssertEqual(directoryReader.readCount, 1)
        XCTAssertEqual(snapshot.receipts.count, 2)
        XCTAssertEqual(snapshot.plans.count, 2)
        XCTAssertEqual(snapshot.summary.totalKnownFileCount, 4)
    }

    func testSnapshotCapsBeforeDecoding() throws {
        let writer = AuditStore(root: root)
        for index in 0..<100 {
            let url = try writer.save(receipt: makeReceipt(id: "receipt-\(index)"))
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
                ofItemAtPath: url.path
            )
        }
        let decoder = SpyAuditDecoder()
        let dataReader = SpyAuditDataReader()
        let store = AuditStore(
            root: root,
            directoryReader: SpyAuditDirectoryReader(),
            dataReader: dataReader,
            decoder: decoder
        )

        let snapshot = store.snapshot(limitPerKind: 20)

        XCTAssertEqual(dataReader.readCount, 20)
        XCTAssertEqual(
            dataReader.readFilenames,
            (80..<100).reversed().map { "receipt-receipt-\($0).json" }
        )
        XCTAssertEqual(decoder.receiptDecodeCount, 20)
        XCTAssertEqual(snapshot.receipts.count, 20)
        XCTAssertEqual(snapshot.receipts.first?.id, "receipt-99")
    }

    func testSnapshotRetainsScanSessionDecodeWarnings() throws {
        let store = AuditStore(root: root)
        try store.saveScanSession(makeScanSession(id: "valid"))
        try Data("not-json".utf8).write(
            to: root.appendingPathComponent("scan-session-v1-corrupt.json")
        )
        let directoryReader = SpyAuditDirectoryReader()
        let snapshotStore = AuditStore(
            root: root,
            directoryReader: directoryReader,
            decoder: JSONAuditDecoder()
        )

        let snapshot = snapshotStore.snapshot(limitPerKind: 20)

        XCTAssertEqual(directoryReader.readCount, 1)
        XCTAssertEqual(snapshot.scanSessions.sessions.map(\.id), ["valid"])
        XCTAssertEqual(snapshot.scanSessions.warnings.map(\.kind), [.unreadableScanSession])
    }

    func testListScanSessionsResultPropagatesDirectoryEnumerationFailure() {
        let store = AuditStore(
            root: root,
            directoryReader: ThrowingAuditDirectoryReader(),
            decoder: JSONAuditDecoder()
        )

        XCTAssertThrowsError(try store.listScanSessionsResult(limit: 20)) { error in
            let error = error as NSError
            XCTAssertEqual(error.domain, "AuditStoreSnapshotTests")
            XCTAssertEqual(error.code, 41)
        }
    }

    func testSnapshotFallsBackToEmptyWhenDirectoryEnumerationFails() {
        let store = AuditStore(
            root: root,
            directoryReader: ThrowingAuditDirectoryReader(),
            decoder: JSONAuditDecoder()
        )

        let snapshot = store.snapshot(limitPerKind: 20)

        XCTAssertEqual(snapshot.summary.rootPath, root.standardizedFileURL.path)
        XCTAssertEqual(snapshot.summary.totalKnownFileCount, 0)
        XCTAssertTrue(snapshot.scanSessions.sessions.isEmpty)
        XCTAssertTrue(snapshot.scanSessions.warnings.isEmpty)
        XCTAssertTrue(snapshot.receipts.isEmpty)
    }

    func testListScanSessionsResultPreservesFilenameOrderedWarnings() throws {
        let alpha = root.appendingPathComponent("scan-session-v1-alpha.json")
        let zulu = root.appendingPathComponent("scan-session-v1-zulu.json")
        try Data("not-json".utf8).write(to: alpha)
        try Data("also-not-json".utf8).write(to: zulu)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: alpha.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: zulu.path
        )

        let result = try AuditStore(root: root).listScanSessionsResult(limit: 20)

        XCTAssertEqual(
            result.warnings.map { URL(fileURLWithPath: $0.path).lastPathComponent },
            [alpha.lastPathComponent, zulu.lastPathComponent]
        )
    }

    private func makePlan(id: String) -> ReclaimPlan {
        ReclaimPlan(id: id, mode: "test", items: [], dryRunSummary: [])
    }

    private func makeReceipt(id: String) -> ExecutionReceipt {
        ExecutionReceipt(
            id: id,
            ruleVersion: "test",
            mode: ExecutionMode.dryRun.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: [],
            userConfirmed: false
        )
    }

    private func makeScanSession(id: String) -> ScanSession {
        ScanSession(
            id: id,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            appVersion: "test",
            ruleVersion: "test",
            preset: .developer,
            scopeDigest: "scope",
            policyDigest: "policy"
        )
    }
}

private final class SpyAuditDataReader: AuditDataReading, @unchecked Sendable {
    private let lock = NSLock()
    private var readURLs: [URL] = []

    var readCount: Int {
        lock.withLock { readURLs.count }
    }

    var readFilenames: [String] {
        lock.withLock { readURLs.map(\.lastPathComponent) }
    }

    func read(from url: URL) throws -> Data {
        lock.withLock { readURLs.append(url) }
        return try Data(contentsOf: url)
    }
}

private struct ThrowingAuditDirectoryReader: AuditDirectoryReading {
    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        throw NSError(domain: "AuditStoreSnapshotTests", code: 41)
    }
}

private final class SpyAuditDirectoryReader: AuditDirectoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0

    var readCount: Int {
        lock.withLock { reads }
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        lock.withLock { reads += 1 }
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

private final class SpyAuditDecoder: AuditDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private let decoder = JSONAuditDecoder()
    private var receiptDecodes = 0

    var receiptDecodeCount: Int {
        lock.withLock { receiptDecodes }
    }

    func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        if type == ExecutionReceipt.self {
            lock.withLock { receiptDecodes += 1 }
        }
        return try decoder.decode(type, from: data)
    }
}
