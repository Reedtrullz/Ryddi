import XCTest
@testable import ReclaimerCore

final class FastScannerTests: XCTestCase {
    func testDefaultRootsDoesNotCrash() {
        let roots = FastScanner.defaultRoots()
        XCTAssertFalse(roots.isEmpty, "Should find at least some roots on any real Mac")
    }

    func testFastScannerClassifiesCacheAsSafe() async throws {
        let engine = try RuleEngine.bundled()
        let scanner = FastScanner(ruleEngine: engine)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-test-\(UUID().uuidString)")

        let cacheDir = root.appendingPathComponent("Library/Caches/TestCache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1_000_000).write(to: cacheDir.appendingPathComponent("blob"))
        defer { try? FileManager.default.removeItem(at: root) }

        let items = try await scanner.scan(roots: [ScanRoot(name: "Test", path: cacheDir.path)])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].bucket, .safe)
        XCTAssertGreaterThan(items[0].sizeBytes, 0)
        XCTAssertFalse(items[0].ruleTitle.isEmpty)
    }

    func testRuleEngineClassifiesNeverTouch() throws {
        let engine = try RuleEngine.bundled()
        let classification = engine.classify(
            path: "/Users/test/.hermes/config.yaml",
            isDirectory: false,
            isSymbolicLink: false
        )
        XCTAssertEqual(classification.safetyClass, .neverTouch)
    }

    func testRuleEngineClassifiesAutoSafe() throws {
        let engine = try RuleEngine.bundled()
        let classification = engine.classify(
            path: "/Users/test/Library/Caches/Codex/Cache_Data/blob",
            isDirectory: false,
            isSymbolicLink: false
        )
        XCTAssertEqual(classification.safetyClass, .autoSafe)
    }
}
