import Foundation
import XCTest
@testable import ReclaimerCore

final class BoundedScanTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiBoundedScan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<8 {
            let directory = root.appendingPathComponent("group-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for child in 0..<8 {
                try Data(repeating: UInt8(child), count: 32).write(
                    to: directory.appendingPathComponent("item-\(child).bin")
                )
            }
        }
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func testBudgetProducesBoundedCoverageAndAnnotatesFindings() throws {
        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
        let result = scanner.scanWithCoverage(
            scopes: [ScanScope(name: "Fixture", root: root)],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 4,
                measurementDepth: 4,
                measurementItemBudget: 12,
                deduplicateHardLinks: true
            )
        )

        XCTAssertEqual(result.coverage.state, .bounded)
        XCTAssertEqual(result.coverage.requestedItemBudget, 12)
        XCTAssertLessThanOrEqual(result.coverage.measuredItemCount, 12)
        XCTAssertGreaterThan(result.coverage.skippedItemCount, 0)
        XCTAssertTrue(result.findings.allSatisfy { $0.measurementCoverage == ScanCoverageState.bounded.rawValue })
        XCTAssertTrue(result.coverage.nonClaim.localizedCaseInsensitiveContains("targeted rescan"))
    }

    func testCompleteCoverageIsReportedForSmallTargetedScope() throws {
        let target = root.appendingPathComponent("small.txt")
        try Data("small".utf8).write(to: target)
        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
        let result = scanner.scanWithCoverage(
            scopes: [ScanScope(name: "Targeted", root: target)],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 1,
                measurementDepth: 1,
                measurementItemBudget: 10
            )
        )

        XCTAssertEqual(result.coverage.state, .complete)
        XCTAssertEqual(result.coverage.measuredItemCount, 1)
        XCTAssertEqual(result.coverage.skippedItemCount, 0)
        XCTAssertEqual(result.findings.first?.measurementCoverage, ScanCoverageState.complete.rawValue)
    }

    func testMissingRootProducesDegradedCoverage() throws {
        let missing = root.appendingPathComponent("does-not-exist")
        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
        let result = scanner.scanWithCoverage(
            scopes: [ScanScope(name: "Missing", root: missing)],
            options: ScanOptions(measurementItemBudget: 10)
        )

        XCTAssertEqual(result.coverage.state, .degraded)
        XCTAssertEqual(result.coverage.rootsVisited, 1)
        XCTAssertEqual(result.coverage.rootsDenied, 1)
        XCTAssertTrue(result.coverage.evidence.joined(separator: " ").localizedCaseInsensitiveContains("unreadable"))
    }

    func testHardLinksAreMeasuredOnceWhenDeduplicationEnabled() throws {
        let linkRoot = root.appendingPathComponent("links", isDirectory: true)
        try FileManager.default.createDirectory(at: linkRoot, withIntermediateDirectories: true)
        let original = linkRoot.appendingPathComponent("original.bin")
        let sibling = linkRoot.appendingPathComponent("sibling.bin")
        try Data(repeating: 0x41, count: 4_096).write(to: original)
        try FileManager.default.linkItem(at: original, to: sibling)

        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())
        let result = scanner.scanWithCoverage(
            scopes: [ScanScope(name: "Hard links", root: linkRoot)],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 1,
                measurementDepth: 1,
                measurementItemBudget: 100,
                deduplicateHardLinks: true
            )
        )
        let childFindings = result.findings.filter {
            $0.displayName == original.lastPathComponent || $0.displayName == sibling.lastPathComponent
        }

        XCTAssertEqual(childFindings.count, 2, "paths: \(result.findings.map { $0.path })")
        XCTAssertEqual(childFindings.map(\.allocatedSize).reduce(0, +), childFindings.map(\.allocatedSize).max())
        XCTAssertEqual(result.coverage.state, .complete)
    }
}
