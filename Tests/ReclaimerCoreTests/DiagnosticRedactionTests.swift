import XCTest
@testable import ReclaimerCore

final class DiagnosticRedactionTests: XCTestCase {
    func testDiagnosticMetadataContainsTypedCountsAndNeverPrivatePayloadFields() throws {
        let metadata = DiagnosticMetadataBuilder.build(
            appVersion: "0.3.0 /Users/private alias@example",
            preset: .developer,
            stage: .dryRunReady,
            findingCount: 12,
            readableScopeCount: 4,
            totalScopeCount: 6,
            durations: [.scan: 125, .plan: 18],
            eventCounts: [.staleScanRejected: 1],
            lastErrorKind: .dryRunFailed,
            now: Date(timeIntervalSince1970: 1),
            id: "fixture-id"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = try XCTUnwrap(String(data: encoder.encode(metadata), encoding: .utf8))
        XCTAssertEqual(metadata.findingCount, 12)
        XCTAssertEqual(metadata.stage, .dryRunReady)
        XCTAssertTrue(text.contains("staleScanRejected"))
        for forbidden in ["/Users/private", "alias@example", "secret-command-output", "private-rule-text"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        for forbiddenKey in ["path", "alias", "username", "commandOutput", "ruleText", "fileContents"] {
            XCTAssertNil(object[forbiddenKey], forbiddenKey)
        }
    }

    func testDiagnosticSummaryStoreRefusesOverwrite() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiDiagnosticStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = DiagnosticMetadataBuilder.build(
            appVersion: "0.3.0",
            preset: .developer,
            stage: nil,
            findingCount: 0,
            readableScopeCount: 0,
            totalScopeCount: 0,
            durations: [:],
            eventCounts: [:],
            lastErrorKind: nil,
            id: "same-id"
        )
        let store = ReportStore(root: root)

        _ = try store.save(diagnosticMetadata: metadata)
        XCTAssertThrowsError(try store.save(diagnosticMetadata: metadata))
    }

    func testAppLoggerUsesTypedPublicMetadataWithoutPathInterpolation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/MacDiskReclaimerApp/RyddiLog.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Logger(subsystem: \"com.reidar.ryddi\""))
        XCTAssertTrue(source.contains("OSSignposter"))
        XCTAssertTrue(source.contains("privacy: .public"))
        XCTAssertFalse(source.contains(".path,"))
        XCTAssertFalse(source.contains("commandOutput"))
        XCTAssertFalse(source.contains("ruleText"))
    }
}
