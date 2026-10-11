import XCTest
@testable import ReclaimerCore

final class GeneratedOutputSafetyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-generated-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testBuildNamesDoNotAuthorizePersonalContents() throws {
        for (index, relativePath) in [
            "target", "__pycache__", ".build", "DerivedData", "node_modules/.cache",
            ".gradle/build", ".swiftpm/debug", ".spm-build", "build",
        ].enumerated() {
            let directory = try directoryFixture(relativePath, fileName: "personal-\(index).bin")
            let path = try XCTUnwrap(FileIdentity.capture(path: directory.path)?.canonicalPath)
            let recommendation = try XCTUnwrap(
                DeepAuditScanner().scan(path: root.path).first { $0.path == path },
                relativePath
            )

            XCTAssertEqual(recommendation.action, .reviewRequired, relativePath)
            XCTAssertLessThan(recommendation.safetyScore, 0.8, relativePath)
        }
    }

    func testManifestDoesNotProveEveryBuildDescendantIsGenerated() throws {
        let directory = try directoryFixture("project/.build/debug", fileName: "object.o")
        try Data("// swift-tools-version: 6.0\nimport PackageDescription\n".utf8)
            .write(to: root.appendingPathComponent("project/Package.swift"))
        let personal = root.appendingPathComponent("project/.build/notes.txt")
        let original = Data("Unique personal work, not a compiler product.".utf8)
        try original.write(to: personal)
        try age(root.appendingPathComponent("project/.build"))

        let recommendations = try DeepAuditScanner().scan(path: root.path)
        XCTAssertFalse(recommendations.contains {
            $0.category == .buildArtifact && $0.action == .moveToTrash && $0.safetyScore >= 0.8
        })
        XCTAssertTrue(recommendations.contains { $0.category == .buildArtifact })
        XCTAssertEqual(try Data(contentsOf: personal), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testRuleFallbackCannotRelabelBuildDirectoryAsExecutableLog() throws {
        let directory = try directoryFixture("__pycache__", fileName: "personal.bin")
        let engine = RuleEngine(version: "fixture", rules: [
            ReclaimerRule(
                id: "fixture.cache", title: "Fixture cache", category: "Cache", priority: 100,
                safetyClass: .autoSafe, actionKind: .trash,
                match: RuleMatchSpec(basenameAny: ["__pycache__"]), evidence: ["Fixture rule"]
            ),
        ])
        let path = try XCTUnwrap(FileIdentity.capture(path: directory.path)?.canonicalPath)
        let recommendation = try XCTUnwrap(
            DeepAuditScanner(ruleEngine: engine).scan(path: root.path).first { $0.path == path }
        )

        XCTAssertEqual(recommendation.action, .reviewRequired)
        XCTAssertLessThan(recommendation.safetyScore, 0.8)
    }

    func testFinalValidationRejectsStaleOrRelabeledHighSafetyRecommendations() throws {
        let directory = try directoryFixture("__pycache__", fileName: "personal.bin")
        let identity = try XCTUnwrap(FileIdentity.capture(path: directory.path))
        for category in [BloatCategory.buildArtifact, .oldLog] {
            let recommendation = ReclaimRecommendation(
                path: directory.path, category: category, reclaimableBytes: 12_000_000,
                safetyScore: 0.9, effortScore: 1, description: "Old unsafe recommendation",
                action: .moveToTrash, identity: identity
            )

            XCTAssertThrowsError(try CleanupValidator().validate(recommendation, scanRoot: root.path)) {
                XCTAssertEqual($0 as? CleanupValidationError, .classificationChanged)
            }
        }
        XCTAssertTrue(identity.matchesCurrent(path: directory.path))
    }

    func testOrdinaryOldLogStillPassesTheAuditSafetyBoundary() throws {
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let file = logs.appendingPathComponent("old.log")
        try Data(repeating: 1, count: 2_000_000).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -40 * 24 * 3600)],
            ofItemAtPath: file.path
        )
        let recommendation = try XCTUnwrap(
            DeepAuditScanner().scan(path: root.path).first { $0.category == .oldLog }
        )

        XCTAssertEqual(recommendation.action, .moveToTrash)
        XCTAssertGreaterThanOrEqual(recommendation.safetyScore, 0.8)
        XCTAssertEqual(
            try CleanupValidator().validate(recommendation, scanRoot: root.path).path,
            recommendation.identity?.canonicalPath
        )
    }

    private func directoryFixture(_ path: String, fileName: String) throws -> URL {
        let directory = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0xAC, count: 12_000_000)
            .write(to: directory.appendingPathComponent(fileName))
        try age(directory)
        return directory
    }

    private func age(_ directory: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -48 * 3600)],
            ofItemAtPath: directory.path
        )
    }
}
