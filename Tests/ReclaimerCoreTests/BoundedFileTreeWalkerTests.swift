import Foundation
import XCTest
@testable import ReclaimerCore

final class BoundedFileTreeWalkerTests: XCTestCase {
    func testMeasurementDepthOneExcludesFileFourLevelsBelowRoot() throws {
        let fixture = try ScannerFixture()
        let root = try fixture.directory("root")
        let deep = try fixture.directory("root/a/b/c")
        try fixture.write(bytes: 64 * 1024, to: deep.appendingPathComponent("deep.bin"))

        let result = try FileScanner().scanWithCoverage(
            scopes: [ScanScope(name: "Root", root: root)],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 0,
                measurementDepth: 1,
                measurementItemBudget: 100
            )
        )

        let finding = try XCTUnwrap(result.findings.first { $0.path == root.path })
        XCTAssertEqual(finding.logicalSize, 0)
        XCTAssertEqual(finding.allocatedSize, 0)
        XCTAssertEqual(result.coverage.scopeCoverage.first?.deepestMeasuredLevel, 1)
    }

    func testRoundRobinBudgetMeasuresBothReadableRoots() throws {
        let fixture = try ScannerFixture()
        let first = try fixture.tree("first", files: 8, bytesPerFile: 4096)
        let second = try fixture.tree("second", files: 1, bytesPerFile: 4096)
        let result = try FileScanner().scanWithCoverage(
            scopes: [ScanScope(name: "First", root: first), ScanScope(name: "Second", root: second)],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 1,
                measurementDepth: 8,
                measurementItemBudget: 4
            )
        )
        XCTAssertGreaterThan(result.coverage.scopeCoverage[0].measuredItemCount, 0)
        XCTAssertGreaterThan(result.coverage.scopeCoverage[1].measuredItemCount, 0)
        XCTAssertGreaterThan(result.findings.first { $0.path == second.path }?.allocatedSize ?? 0, 0)
        XCTAssertEqual(result.coverage.state, .bounded)
    }

    func testCancellationDuringDirectoryReadStopsChildScheduling() throws {
        let fixture = try ScannerFixture()
        let root = try fixture.tree("cancelled", files: 8, bytesPerFile: 4096)
        let cancellation = CancellationProbe()
        let fileManager = CancellingFileManager(cancellation: cancellation)
        let tree = BoundedFileTreeWalker(scopeReadabilityProvider: { _, _ in .readable }).walk(
            scopes: [ScanScope(name: "Cancelled", root: root)],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 1,
                measurementDepth: 1,
                measurementItemBudget: 100
            ),
            fileManager: fileManager,
            userPathPolicy: .empty,
            control: ScanControl(isCancelled: { cancellation.isCancelled })
        )

        XCTAssertEqual(tree.nodes.count, 1)
        XCTAssertEqual(tree.coverage.measuredItemCount, 1)
        XCTAssertEqual(tree.coverage.scopeCoverage[0].skippedItemCount, 0)
        XCTAssertEqual(tree.coverage.scopeCoverage[0].state, .bounded)
        XCTAssertTrue(tree.coverage.scopeCoverage[0].evidence.contains { $0.contains("cancelled") })
        XCTAssertEqual(tree.coverage.state, .bounded)
        XCTAssertTrue(tree.coverage.evidence.contains { $0.contains("cancelled") })
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

private final class CancellingFileManager: FileManager, @unchecked Sendable {
    private let cancellation: CancellationProbe

    init(cancellation: CancellationProbe) {
        self.cancellation = cancellation
        super.init()
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        let children = try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
        cancellation.cancel()
        return children
    }
}

private final class ScannerFixture {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiScannerFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func directory(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func tree(_ path: String, files: Int, bytesPerFile: Int) throws -> URL {
        let directory = try directory(path)
        for index in 0..<files {
            try write(bytes: bytesPerFile, to: directory.appendingPathComponent("item-\(index).bin"))
        }
        return directory
    }

    func write(bytes: Int, to url: URL) throws {
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }
}
