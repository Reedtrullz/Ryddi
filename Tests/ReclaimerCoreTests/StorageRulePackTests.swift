import XCTest
@testable import ReclaimerCore

final class StorageRulePackTests: XCTestCase {
    func testChromeCloneRuleIsReviewOnlyAndTyped() throws {
        let engine = try RuleEngine.bundled()
        let classification = engine.classify(
            path: "/private/var/folders/example/X/com.google.Chrome.code_sign_clone/helper",
            isDirectory: false,
            isSymbolicLink: false
        )
        let match = try XCTUnwrap(classification.matches.first { $0.ruleID == "chrome.code-sign-clone.review" })

        XCTAssertEqual(match.safetyClass, .reviewRequired)
        XCTAssertEqual(match.actionKind, .openGuidance)
        XCTAssertTrue(match.conditionGates.contains(.manualReviewRequired))
        XCTAssertTrue(match.evidence.joined(separator: " ").localizedCaseInsensitiveContains("hard"))
    }

    func testCodexLogsUseOpenAgeAndFinalClassificationGates() throws {
        let engine = try RuleEngine.bundled()
        let classification = engine.classify(
            path: "/Users/test/Library/Logs/com.openai.codex/session.log",
            isDirectory: false,
            isSymbolicLink: false
        )
        let match = try XCTUnwrap(classification.matches.first { $0.ruleID == "codex.desktop-logs.safe-condition" })

        XCTAssertEqual(match.safetyClass, .safeAfterCondition)
        XCTAssertEqual(match.actionKind, .trash)
        XCTAssertTrue(match.conditionGates.contains(.openFileClear))
        XCTAssertTrue(match.conditionGates.contains(.minimumAgeRequired))
        XCTAssertTrue(match.conditionGates.contains(.finalClassificationRequired))
        XCTAssertEqual(match.gateEvidence.minimumAgeDays, 3)
    }

    func testProtectedAndNativeBucketsRemainConservative() throws {
        let engine = try RuleEngine.bundled()
        let sessions = engine.classify(
            path: "/Users/test/.codex/sessions/2026/rollout.jsonl",
            isDirectory: false,
            isSymbolicLink: false
        )
        let colima = engine.classify(
            path: "/Users/test/.colima/default/diffdisk",
            isDirectory: false,
            isSymbolicLink: false
        )
        let npm = engine.classify(
            path: "/Users/test/.npm/_cacache/content-v2",
            isDirectory: true,
            isSymbolicLink: false
        )
        let stremio = engine.classify(
            path: "/Users/test/Library/Application Support/stremio-server/stremio-cache",
            isDirectory: true,
            isSymbolicLink: false
        )

        XCTAssertEqual(sessions.safetyClass, .preserveByDefault)
        XCTAssertEqual(colima.actionKind, .nativeToolCommand)
        XCTAssertEqual(colima.safetyClass, .reviewRequired)
        XCTAssertEqual(npm.actionKind, .nativeToolCommand)
        XCTAssertTrue(npm.matches.contains { $0.ruleID == "package.npm-cache.native" })
        XCTAssertEqual(stremio.actionKind, .deleteCache)
        XCTAssertTrue(stremio.matches.contains { $0.ruleID == "stremio.named-cache.safe-condition" })
    }
}
