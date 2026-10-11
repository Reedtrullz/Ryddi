import XCTest
@testable import ReclaimerCore

final class KnownRootSafetyTests: XCTestCase {
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: canonicalizedPath(FileManager.default.temporaryDirectory.path))
            .appendingPathComponent("ryddi-root-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLookalikeAndEmbeddedPathsAreNotUnconditional() throws {
        let engine = try engine()
        let relatives = [
            ".codex/cache-personal/blob", ".codex/.tmp-backup/blob",
            ".hermes/cache-backup/blob", ".hermes/tmp-personal/blob",
            ".hermes/hermes-agent/.build-backup/blob",
            "Library/Caches/Codex-backup/blob",
            "Library/Developer/Xcode/DerivedData-archive/blob",
            "unrelated/.codex/cache/blob", "unrelated/.hermes/cache/blob",
            "unrelated/Library/Developer/Xcode/DerivedData/blob",
            ".codex/cache/../../cache-personal/blob",
        ]
        for relative in relatives {
            let path = try directory(relative).path
            XCTAssertNotEqual(classify(path, with: engine).safetyClass, .autoSafe, path)
        }
        let embedded = try directory("unrelated/private/tmp/codex/blob")
        XCTAssertNotEqual(classify(embedded.path, with: engine).safetyClass, .autoSafe)
    }

    func testExactKnownRootsAndDescendantsRemainUnconditional() throws {
        let engine = try engine()
        for relative in [".codex/cache", ".codex/.tmp", "Library/Caches/Codex",
                         "Library/Developer/Xcode/DerivedData", ".hermes/cache",
                         ".hermes/tmp", ".hermes/hermes-agent/.build"] {
            let directory = try directory(relative)
            let child = directory.appendingPathComponent("child/blob")
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            XCTAssertEqual(classify(directory.path, with: engine).safetyClass, .autoSafe, relative)
            XCTAssertEqual(classify(child.path, with: engine).safetyClass, .autoSafe, relative)
        }
    }

    func testAbsoluteRootRequiresExistingExactRootAndContainsOnlyDescendants() throws {
        let scratch = try directory("scratch/codex")
        let child = try directory("scratch/codex/child")
        let sibling = try directory("scratch/codex-personal")
        let rule = ReclaimerRule(id: "fixture.absolute", title: "Known scratch", category: "Fixture", priority: 100,
                                 safetyClass: .autoSafe, actionKind: .trash,
                                 match: RuleMatchSpec(rootAny: [scratch.path]), evidence: [])
        let engine = RuleEngine(version: "test", rules: [rule])
        XCTAssertEqual(classify(scratch.path, with: engine).safetyClass, .autoSafe)
        XCTAssertEqual(classify(child.path, with: engine).safetyClass, .autoSafe)
        XCTAssertEqual(classify(sibling.path, with: engine).safetyClass, .reviewRequired)
        XCTAssertEqual(classify(scratch.appendingPathComponent("missing").path, with: engine).safetyClass, .reviewRequired)
    }

    func testKnownRootSymlinkDoesNotTrustItsPersonalTarget() throws {
        let personal = root.appendingPathComponent("personal")
        try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
        try directory(".codex")
        let link = home.appendingPathComponent(".codex/cache")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: personal)
        let blob = personal.appendingPathComponent("blob")
        try Data("unique personal content".utf8).write(to: blob)

        let engine = try engine()
        XCTAssertNotEqual(classify(link.appendingPathComponent("blob").path, with: engine).safetyClass, .autoSafe)
        XCTAssertNotEqual(engine.classify(path: link.path, isDirectory: false, isSymbolicLink: true).safetyClass, .autoSafe)
        XCTAssertEqual(try Data(contentsOf: blob), Data("unique personal content".utf8))
    }

    func testDescendantSymlinkEscapeIsNotUnconditional() throws {
        let cache = try directory(".codex/cache")
        let personal = root.appendingPathComponent("personal")
        try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
        let link = cache.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: personal)
        try Data("unique".utf8).write(to: personal.appendingPathComponent("blob"))

        XCTAssertNotEqual(classify(link.appendingPathComponent("blob").path, with: try engine()).safetyClass, .autoSafe)
    }

    func testSymlinkAliasWithinRootDoesNotHideProtectedPaths() throws {
        let protected = try directory(".codex/cache/.codex/skills")
        try Data("unique".utf8).write(to: protected.appendingPathComponent("blob"))
        let alias = home.appendingPathComponent(".codex/cache/alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: protected)
        XCTAssertNotEqual(classify(alias.appendingPathComponent("blob").path, with: try engine()).safetyClass, .autoSafe)
    }

    func testScannerAndFinalValidationRejectLookalikeSafeRecords() async throws {
        let sibling = try directory(".codex/cache-personal/child")
        try Data("unique".utf8).write(to: sibling.appendingPathComponent("blob"))
        let engine = try engine()
        let items = try await FastScanner(ruleEngine: engine).scan(roots: [
            ScanRoot(name: "Fixture", path: sibling.deletingLastPathComponent().path),
        ])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.bucket, .review)

        let stale = ScanItem(name: "child", path: sibling.path, sizeBytes: 6,
                             bucket: .safe, ruleTitle: "Old unsafe classification", safetyClass: .autoSafe,
                             actionKind: .trash, scanRoot: home.path,
                             identity: try XCTUnwrap(FileIdentity.capture(path: sibling.path)))
        XCTAssertThrowsError(try CleanupValidator().validate(stale, ruleEngine: engine)) {
            XCTAssertEqual($0 as? CleanupValidationError, .classificationChanged)
        }
    }

    func testValidKnownCachePassesFinalValidationWithoutCleanup() throws {
        let child = try directory(".codex/cache/child")
        let identity = try XCTUnwrap(FileIdentity.capture(path: child.path))
        let item = ScanItem(name: "child", path: child.path, sizeBytes: 0,
                            bucket: .safe, ruleTitle: "Cache", safetyClass: .autoSafe,
                            actionKind: .trash, scanRoot: home.path, identity: identity)
        XCTAssertEqual(try CleanupValidator().validate(item, ruleEngine: try engine()).path, identity.canonicalPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
    }

    func testLegacyGuidanceAndUserProtectionRemainCompatible() throws {
        let legacy = Data(#"{"containsAny":["/cache/"],"suffixAny":[],"basenameAny":[],"pathExtensionAny":[]}"#.utf8)
        let match = try JSONDecoder().decode(RuleMatchSpec.self, from: legacy)
        XCTAssertEqual(try JSONDecoder().decode(RuleMatchSpec.self, from: JSONEncoder().encode(match)), match)
        let bundled = try engine()
        let personal = try directory("Documents/cache/blob")
        let credential = try directory(".codex/cache/auth.json")
        let user = ReclaimerRule(id: "user.auto", title: "Unsafe user override", category: "Fixture", priority: 2000,
                                 safetyClass: .autoSafe, actionKind: .trash,
                                 match: RuleMatchSpec(rootAny: [home.path]), evidence: [])
        let combined = RuleEngine(version: bundled.version, rules: bundled.rules + [user], userRuleIDs: [user.id], homeDirectory: home)
        XCTAssertEqual(classify(personal.path, with: combined).safetyClass, .preserveByDefault)
        XCTAssertEqual(classify(credential.path, with: combined).safetyClass, .neverTouch)
        XCTAssertEqual(classify(home.appendingPathComponent("Library/Caches/SomeApp/blob").path, with: bundled).safetyClass, .safeAfterCondition)
    }

    func testLegacyAutoSafeRuleNeedsAnExplicitRoot() throws {
        let rule = ReclaimerRule(id: "legacy.auto", title: "Legacy cache", category: "Fixture", priority: 100,
                                 safetyClass: .autoSafe, actionKind: .trash,
                                 match: RuleMatchSpec(containsAny: ["/.codex/cache"]), evidence: [])
        let engine = RuleEngine(version: "legacy", rules: [rule])
        let sibling = try directory(".codex/cache-personal/blob")
        XCTAssertEqual(classify(sibling.path, with: engine).safetyClass, .reviewRequired)
    }

    private func engine() throws -> RuleEngine {
        try RuleEngine.bundled(homeDirectory: home)
    }

    private func classify(_ path: String, with engine: RuleEngine) -> Classification {
        engine.classify(path: path, isDirectory: false, isSymbolicLink: false)
    }

    @discardableResult
    private func directory(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
