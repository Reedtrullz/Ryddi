import Darwin
import Foundation
import XCTest
@testable import ReclaimerCore

final class ScopeAccessProbeTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiScopeAccessProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot, FileManager.default.fileExists(atPath: fixtureRoot.path) {
            try FileManager.default.removeItem(at: fixtureRoot)
        }
    }

    func testEmptyReadableDirectoryUsesListingOperation() {
        let result = FileManagerScopeAccessProbe().probe(fixtureRoot)

        XCTAssertEqual(result.state, .readable)
        XCTAssertEqual(result.operation, .listDirectory)
        XCTAssertNil(result.errorCode)
        XCTAssertTrue(result.detail.contains("discarded"))
    }

    func testRegularFileIsOpenedReadOnlyAndClosedWithoutReading() throws {
        let file = fixtureRoot.appendingPathComponent("fixture.txt")
        try Data("private fixture contents".utf8).write(to: file)

        let result = FileManagerScopeAccessProbe().probe(file)

        XCTAssertEqual(result.state, .readable)
        XCTAssertEqual(result.operation, .openFile)
        XCTAssertNil(result.errorCode)
        XCTAssertTrue(result.detail.contains("without reading"))
        XCTAssertFalse(result.detail.contains("private fixture contents"))
    }

    func testExistingDirectoryWhoseListingIsDeniedIsNotReadable() {
        let underlying = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EPERM),
            userInfo: ["private-entry": "do-not-record"]
        )
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: 257,
            userInfo: [NSUnderlyingErrorKey: underlying, NSFilePathErrorKey: "/Users/private/secret"]
        )
        let fileManager = StubProbeFileManager(
            fileType: .typeDirectory,
            listingError: error,
            directoryEntries: ["private-name"]
        )

        let result = FileManagerScopeAccessProbe(fileManager: fileManager)
            .probe(URL(fileURLWithPath: "/protected"))

        XCTAssertEqual(result.state, .permissionDenied)
        XCTAssertEqual(result.operation, .listDirectory)
        XCTAssertEqual(result.errorCode, Int(EPERM))
        XCTAssertFalse(result.detail.contains("private"))
        XCTAssertFalse(result.detail.contains("secret"))
    }

    func testDirectoryEntryNamesAreDiscardedFromEvidence() {
        let fileManager = StubProbeFileManager(
            fileType: .typeDirectory,
            directoryEntries: ["customer-secrets.db"]
        )

        let result = FileManagerScopeAccessProbe(fileManager: fileManager)
            .probe(URL(fileURLWithPath: "/fixture"))

        XCTAssertEqual(result.state, .readable)
        XCTAssertEqual(result.operation, .listDirectory)
        XCTAssertFalse(result.detail.contains("customer-secrets.db"))
    }

    func testMissingPathUsesNormalizedENOENTEvidence() {
        let missing = fixtureRoot.appendingPathComponent("missing")

        let result = FileManagerScopeAccessProbe().probe(missing)

        XCTAssertEqual(result.state, .missing)
        XCTAssertEqual(result.operation, .metadata)
        XCTAssertEqual(result.errorCode, Int(ENOENT))
    }

    func testNestedENOTDIRIsNormalizedAsMissing() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTDIR))
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileReadUnknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        let fileManager = StubProbeFileManager(metadataError: error)

        let result = FileManagerScopeAccessProbe(fileManager: fileManager)
            .probe(URL(fileURLWithPath: "/not-a-directory/child"))

        XCTAssertEqual(result.state, .missing)
        XCTAssertEqual(result.operation, .metadata)
        XCTAssertEqual(result.errorCode, Int(ENOTDIR))
    }

    func testDirectCocoa257IsUnknownRatherThanPOSIXEACCES() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: 257,
            userInfo: [NSFilePathErrorKey: "/Users/private/secret"]
        )
        let fileManager = StubProbeFileManager(metadataError: error)

        let result = FileManagerScopeAccessProbe(fileManager: fileManager)
            .probe(URL(fileURLWithPath: "/protected"))

        XCTAssertEqual(result.state, .unknown)
        XCTAssertEqual(result.operation, .metadata)
        XCTAssertNil(result.errorCode)
        XCTAssertFalse(result.detail.contains("/Users/private/secret"))
    }

    func testUnclassifiedPOSIXFailureRemainsUnknownWithNumericCode() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
        let fileManager = StubProbeFileManager(metadataError: error)

        let result = FileManagerScopeAccessProbe(fileManager: fileManager)
            .probe(URL(fileURLWithPath: "/fixture"))

        XCTAssertEqual(result.state, .unknown)
        XCTAssertEqual(result.operation, .metadata)
        XCTAssertEqual(result.errorCode, Int(EIO))
    }

    func testFIFOStopsAfterMetadataWithoutOpening() throws {
        let fifo = fixtureRoot.appendingPathComponent("fixture.fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)

        let result = FileManagerScopeAccessProbe().probe(fifo)

        XCTAssertEqual(result.state, .unknown)
        XCTAssertEqual(result.operation, .metadata)
        XCTAssertNil(result.errorCode)
        XCTAssertTrue(result.detail.contains("no open"))
    }

    func testAdvisorRecordsOperationEvidenceWithoutClaimingFullDiskAccessState() {
        let probe = FixedScopeAccessProbe(result: ScopeAccessProbeResult(
            state: .permissionDenied,
            operation: .listDirectory,
            errorCode: Int(EACCES),
            detail: "Directory listing failed because permission was denied."
        ))
        let scope = ScanScope(name: "Protected", root: URL(fileURLWithPath: "/protected"))

        let report = PermissionAdvisor.report(scopes: [scope], probe: probe)

        XCTAssertEqual(report.deniedCount, 1)
        XCTAssertEqual(report.scopeSummaries.first?.operation, .listDirectory)
        XCTAssertEqual(report.scopeSummaries.first?.errorCode, Int(EACCES))
        XCTAssertEqual(
            report.scopeSummaries.first?.detail,
            "Directory listing failed because permission was denied."
        )
        XCTAssertTrue(report.nonClaims.contains { $0.contains("does not") && $0.contains("Full Disk Access") })
    }

    func testFindingOverviewUsesInjectedScopeAccessProbe() {
        let probe = FixedScopeAccessProbe(result: ScopeAccessProbeResult(
            state: .permissionDenied,
            operation: .openFile,
            errorCode: Int(EPERM),
            detail: "Read-only file open failed because permission was denied."
        ))
        let scope = ScanScope(name: "Protected file", root: URL(fileURLWithPath: "/protected/file"))

        let overview = FindingAnalytics.overview(
            findings: [],
            scopes: [scope],
            scopeAccessProbe: probe
        )

        XCTAssertEqual(overview.scopeSummaries.first?.permissionState, .denied)
        XCTAssertEqual(overview.scopeSummaries.first?.operation, .openFile)
        XCTAssertEqual(overview.scopeSummaries.first?.errorCode, Int(EPERM))
        XCTAssertEqual(
            overview.scopeSummaries.first?.detail,
            "Read-only file open failed because permission was denied."
        )
    }

    func testScannerPreservesUnknownSeparatelyFromPermissionDenied() throws {
        let probe = FixedScopeAccessProbe(result: ScopeAccessProbeResult(
            state: .unknown,
            operation: .metadata,
            errorCode: Int(EIO),
            detail: "Metadata check failed with an unclassified POSIX error."
        ))
        let scanner = try FileScanner(
            openFileChecker: NoOpenFilesChecker(),
            scopeAccessProbe: probe
        )

        let result = scanner.scanWithCoverage(
            scopes: [ScanScope(name: "Unknown", root: fixtureRoot)],
            options: ScanOptions(measurementItemBudget: 10)
        )

        XCTAssertEqual(result.coverage.state, .degraded)
        XCTAssertEqual(result.coverage.rootsPermissionDenied, 0)
        XCTAssertEqual(result.coverage.rootsUnknown, 1)
        XCTAssertTrue(result.coverage.evidence.contains { $0.localizedCaseInsensitiveContains("check failed") })
        XCTAssertTrue(result.findings.contains { finding in
            finding.evidence.contains { $0.kind == PermissionState.unknown.rawValue }
        })
    }

    func testLegacyScanSnapshotDecodesScopeSummaryWithoutOperationEvidence() throws {
        let json = """
        {
          "id": "legacy",
          "createdAt": 0,
          "findingCount": 0,
          "totalLogicalSize": 0,
          "totalAllocatedSize": 0,
          "expectedAutoSafeBytes": 0,
          "reviewBytes": 0,
          "protectedBytes": 0,
          "categorySummaries": [],
          "safetySummaries": [],
          "scopeBuckets": [],
          "scopeSummaries": [
            {
              "name": "Legacy scope",
              "path": "/legacy",
              "permissionState": "readable",
              "message": "Directory is readable."
            }
          ],
          "topFindingPaths": []
        }
        """

        let snapshot = try JSONDecoder().decode(ScanSnapshot.self, from: Data(json.utf8))
        let summary = try XCTUnwrap(snapshot.scopeSummaries.first)

        XCTAssertEqual(summary.permissionState, .readable)
        XCTAssertNil(summary.operation)
        XCTAssertNil(summary.errorCode)
        XCTAssertNil(summary.detail)
    }
}

private struct FixedScopeAccessProbe: ScopeAccessProbing {
    let result: ScopeAccessProbeResult

    func probe(_ url: URL) -> ScopeAccessProbeResult {
        result
    }
}

private final class StubProbeFileManager: FileManager, @unchecked Sendable {
    private let fileType: FileAttributeType
    private let metadataError: Error?
    private let listingError: Error?
    private let directoryEntries: [String]

    init(
        fileType: FileAttributeType = .typeRegular,
        metadataError: Error? = nil,
        listingError: Error? = nil,
        directoryEntries: [String] = []
    ) {
        self.fileType = fileType
        self.metadataError = metadataError
        self.listingError = listingError
        self.directoryEntries = directoryEntries
        super.init()
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if let metadataError {
            throw metadataError
        }
        return [.type: fileType]
    }

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        if let listingError {
            throw listingError
        }
        return directoryEntries
    }
}
