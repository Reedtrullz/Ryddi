import XCTest
@testable import ReclaimerCore

final class HomePresentationTests: XCTestCase {
    func testNoMapRequiresUserStartedScan() {
        let home = HomePresentationBuilder.build(input: input(map: nil))
        XCTAssertEqual(home.primaryAction, .scanMac)
        XCTAssertTrue(home.suggestions.isEmpty)
    }

    func testScanningAndVerificationPrecedence() {
        XCTAssertEqual(
            HomePresentationBuilder.build(input: input(isScanning: true, map: map)).primaryAction,
            .cancelScan
        )
        XCTAssertEqual(
            HomePresentationBuilder.build(input: input(map: map, hasPendingVerification: true)).primaryAction,
            .verifyCleanup
        )
    }

    func testSuggestionsAreCappedAndSafeMaintenanceRanksFirst() {
        let findings = [
            finding(id: "personal", safety: .reviewRequired, action: .trash, bytes: 10_000),
            finding(id: "safe", safety: .autoSafe, action: .deleteCache, bytes: 100),
            finding(id: "condition", safety: .safeAfterCondition, action: .trash, bytes: 90),
            finding(id: "native", safety: .reviewRequired, action: .nativeToolCommand, bytes: 80),
            finding(id: "keep", safety: .preserveByDefault, action: .reportOnly, bytes: 70)
        ]
        let home = HomePresentationBuilder.build(input: input(map: map, findings: findings))
        XCTAssertEqual(home.primaryAction, .reviewSuggestions)
        XCTAssertEqual(home.suggestions.count, 3)
        XCTAssertEqual(home.suggestions.first?.kind, .safeMaintenance)
        XCTAssertEqual(home.hiddenSuggestionCount, 2)
    }

    func testStaleMapCannotCreateActionableSuggestions() {
        let home = HomePresentationBuilder.build(input: input(
            map: map,
            findings: [finding(id: "safe", safety: .autoSafe, action: .trash, bytes: 100)],
            evidenceIsCurrent: false
        ))
        XCTAssertEqual(home.primaryAction, .scanAgain)
        XCTAssertTrue(home.suggestions.isEmpty)
    }

    private func input(
        isScanning: Bool = false,
        map: GuidedMapSnapshot?,
        findings: [Finding] = [],
        hasPendingVerification: Bool = false,
        accessIsLimited: Bool = false,
        evidenceIsCurrent: Bool = true
    ) -> HomePresentationInput {
        HomePresentationInput(
            isScanning: isScanning,
            map: map,
            findings: findings,
            hasPendingVerification: hasPendingVerification,
            accessIsLimited: accessIsLimited,
            evidenceIsCurrent: evidenceIsCurrent
        )
    }

    private var map: GuidedMapSnapshot {
        GuidedMapSnapshot(
            scanID: "scan",
            capturedAt: Date(timeIntervalSince1970: 1),
            scopeDescription: "Test",
            volumeCapacityBytes: 100,
            volumeAvailableBytes: 50,
            measuredAllocatedBytes: 50,
            evidenceState: .complete,
            rootID: "root",
            nodes: []
        )
    }

    private func finding(
        id: String,
        safety: SafetyClass,
        action: ActionKind,
        bytes: Int64
    ) -> Finding {
        Finding(
            id: id,
            scopeName: "Test",
            path: "/tmp/\(id)",
            displayName: id,
            logicalSize: bytes,
            allocatedSize: bytes,
            isDirectory: false,
            safetyClass: safety,
            actionKind: action,
            ruleMatches: [],
            evidence: []
        )
    }
}
