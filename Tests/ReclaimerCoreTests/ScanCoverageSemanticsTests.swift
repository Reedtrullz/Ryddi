import Foundation
import XCTest
@testable import ReclaimerCore

final class ScanCoverageSemanticsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiCoverageSemantics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func testLegacyCoverageJSONDecodesNewCountersAsZero() throws {
        let json = """
        {
          "state": "degraded",
          "requestedItemBudget": 100,
          "measuredItemCount": 12,
          "skippedItemCount": 0,
          "rootsVisited": 2,
          "rootsDenied": 1,
          "maximumMeasurementDepth": 4,
          "evidence": ["Legacy evidence"]
        }
        """

        let coverage = try JSONDecoder().decode(ScanCoverage.self, from: Data(json.utf8))

        XCTAssertEqual(coverage.rootsDenied, 1)
        XCTAssertEqual(coverage.rootsMissing, 0)
        XCTAssertEqual(coverage.rootsPermissionDenied, 0)
        XCTAssertEqual(coverage.rootsUnknown, 0)
        XCTAssertNil(coverage.scopeAccessSummaries)
    }

    func testMissingOptionalRootIsRecordedWithoutDegradingCoverage() throws {
        let missing = root.appendingPathComponent("optional-tool-cache", isDirectory: true)
        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())

        let result = scanner.scanWithCoverage(
            scopes: [ScanScope(name: "Optional cache", root: missing)],
            options: ScanOptions(measurementItemBudget: 10)
        )

        XCTAssertEqual(result.coverage.state, .complete)
        XCTAssertEqual(result.coverage.rootsMissing, 1)
        XCTAssertEqual(result.coverage.rootsPermissionDenied, 0)
        XCTAssertEqual(result.coverage.rootsDenied, 0)
        XCTAssertTrue(result.coverage.evidence.joined(separator: " ").contains("not present"))
    }

    func testEACCESAndEPERMRootsArePermissionDeniedAndDegradeCoverage() throws {
        for code in [POSIXErrorCode.EACCES, .EPERM] {
            let scanner = try FileScanner(
                openFileChecker: NoOpenFilesChecker(),
                scopeReadabilityProvider: { _, _ in
                    ScopeReadability.classify(error: POSIXError(code))
                }
            )

            let result = scanner.scanWithCoverage(
                scopes: [ScanScope(name: code == .EACCES ? "EACCES" : "EPERM", root: self.root)],
                options: ScanOptions(measurementItemBudget: 10)
            )

            XCTAssertEqual(result.coverage.state, .degraded, "\(code)")
            XCTAssertEqual(result.coverage.rootsMissing, 0, "\(code)")
            XCTAssertEqual(result.coverage.rootsPermissionDenied, 1, "\(code)")
            XCTAssertEqual(result.coverage.rootsDenied, 1, "\(code)")
        }
    }

    func testBudgetExhaustionIsBoundedIndependentlyOfMissingRoots() throws {
        let measuredRoot = root.appendingPathComponent("measured", isDirectory: true)
        try FileManager.default.createDirectory(at: measuredRoot, withIntermediateDirectories: true)
        for index in 0..<8 {
            try Data(repeating: UInt8(index), count: 32).write(
                to: measuredRoot.appendingPathComponent("item-\(index).bin")
            )
        }
        let missing = root.appendingPathComponent("optional-missing", isDirectory: true)
        let scanner = try FileScanner(openFileChecker: NoOpenFilesChecker())

        let result = scanner.scanWithCoverage(
            scopes: [
                ScanScope(name: "Measured", root: measuredRoot),
                ScanScope(name: "Optional missing", root: missing)
            ],
            options: ScanOptions(
                minimumFindingSize: 0,
                maximumFindingDepth: 2,
                measurementDepth: 2,
                measurementItemBudget: 3
            )
        )

        XCTAssertEqual(result.coverage.state, .bounded)
        XCTAssertLessThanOrEqual(result.coverage.measuredItemCount, 3)
        XCTAssertGreaterThan(result.coverage.skippedItemCount, 0)
        XCTAssertEqual(result.coverage.rootsMissing, 1)
        XCTAssertEqual(result.coverage.rootsPermissionDenied, 0)
    }
}
