import XCTest
@testable import ReclaimerCore

@MainActor
final class ScanCoverageTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ryddi-coverage-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func oldLog(in root: URL, name: String = "old.log") throws -> URL {
        let file = root.appendingPathComponent(name)
        try Data(repeating: 1, count: 1_100_000).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -40 * 86_400)], ofItemAtPath: file.path)
        return file
    }

    func testNonzeroDuRetainsCandidatesOnlyForReview() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent(".codex/cache")
        let child = cache.appendingPathComponent("Cache_Data")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let output = Data("10\t\(child.path)\n20\t\(cache.path)\n".utf8)
        let scanner = FastScanner(ruleEngine: try RuleEngine.bundled(homeDirectory: root), measure: { _ in
            ScanProcessOutput(data: output, status: 1)
        })
        let roots = [ScanRoot(name: "Fixture", path: cache.path)]
        let result = try await scanner.scanWithCoverage(roots: roots)
        XCTAssertEqual(result.coverage.first?.status, .partial)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].bucket, .review)
        XCTAssertEqual(result.items[0].safetyClass, .reviewRequired)
        XCTAssertTrue(result.coverage[0].reasons[0].contains("status 1"))
        do { _ = try await scanner.scan(roots: roots); XCTFail("Strict callers must reject partial coverage") }
        catch { XCTAssertTrue(error is ScanCoverageError) }
    }

    func testRootFailuresDoNotEraseIndependentCompleteRoots() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try oldLog(in: root)
        let scanner = FastScanner(ruleEngine: try RuleEngine.bundled())
        let result = try await scanner.scanWithCoverage(roots: [
            ScanRoot(name: "Readable", path: root.path),
            ScanRoot(name: "Missing", path: root.appendingPathComponent("missing").path),
            ScanRoot(name: "File", path: file.path),
        ])
        XCTAssertEqual(result.coverage.filter { $0.status == .complete }.count, 1)
        XCTAssertEqual(result.coverage.filter { $0.status == .failed }.count, 1)
        XCTAssertEqual(result.coverage.filter { $0.status == .skipped }.count, 1)
    }

    func testMalformedRowsAreBoundedAndOutsideRootCannotBecomeCandidate() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("selected")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let outside = try oldLog(in: root)
        let output = Data((String(repeating: "invalid\n", count: 100) + "10\t\(outside.path)\n").utf8)
        let scanner = FastScanner(ruleEngine: try RuleEngine.bundled(), measure: { _ in ScanProcessOutput(data: output, status: 0) })
        let result = try await scanner.scanWithCoverage(roots: [ScanRoot(name: "Fixture", path: selected.path)])
        XCTAssertEqual(result.coverage[0].status, .failed)
        XCTAssertEqual(result.coverage[0].reasons.count, 32)
        XCTAssertTrue(result.items.isEmpty)
    }

    func testEmptyCompletedAuditDiffersFromMissingAndUnreadableRoot() throws {
        let root = try fixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let scanner = DeepAuditScanner()
        let empty = try scanner.scanWithCoverage(path: root.path)
        XCTAssertEqual(empty.coverage.status, .complete)
        XCTAssertTrue(empty.recommendations.isEmpty)
        XCTAssertEqual(try scanner.scanWithCoverage(path: root.appendingPathComponent("missing").path).coverage.status, .failed)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path)
        let denied = try scanner.scanWithCoverage(path: root.path)
        XCTAssertEqual(denied.coverage.status, .failed)
        XCTAssertFalse(denied.coverage.reasons.isEmpty)
        XCTAssertThrowsError(try scanner.scan(path: root.path)) { XCTAssertTrue($0 is ScanCoverageError) }
    }

    func testMetadataDenialPreservesAvailableObservationWithoutDeletionEligibility() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = try oldLog(in: root)
        try Data([1]).write(to: root.appendingPathComponent("denied.txt"))
        let scanner = DeepAuditScanner(readMetadata: { url in
            if url.lastPathComponent == "denied.txt" { throw CocoaError(.fileReadNoPermission) }
            return try DeepAuditScanner.metadata(url)
        })
        let result = try scanner.scanWithCoverage(path: root.path)
        XCTAssertEqual(result.coverage.status, .partial)
        XCTAssertTrue(result.coverage.reasons.contains { $0.contains("Metadata unavailable") })
        let retained = try XCTUnwrap(result.recommendations.first { $0.path == canonicalizedPath(log.path) })
        XCTAssertEqual(retained.action, .reviewRequired)
        XCTAssertLessThan(retained.safetyScore, 0.8)
        XCTAssertThrowsError(try scanner.scan(path: root.path)) { XCTAssertTrue($0 is ScanCoverageError) }
    }

    func testEnumerationFailurePreservesReadableSiblingOnlyForReview() throws {
        let root = try fixture()
        let denied = root.appendingPathComponent("denied")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
            try? FileManager.default.removeItem(at: root)
        }
        _ = try oldLog(in: root)
        try Data([1]).write(to: denied.appendingPathComponent("hidden.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        let result = try DeepAuditScanner().scanWithCoverage(path: root.path)
        XCTAssertEqual(result.coverage.status, .partial)
        XCTAssertTrue(result.coverage.reasons.contains { $0.contains("Enumeration failed") })
        XCTAssertFalse(result.recommendations.isEmpty)
        XCTAssertTrue(result.recommendations.allSatisfy { $0.action == .reviewRequired })
    }

    func testContentReadFailureIsNotSilentDuplicateSuccess() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try oldLog(in: root)
        for name in ["a", "b"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 10).write(to: directory.appendingPathComponent("duplicate.bin"))
        }
        let scanner = DeepAuditScanner(readMetadata: { url in
            let metadata = try DeepAuditScanner.metadata(url)
            if url.lastPathComponent == "duplicate.bin" { try FileManager.default.removeItem(at: url) }
            return metadata
        })
        let result = try scanner.scanWithCoverage(path: root.path)
        XCTAssertEqual(result.coverage.status, .partial)
        XCTAssertTrue(result.coverage.reasons.contains { $0.contains("Duplicate content could not be verified") })
        XCTAssertFalse(result.recommendations.contains { $0.category == .duplicateFile })
        XCTAssertTrue(result.recommendations.allSatisfy { $0.action == .reviewRequired })
    }

    func testEntryLimitProducesExplicitPartialResultAndKeepsStrictError() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try oldLog(in: root, name: "first.log")
        _ = try oldLog(in: root, name: "second.log")
        let scanner = DeepAuditScanner(maximumEntries: 1)
        let result = try scanner.scanWithCoverage(path: root.path)
        XCTAssertEqual(result.coverage.status, .partial)
        XCTAssertEqual(result.recommendations.count, 1)
        XCTAssertEqual(result.recommendations[0].action, .reviewRequired)
        XCTAssertThrowsError(try scanner.scan(path: root.path)) { XCTAssertEqual($0 as? ScanWorkError, .entryLimit) }
    }

    func testCoverageJSONTextAndLegacyDecodeNeverClaimAutomaticEligibility() throws {
        let rec = ReclaimRecommendation(path: "/fixture", category: .oldLog, reclaimableBytes: 100,
                                        safetyScore: 0.9, effortScore: 1, description: "Fixture", action: .moveToTrash)
        let report = AuditReport(scannedPaths: ["/fixture"], totalBytes: 100, bloatBytes: 100,
                                 reclaimableBytes: 100, recommendations: [rec],
                                 coverage: [ScanCoverage(path: "/fixture", status: .partial, reasons: ["Metadata denied"])])
        XCTAssertFalse(report.hasCompleteCoverage)
        XCTAssertEqual(report.safeToReclaimBytes, 0)
        XCTAssertEqual(report.needsReviewBytes, 100)
        XCTAssertTrue(AuditReportFormatter.plainText(report: report).contains("Coverage: /fixture: partial"))
        let data = AuditReportFormatter.json(report: report)
        XCTAssertEqual(try JSONDecoder().decode(AuditReport.self, from: data).coverage, report.coverage)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "coverage")
        let old = try JSONDecoder().decode(AuditReport.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(old.hasCompleteCoverage)
        XCTAssertEqual(old.safeToReclaimBytes, 0)
        XCTAssertTrue(AuditReportFormatter.plainText(report: old).contains("unverified (legacy report)"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func cli(path: String, json: Bool) throws -> ScanProcessOutput {
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent(".build/debug/RyddiApp")
        process.arguments = ["audit", path] + (json ? ["--json"] : [])
        return try BoundedScanProcess.run(process, timeout: 10, maximumOutputBytes: 1_048_576)
    }

    func testCLIEmptySuccessHasExplicitCompleteCoverageAndExitZero() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try cli(path: root.path, json: true)
        XCTAssertEqual(output.status, 0)
        let report = try JSONDecoder().decode(AuditReport.self, from: output.data)
        XCTAssertTrue(report.hasCompleteCoverage)
        XCTAssertTrue(report.recommendations.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testCLIFailedRootJSONHasCoverageAndExitTwo() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try cli(path: root.appendingPathComponent("missing").path, json: true)
        XCTAssertEqual(output.status, 2)
        XCTAssertEqual(try JSONDecoder().decode(AuditReport.self, from: output.data).coverage[0].status, .failed)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testCLIFailedRootTextHasWarningAndExitTwo() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try cli(path: root.appendingPathComponent("missing").path, json: false)
        XCTAssertEqual(output.status, 2)
        let text = String(decoding: output.data, as: UTF8.self)
        XCTAssertTrue(text.contains("Coverage:"))
        XCTAssertTrue(text.contains("failed"))
        XCTAssertTrue(text.contains("Automatic cleanup is unavailable"))
    }

    func testAutomaticCleanupRefusalPrecedesConfirmationAndGUIHasCoverageGuard() throws {
        let code = try String(contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/CLI.swift"), encoding: .utf8)
        let refusal = try XCTUnwrap(code.range(of: "guard report.hasCompleteCoverage else"))
        let prompt = try XCTUnwrap(code.range(of: "Confirm (y/N)"))
        XCTAssertLessThan(refusal.lowerBound, prompt.lowerBound)
        let engine = try String(contentsOf: repositoryRoot.appendingPathComponent("Sources/RyddiApp/ScanEngine.swift"), encoding: .utf8)
        XCTAssertTrue(engine.contains("guard let report = auditReport, report.hasCompleteCoverage else { return }"))
        XCTAssertTrue(engine.contains("Incomplete scan coverage:"))
    }
}
