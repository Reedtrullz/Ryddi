import XCTest
@testable import ReclaimerCore

final class SafeActionPlannerTests: XCTestCase {
    func testPlannerMapsKnownFindingsToSafeActions() throws {
        let findings = [
            finding(
                path: "/Users/reidar/Library/Caches/Homebrew",
                displayName: "Homebrew",
                size: 2_000_000_000,
                safety: .safeAfterCondition,
                action: .nativeToolCommand,
                category: "Developer cache"
            ),
            finding(
                path: "/Applications/Old Example.app",
                displayName: "Old Example.app",
                size: 400_000_000,
                safety: .reviewRequired,
                action: .trash,
                category: "Applications"
            ),
            finding(
                path: "/Users/reidar/.npm/_cacache",
                displayName: "_cacache",
                size: 1_000_000_000,
                safety: .safeAfterCondition,
                action: .nativeToolCommand,
                category: "Developer cache"
            )
        ]

        let actions = SafeActionPlanner().build(findings: findings)

        XCTAssertEqual(Set(actions.map(\.kind)), [.homebrewCleanup, .openFinderReview, .packageCacheGuidance])
        XCTAssertEqual(actions.first { $0.kind == .homebrewCleanup }?.commandPreview, ["brew", "cleanup", "--dry-run"])
        XCTAssertEqual(actions.first { $0.kind == .homebrewCleanup }?.requiredConditions, [.nativeToolRequired, .finalClassificationRequired])
        let appReview = try XCTUnwrap(actions.first { $0.id.hasPrefix("app-bundle-review:") })
        XCTAssertEqual(appReview.requiredConditions, [.manualReviewRequired, .appQuitRequired, .notSymbolicLink, .finalClassificationRequired])
        XCTAssertFalse(appReview.destructive)
        XCTAssertTrue(appReview.reviewRequired)
        XCTAssertEqual(actions.first { $0.kind == .packageCacheGuidance }?.reviewRequired, true)
    }

    func testPlannerAddsAuditPruneActionWhenAuditStoreExceedsThresholds() throws {
        let summary = AuditStoreSummary(
            rootPath: "/Users/reidar/Library/Application Support/Ryddi/Audit",
            totalKnownFileCount: 501,
            totalKnownBytes: 600 * 1_024 * 1_024,
            unknownFileCount: 0,
            symlinkCount: 0,
            items: []
        )

        let actions = SafeActionPlanner().build(findings: [], auditSummary: summary)

        let action = try XCTUnwrap(actions.first { $0.kind == .auditPrune })
        XCTAssertEqual(action.estimatedBytes, summary.totalKnownBytes)
        XCTAssertEqual(action.commandPreview, ["reclaimer", "audit", "prune", "--dry-run", "--older-than-days", "30", "--keep-recent", "100"])
        XCTAssertEqual(action.requiredConditions, [.manualReviewRequired, .finalClassificationRequired])
        XCTAssertFalse(action.destructive)
        XCTAssertTrue(action.detail.localizedCaseInsensitiveContains("manual"))
    }

    func testPlannerDoesNotProduceExecutableActionsForProtectedStorage() {
        let findings = [
            finding(
                path: "/Users/reidar/.codex/sessions",
                displayName: "sessions",
                safety: .preserveByDefault,
                action: .reportOnly,
                category: "Codex"
            ),
            finding(
                path: "/Users/reidar/Library/Application Support/Google/Chrome/Profile 1",
                displayName: "Profile 1",
                safety: .reviewRequired,
                action: .reportOnly,
                category: "Browser profile"
            ),
            finding(
                path: "/Users/reidar/.colima/default/disk.img",
                displayName: "disk.img",
                safety: .reviewRequired,
                action: .nativeToolCommand,
                category: "Containers"
            ),
            finding(
                path: "/Users/reidar/Library/Caches/Homebrew",
                displayName: "Homebrew",
                safety: .preserveByDefault,
                action: .nativeToolCommand,
                category: "Developer cache"
            )
        ]

        let actions = SafeActionPlanner().build(findings: findings)

        XCTAssertTrue(actions.isEmpty)
    }

    private func finding(
        path: String,
        displayName: String,
        size: Int64 = 100_000,
        safety: SafetyClass,
        action: ActionKind,
        category: String
    ) -> Finding {
        Finding(
            scopeName: "Fixture",
            path: path,
            displayName: displayName,
            logicalSize: size,
            allocatedSize: size,
            isDirectory: true,
            safetyClass: safety,
            actionKind: action,
            ruleMatches: [
                RuleMatch(
                    ruleID: "fixture",
                    title: displayName,
                    category: category,
                    safetyClass: safety,
                    actionKind: action,
                    evidence: ["fixture"]
                )
            ],
            evidence: [Evidence(kind: "fixture", message: "fixture")]
        )
    }
}
