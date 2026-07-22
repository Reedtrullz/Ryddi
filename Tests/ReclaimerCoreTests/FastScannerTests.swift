import XCTest
@testable import ReclaimerCore

final class FastScannerTests: XCTestCase {
    func testPackageVersionGroupingUsesStableIdentity() {
        let versionOne = ScanItem(
            name: "package@1.2.3", path: "/tmp/package-1", sizeBytes: 1,
            bucket: .review, ruleTitle: "Fixture"
        )
        let versionTwo = ScanItem(
            name: "package@2.0.0-beta", path: "/tmp/package-2", sizeBytes: 2,
            bucket: .review, ruleTitle: "Fixture"
        )
        let first = ScanItemGroup(baseName: versionOne.groupKey, items: [versionOne, versionTwo])
        let second = ScanItemGroup(baseName: versionOne.groupKey, items: [versionOne, versionTwo])

        XCTAssertEqual(versionOne.groupKey, "package")
        XCTAssertEqual(versionTwo.groupKey, "package")
        XCTAssertEqual(first.id, second.id)
    }

    func testGroupingDoesNotCollapseOrdinaryAtNames() {
        let emailLike = ScanItem(
            name: "user@host.key", path: "/tmp/email", sizeBytes: 1,
            bucket: .review, ruleTitle: "Fixture"
        )
        let retinaAsset = ScanItem(
            name: "image@2x.png", path: "/tmp/image", sizeBytes: 1,
            bucket: .review, ruleTitle: "Fixture"
        )

        XCTAssertEqual(emailLike.groupKey, emailLike.name)
        XCTAssertEqual(retinaAsset.groupKey, retinaAsset.name)
    }

    func testDefaultRootsDoesNotCrash() {
        let roots = FastScanner.defaultRoots()
        XCTAssertFalse(roots.isEmpty, "Should find at least some roots on any real Mac")
    }

    func testFastScannerClassifiesUnconditionalCacheAsSafe() async throws {
        let engine = try RuleEngine.bundled()
        let scanner = FastScanner(ruleEngine: engine)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-test-\(UUID().uuidString)")

        let cacheDir = root.appendingPathComponent(".codex/cache")
        let child = cacheDir.appendingPathComponent("Cache_Data")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1_000_000).write(to: child.appendingPathComponent("blob"))
        defer { try? FileManager.default.removeItem(at: root) }

        let items = try await scanner.scan(roots: [ScanRoot(name: "Test", path: cacheDir.path)])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].bucket, .safe)
        XCTAssertGreaterThan(items[0].sizeBytes, 0)
        XCTAssertFalse(items[0].ruleTitle.isEmpty)
        XCTAssertEqual(items[0].safetyClass, .autoSafe)
        XCTAssertNotNil(items[0].identity)
    }

    func testFastScannerKeepsConditionalCacheInReview() async throws {
        let scanner = FastScanner(ruleEngine: try RuleEngine.bundled())
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-test-\(UUID().uuidString)")
        let cacheRoot = root.appendingPathComponent("Library/Caches")
        let child = cacheRoot.appendingPathComponent("SomeApp")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_000_000).write(to: child.appendingPathComponent("blob"))
        defer { try? FileManager.default.removeItem(at: root) }

        let items = try await scanner.scan(roots: [
            ScanRoot(name: "Caches", path: cacheRoot.path),
            ScanRoot(name: "Duplicate root", path: cacheRoot.path),
        ])

        XCTAssertEqual(items.count, 1, "Duplicate roots and root-total rows must not inflate results")
        XCTAssertEqual(items[0].bucket, .review)
        XCTAssertEqual(items[0].safetyClass, .safeAfterCondition)
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
