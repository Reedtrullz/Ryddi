import XCTest
@testable import ReclaimerCore

final class DeepAuditScannerTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDetectsBuildArtifact() throws {
        let buildDir = tempDir.appendingPathComponent("myapp/.build/debug")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 20_000_000).write(to: buildDir.appendingPathComponent("blob"))
        let old = Date(timeIntervalSinceNow: -3600 * 48)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: buildDir.path)

        let recs = try DeepAuditScanner().scan(path: tempDir.path)
        let found = recs.first { $0.category == .buildArtifact }
        XCTAssertNotNil(found)
        XCTAssertTrue(found!.path.contains(".build"))
        XCTAssertGreaterThan(found!.reclaimableBytes, 0)
    }

    func testDetectsOldLog() throws {
        let logs = tempDir.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2_000_000).write(to: logs.appendingPathComponent("old.log"))
        let old = Date(timeIntervalSinceNow: -3600 * 24 * 40)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: logs.appendingPathComponent("old.log").path)

        let recs = try DeepAuditScanner().scan(path: tempDir.path)
        let found = recs.first { $0.category == .oldLog }
        XCTAssertNotNil(found)
        XCTAssertTrue(found!.path.hasSuffix(".log"))
    }

    func testDetectsAISessionCache() throws {
        let sessions = tempDir.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2_000_000).write(to: sessions.appendingPathComponent("session_1.jsonl"))

        let recs = try DeepAuditScanner().scan(path: tempDir.path)
        let found = recs.first { $0.category == .aiSessionCache }
        XCTAssertNotNil(found)
        XCTAssertTrue(found!.path.contains(".codex"))
    }

    func testDetectsDuplicateFile() throws {
        let d1 = tempDir.appendingPathComponent("dir1")
        let d2 = tempDir.appendingPathComponent("dir2")
        try FileManager.default.createDirectory(at: d1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: d2, withIntermediateDirectories: true)
        let data = Data(repeating: 0xAB, count: 6_000_000)
        try data.write(to: d1.appendingPathComponent("file.bin"))
        try data.write(to: d2.appendingPathComponent("file.bin"))

        let recs = try DeepAuditScanner().scan(path: tempDir.path)
        let found = recs.first { $0.category == .duplicateFile }
        XCTAssertNotNil(found)
        XCTAssertGreaterThan(found!.reclaimableBytes, 0)
    }

    func testDetectsOldInstaller() throws {
        let downloads = tempDir.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 15_000_000).write(to: downloads.appendingPathComponent("app.dmg"))
        let old = Date(timeIntervalSinceNow: -3600 * 24 * 100)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: downloads.appendingPathComponent("app.dmg").path)

        let recs = try DeepAuditScanner().scan(path: tempDir.path)
        let found = recs.first { $0.category == .oldInstaller }
        XCTAssertNotNil(found)
        XCTAssertTrue(found!.path.hasSuffix(".dmg"))
    }

    func testSafetyCheckerProtectsRecentNodeModules() throws {
        let project = tempDir.appendingPathComponent("project")
        let nm = project.appendingPathComponent("node_modules/big")
        try FileManager.default.createDirectory(at: nm, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 20_000_000).write(to: nm.appendingPathComponent("x"))
        try "{}".data(using: .utf8)!.write(to: project.appendingPathComponent("package.json"))
        let recent = Date(timeIntervalSinceNow: -3600 * 24 * 2)
        try FileManager.default.setAttributes([.modificationDate: recent], ofItemAtPath: project.appendingPathComponent("package.json").path)

        let recs = try DeepAuditScanner().scan(path: tempDir.path)
        let found = recs.first { $0.path.contains("node_modules") }
        XCTAssertNotNil(found)
        XCTAssertLessThanOrEqual(found!.safetyScore, 0.3)
        if case .reviewRequired = found!.action {} else {
            XCTFail("Expected reviewRequired for recent node_modules")
        }
    }

    func testSafetyCheckerProtectsRecentBuildDir() throws {
        let build = tempDir.appendingPathComponent("project/.build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 20_000_000).write(to: build.appendingPathComponent("x"))
        let recent = Date(timeIntervalSinceNow: -3600 * 2)
        try FileManager.default.setAttributes([.modificationDate: recent], ofItemAtPath: build.path)

        let recs = try DeepAuditScanner().scan(path: tempDir.path)
        let found = recs.first { $0.path.contains(".build") }
        XCTAssertNotNil(found)
        XCTAssertLessThanOrEqual(found!.safetyScore, 0.3)
        if case .reviewRequired = found!.action {} else {
            XCTFail("Expected reviewRequired for recent build dir")
        }
    }

    func testImpactScorer() {
        let rec = ReclaimRecommendation(
            path: "/tmp/x", category: .oldLog,
            reclaimableBytes: 1000, safetyScore: 0.9, effortScore: 1.0,
            description: "test", action: .moveToTrash
        )
        let expected = Double(1000) * 0.9 / (1.0 - 1.0 * 0.5 + 0.5)
        XCTAssertEqual(ImpactScorer.score(rec), expected, accuracy: 0.001)
    }

    func testFormatterPlainText() {
        let rec = ReclaimRecommendation(
            path: "/tmp/x", category: .buildArtifact,
            reclaimableBytes: 4_294_967_296, safetyScore: 0.9, effortScore: 1.0,
            description: "test", action: .moveToTrash
        )
        let report = AuditReport(scannedPaths: ["/tmp"], totalBytes: 10, bloatBytes: 5, reclaimableBytes: 5, recommendations: [rec])
        let text = AuditReportFormatter.plainText(report: report)
        XCTAssertTrue(text.contains("=== Ryddi Deep Audit:"))
        XCTAssertTrue(text.contains("buildArtifact"))
    }

    func testFormatterJSON() {
        let rec = ReclaimRecommendation(
            path: "/tmp/x", category: .oldLog,
            reclaimableBytes: 1000, safetyScore: 0.8, effortScore: 1.0,
            description: "test", action: .moveToTrash
        )
        let report = AuditReport(scannedPaths: ["/tmp"], totalBytes: 1000, bloatBytes: 1000, reclaimableBytes: 1000, recommendations: [rec])
        let data = AuditReportFormatter.json(report: report)
        let decoded = try? JSONDecoder().decode(AuditReport.self, from: data)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.recommendations.first?.path, "/tmp/x")
    }
}
