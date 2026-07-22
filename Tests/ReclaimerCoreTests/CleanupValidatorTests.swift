import XCTest
@testable import ReclaimerCore

final class CleanupValidatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        let temporaryPath = FileManager.default.temporaryDirectory.path
        let canonicalTemporaryPath = try XCTUnwrap(FileIdentity.capture(path: temporaryPath)?.canonicalPath)
        root = URL(fileURLWithPath: canonicalTemporaryPath)
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

    func testAcceptsReviewedSessionFile() throws {
        let sessions = root.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("session.jsonl")
        try Data("{}\n".utf8).write(to: session)
        let identity = try XCTUnwrap(FileIdentity.capture(path: session.path))

        XCTAssertEqual(
            try CleanupValidator().validateSessionFile(
                path: session.path,
                allowedRoots: [sessions.path],
                scannedIdentity: identity
            ).path,
            identity.canonicalPath
        )
    }

    func testRejectsSessionOutsideReviewedRoot() throws {
        let sessions = root.appendingPathComponent(".codex/sessions")
        let outside = root.appendingPathComponent("outside/session.jsonl")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: outside)
        let identity = try XCTUnwrap(FileIdentity.capture(path: outside.path))

        XCTAssertThrowsError(
            try CleanupValidator().validateSessionFile(
                path: outside.path,
                allowedRoots: [sessions.path],
                scannedIdentity: identity
            )
        ) { XCTAssertEqual($0 as? CleanupValidationError, .outsideReviewedRoot) }
    }

    func testRejectsUnsupportedSessionExtension() throws {
        let sessions = root.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("session.sqlite")
        try Data("not a transcript".utf8).write(to: session)
        let identity = try XCTUnwrap(FileIdentity.capture(path: session.path))

        XCTAssertThrowsError(
            try CleanupValidator().validateSessionFile(
                path: session.path,
                allowedRoots: [sessions.path],
                scannedIdentity: identity
            )
        ) { XCTAssertEqual($0 as? CleanupValidationError, .unsupportedSessionFile) }
    }

    func testRejectsOpenSessionFile() throws {
        let sessions = root.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("active.jsonl")
        try Data("{}\n".utf8).write(to: session)
        let handle = try FileHandle(forWritingTo: session)
        defer { try? handle.close() }
        let identity = try XCTUnwrap(FileIdentity.capture(path: session.path))

        XCTAssertThrowsError(
            try CleanupValidator().validateSessionFile(
                path: session.path,
                allowedRoots: [sessions.path],
                scannedIdentity: identity
            )
        ) { XCTAssertEqual($0 as? CleanupValidationError, .openFiles) }
    }

    func testSessionArchiveIsVerifiedAndKeepsOriginal() throws {
        let session = root.appendingPathComponent("session.jsonl")
        try Data(repeating: 65, count: 1_000_000).write(to: session)
        let archives = root.appendingPathComponent("archives")

        let archive = try SessionArchiveWriter().writeVerifiedArchive(
            source: session,
            destinationDirectory: archives
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: session.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertLessThan(
            try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max,
            1_000_000
        )
        let verifier = Process()
        verifier.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        verifier.arguments = ["-t", "--", archive.path]
        try verifier.run()
        verifier.waitUntilExit()
        XCTAssertEqual(verifier.terminationStatus, 0)
    }

    func testSessionArchiveRejectsRedirectedDestination() throws {
        let session = root.appendingPathComponent("session.jsonl")
        try Data("{}\n".utf8).write(to: session)
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let redirected = root.appendingPathComponent("redirected")
        try FileManager.default.createSymbolicLink(at: redirected, withDestinationURL: outside)

        XCTAssertThrowsError(
            try SessionArchiveWriter().writeVerifiedArchive(
                source: session,
                destinationDirectory: redirected.appendingPathComponent("archives")
            )
        ) { XCTAssertEqual($0 as? SessionArchiveError, .invalidDestination) }
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
