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
