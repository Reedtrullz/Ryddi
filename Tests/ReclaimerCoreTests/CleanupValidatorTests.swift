import XCTest
@testable import ReclaimerCore

final class CleanupValidatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-validator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAcceptsUnchangedAutoSafeDescendant() throws {
        let itemURL = root.appendingPathComponent("cache/item")
        try FileManager.default.createDirectory(at: itemURL, withIntermediateDirectories: true)
        let engine = testRuleEngine(safety: .autoSafe, action: .trash)
        let identity = try XCTUnwrap(FileIdentity.capture(path: itemURL.path))
        let item = ScanItem(
            name: "item", path: itemURL.path, sizeBytes: 10,
            bucket: .safe, ruleTitle: "Test cache", safetyClass: .autoSafe,
            actionKind: .trash, scanRoot: root.path, identity: identity
        )

        XCTAssertEqual(
            try CleanupValidator().validate(item, ruleEngine: engine).path,
            identity.canonicalPath
        )
    }

    func testRejectsChangedFilesystemIdentity() throws {
        let itemURL = root.appendingPathComponent("cache/item")
        try FileManager.default.createDirectory(at: itemURL, withIntermediateDirectories: true)
        let identity = try XCTUnwrap(FileIdentity.capture(path: itemURL.path))
        try FileManager.default.removeItem(at: itemURL)
        try Data("replacement".utf8).write(to: itemURL)
        let item = ScanItem(
            name: "item", path: itemURL.path, sizeBytes: 10,
            bucket: .safe, ruleTitle: "Test cache", safetyClass: .autoSafe,
            actionKind: .trash, scanRoot: root.path, identity: identity
        )

        XCTAssertThrowsError(try CleanupValidator().validate(item, ruleEngine: testRuleEngine(safety: .autoSafe, action: .trash))) {
            XCTAssertEqual($0 as? CleanupValidationError, .changedIdentity)
        }
    }

    func testRejectsConditionalClassification() throws {
        let itemURL = root.appendingPathComponent("cache/item")
        try FileManager.default.createDirectory(at: itemURL, withIntermediateDirectories: true)
        let item = ScanItem(
            name: "item", path: itemURL.path, sizeBytes: 10,
            bucket: .safe, ruleTitle: "Test cache", safetyClass: .safeAfterCondition,
            actionKind: .trash, scanRoot: root.path,
            identity: FileIdentity.capture(path: itemURL.path)
        )

        XCTAssertThrowsError(try CleanupValidator().validate(item, ruleEngine: testRuleEngine(safety: .safeAfterCondition, action: .trash))) {
            XCTAssertEqual($0 as? CleanupValidationError, .notSelectedSafeItem)
        }
    }

    func testRejectsDirectoryContainingOpenFile() throws {
        let itemURL = root.appendingPathComponent("cache/item")
        try FileManager.default.createDirectory(at: itemURL, withIntermediateDirectories: true)
        let openURL = itemURL.appendingPathComponent("active.log")
        _ = FileManager.default.createFile(atPath: openURL.path, contents: Data("active".utf8))
        let handle = try FileHandle(forWritingTo: openURL)
        defer { try? handle.close() }
        let item = ScanItem(
            name: "item", path: itemURL.path, sizeBytes: 10,
            bucket: .safe, ruleTitle: "Test cache", safetyClass: .autoSafe,
            actionKind: .trash, scanRoot: root.path,
            identity: FileIdentity.capture(path: itemURL.path)
        )

        XCTAssertThrowsError(try CleanupValidator().validate(item, ruleEngine: testRuleEngine(safety: .autoSafe, action: .trash))) {
            XCTAssertEqual($0 as? CleanupValidationError, .openFiles)
        }
    }

    private func testRuleEngine(safety: SafetyClass, action: ActionKind) -> RuleEngine {
        RuleEngine(version: "test", rules: [
            ReclaimerRule(
                id: "test.cache", title: "Test cache", category: "Cache", priority: 100,
                safetyClass: safety, actionKind: action,
                match: RuleMatchSpec(containsAny: ["/cache/"]),
                evidence: ["Fixture rule"]
            )
        ])
    }
}
