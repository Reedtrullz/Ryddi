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
            finding(id: "safe", safety: .autoSafe, action: .trash, bytes: 100),
            finding(id: "condition", safety: .safeAfterCondition, action: .trash, bytes: 90),
            finding(id: "native", safety: .reviewRequired, action: .nativeToolCommand, bytes: 80),
            finding(id: "keep", safety: .preserveByDefault, action: .reportOnly, bytes: 70)
        ]
        let home = HomePresentationBuilder.build(input: input(map: map, findings: findings))
        XCTAssertEqual(home.primaryAction, .reviewReclaimableSpace)
        XCTAssertEqual(home.suggestions.count, 3)
        XCTAssertEqual(home.suggestions.first?.kind, .safeMaintenance)
        XCTAssertEqual(home.reclaimSuggestion?.findingIDs, ["safe"])
        XCTAssertEqual(home.reclaimSuggestion?.estimatedReclaimBytes, 100)
        XCTAssertEqual(home.hiddenSuggestionCount, 2)
    }

    func testNativeOnlyResultDoesNotPromiseReclaimableSpace() {
        let home = HomePresentationBuilder.build(input: input(
            map: map,
            findings: [finding(id: "native", safety: .safeAfterCondition, action: .nativeToolCommand, bytes: 8_000)]
        ))

        XCTAssertEqual(home.primaryAction, .exploreLargestFiles)
        XCTAssertNil(home.reclaimSuggestion)
        XCTAssertEqual(home.suggestions.first?.kind, .nativeMaintenance)
        XCTAssertNil(home.suggestions.first?.estimatedReclaimBytes)
        XCTAssertEqual(home.suggestions.first?.kind.intent, .useNativeMaintenance)
    }

    func testProtectedAndPersonalBytesStayOutOfReclaimSuggestion() {
        let home = HomePresentationBuilder.build(input: input(
            map: map,
            findings: [
                finding(id: "safe", safety: .autoSafe, action: .trash, bytes: 200),
                finding(id: "cache", safety: .autoSafe, action: .deleteCache, bytes: 10_000),
                finding(id: "personal", safety: .reviewRequired, action: .trash, bytes: 20_000),
                finding(id: "protected", safety: .neverTouch, action: .reportOnly, bytes: 30_000)
            ]
        ))

        XCTAssertEqual(home.reclaimSuggestion?.estimatedReclaimBytes, 200)
        XCTAssertEqual(home.reclaimSuggestion?.findingIDs, ["safe"])
        XCTAssertEqual(HomeSuggestionKind.protected.intent, .informational)
        XCTAssertEqual(HomeSuggestionKind.reviewPersonalFiles.intent, .inspectPersonalFiles)
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
